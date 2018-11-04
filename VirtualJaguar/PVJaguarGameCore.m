#import "PVJaguarGameCore.h"

@import PVSupport;
@import OpenGLES.ES3;

#import "jaguar.h"
#import "file.h"
#import "jagbios.h"
#import "jagbios2.h"
#include "jagstub2bios.h"
#include "memory.h"
#include "log.h"
#include "tom.h"
#include "dsp.h"
#include "m68kinterface.h"
#include "settings.h"
#include "joystick.h"
#include "dac.h"
#include "libretro.h"

#pragma clang diagnostic push
#pragma clang diagnostic error "-Wall"

__weak static PVJaguarGameCore *_current;

@interface PVJaguarGameCore ()
{
    int videoWidth, videoHeight;
    double sampleRate;
    uint32_t *buffer;
    dispatch_queue_t audioQueue;
    dispatch_queue_t videoQueue;
    dispatch_group_t renderGroup;

    dispatch_semaphore_t waitToBeginFrameSemaphore;

}
@end

#define PARALLEL_GFX_AUDIO_CALLS 1
#define SAMPLERATE 48000
#define BUFPAL  1920
#define BUFNTSC 1600
#define BUFMAX (2048 * 2)

@implementation PVJaguarGameCore

- (id)init
{
    if (self = [super init]) {
        videoWidth = 1024;
        videoHeight = 512;
        sampleRate = SAMPLERATE;
        
        dispatch_queue_attr_t priorityAttribute = dispatch_queue_attr_make_with_qos_class( DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, -1);
        audioQueue = dispatch_queue_create("com.provenance.jaguar.audio", priorityAttribute);
        videoQueue = dispatch_queue_create("com.provenance.jaguar.video", priorityAttribute);
        renderGroup = dispatch_group_create();

        waitToBeginFrameSemaphore = dispatch_semaphore_create(0);

//        buffer = (uint32_t*)calloc(sizeof(uint32_t), videoWidth * videoHeight);
//        sampleBuffer = (uint16_t *)malloc(BUFMAX * sizeof(uint16_t));
//        memset(sampleBuffer, 0, BUFMAX * sizeof(uint16_t));
    }
    
    _current = self;
    
    return self;
}

- (BOOL)loadFileAtPath:(NSString *)path
{
    NSString *batterySavesDirectory = [self batterySavesPath];
    
    if([batterySavesDirectory length] != 0)
    {
        [[NSFileManager defaultManager] createDirectoryAtPath:batterySavesDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
        
        NSString *filePath = [batterySavesDirectory stringByAppendingString:@"/"];
        strcpy(vjs.EEPROMPath, [filePath UTF8String]);
    }
    
    videoWidth           = 320;
    videoHeight          = 240;
    buffer  = (uint32_t *)calloc(sizeof(uint32_t), 1024 * 512);
    sampleBuffer = (uint16_t *)malloc(BUFMAX * sizeof(uint16_t)); //found in dac.h
    memset(sampleBuffer, 0, BUFMAX * sizeof(uint16_t));
    
//    //LogInit("vj.log");                                      // initialize log file for debugging
    vjs.hardwareTypeNTSC = true;

	strcpy(vjs.romName, path.lastPathComponent.cString);

	BOOL externalBIOS = false;

	// Look to see if user has copied a bios into the bios dir
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *biosPath = [self.BIOSPath stringByAppendingPathComponent:@"jagboot.rom"];
	if ([fm fileExistsAtPath:biosPath]) {
		ILOG(@"Using bios at path %@", biosPath);
		strcpy(vjs.jagBootPath, biosPath.cString);
		// No idea if this is working actually - does useJaguarBIOS do something?
		vjs.useJaguarBIOS = false;
		externalBIOS = true;
	} else {
		ILOG(@"No external BIOS found. Using no BIOS.");
		vjs.useJaguarBIOS = false;
	}

	//TODO: Make these core options
	vjs.useFastBlitter = false;

    JaguarInit();                                             // set up hardware
	if (!externalBIOS) {
		memcpy(jagMemSpace + 0xE00000, (vjs.biosType == BT_K_SERIES ? jaguarBootROM : jaguarBootROM2), 0x20000); // Use the stock BIOS
	} else {
		NSData *data = [NSData dataWithContentsOfFile:biosPath];
		memcpy(jagMemSpace + 0xE00000, data.bytes, data.length); // Use the stock BIOS
	}

    // Load up the default ROM if in Alpine mode:
    if (vjs.hardwareTypeAlpine)
    {
        NSData* alpineData = [NSData dataWithContentsOfFile:@(vjs.alpineROMPath)];

        BOOL romLoaded = JaguarLoadFile((uint8_t*)alpineData.bytes, alpineData.length);

        // If regular load failed, try just a straight file load
        // (Dev only! I don't want people to start getting lazy with their releases again! :-P)
        if (!romLoaded) {
            romLoaded = AlpineLoadFile((uint8_t*)alpineData.bytes, alpineData.length);
        }

        if (romLoaded) {
            ILOG(@"Alpine Mode: Successfully loaded file \"%s\".\n", vjs.alpineROMPath);
        } else {
            ILOG(@"Alpine Mode: Unable to load file \"%s\"!\n", vjs.alpineROMPath);
        }
        
        // Attempt to load/run the ABS file...
//        LoadSoftware(@(vjs.absROMPath));
        memcpy(jagMemSpace + 0xE00000, jaguarDevBootROM2, 0x20000);    // Use the stub BIOS

        return romLoaded;
    } else {
        return [self loadSoftware:path];
    }
    
    return NO;
}

- (BOOL)loadSoftware:(NSString *)path {
    NSData* romData = [NSData dataWithContentsOfFile:path];

    uint8_t * biosPointer = jaguarBootROM;
	NSFileManager *fm = [NSFileManager defaultManager];

	NSString *biosPath = [self.BIOSPath stringByAppendingPathComponent:@"jagboot.rom"];
	BOOL externalBIOS = false;
	if ([fm fileExistsAtPath:biosPath]) {
		// No idea if this is working actually
		biosPointer = [NSData dataWithContentsOfFile:biosPath].bytes;
	}
    
    if (!externalBIOS && vjs.hardwareTypeAlpine) {
        biosPointer = jaguarDevBootROM2;
    }
    
    memcpy(jagMemSpace + 0xE00000, biosPointer, 0x20000);
    
    JaguarReset();
    DACPauseAudioThread(false);
    
    // We have to load our software *after* the Jaguar RESET
    BOOL cartridgeLoaded = JaguarLoadFile((uint8_t*)romData.bytes, romData.length);   // load rom
    SET32(jaguarMainRAM, 0, 0x00200000);        // Set top of stack...
    
    [self initVideo];

    // This is icky because we've already done it
    // it gets worse :-P
    if (!vjs.useJaguarBIOS) {
        SET32(jaguarMainRAM, 4, jaguarRunAddress);
    }
    
    m68k_pulse_reset();

    return cartridgeLoaded;
}

- (void)executeFrame
{
    if (self.controller1 || self.controller2) {
        [self pollControllers];
    }
#if PARALLEL_GFX_AUDIO_CALLS
    dispatch_group_enter(renderGroup);
    dispatch_async(videoQueue, ^{
        JaguarExecuteNew();
        dispatch_group_leave(renderGroup);
    });

    NSUInteger bufferSize = vjs.hardwareTypeNTSC ? BUFNTSC : BUFPAL;
    // Don't block the frame draw waiting for audio
    dispatch_group_enter(renderGroup);
    dispatch_async(audioQueue, ^{
        SDLSoundCallback(NULL, sampleBuffer, bufferSize);
        [[_current ringBufferAtIndex:0] write:sampleBuffer maxLength:bufferSize*2];
        dispatch_group_leave(renderGroup);
    });
	float frameTime = vjs.hardwareTypeNTSC ? 1.0/60.0 : 1.0/50.0;
	dispatch_time_t killTime = dispatch_time(DISPATCH_TIME_NOW, frameTime * NSEC_PER_SEC);
	dispatch_group_wait(renderGroup, killTime);
#else
    JaguarExecuteNew();
    NSUInteger bufferSize = vjs.hardwareTypeNTSC ? BUFNTSC : BUFPAL;

    SDLSoundCallback(NULL, sampleBuffer, bufferSize);
    [[_current ringBufferAtIndex:0] write:sampleBuffer maxLength:bufferSize*2];
#endif
 }

- (void)initVideo
{
    JaguarSetScreenPitch(videoWidth);
    JaguarSetScreenBuffer(buffer);
    for (int i = 0; i < videoWidth * videoHeight; ++i) {
        buffer[i] = 0xFF00FFFF;
    }
}

- (NSUInteger)audioBitDepth
{
    return 16;
}

- (void)setupEmulation
{
}

- (void)stopEmulation
{
    JaguarDone();

    [super stopEmulation];
}

- (void)resetEmulation
{
    JaguarReset();
}

- (void)dealloc
{
    _current = nil;
    free(buffer);
    free(sampleBuffer);
}

- (CGRect)screenRect
{
    return CGRectMake(0, 0, TOMGetVideoModeWidth(), TOMGetVideoModeHeight());
}

- (CGSize)bufferSize
{
    return CGSizeMake(videoWidth, videoHeight);
}

- (CGSize)aspectSize
{
    return CGSizeMake(videoWidth, videoHeight);
}

- (const void *)videoBuffer
{
    return buffer;
}

- (GLenum)pixelFormat
{
    return GL_BGRA;
}

- (GLenum)pixelType
{
    return GL_UNSIGNED_BYTE;
}

- (GLenum)internalPixelFormat
{
    return GL_RGBA;
}

- (double)audioSampleRate
{
    return sampleRate;
}

- (NSTimeInterval)frameInterval
{
    return vjs.hardwareTypeNTSC ? 60 : 50;
}

- (NSUInteger)channelCount
{
    return 2;
}

#pragma mark Input
- (void)pollControllers {
    joypad0Buttons[BUTTON_U]      = 0x00;
    joypad0Buttons[BUTTON_D]      = 0x00;
    joypad0Buttons[BUTTON_L]      = 0x00;
    joypad0Buttons[BUTTON_R]      = 0x00;
    joypad0Buttons[BUTTON_A]      = 0x00;
    joypad0Buttons[BUTTON_B]      = 0x00;
    joypad0Buttons[BUTTON_C]      = 0x00;
    joypad0Buttons[BUTTON_PAUSE]  = 0x00;
    joypad0Buttons[BUTTON_OPTION] = 0x00;
    joypad0Buttons[BUTTON_0]      = 0x00;
    joypad0Buttons[BUTTON_1]      = 0x00;
    joypad0Buttons[BUTTON_2]      = 0x00;
    joypad0Buttons[BUTTON_3]      = 0x00;
    joypad0Buttons[BUTTON_4]      = 0x00;
    joypad0Buttons[BUTTON_5]      = 0x00;
    joypad0Buttons[BUTTON_6]      = 0x00;
    
    joypad1Buttons[BUTTON_U]      = 0x00;
    joypad1Buttons[BUTTON_D]      = 0x00;
    joypad1Buttons[BUTTON_L]      = 0x00;
    joypad1Buttons[BUTTON_R]      = 0x00;
    joypad1Buttons[BUTTON_A]      = 0x00;
    joypad1Buttons[BUTTON_B]      = 0x00;
    joypad1Buttons[BUTTON_C]      = 0x00;
    joypad1Buttons[BUTTON_PAUSE]  = 0x00;
    joypad1Buttons[BUTTON_OPTION] = 0x00;
    joypad1Buttons[BUTTON_0]      = 0x00;
    joypad1Buttons[BUTTON_1]      = 0x00;
    joypad1Buttons[BUTTON_2]      = 0x00;
    joypad1Buttons[BUTTON_3]      = 0x00;
    joypad1Buttons[BUTTON_4]      = 0x00;
    joypad1Buttons[BUTTON_5]      = 0x00;
    joypad1Buttons[BUTTON_6]      = 0x00;
    
    for (NSInteger playerIndex = 0; playerIndex < 2; playerIndex++) {
        GCController *controller = nil;
        uint8_t *currentController;
        
        if (self.controller1 && playerIndex == 0) {
            controller = self.controller1;
            currentController = joypad0Buttons;
        }
        else if (self.controller2 && playerIndex == 1)
        {
            controller = self.controller2;
            currentController = joypad1Buttons;
        }
        
        if ([controller extendedGamepad]) {
            GCExtendedGamepad *gamepad     = [controller extendedGamepad];
            GCControllerDirectionPad *dpad = [gamepad dpad];
            
            // DPAD
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonUp]] = (dpad.up.isPressed || gamepad.leftThumbstick.up.isPressed) ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonDown]] = (dpad.down.isPressed || gamepad.leftThumbstick.down.isPressed) ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonLeft]] = (dpad.left.isPressed || gamepad.leftThumbstick.left.isPressed) ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonRight]] = (dpad.right.isPressed || gamepad.leftThumbstick.right.isPressed) ? 0xFF : 0x00;
            // Buttons
            
            // Fire 1
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonC]] = gamepad.buttonX.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonB]] = gamepad.buttonA.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonA]] = gamepad.buttonB.isPressed ? 0xFF : 0x00;

            // Pause
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonPause]] = gamepad.leftTrigger.isPressed ? 0xFF : 0x00;
            // Option
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonOption]] = gamepad.rightTrigger.isPressed ? 0xFF : 0x00;
            
            // # & * (used by some games like NBA Jam to exit game)
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonPause]] =  gamepad.leftShoulder.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonOption]] = gamepad.rightShoulder.isPressed ? 0xFF : 0x00;

        } else if ([controller gamepad]) {
            GCGamepad *gamepad = [controller gamepad];
            GCControllerDirectionPad *dpad = [gamepad dpad];
            
            // DPAD
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonUp]] = dpad.up.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonDown]] = dpad.down.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonLeft]] = dpad.left.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonRight]] = dpad.right.isPressed ? 0xFF : 0x00;
            // Buttons
            
            // Fire 1
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonC]] = gamepad.buttonX.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonB]] = gamepad.buttonA.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonA]] = gamepad.buttonB.isPressed ? 0xFF : 0x00;
            
            // Triggers
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonPause]] = gamepad.leftShoulder.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonOption]] = gamepad.rightShoulder.isPressed ? 0xFF : 0x00;
        }
#if TARGET_OS_TV
        else if ([controller microGamepad]) {
            GCMicroGamepad *gamepad = [controller microGamepad];
            GCControllerDirectionPad *dpad = [gamepad dpad];
            
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonUp]]    = dpad.up.value > 0.5 ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonDown]]  = dpad.down.value > 0.5 ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonLeft]]  = dpad.left.value > 0.5 ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonRight]] = dpad.right.value > 0.5 ? 0xFF : 0x00;
            
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonC]] = gamepad.buttonX.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButtonB]] = gamepad.buttonA.isPressed ? 0xFF : 0x00;
        }
#endif
    }
}

- (void)didPushJaguarButton:(PVJaguarButton)button forPlayer:(NSInteger)player
{
    uint8_t *currentController;
    
    if (player == 0) {
        currentController = joypad0Buttons;
    } else if (player == 1) {
        currentController = joypad1Buttons;
    } else {
        return;
    }
    
    // special cases to prevent invalid inputs
    if (button == PVJaguarButtonRight && currentController[BUTTON_L]) {
        currentController[BUTTON_L] = 0x00;
        currentController[BUTTON_R] = 0x01;
    }
    else if (button == PVJaguarButtonLeft && currentController[BUTTON_R]) {
        currentController[BUTTON_R] = 0x00;
        currentController[BUTTON_L] = 0x01;
    }
    else if (button == PVJaguarButtonDown && currentController[BUTTON_U]) {
        currentController[BUTTON_U] = 0x00;
        currentController[BUTTON_D] = 0x01;
    }
    else if (button == PVJaguarButtonUp && currentController[BUTTON_D]) {
        currentController[BUTTON_D] = 0x00;
        currentController[BUTTON_U] = 0x01;
    }
    else {
        int index = [self getIndexForPVJaguarButton:button];
        currentController[index] = 0x01;
    }
}

- (void)didReleaseJaguarButton:(PVJaguarButton)button forPlayer:(NSInteger)player
{
    uint8_t *currentController;
    
    if (player == 0) {
        currentController = joypad0Buttons;
    } else if (player == 1) {
        currentController = joypad1Buttons;
    } else {
        return;
    }
    
    int index = [self getIndexForPVJaguarButton:button];
    currentController[index] = 0x00;
}

- (int)getIndexForPVJaguarButton:(PVJaguarButton)btn {
    switch (btn) {
        case PVJaguarButtonUp:
            return BUTTON_U;
        case PVJaguarButtonDown:
            return BUTTON_D;
        case PVJaguarButtonLeft:
            return BUTTON_L;
        case PVJaguarButtonRight:
            return BUTTON_R;
        case PVJaguarButtonA:
            return BUTTON_A;
        case PVJaguarButtonB:
            return BUTTON_B;
        case PVJaguarButtonC:
            return BUTTON_C;
        case PVJaguarButtonPause:
            return BUTTON_PAUSE;
        case PVJaguarButtonOption:
            return BUTTON_OPTION;
        case PVJaguarButton1:
            return BUTTON_1;
        case PVJaguarButton2:
            return BUTTON_2;
        case PVJaguarButton3:
            return BUTTON_3;
        case PVJaguarButton4:
            return BUTTON_4;
        case PVJaguarButton5:
            return BUTTON_5;
        case PVJaguarButton6:
            return BUTTON_6;
        case PVJaguarButton7:
            return BUTTON_7;
        case PVJaguarButton8:
            return BUTTON_8;
        case PVJaguarButton9:
            return BUTTON_9;
        case PVJaguarButton0:
            return BUTTON_0;
        case PVJaguarButtonAsterisk:
            return BUTTON_s;
        case PVJaguarButtonPound:
            return BUTTON_d;
        default:
            return -1;
    }
}

- (void)loadSaveFile:(NSString *)path forType:(int)type
{
//    size_t size = retro_get_memory_size(type);
//    void *ramData = retro_get_memory_data(type);
//
//    if (size == 0 || !ramData)
//    {
//        return;
//    }
//
//    NSData *data = [NSData dataWithContentsOfFile:path];
//    if (!data || ![data length])
//    {
//        DLog(@"Couldn't load save file.");
//    }
//
//    [data getBytes:ramData length:size];
}

- (void)writeSaveFile:(NSString *)path forType:(int)type
{
//    size_t size = retro_get_memory_size(type);
//    void *ramData = retro_get_memory_data(type);
//
//    if (ramData && (size > 0))
//    {
//        retro_serialize(ramData, size);
//        NSData *data = [NSData dataWithBytes:ramData length:size];
//        BOOL success = [data writeToFile:path atomically:YES];
//        if (!success)
//        {
//            DLog(@"Error writing save file");
//        }
//    }
}

- (BOOL)saveStateToFileAtPath:(NSString *)fileName
{
    return NO;
}

- (BOOL)loadStateFromFileAtPath:(NSString *)fileName
{
    return NO;
}
- (BOOL)saveStateToFileAtPath:(NSString *)path error:(NSError *__autoreleasing *)error {
	return NO;
}

- (BOOL)loadStateFromFileAtPath:(NSString *)path error:(NSError**)error {
	return NO;
}

-(BOOL)supportsSaveStates {
	return NO;
}

@end
