#pragma once

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>

namespace vc {

// Single-writer/single-reader ring. The reader resamples by up to ±0.5% to
// absorb clock drift between the capture device and the playback device.
class DriftRing {
public:
    void init(double sampleRate) {
        sr = sampleRate;
        size_t capacity = 1;
        while (capacity < sampleRate) capacity <<= 1;
        buf.assign(capacity, 0.0f);
        mask = capacity - 1;
    }

    void write(const float *x, uint32_t n) {
        const uint64_t w = writePos.load(std::memory_order_relaxed);
        for (uint32_t i = 0; i < n; ++i) buf[(w + i) & mask] = x[i];
        if (n > maxWrite.load(std::memory_order_relaxed)) maxWrite.store(n, std::memory_order_relaxed);
        writePos.store(w + n, std::memory_order_release);
    }

    void read(float *out, uint32_t n) {
        maxRead = std::max(maxRead, n);
        const double maxW = maxWrite.load(std::memory_order_relaxed);
        const double target = maxRead + maxW + sr * 0.003;
        const uint64_t w = writePos.load(std::memory_order_acquire);
        double fill = double(w) - readPos;

        const bool overflowed = fill > double(buf.size()) - maxW - 8 || fill > target + sr * 0.2;
        if (!primed || overflowed) {
            if (fill < target) {
                std::memset(out, 0, n * sizeof(float));
                return;
            }
            readPos = double(w) - target;
            fill = fillSmooth = target;
            primed = true;
        }
        if (fill < n * 1.006 + 3) {
            std::memset(out, 0, n * sizeof(float));
            primed = false;
            readPos = double(w);
            underrunCount.fetch_add(1, std::memory_order_relaxed);
            return;
        }

        fillSmooth += (fill - fillSmooth) * (1.0 - std::exp(-double(n) / sr));
        const double ratio = 1.0 + std::clamp((fillSmooth - target) / (sr * 5.0), -0.005, 0.005);

        for (uint32_t i = 0; i < n; ++i) {
            const uint64_t i0 = uint64_t(readPos);
            const float f = float(readPos - double(i0));
            const float xm1 = buf[(i0 - 1) & mask], x0 = buf[i0 & mask];
            const float x1 = buf[(i0 + 1) & mask], x2 = buf[(i0 + 2) & mask];
            const float c = (x1 - xm1) * 0.5f, v = x0 - x1, wv = c + v;
            const float a = wv + v + (x2 - x0) * 0.5f, b = wv + a;
            out[i] = ((a * f - b) * f + c) * f + x0;
            readPos += ratio;
        }
    }

    uint32_t underruns() const { return underrunCount.load(std::memory_order_relaxed); }

private:
    std::vector<float> buf;
    size_t mask = 0;
    double sr = 48000;
    std::atomic<uint64_t> writePos{0};
    std::atomic<uint32_t> maxWrite{0};
    std::atomic<uint32_t> underrunCount{0};
    // Reader-thread state.
    double readPos = 0, fillSmooth = 0;
    uint32_t maxRead = 0;
    bool primed = false;
};

} // namespace vc
