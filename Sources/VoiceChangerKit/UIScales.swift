import Foundation

public enum SliderScale {
    /// Position of `value` in `range` as 0...1, clamped.
    public static func fraction(of value: Float, in range: ClosedRange<Float>) -> Double {
        let span = Double(range.upperBound - range.lowerBound)
        guard span > 0 else { return 0 }
        return min(max(Double(value - range.lowerBound) / span, 0), 1)
    }

    /// Value for a horizontal position `x` on a track `width` wide, clamped to `range`. width <= 0 returns range.lowerBound.
    public static func value(atX x: Double, width: Double, in range: ClosedRange<Float>) -> Float {
        guard width > 0 else { return range.lowerBound }
        let t = min(max(x / width, 0), 1)
        return range.lowerBound + Float(t) * (range.upperBound - range.lowerBound)
    }

    /// `value` moved by `steps` twentieths of the range, clamped.
    public static func stepped(_ value: Float, by steps: Int, in range: ClosedRange<Float>) -> Float {
        let step = (range.upperBound - range.lowerBound) / 20
        return min(max(value + Float(steps) * step, range.lowerBound), range.upperBound)
    }
}

public enum LevelScale {
    /// Linear peak mapped over -60 dB...0 dB to 0...1, clamped. peak <= 0.001 returns 0.
    public static func fraction(forPeak peak: Float) -> Double {
        guard peak > 0.001 else { return 0 }
        return min(max((20 * Double(log10(peak)) + 60) / 60, 0), 1)
    }
}
