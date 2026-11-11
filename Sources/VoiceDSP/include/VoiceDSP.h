#ifndef VOICE_DSP_H
#define VOICE_DSP_H

#include <CoreAudioTypes/CoreAudioTypes.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct vc_engine vc_engine;

typedef struct {
    float pitchSemitones;
    float formantSemitones;
    float robotMix;
    float robotHz;
    float distortion;
    float lowGainDb;
    float midGainDb;
    float highGainDb;
    float lowCutHz;
    float highCutHz;
    float reverbMix;
    float reverbSize;
    float gateThresholdDb; // <= -80 disables the gate
    float outputGainDb;
    bool bypass;
} vc_params;

#define VC_OUTPUT_VIRTUAL_MIC 0
#define VC_OUTPUT_MONITOR 1

vc_engine *vc_create(double sampleRate);
void vc_destroy(vc_engine *engine);

void vc_set_params(vc_engine *engine, const vc_params *params);
void vc_set_monitor_volume(vc_engine *engine, float volume);

// Realtime-safe. Float32 input in any channel layout; output is mono.
void vc_capture(vc_engine *engine, const AudioBufferList *input, uint32_t frames);
void vc_render(vc_engine *engine, int output, AudioBufferList *buffers, uint32_t frames);

// Peak levels since the previous call.
void vc_read_levels(vc_engine *engine, float *inputPeak, float *outputPeak);
uint32_t vc_underruns(vc_engine *engine, int output);

#ifdef __cplusplus
}
#endif

#endif
