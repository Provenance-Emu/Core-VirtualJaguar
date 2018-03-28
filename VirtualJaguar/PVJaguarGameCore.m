#import <PVSupport/OERingBuffer.h>
#import <PVSupport/DebugUtils.h>

#import <PVSupport/PVSupport-Swift.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>
#import "PVJaguarGameCore.h"
#import "jaguar.h"
#import "file.h"
#import "jagbios.h"
#import "jagbios2.h"
#include "memory.h"
#include "log.h"
#include "tom.h"
#include "dsp.h"
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
    
    NSData* romData = [NSData dataWithContentsOfFile:path];

    videoWidth           = 320;
    videoHeight          = 240;
    buffer  = (uint32_t *)calloc(sizeof(uint32_t), 1024 * 512);
    sampleBuffer = (uint16_t *)malloc(BUFMAX * sizeof(uint16_t)); //found in dac.h
    memset(sampleBuffer, 0, BUFMAX * sizeof(uint16_t));
    
//    //LogInit("vj.log");                                      // initialize log file for debugging
    vjs.hardwareTypeNTSC = true;
    
    //TODO: Make these core options
    vjs.useJaguarBIOS = false;
    vjs.useFastBlitter = false;

    JaguarInit();                                             // set up hardware
    memcpy(jagMemSpace + 0xE00000, (vjs.biosType == BT_K_SERIES ? jaguarBootROM : jaguarBootROM2), 0x20000); // Use the stock BIOS
    [self initVideo];
    SET32(jaguarMainRAM, 0, 0x00200000);                      // set up stack

    JaguarLoadFile((uint8_t*)romData.bytes, romData.length);   // load rom
    JaguarReset();
    
    return YES;
}

- (void)executeFrame
{
#if PARALLEL_GFX_AUDIO_CALLS
    dispatch_group_enter(renderGroup);
    dispatch_async(videoQueue, ^{
        JaguarExecuteNew();
        dispatch_group_leave(renderGroup);
    });
    
    dispatch_group_wait(renderGroup, DISPATCH_TIME_FOREVER);

    NSUInteger bufferSize = vjs.hardwareTypeNTSC == 1 ? BUFNTSC : BUFPAL;
    // Don't block the frame draw waiting for audio
    dispatch_group_enter(renderGroup);
    dispatch_async(audioQueue, ^{
        SDLSoundCallback(NULL, sampleBuffer, bufferSize);
        [[_current ringBufferAtIndex:0] write:sampleBuffer maxLength:bufferSize*2];
        dispatch_group_leave(renderGroup);
    });
#else
    JaguarExecuteNew();
    NSUInteger bufferSize = vjs.hardwareTypeNTSC == 1 ? BUFNTSC : BUFPAL;

    SDLSoundCallback(NULL, sampleBuffer, bufferSize);
    [[_current ringBufferAtIndex:0] write:sampleBuffer maxLength:bufferSize*2];
#endif
 }

- (void)initVideo
{
    JaguarSetScreenPitch(videoWidth);
    JaguarSetScreenBuffer(buffer);
    for (int i = 0; i < videoWidth * videoHeight; ++i)
        buffer[i] = 0xFF00FFFF;
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
    return 60;
}

- (NSUInteger)channelCount
{
    return 2;
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

@end
