#pragma once

#include <algorithm>
#include <cmath>
#include <vector>

namespace vc {

inline float dbToLinear(float db) { return std::pow(10.0f, db / 20.0f); }

// RBJ cookbook biquads, transposed direct form II.
struct Biquad {
    float b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0, z1 = 0, z2 = 0;

    inline float process(float x) {
        const float y = b0 * x + z1;
        z1 = b1 * x - a1 * y + z2;
        z2 = b2 * x - a2 * y;
        return y;
    }

    void run(float *x, int n) {
        for (int i = 0; i < n; ++i) x[i] = process(x[i]);
    }

    void set(double B0, double B1, double B2, double A0, double A1, double A2) {
        b0 = float(B0 / A0); b1 = float(B1 / A0); b2 = float(B2 / A0);
        a1 = float(A1 / A0); a2 = float(A2 / A0);
    }

    void lowpass(double f, double sr, double q = 0.707) {
        const double w = 2 * M_PI * f / sr, c = std::cos(w), alpha = std::sin(w) / (2 * q);
        set((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + alpha, -2 * c, 1 - alpha);
    }

    void highpass(double f, double sr, double q = 0.707) {
        const double w = 2 * M_PI * f / sr, c = std::cos(w), alpha = std::sin(w) / (2 * q);
        set((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha);
    }

    void peak(double f, double sr, double q, double db) {
        const double A = std::pow(10.0, db / 40.0);
        const double w = 2 * M_PI * f / sr, c = std::cos(w), alpha = std::sin(w) / (2 * q);
        set(1 + alpha * A, -2 * c, 1 - alpha * A, 1 + alpha / A, -2 * c, 1 - alpha / A);
    }

    void lowShelf(double f, double sr, double db) {
        const double A = std::pow(10.0, db / 40.0);
        const double w = 2 * M_PI * f / sr, c = std::cos(w);
        const double k = 2 * std::sqrt(A) * std::sin(w) / 2 * M_SQRT2;
        set(A * ((A + 1) - (A - 1) * c + k), 2 * A * ((A - 1) - (A + 1) * c), A * ((A + 1) - (A - 1) * c - k),
            (A + 1) + (A - 1) * c + k, -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - k);
    }

    void highShelf(double f, double sr, double db) {
        const double A = std::pow(10.0, db / 40.0);
        const double w = 2 * M_PI * f / sr, c = std::cos(w);
        const double k = 2 * std::sqrt(A) * std::sin(w) / 2 * M_SQRT2;
        set(A * ((A + 1) + (A - 1) * c + k), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - k),
            (A + 1) - (A - 1) * c + k, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - k);
    }
};

// Mono Freeverb (Jezar's public-domain design).
class Reverb {
public:
    void init(double sr) {
        static const int combLen[8] = {1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617};
        static const int allpassLen[4] = {556, 441, 341, 225};
        const double scale = sr / 44100.0;
        for (int i = 0; i < 8; ++i) combs[i].buf.assign(size_t(combLen[i] * scale), 0.0f);
        for (int i = 0; i < 4; ++i) allpasses[i].buf.assign(size_t(allpassLen[i] * scale), 0.0f);
    }

    inline float process(float x, float feedback) {
        const float in = x * 0.015f;
        float out = 0;
        for (auto &c : combs) out += c.process(in, feedback);
        for (auto &a : allpasses) out = a.process(out);
        return out;
    }

private:
    struct Comb {
        std::vector<float> buf;
        size_t i = 0;
        float store = 0;
        inline float process(float x, float feedback) {
            const float y = buf[i];
            store = y * 0.7f + store * 0.3f;
            buf[i] = x + store * feedback;
            if (++i == buf.size()) i = 0;
            return y;
        }
    };
    struct Allpass {
        std::vector<float> buf;
        size_t i = 0;
        inline float process(float x) {
            const float b = buf[i];
            buf[i] = x + b * 0.5f;
            if (++i == buf.size()) i = 0;
            return b - x;
        }
    };
    Comb combs[8];
    Allpass allpasses[4];
};

} // namespace vc
