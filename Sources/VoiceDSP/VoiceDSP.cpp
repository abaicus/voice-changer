#include "VoiceDSP.h"

#include "DriftRing.h"
#include "Effects.h"
#include "vendor/signalsmith-stretch/signalsmith-stretch.h"

#include <atomic>
#include <cstring>

namespace {

constexpr int kMaxBlock = 4096;
constexpr int kMaxChannels = 8;

class Processor {
public:
    explicit Processor(double sampleRate) : sr(sampleRate), stretch(1), scratch(kMaxBlock) {
        // 50 ms analysis block: enough periods of a low voice, and it is the latency we pay.
        stretch.configure(1, int(sr * 0.05), int(sr * 0.0125));
        reverb.init(sr);
        envRelease = float(std::exp(-1.0 / (sr * 0.05)));
        gateAttack = float(1.0 - std::exp(-1.0 / (sr * 0.003)));
        gateRelease = float(1.0 - std::exp(-1.0 / (sr * 0.12)));
        gainSmooth = float(1.0 - std::exp(-1.0 / (sr * 0.02)));
    }

    // `in` and `out` must not alias; n <= kMaxBlock.
    void process(const float *in, float *out, int n, const vc_params &p) {
        if (p.bypass) {
            std::memcpy(out, in, n * sizeof(float));
            return;
        }
        float *gated = scratch.data();
        gate(in, gated, n, p);
        shift(gated, out, n, p);

        if (p.robotMix > 0.001f) {
            const double inc = 2 * M_PI * std::clamp(p.robotHz, 20.0f, 2000.0f) / sr;
            const float mix = std::min(p.robotMix, 1.0f);
            for (int i = 0; i < n; ++i) {
                out[i] *= (1 - mix) + mix * float(std::sin(robotPhase));
                robotPhase += inc;
                if (robotPhase > 2 * M_PI) robotPhase -= 2 * M_PI;
            }
        }

        if (p.distortion > 0.001f) {
            const float drive = 1 + std::min(p.distortion, 1.0f) * 30;
            const float makeup = 1 / std::sqrt(drive);
            for (int i = 0; i < n; ++i) out[i] = std::tanh(out[i] * drive) * makeup;
        }

        equalize(out, n, p);

        if (p.reverbMix > 0.001f) {
            const float mix = std::min(p.reverbMix, 1.0f);
            const float feedback = 0.7f + 0.28f * std::clamp(p.reverbSize, 0.0f, 1.0f);
            for (int i = 0; i < n; ++i)
                out[i] = out[i] * (1 - 0.6f * mix) + reverb.process(out[i], feedback) * mix * 1.5f;
        }

        const float targetGain = vc::dbToLinear(p.outputGainDb);
        for (int i = 0; i < n; ++i) {
            outGain += (targetGain - outGain) * gainSmooth;
            const float y = out[i] * outGain, mag = std::fabs(y);
            out[i] = mag <= 0.7f ? y : std::copysign(0.7f + 0.3f * std::tanh((mag - 0.7f) / 0.3f), y);
        }
    }

private:
    void gate(const float *in, float *out, int n, const vc_params &p) {
        if (p.gateThresholdDb <= -79.5f) {
            std::memcpy(out, in, n * sizeof(float));
            gateGain = 1;
            return;
        }
        const float threshold = vc::dbToLinear(p.gateThresholdDb);
        for (int i = 0; i < n; ++i) {
            const float mag = std::fabs(in[i]);
            gateEnv = mag > gateEnv ? mag : gateEnv * envRelease;
            if (gateEnv > threshold) gateOpen = true;
            else if (gateEnv < threshold * 0.5f) gateOpen = false;
            gateGain += ((gateOpen ? 1.0f : 0.0f) - gateGain) * (gateOpen ? gateAttack : gateRelease);
            out[i] = in[i] * gateGain;
        }
    }

    void shift(float *in, float *out, int n, const vc_params &p) {
        const bool wanted = std::fabs(p.pitchSemitones) > 0.01f || std::fabs(p.formantSemitones) > 0.01f;
        if (!wanted) {
            std::memcpy(out, in, n * sizeof(float));
            shifting = false;
            return;
        }
        if (!shifting) stretch.reset();
        shifting = true;
        if (p.pitchSemitones != pitch || p.formantSemitones != formant) {
            pitch = p.pitchSemitones;
            formant = p.formantSemitones;
            stretch.setTransposeSemitones(pitch);
            // compensatePitch keeps the vocal tract where it was, so the two sliders are independent.
            stretch.setFormantSemitones(formant, true);
        }
        float *ins[1] = {in}, *outs[1] = {out};
        stretch.process(ins, n, outs, n);
    }

    void equalize(float *x, int n, const vc_params &p) {
        const double nyquistGuard = sr * 0.45;
        if (!eqReady || p.lowCutHz != eq.lowCutHz || p.highCutHz != eq.highCutHz || p.lowGainDb != eq.lowGainDb ||
            p.midGainDb != eq.midGainDb || p.highGainDb != eq.highGainDb) {
            eq = p;
            eqReady = true;
            highpass.highpass(std::clamp(double(p.lowCutHz), 10.0, nyquistGuard), sr);
            lowpass.lowpass(std::clamp(double(p.highCutHz), 100.0, nyquistGuard), sr);
            low.lowShelf(200, sr, p.lowGainDb);
            mid.peak(1000, sr, 0.9, p.midGainDb);
            high.highShelf(std::min(5000.0, nyquistGuard), sr, p.highGainDb);
        }
        if (p.lowCutHz > 25) highpass.run(x, n);
        if (p.highCutHz < 19000 && p.highCutHz < nyquistGuard) lowpass.run(x, n);
        if (std::fabs(p.lowGainDb) > 0.05f) low.run(x, n);
        if (std::fabs(p.midGainDb) > 0.05f) mid.run(x, n);
        if (std::fabs(p.highGainDb) > 0.05f) high.run(x, n);
    }

    double sr;
    signalsmith::stretch::SignalsmithStretch<float> stretch;
    std::vector<float> scratch;
    vc::Reverb reverb;
    vc::Biquad highpass, lowpass, low, mid, high;
    vc_params eq{};
    bool eqReady = false, shifting = false, gateOpen = true;
    float pitch = 0, formant = 0;
    float gateEnv = 0, gateGain = 1, outGain = 1;
    float envRelease, gateAttack, gateRelease, gainSmooth;
    double robotPhase = 0;
};

float blockPeak(const float *x, int n) {
    float peak = 0;
    for (int i = 0; i < n; ++i) peak = std::max(peak, std::fabs(x[i]));
    return peak;
}

void raisePeak(std::atomic<float> &slot, float peak) {
    if (peak > slot.load(std::memory_order_relaxed)) slot.store(peak, std::memory_order_relaxed);
}

} // namespace

struct vc_engine {
    explicit vc_engine(double sampleRate) : sr(sampleRate), processor(sampleRate), mono(kMaxBlock), processed(kMaxBlock) {
        for (auto &ring : rings) ring.init(sampleRate);
        mixSmooth = float(1.0 - std::exp(-1.0 / (sampleRate * 0.05)));
    }

    // Sums all channels, then divides by the number that carry signal, so a mic on
    // one input of a stereo interface is not halved and a dual-mono mic is not doubled.
    void mixDown(const AudioBufferList *abl, uint32_t offset, int n) {
        std::memset(mono.data(), 0, n * sizeof(float));
        int channel = 0;
        float loudest = 0;
        for (UInt32 b = 0; b < abl->mNumberBuffers; ++b) {
            const AudioBuffer &buffer = abl->mBuffers[b];
            const int stride = int(buffer.mNumberChannels);
            const float *data = static_cast<const float *>(buffer.mData);
            if (!data) continue;
            for (int c = 0; c < stride; ++c, ++channel) {
                const float *src = data + size_t(offset) * stride + c;
                float peak = 0;
                for (int i = 0; i < n; ++i) {
                    const float s = src[size_t(i) * stride];
                    mono[i] += s;
                    peak = std::max(peak, std::fabs(s));
                }
                if (channel < kMaxChannels) {
                    const float decay = float(std::exp(-double(n) / (sr * 5.0)));
                    channelEnv[channel] = std::max(peak, channelEnv[channel] * decay);
                    loudest = std::max(loudest, channelEnv[channel]);
                }
            }
        }
        const int tracked = std::min(channel, kMaxChannels);
        int active = 0;
        for (int c = 0; c < tracked; ++c)
            if (channelEnv[c] > loudest * 0.05f) ++active;
        if (active == 0) active = std::max(channel, 1);
        const float target = 1.0f / float(active);
        for (int i = 0; i < n; ++i) {
            mixGain += (target - mixGain) * mixSmooth;
            mono[i] *= mixGain;
        }
    }

    double sr;
    Processor processor;
    vc::DriftRing rings[2];
    std::vector<float> mono, processed;
    float channelEnv[kMaxChannels] = {};
    float mixGain = 1, mixSmooth = 0;

    std::atomic_flag paramLock = ATOMIC_FLAG_INIT;
    vc_params pending{};
    vc_params active{};

    std::atomic<float> inputPeak{0}, outputPeak{0}, monitorVolume{1};
    float monitorGain = 1;
};

vc_engine *vc_create(double sampleRate) { return new vc_engine(sampleRate); }
void vc_destroy(vc_engine *engine) { delete engine; }

void vc_set_params(vc_engine *engine, const vc_params *params) {
    while (engine->paramLock.test_and_set(std::memory_order_acquire)) {}
    engine->pending = *params;
    engine->paramLock.clear(std::memory_order_release);
}

void vc_set_monitor_volume(vc_engine *engine, float volume) {
    engine->monitorVolume.store(volume, std::memory_order_relaxed);
}

void vc_capture(vc_engine *engine, const AudioBufferList *input, uint32_t frames) {
    // Never wait on the audio thread: if the UI holds the lock, keep last block's params.
    if (!engine->paramLock.test_and_set(std::memory_order_acquire)) {
        engine->active = engine->pending;
        engine->paramLock.clear(std::memory_order_release);
    }
    for (uint32_t offset = 0; offset < frames; offset += kMaxBlock) {
        const int n = int(std::min<uint32_t>(kMaxBlock, frames - offset));
        float *mono = engine->mono.data(), *out = engine->processed.data();
        engine->mixDown(input, offset, n);
        raisePeak(engine->inputPeak, blockPeak(mono, n));
        engine->processor.process(mono, out, n, engine->active);
        raisePeak(engine->outputPeak, blockPeak(out, n));
        for (auto &ring : engine->rings) ring.write(out, uint32_t(n));
    }
}

void vc_render(vc_engine *engine, int output, AudioBufferList *buffers, uint32_t frames) {
    if (buffers->mNumberBuffers == 0 || !buffers->mBuffers[0].mData) return;
    float *out = static_cast<float *>(buffers->mBuffers[0].mData);
    engine->rings[output == VC_OUTPUT_MONITOR ? 1 : 0].read(out, frames);
    if (output == VC_OUTPUT_MONITOR) {
        const float target = engine->monitorVolume.load(std::memory_order_relaxed);
        for (uint32_t i = 0; i < frames; ++i) {
            engine->monitorGain += (target - engine->monitorGain) * 0.002f;
            out[i] *= engine->monitorGain;
        }
    }
    for (UInt32 b = 1; b < buffers->mNumberBuffers; ++b)
        if (buffers->mBuffers[b].mData) std::memcpy(buffers->mBuffers[b].mData, out, frames * sizeof(float));
}

void vc_read_levels(vc_engine *engine, float *inputPeak, float *outputPeak) {
    *inputPeak = engine->inputPeak.exchange(0, std::memory_order_relaxed);
    *outputPeak = engine->outputPeak.exchange(0, std::memory_order_relaxed);
}

uint32_t vc_underruns(vc_engine *engine, int output) {
    return engine->rings[output == VC_OUTPUT_MONITOR ? 1 : 0].underruns();
}
