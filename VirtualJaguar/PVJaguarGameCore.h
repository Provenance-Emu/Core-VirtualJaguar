/*
 Copyright (c) 2010 OpenEmu Team
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * Neither the name of the OpenEmu Team nor the
 names of its contributors may be used to endorse or promote products
 derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITYj AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


@import Foundation;
@import PVCoreBridge;
@import PVVirtualJaguarSwift;
@import PVVirtualJaguarC;
#import <PVCoreObjCBridge/PVCoreObjCBridge.h>

#define AUDIO_BIT_DEPTH 16
#define AUDIO_CHANNELS 2
#define AUDIO_SAMPLERATE 48000
#define BUFPAL  1920
#define BUFNTSC 1600
#define BUFMAX (2048 * sizeof(uint16_t))
#define VIDEO_WIDTH 1024
#define VIDEO_HEIGHT 512

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

extern uint16_t eeprom_ram[];

int doom_res_hack=0; // Doom Hack to double pixel if pwidth==8 (163*2)

@interface PVJaguarGameCore (ObjCCoreBridge) <ObjCCoreBridge>

// MARK: Core
- (void)loadFileAtPath:(NSString *)path error:(NSError * __autoreleasing *)error;
- (void)executeFrameSkippingFrame:(BOOL)skip;
- (void)executeFrame;
- (void)swapBuffers;
- (void)stopEmulation;
- (void)resetEmulation;

// MARK: Output
- (CGRect)screenRect;
- (const void *)videoBuffer;
- (NSTimeInterval)frameInterval;
- (BOOL)rendersToOpenGL;


// MARK: Input
- (void)pollControllers;

// MARK: Save States
- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *)) __attribute__((noescape)) block;
- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *)) __attribute__((noescape)) block;


@end
//
//@interface PVJaguarGameCoreObjCBridge : PVCoreObjCBridge
//@end

JagBuffer* initJagBuffer(const char *label);


NS_HEADER_AUDIT_END(nullability, sendability)
