//
//  JaguarBuffer.h
//
//
//  Created by Joseph Mattiello on 5/27/24.
//

#pragma once

#ifndef JaguarBuffer_h
#define JaguarBuffer_h

#include <stdint.h>
#include <stdbool.h>

#define AUDIO_BIT_DEPTH 16
#define AUDIO_CHANNELS 2
#define AUDIO_SAMPLERATE 48000
#define BUFPAL  1920
#define BUFNTSC 1600
#define BUFMAX 2048
#define VIDEO_WIDTH 1024
#define VIDEO_HEIGHT 512

extern uint8_t joypad0Buttons[21];
extern uint8_t joypad1Buttons[21];

typedef struct JagBuffer {
    char label[256];
    uint32_t *videoBuffer;
    uint16_t *sampleBuffer;

    bool read;
    bool written;
    bool audio_read;
    bool audio_written;

    unsigned long frameNumber;
    struct JagBuffer* next;
} JagBuffer;

static inline void SetJoyPadValue(uint32_t joypad, int index, uint8_t value) {
    if(joypad == 0) {
        joypad0Buttons[index] = value;
    } else {
        joypad1Buttons[index] = value;
    }
}

#endif /* JaguarBuffer_h */
