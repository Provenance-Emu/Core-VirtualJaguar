#import "PVJaguarGameCore.h"

@import PVSupport;
#import <PVLogging/PVLogging.h>

#if !TARGET_OS_MACCATALYST && !TARGET_OS_OSX
#import <OpenGLES/gltypes.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>
#import <OpenGLES/EAGL.h>
#else
#import <OpenGL/OpenGL.h>
#import <GLUT/GLUT.h>
#endif

#import "jaguar.h"
#import "file.h"
#import "jagbios.h"
#import "jagbios2.h"
#include "jagstub2bios.h"
#include "memory.h"
#include "tom.h"
#include "dsp.h"
#include "m68kinterface.h"
#include "settings.h"
#include "joystick.h"
#include "dac.h"
#include "libretro.h"

#import <PVVirtualJaguar/PVVirtualJaguar-Swift.h>

//#pragma clang diagnostic push
//#pragma clang diagnostic error "-Wall"

__weak static PVJaguarGameCore *_current;
retro_audio_sample_batch_t audio_batch_cb;
void retro_set_audio_sample_batch(retro_audio_sample_batch_t cb) { audio_batch_cb = cb; }

extern uint16_t eeprom_ram[];

//retro_audio_sample_batch_t audio_batch_cb(const int16_t * data, size_t frames);

int doom_res_hack=0; // Doom Hack to double pixel if pwidth==8 (163*2)

@interface PVJaguarGameCore ()
{
	@public
    int videoWidth, videoHeight, bufferSize;
	float frameTime;
	bool multithreaded;
    double sampleRate;
    struct JagBuffer * videoBuffer;
    dispatch_queue_t audioQueue;
    dispatch_queue_t videoQueue;
    dispatch_group_t renderGroup;

    dispatch_semaphore_t waitToBeginFrameSemaphore;

}

@end

#define AUDIO_BIT_DEPTH 16
#define AUDIO_CHANNELS 2
#define AUDIO_SAMPLERATE 48000
#define BUFPAL  1920
#define BUFNTSC 1600
#define BUFMAX (2048 * sizeof(uint16_t))
#define VIDEO_WIDTH 1024
#define VIDEO_HEIGHT 512

typedef struct JagBuffer {
    char label[256];
    uint32_t buffer[VIDEO_WIDTH * VIDEO_HEIGHT];
    uint16_t * sampleBuffer[BUFMAX];

    bool read;
    bool written;
    bool audio_read;
    bool audio_written;

    u_long frameNumber;
    struct JagBuffer* next;
} JagBuffer;

JagBuffer* initJagBuffer(const char *label);
JagBuffer* initJagBuffer(const char *label) {
    JagBuffer* buffer = malloc(sizeof(*buffer));
    if (buffer != NULL) {
        memset(buffer->sampleBuffer, 0, BUFMAX);
        strncpy( buffer->label, label, 256);
    }
    return buffer;
}

static const size_t update_audio_batch(const int16_t *data, const size_t frames)
{
	__strong PVJaguarGameCore* current = _current;
	if(current == nil)
		return 0;

//	dispatch_group_enter(current->renderGroup);
//	dispatch_async(current->audioQueue, ^{
//		dispatch_time_t killTime = dispatch_time(DISPATCH_TIME_NOW, frameTime * NSEC_PER_SEC);
//		dispatch_semaphore_wait(current->waitToBeginFrameSemaphore, killTime);
		return [[current ringBufferAtIndex:0] write:data maxLength:frames << 2];
        //    [[_current ringBufferAtIndex:0] write:sampleBuffer maxLength:bufferSize*2];

//		[[current ringBufferAtIndex:0] write:data maxLength:frames * [current channelCount] * 2];
//		dispatch_group_leave(current->renderGroup);
//	});

//	return frames;
}

@implementation PVJaguarGameCore

- (id)init
{
    if (self = [super init]) {
        videoWidth = VIDEO_WIDTH;
        videoHeight = VIDEO_HEIGHT;
        sampleRate = AUDIO_SAMPLERATE;
        
        dispatch_queue_attr_t priorityAttribute = dispatch_queue_attr_make_with_qos_class( DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0);
        audioQueue = dispatch_queue_create("com.provenance.jaguar.audio", priorityAttribute);
        videoQueue = dispatch_queue_create("com.provenance.jaguar.video", priorityAttribute);
        renderGroup = dispatch_group_create();

        waitToBeginFrameSemaphore = dispatch_semaphore_create(0);

		multithreaded = self.virtualjaguar_mutlithreaded;
//        buffer = (uint32_t*)calloc(sizeof(uint32_t), videoWidth * videoHeight);
//        sampleBuffer = (uint16_t *)malloc(BUFMAX * sizeof(uint16_t));
//        memset(sampleBuffer, 0, BUFMAX * sizeof(uint16_t));
    }
    
    _current = self;
    
    return self;
}

- (BOOL)loadFileAtPath:(NSString *)path
{
    NSString *batterySavesDirectory = self.batterySavesPath;
    
    if([batterySavesDirectory length] != 0)
    {
        [[NSFileManager defaultManager] createDirectoryAtPath:batterySavesDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
        
        NSString *filePath = [batterySavesDirectory stringByAppendingString:@"/"];
        strcpy(vjs.EEPROMPath, filePath.fileSystemRepresentation);
    }
    
    videoWidth           = 320;
    videoHeight          = 240;

    struct JagBuffer *buffer1 = initJagBuffer("a");
    struct JagBuffer *buffer2 = initJagBuffer("b");
    
    buffer1->next = buffer2;
    buffer2->next = buffer1;

    videoBuffer = buffer1;
//    frontBuffer  = (uint32_t *)calloc(sizeof(uint32_t), 1024 * 512);
//    backBuffer  = (uint32_t *)calloc(sizeof(uint32_t), 1024 * 512);

    sampleBuffer = (uint16_t *)malloc(BUFMAX * sizeof(uint16_t)); //found in dac.h
    memset(sampleBuffer, 0, BUFMAX * sizeof(uint16_t));
    
//    //LogInit("vj.log");                                      // initialize log file for debugging
    vjs.hardwareTypeNTSC = true;

	strcpy(vjs.romName, [path.lastPathComponent cStringUsingEncoding:NSUTF8StringEncoding]);

	BOOL externalBIOS = false;

	// Look to see if user has copied a bios into the bios dir
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *biosPath = [self.BIOSPath stringByAppendingPathComponent:@"jagboot.rom"];
	if ([fm fileExistsAtPath:biosPath] && self.virtualjaguar_bios) {
		ILOG(@"Using bios at path %@", biosPath);
		strcpy(vjs.jagBootPath, [biosPath cStringUsingEncoding:NSUTF8StringEncoding]);
		// No idea if this is working actually - does useJaguarBIOS do something?
		vjs.useJaguarBIOS = true;
		externalBIOS = true;
	} else {
		ILOG(@"No external BIOS found. Using no BIOS.");
		vjs.useJaguarBIOS = false;
		externalBIOS = false;
	}

	vjs.useFastBlitter = self.virtualjaguar_usefastblitter;

	retro_set_audio_sample_batch(update_audio_batch);

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
//        if (!romLoaded) {
//            romLoaded = AlpineLoadFile((uint8_t*)alpineData.bytes, alpineData.length);
//        }

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

    const void * _Nullable biosPointer = jaguarBootROM;
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

	if ([path.lowercaseString containsString:@"doom"]) {
		doom_res_hack = 1;
	} else { doom_res_hack = 0; }
    
    memcpy(jagMemSpace + 0xE00000, biosPointer, 0x20000);
        
    // We have to load our software *after* the Jaguar RESET
    SET32(jaguarMainRAM, 0, 0x00200000);        // Set top of stack...
    BOOL cartridgeLoaded = JaguarLoadFile((uint8_t*)romData.bytes, romData.length);   // load rom
    
    JaguarReset();

    [self initVideo];

    // This is icky because we've already done it
    // it gets worse :-P
    if (!vjs.useJaguarBIOS) {
        SET32(jaguarMainRAM, 4, jaguarRunAddress);
    }
    
    m68k_pulse_reset();

	bufferSize = vjs.hardwareTypeNTSC ? BUFNTSC : BUFPAL;
	frameTime = vjs.hardwareTypeNTSC ? 1.0/60.0 : 1.0/50.0;

    return cartridgeLoaded;
}

#define BS(b) b?"Y":"N"

-(void)executeFrameSkippingFrame:(BOOL)skip {
    __volatile static u_long frameCount = 0;

    static dispatch_once_t onceToken;
    static NSDate *g_date = NULL;
    dispatch_once(&onceToken, ^{
        g_date = [NSDate date];
    });

    frameCount++;

    NSDate *now = [NSDate date];

    g_date = now;

    u_long currentFrame = frameCount;
//    NSDate *last = [g_date copy];
//    NSTimeInterval timeSinceLast = [last timeIntervalSinceNow];
//    printf("executeFrameSkippingFrame: skip: %s\ttime:%lu\n", BS(skip), timeSinceLast);

    if (self.controller1 || self.controller2) {
        [self pollControllers];
    }
    
    if (multithreaded) {
    __block BOOL expired = NO;
    dispatch_time_t killTime = dispatch_time(DISPATCH_TIME_NOW, frameTime * NSEC_PER_SEC);

    struct JagBuffer*videoBuffer = self->videoBuffer;

    MAKEWEAK(self);
    dispatch_group_enter(renderGroup);
    dispatch_async(videoQueue, ^{
        MAKESTRONG(self);
        vjs.frameSkip = skip || expired;
//        printf("will write frame %lul\written: %s\tread:%s\tlabel:%s\n", videoBuffer->frameNumber, BS(videoBuffer->written), BS(videoBuffer->read), videoBuffer->label);
        JaguarExecuteNew();
        videoBuffer->written = YES;
        videoBuffer->frameNumber = currentFrame;
//        printf("did write frame %lul\tskip: %s\texpired:%s\nlabel:%s\n", videoBuffer->frameNumber, BS(skip), BS(expired), videoBuffer->label);
        dispatch_semaphore_signal(strongself->waitToBeginFrameSemaphore);
        dispatch_group_leave(strongself->renderGroup);
    });

    dispatch_group_enter(renderGroup);
    dispatch_async(audioQueue, ^{
        MAKESTRONG(self);
        dispatch_semaphore_wait(strongself->waitToBeginFrameSemaphore, killTime);
        SoundCallback(NULL, strongself->videoBuffer->sampleBuffer, strongself->bufferSize);
//        [[_current ringBufferAtIndex:0] write:videoBuffer->sampleBuffer maxLength:bufferSize*2];
//        printf("wrote audio frame %lul\tlabel:%s\n", videoBuffer->frameNumber, videoBuffer->label);
        dispatch_group_leave(strongself->renderGroup);
    });
//        // Don't block the frame draw waiting for audio
//    dispatch_group_enter(renderGroup);
//    dispatch_async(audioQueue, ^{
//        SDLSoundCallback(NULL, sampleBuffer, bufferSize);
//        [[_current ringBufferAtIndex:0] write:sampleBuffer maxLength:bufferSize*2];
//        dispatch_group_leave(renderGroup);
//    });

//    dispatch_group_wait(renderGroup, killTime);
//    expired = YES;
    } else {
        vjs.frameSkip = skip;
        JaguarExecuteNew();
        NSUInteger bufferSize = vjs.hardwareTypeNTSC ? BUFNTSC : BUFPAL;

        SoundCallback(NULL, sampleBuffer, bufferSize);
    //    [[_current ringBufferAtIndex:0] write:sampleBuffer maxLength:bufferSize*2];

    }
}

//- (void)runRenderThread {
//    @autoreleasepool
//    {
//        [self.renderDelegate startRenderingOnAlternateThread];
//        [NSThread detachNewThreadSelector:@selector(runEmuThread) toTarget:self withObject:nil];
//
//        CFAbsoluteTime lastTime = CFAbsoluteTimeGetCurrent();
//
//        while (!has_init) {}
//        while ( !shouldStop )
//        {
//            [self.frontBufferCondition lock];
//            while (!shouldStop && self.isFrontBufferReady) [self.frontBufferCondition wait];
//            [self.frontBufferCondition unlock];
//
//            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
//            CFTimeInterval deltaTime = now - lastTime;
//            while ( !shouldStop && !rend_single_frame() ) {}
//            [self swapBuffers];
//            lastTime = now;
//        }
//    }
//}
//
//- (void)runEmuThread {
//    @autoreleasepool
//    {
//        [self reicastMain];
//
//            // Core returns
//
//            // Unlock rendering thread
//        dispatch_semaphore_signal(coreWaitToEndFrameSemaphore);
//
//        [super stopEmulation];
//    }
//}

- (void)executeFrame {
    [self executeFrameSkippingFrame:NO];
}

- (void)initVideo {
    JaguarSetScreenPitch(videoWidth);
    JaguarSetScreenBuffer(videoBuffer->buffer);
    for (int i = 0; i < videoWidth * videoHeight; ++i) {
        videoBuffer->buffer[i] = 0xFF00FFFF;
        videoBuffer->next->buffer[i] = 0xFF00FFFF;
    }
}

- (BOOL)isDoubleBuffered {
//    BOOL f = self.virtualjaguar_double_buffer;
//    VLOG(@"double buffer %i". self.virtualjaguar_double_buffer);
//    return self.virtualjaguar_double_buffer;
    // TODO: Fix graphics tearing when this is on
    return false;
}

- (void)swapBuffers {
//    printf("swap buffers: current: %s, count: %i, read: %s, written: %s, next: read: %s, written: %s",
//           videoBuffer->label,
//           videoBuffer->frameNumber,
//           BS(videoBuffer->read),
//           BS(videoBuffer->written),
//           BS(videoBuffer->next->read),
//           BS(videoBuffer->next->written));

    videoBuffer->read = YES;
    videoBuffer = videoBuffer->next;
    videoBuffer->written = NO;
    videoBuffer->read = NO;
    JaguarSetScreenBuffer(videoBuffer->buffer);
}

- (NSUInteger)audioBitDepth { return AUDIO_BIT_DEPTH; }

- (void)setupEmulation { }

- (void)stopEmulation {
    JaguarDone();

    [super stopEmulation];
}

- (void)resetEmulation {
    JaguarReset();
}

- (void)dealloc {
    _current = nil;
    struct JagBuffer* ab = videoBuffer;
    struct JagBuffer* next = videoBuffer->next;

    while(next->next != ab) {
        struct JagBuffer* temp = next->next;
        free(next);
        next = temp;
    };
    [self delloc_sampleBuffer];
}

-(void)delloc_sampleBuffer {
//    if (sampleBuffer != nil) {
//        free(sampleBuffer);
//    }
//    sampleBuffer = nil;
}

- (CGRect)screenRect {
    return CGRectMake(0, 0, TOMGetVideoModeWidth(), TOMGetVideoModeHeight());
}

- (CGSize)bufferSize {
    return CGSizeMake(videoWidth, videoHeight);
}

- (CGSize)aspectSize {
    return CGSizeMake(videoWidth, videoHeight);
}

- (const void *)videoBuffer {
    return videoBuffer->buffer;
}

- (GLenum)pixelFormat {
    return GL_BGRA;
}

- (GLenum)pixelType {
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
    return AUDIO_CHANNELS;
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
        
        if (currentController == nil) {
            ELOG(@"currentController is nil");
            continue;
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

void *retro_get_memory_data(unsigned type)
{
   if(type == RETRO_MEMORY_SYSTEM_RAM)
      return jaguarMainRAM;
   else if (type == RETRO_MEMORY_SAVE_RAM)
      return eeprom_ram;
   else return NULL;
}

size_t retro_get_memory_size(unsigned type)
{
   if(type == RETRO_MEMORY_SYSTEM_RAM)
      return 0x200000;
   else if (type == RETRO_MEMORY_SAVE_RAM)
      return 128;
   else return 0;
}

- (BOOL)loadSaveFile:(NSString *)path forType:(int)type {
    size_t size = retro_get_memory_size(type);
    void *ramData = retro_get_memory_data(type);

    if (size == 0 || !ramData)
    {
        return false;
    }

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || ![data length])
    {
        DLog(@"Couldn't load save file.");
        return false;
    }

    [data getBytes:ramData length:size];
    // TODO: Should instead use SET32 or a byte copy to jaguarMainRAM/eeprom?
    return true;
}

- (BOOL)writeSaveFile:(NSString *)path forType:(int)type {
    size_t size = retro_get_memory_size(type);
    void *ramData = retro_get_memory_data(type);

    if (ramData && (size > 0))
    {
        NSData *data = [NSData dataWithBytes:ramData length:size];
        BOOL success = [data writeToFile:path atomically:YES];
        if (!success)
        {
            DLog(@"Error writing save file");
        }
        return success;
    } else { return false; }
}

//- (BOOL)saveStateToFileAtPath:(NSString *)fileName error:(NSError**)error   {
//    NSAssert(NO, @"Shouldn't be here since we overwrite the async call");
//}
//
//- (BOOL)loadStateFromFileAtPath:(NSString *)fileName error:(NSError**)error   {
//    NSAssert(NO, @"Shouldn't be here since we overwrite the async call");
//}

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block {
    __block BOOL wasPaused = [self isEmulationPaused];
    [self setPauseEmulation:true];

    BOOL status = [self writeSaveFile:[fileName stringByAppendingString:@"system"]
                              forType:RETRO_MEMORY_SYSTEM_RAM];
    if (status) {
        status = [self writeSaveFile:[fileName stringByAppendingString:@"eeprom"]
                                  forType:RETRO_MEMORY_SAVE_RAM];
    }
    [self setPauseEmulation:wasPaused];
    if (block) {
        NSError *error = nil;
        if (!status) {
            error = [NSError errorWithDomain:@"org.provenance.GameCore.ErrorDomain"
                                                 code:-5
                                             userInfo:@{
                                                        NSLocalizedDescriptionKey : @"Jagar Could not save the current state.",
                                                        NSFilePathErrorKey : fileName
                                                        }];


        }
        dispatch_async(dispatch_get_main_queue(), ^{
            block(status, error);
        });
    }
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block {
    __block BOOL wasPaused = [self isEmulationPaused];
    [self setPauseEmulation:true];

    BOOL status = [self loadSaveFile:[fileName stringByAppendingString:@"system"]
                             forType:RETRO_MEMORY_SYSTEM_RAM];
    if (status) {
        status = [self loadSaveFile:[fileName stringByAppendingString:@"eeprom"]
                            forType:RETRO_MEMORY_SAVE_RAM];
    }
    [self setPauseEmulation:wasPaused];

    if (block) {
        NSError *error = nil;
        if (!status) {
            error = [NSError errorWithDomain:@"org.provenance.GameCore.ErrorDomain"
                                                 code:-5
                                             userInfo:@{
                                                        NSLocalizedDescriptionKey : @"Jagar Could not load the current state.",
                                                        NSFilePathErrorKey : fileName
                                                        }];


        }
        dispatch_async(dispatch_get_main_queue(), ^{
            block(status, error);
        });
    }
}


-(BOOL)supportsSaveStates {
	return NO;
}

-(void)virtualjaguar_bios:(BOOL)value {
	_virtualjaguar_bios = value;
	vjs.useJaguarBIOS = value;
}

-(void)virtualjaguar_usefastblitter:(BOOL)value {
	_virtualjaguar_usefastblitter = value;
	vjs.useFastBlitter = value;
}

-(void)virtualjaguar_doom_res_hack:(BOOL)value {
	_virtualjaguar_doom_res_hack = value;
	doom_res_hack = value;
}

-(void)virtualjaguar_pal:(BOOL)value {
	_virtualjaguar_pal = value;
	vjs.hardwareTypeNTSC = !value;
}

@end
