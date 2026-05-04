@import Foundation;
#import <objc/message.h>
@import PVCoreBridge;
@import PVEmulatorCore;
#if !TARGET_OS_WATCH
@import GameController;
#endif
@import PVSupport;
@import PVLoggingObjC;
@import PVCoreObjCBridge;
@import libjaguar;
@import libretro_common;

#import "PVJaguarGameCoreBridge.h"

#if __has_include(<OpenGLES/ES3/gl.h>)
#import <OpenGLES/gltypes.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>
#import <OpenGLES/EAGL.h>
#elif __has_include(<OpenGL/OpenGL.h>)
#import <OpenGL/OpenGL.h>
#import <GLUT/GLUT.h>
#endif

extern uint16_t eeprom_ram[64];
extern uint8_t *mtMem;
extern uint32_t jaguarMainROMCRC32;

// TOM (video) functions not in libjaguar public headers
extern uint32_t TOMGetVideoModeWidth(void);
extern uint32_t TOMGetVideoModeHeight(void);
extern uint32_t tomWidth;
extern uint32_t tomHeight;

// JERRY (audio) functions
extern void SoundCallback(void *userdata, uint16_t *buffer, int length);
extern uint16_t *sampleBuffer;

// JERRY (joystick) - button constants and joypad state
enum {
    BUTTON_FIRST = 0,
    BUTTON_U = 0, BUTTON_D = 1, BUTTON_L = 2, BUTTON_R = 3,
    BUTTON_s = 4, BUTTON_7 = 5, BUTTON_4 = 6, BUTTON_1 = 7,
    BUTTON_0 = 8, BUTTON_8 = 9, BUTTON_5 = 10, BUTTON_2 = 11,
    BUTTON_d = 12, BUTTON_9 = 13, BUTTON_6 = 14, BUTTON_3 = 15,
    BUTTON_A = 16, BUTTON_B = 17, BUTTON_C = 18,
    BUTTON_OPTION = 19, BUTTON_PAUSE = 20, BUTTON_LAST = 20
};
extern uint8_t joypad0Buttons[];
extern uint8_t joypad1Buttons[];
extern bool joysticksEnabled;

// BIOS
extern uint8_t jaguarBootROM[];

// M68K
extern void m68k_pulse_reset(void);

// libretro API
size_t retro_serialize_size(void);
bool retro_serialize(void *data, size_t size);
bool retro_unserialize(const void *data, size_t size);
void retro_cheat_reset(void);
void retro_cheat_set(unsigned index, bool enabled, const char *code);
void *retro_get_memory_data(unsigned type);
size_t retro_get_memory_size(unsigned type);

retro_audio_sample_batch_t audio_batch_cb;
void retro_set_audio_sample_batch_jaguar(retro_audio_sample_batch_t cb) { audio_batch_cb = cb; }

@import PVAudio;
@import PVObjCUtils;

__weak static PVJaguarGameCoreBridge *_current;

JagBuffer* initJagBuffer(const char *label) {
    JagBuffer* buffer = malloc(sizeof(JagBuffer));
    if (buffer != NULL) {
        // Allocate buffer using actual content dimensions
        const size_t width = VIDEO_WIDTH; // TOMGetVideoModeWidth();
        const size_t height = VIDEO_HEIGHT; // TOMGetVideoModeHeight();
        const size_t alignedWidth = (width + 3) & ~3;
        const size_t bufferSize = alignedWidth * height * sizeof(uint32_t);

        buffer->videoBuffer = (uint32_t *)calloc(1, bufferSize);
        memset(buffer->videoBuffer, 0, bufferSize);

        buffer->sampleBuffer = (uint16_t *)malloc(BUFMAX * sizeof(uint16_t));
        memset(buffer->sampleBuffer, 0, BUFMAX * sizeof(uint16_t));

        strncpy(buffer->label, label, 256);
        buffer->written = false;
        buffer->read = false;
        buffer->frameNumber = 0;
    }
    return buffer;
}

static const size_t update_audio_batch(const int16_t *data, const size_t frames) {
    __strong PVJaguarGameCoreBridge* current = _current;
    if(current == nil)
        return 0;

    id rb = [current ringBufferAtIndex:0];
    if (rb && [rb respondsToSelector:@selector(write:size:)]) {
        return (size_t)((NSInteger (*)(id, SEL, const void *, NSInteger))objc_msgSend)(rb, @selector(write:size:), data, (NSInteger)(frames << 2));
    }
    return 0;
}

@interface PVJaguarGameCoreBridge () <ObjCBridgedCoreBridge>
{
    @public
    int videoWidth, videoHeight, audioBufferSize;
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

//__attribute__((objc_direct_members))
__attribute__((visibility("default")))
@implementation PVJaguarGameCoreBridge
//@synthesize valueChangedHandler;

+ (instancetype)sharedInstance {
    static PVJaguarGameCoreBridge *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[PVJaguarGameCoreBridge alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        videoWidth = VIDEO_WIDTH;
        videoHeight = VIDEO_HEIGHT;
        sampleRate = AUDIO_SAMPLERATE;

        dispatch_queue_attr_t priorityAttribute = dispatch_queue_attr_make_with_qos_class( DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0);
        audioQueue = dispatch_queue_create("com.provenance.jaguar.audio", priorityAttribute);
        videoQueue = dispatch_queue_create("com.provenance.jaguar.video", priorityAttribute);
        renderGroup = dispatch_group_create();
//
        waitToBeginFrameSemaphore = dispatch_semaphore_create(0);

        // TODO: Add option getter
//        multithreaded = self.virtualjaguar_mutlithreaded;

//        buffer = (uint32_t*)calloc(sizeof(uint32_t), videoWidth * videoHeight);
//        sampleBuffer = (uint16_t *)malloc(BUFMAX * sizeof(uint16_t));
//        memset(sampleBuffer, 0, BUFMAX * sizeof(uint16_t));
    }

    _current = self;

    return self;
}

-  (void)loadFileAtPath:(NSString *)path error:(NSError * __nullable __autoreleasing * __nullable)error {
    NSString *batterySavesDirectory = self.batterySavesPath;

    if([batterySavesDirectory length] != 0) {
        NSError *fileError;
        [[NSFileManager defaultManager] createDirectoryAtPath:batterySavesDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&fileError];
        if (fileError != nil) {
            if (error) *error = fileError;
            return;
        }
    }

    self->videoWidth = 320;
    self->videoHeight = 240;

    JaguarInit();

    self->videoWidth = TOMGetVideoModeWidth();
    self->videoHeight = TOMGetVideoModeHeight();

    const size_t alignedWidth = (self->videoWidth + 3) & ~3;

    struct JagBuffer *buffer1 = initJagBuffer("a");
    struct JagBuffer *buffer2 = initJagBuffer("b");

    buffer1->next = buffer2;
    buffer2->next = buffer1;

    self->videoBuffer = buffer1;

    JaguarSetScreenPitch(alignedWidth);
    JaguarSetScreenBuffer(videoBuffer->videoBuffer);

    ILOG(@"Jaguar dimensions - Content: %dx%d, Buffer: %dx%d, Pitch: %d",
         self->videoWidth, self->videoHeight,
         VIDEO_WIDTH, VIDEO_HEIGHT,
         alignedWidth);

    for (int y = 0; y < self->videoHeight; y++) {
        for (int x = 0; x < self->videoWidth; x++) {
            uint32_t color = ((x / 32) % 2 == 0) ? 0xFF0000FF : 0xFF00FF00;
            videoBuffer->videoBuffer[y * self->videoWidth + x] = color;
        }
    }

    sampleBuffer = (uint16_t *)malloc(BUFMAX * sizeof(uint16_t));
    memset(sampleBuffer, 0, BUFMAX * sizeof(uint16_t));

    vjs.hardwareTypeNTSC = true;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *biosPath = [self.BIOSPath stringByAppendingPathComponent:@"jagboot.rom"];
    BOOL externalBIOS = NO;
    if ([fm fileExistsAtPath:biosPath] && self.virtualjaguar_bios) {
        ILOG(@"Using bios at path %@", biosPath);
        vjs.useJaguarBIOS = true;
        externalBIOS = YES;
    } else {
        ILOG(@"No external BIOS found. Using no BIOS.");
        vjs.useJaguarBIOS = false;
    }

    vjs.useFastBlitter = self.virtualjaguar_usefastblitter;

    retro_set_audio_sample_batch_jaguar((unsigned long (*)(const short *, unsigned long))update_audio_batch);

    JaguarInit();

    self->videoWidth = TOMGetVideoModeWidth();
    self->videoHeight = TOMGetVideoModeHeight();
    JaguarSetScreenPitch(self->videoWidth);

    ILOG(@"Jaguar video dimensions: %dx%d", self->videoWidth, self->videoHeight);

    if (!externalBIOS) {
        memcpy(jagMemSpace + 0xE00000, jaguarBootROM, 0x20000);
    } else {
        NSData *data = [NSData dataWithContentsOfFile:biosPath];
        memcpy(jagMemSpace + 0xE00000, data.bytes, data.length);
    }

    [self loadSoftware:path];
}

- (BOOL)loadSoftware:(NSString *)path {
    NSData* romData = [NSData dataWithContentsOfFile:path];

    const void * _Nullable biosPointer = jaguarBootROM;
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *biosPath = [self.BIOSPath stringByAppendingPathComponent:@"jagboot.rom"];
    if ([fm fileExistsAtPath:biosPath]) {
        biosPointer = [NSData dataWithContentsOfFile:biosPath].bytes;
    }

    memcpy(jagMemSpace + 0xE00000, biosPointer, 0x20000);

    SET32(jaguarMainRAM, 0, 0x00200000);
    BOOL cartridgeLoaded = JaguarLoadFile((uint8_t*)romData.bytes, romData.length);

    JaguarReset();

    [self initVideo];

    if (!vjs.useJaguarBIOS) {
        SET32(jaguarMainRAM, 4, jaguarRunAddress);
    }

    m68k_pulse_reset();

    self->audioBufferSize = vjs.hardwareTypeNTSC ? BUFNTSC : BUFPAL;
    self->frameTime = vjs.hardwareTypeNTSC ? 1.0/60.0 : 1.0/50.0;

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

#if !TARGET_OS_WATCH
    if (self.controller1 || self.controller2) {
        [self pollControllers];
    }
#endif

    if (self->multithreaded) {
        dispatch_time_t killTime = dispatch_time(DISPATCH_TIME_NOW, self->frameTime * NSEC_PER_SEC);

        struct JagBuffer*videoBuffer = self->videoBuffer;

        MAKEWEAK(self);
        dispatch_group_enter(self->renderGroup);
        dispatch_async(self->videoQueue, ^{
            MAKESTRONG(self);
            JaguarExecuteNew();
            videoBuffer->written = YES;
            videoBuffer->frameNumber = currentFrame;
            dispatch_semaphore_signal(strongself->waitToBeginFrameSemaphore);
            dispatch_group_leave(strongself->renderGroup);
        });

        dispatch_group_enter(self->renderGroup);
        dispatch_async(self->audioQueue, ^{
            MAKESTRONG(self);
            dispatch_semaphore_wait(strongself->waitToBeginFrameSemaphore, killTime);
            SoundCallback(NULL, ( uint16_t *) strongself->videoBuffer->sampleBuffer, strongself->audioBufferSize);
            dispatch_group_leave(strongself->renderGroup);
        });
    } else {
        JaguarExecuteNew();
        SoundCallback(NULL, sampleBuffer, audioBufferSize);
    }
}

- (void)executeFrame {
    [self executeFrameSkippingFrame:NO];
}

- (void)initVideo {
    JaguarSetScreenPitch(self->videoWidth);
    JaguarSetScreenBuffer(self->videoBuffer->videoBuffer);
    for (int i = 0; i < self->videoWidth * self->videoHeight; ++i) {
        self->videoBuffer->videoBuffer[i] = 0xFF00FFFF;
        self->videoBuffer->next->videoBuffer[i] = 0xFF00FFFF;
    }
}

- (void)swapBuffers {
    //    printf("swap buffers: current: %s, count: %i, read: %s, written: %s, next: read: %s, written: %s",
    //           videoBuffer->label,
    //           videoBuffer->frameNumber,
    //           BS(videoBuffer->read),
    //           BS(videoBuffer->written),
    //           BS(videoBuffer->next->read),
    //           BS(videoBuffer->next->written));

    // TODO: Should we not swap _jagVideoBuffer with the two jagBuffers init'd above?
    // perhaps not since JagBuffer does contain a nextPointer, so in that case
    // remove the double pointers?
    // Also need to test with doubleBuffer to true then @JoeMatt

    // If resolution changes, we need to update the pitch
    if ((tomWidth != videoWidth || tomHeight != videoHeight) && tomWidth > 0 && tomHeight > 0) {
        JaguarSetScreenPitch(videoWidth);
        videoWidth = tomWidth;
        videoHeight = tomHeight;
    }

    videoBuffer->read = YES;
    videoBuffer = videoBuffer->next;
    videoBuffer->written = NO;
    videoBuffer->read = NO;
    JaguarSetScreenBuffer(videoBuffer->videoBuffer);
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

    // wait on main to release buffer memory
//    dispatch_sync(dispatch_get_main_queue(), ^{
        struct JagBuffer* ab = self->videoBuffer;

        if(ab != nil) {
            struct JagBuffer* next = self->videoBuffer->next;

            while(next->next != ab) {
                struct JagBuffer* temp = next->next;
                free(next);
                next = temp;
            };
            free(ab);
        }
        [self delloc_sampleBuffer];

        self->videoBuffer = nil;
//    });
}

-(void)delloc_sampleBuffer {
    if (sampleBuffer != nil) {
        free(sampleBuffer);
    }
    sampleBuffer = nil;
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
    if (self->videoBuffer == nil) {
        return NULL;
    }
    return self->videoBuffer->videoBuffer;
}

- (double)audioSampleRate
{
    return self->sampleRate;
}

- (NSTimeInterval)frameInterval
{
    return vjs.hardwareTypeNTSC ? 60 : 50;
}

- (NSUInteger)channelCount
{
    return AUDIO_CHANNELS;
}

#if !TARGET_OS_WATCH

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
        uint8_t *currentController = NULL;

        if (playerIndex == 0 && self.controller1) {
            controller = self.controller1;
            currentController = joypad0Buttons;
        }
        else if (playerIndex == 1 && self.controller2) {
            controller = self.controller2;
            currentController = joypad1Buttons;
        }

        if (currentController == NULL) {
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

            //numbers
            currentController[[self getIndexForPVJaguarButton:PVJaguarButton1]] = gamepad.rightThumbstick.left.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButton2]] = gamepad.rightThumbstick.up.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButton3]] = gamepad.rightThumbstick.right.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButton4]] = gamepad.rightThumbstick.down.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButton5]] = gamepad.leftThumbstickButton != nil && gamepad.leftThumbstickButton.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButton6]] = gamepad.rightThumbstickButton != nil && gamepad.rightThumbstickButton.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButton7]] =  gamepad.leftShoulder.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButton8]] = gamepad.buttonY.isPressed ? 0xFF : 0x00;
            currentController[[self getIndexForPVJaguarButton:PVJaguarButton9]] = gamepad.rightShoulder.isPressed ? 0xFF : 0x00;
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

#endif

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

- (BOOL)loadSaveFile:(NSString *)path forType:(int)type {
    size_t size = retro_get_memory_size(type);
    void *ramData = retro_get_memory_data(type);

    if (size == 0 || !ramData)
        return false;

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || ![data length])
        return false;

    [data getBytes:ramData length:size];
    return true;
}

- (BOOL)writeSaveFile:(NSString *)path forType:(int)type {
    size_t size = retro_get_memory_size(type);
    void *ramData = retro_get_memory_data(type);

    if (!ramData || size == 0)
        return false;

    NSData *data = [NSData dataWithBytes:ramData length:size];
    return [data writeToFile:path atomically:YES];
}

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *)) __attribute__((noescape)) block {
    BOOL wasPaused = [self isEmulationPaused];
    [self setPauseEmulation:true];

    size_t stateSize = retro_serialize_size();
    void *stateData = malloc(stateSize);
    BOOL status = NO;

    if (stateData) {
        status = retro_serialize(stateData, stateSize);
        if (status) {
            NSData *data = [NSData dataWithBytesNoCopy:stateData length:stateSize freeWhenDone:YES];
            status = [data writeToFile:fileName atomically:YES];
        } else {
            free(stateData);
        }
    }

    [self setPauseEmulation:wasPaused];
    if (block) {
        NSError *error = nil;
        if (!status) {
            error = [NSError errorWithDomain:@"org.provenance.GameCore.ErrorDomain"
                                        code:-5
                                    userInfo:@{
                NSLocalizedDescriptionKey : @"Jaguar: Could not save state.",
                NSFilePathErrorKey : fileName
            }];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            block(status, error);
        });
    }
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *)) __attribute__((noescape)) block {
    BOOL wasPaused = [self isEmulationPaused];
    [self setPauseEmulation:true];

    NSData *data = [NSData dataWithContentsOfFile:fileName];
    BOOL status = NO;

    if (data && [data length] > 0) {
        status = retro_unserialize([data bytes], [data length]);
    }

    [self setPauseEmulation:wasPaused];
    if (block) {
        NSError *error = nil;
        if (!status) {
            error = [NSError errorWithDomain:@"org.provenance.GameCore.ErrorDomain"
                                        code:-5
                                    userInfo:@{
                NSLocalizedDescriptionKey : @"Jaguar: Could not load state.",
                NSFilePathErrorKey : fileName
            }];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            block(status, error);
        });
    }
}

-(BOOL)supportsSaveStates {
    return YES;
}

#pragma mark - Cheats

- (void)setCheat:(NSString *)code setType:(NSString *)type setEnabled:(BOOL)enabled {
    retro_cheat_set(0, enabled, [code UTF8String]);
}

- (BOOL)setCheat:(NSString *)code setType:(NSString *)type setCodeType:(NSString *)codeType
        setIndex:(UInt8)cheatIndex setEnabled:(BOOL)enabled error:(NSError **)error {
    retro_cheat_set(cheatIndex, enabled, [code UTF8String]);
    return YES;
}

- (void)resetCheatCodes {
    retro_cheat_reset();
}

#pragma mark - RetroAchievements

- (NSUInteger)ramSize {
    return retro_get_memory_size(RETRO_MEMORY_SYSTEM_RAM);
}

- (const void *)ramPointer {
    return retro_get_memory_data(RETRO_MEMORY_SYSTEM_RAM);
}

-(void)virtualjaguar_bios:(BOOL)value {
    vjs.useJaguarBIOS = value;
}

-(void)virtualjaguar_usefastblitter:(BOOL)value {
    vjs.useFastBlitter = value;
}

-(void)virtualjaguar_pal:(BOOL)value {
    vjs.hardwareTypeNTSC = !value;
}

- (BOOL)rendersToOpenGL {
    return false;
}

@end

@implementation PVJaguarGameCoreBridge (PVJaguarSystemResponderClient)

- (void)didPushJaguarButton:(PVJaguarButton)button forPlayer:(NSInteger)player {
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
        long index = [self getIndexForPVJaguarButton:button];
        currentController[index] = 0x01;
    }
}

- (void)didReleaseJaguarButton:(PVJaguarButton)button forPlayer:(NSInteger)player {
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

@end
