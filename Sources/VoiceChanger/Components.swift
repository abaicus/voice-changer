import SwiftUI
import VoiceChangerKit

struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(
                    prominent
                        ? AnyShapeStyle(Theme.accent)
                        : AnyShapeStyle(Color.white.opacity(configuration.isPressed ? 0.2 : 0.12)))
            )
            .opacity(prominent && configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 16)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Theme.textTertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.card))
    }
}

struct GradientSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    /// Where the fill starts: the value at which the control does nothing.
    var neutral: Float?
    @Environment(\.isEnabled) private var isEnabled

    private let thumb: CGFloat = 14
    private let track: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let usable = max(width - thumb, 0)
            let fraction = CGFloat(SliderScale.fraction(of: value, in: range))
            let origin = CGFloat(SliderScale.fraction(of: neutral ?? range.lowerBound, in: range))
            let low = min(origin, fraction), high = max(origin, fraction)
            let start = low <= 0 ? 0 : thumb / 2 + low * usable
            let end = high >= 1 ? width : thumb / 2 + high * usable
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                    .frame(height: track)
                Capsule().fill(Theme.accent)
                    .frame(width: max(end - start, 0), height: track)
                    .offset(x: start)
                Circle().fill(Color.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: fraction * usable)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged {
                    value = SliderScale.value(
                        atX: $0.location.x - thumb / 2, width: usable, in: range)
                },
                isEnabled: isEnabled
            )
        }
        .frame(height: 18)
        .opacity(isEnabled ? 1 : 0.4)
        .focusable(isEnabled)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            value = SliderScale.stepped(value, by: -1, in: range)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            value = SliderScale.stepped(value, by: 1, in: range)
            return .handled
        }
        .accessibilityRepresentation {
            Slider(value: $value, in: range) { Text(title) }
        }
    }
}

struct ParamSlider: View {
    enum Unit {
        case semitones, percent, hertz, decibels, gate

        func format(_ value: Float) -> String {
            switch self {
            case .semitones: String(format: "%+.1f st", value)
            case .percent: String(format: "%.0f%%", value * 100)
            case .hertz: String(format: "%.0f Hz", value)
            case .decibels: String(format: "%+.1f dB", value)
            case .gate: value <= -79.5 ? "Off" : String(format: "%.0f dB", value)
            }
        }
    }

    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let unit: Unit
    let neutral: Float

    init(_ title: String, _ value: Binding<Float>, _ range: ClosedRange<Float>, unit: Unit, neutral: Float? = nil) {
        self.title = title
        _value = value
        self.range = range
        self.unit = unit
        self.neutral = neutral ?? (range.contains(0) ? 0 : range.lowerBound)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 84, alignment: .leading)
            GradientSlider(title: title, value: $value, range: range, neutral: neutral)
            Text(unit.format(value))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 62, alignment: .trailing)
        }
    }
}

struct LevelMeter: View {
    /// Linear peak, 0...1.
    let level: Float

    private static let scale = LinearGradient(
        stops: [
            .init(color: Color(red: 0.20, green: 0.84, blue: 0.42), location: 0),
            .init(color: Color(red: 0.20, green: 0.84, blue: 0.42), location: 0.62),
            .init(color: Color(red: 0.98, green: 0.82, blue: 0.20), location: 0.80),
            .init(color: Color(red: 0.98, green: 0.26, blue: 0.24), location: 0.95),
        ], startPoint: .leading, endPoint: .trailing)

    var body: some View {
        let fraction = LevelScale.fraction(forPeak: level)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(Self.scale)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: proxy.size.width * fraction)
                    }
            }
            .animation(.linear(duration: 0.06), value: fraction)
        }
        .frame(minWidth: 120, idealWidth: 160, maxHeight: 6)
        .accessibilityLabel("Level")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

struct PowerButton: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Circle()
                .fill(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.powerOff))
                .frame(width: 56, height: 56)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5))
                .shadow(color: Theme.accentStart.opacity(isOn ? 0.5 : 0), radius: 10)
                .overlay {
                    Image(systemName: isOn ? "stop.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isOn)
        .help(isOn ? "Stop the voice changer" : "Start the voice changer")
        .accessibilityLabel(isOn ? "Stop voice changer" : "Start voice changer")
    }
}

struct PillToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .background(
                    Capsule().fill(
                        configuration.isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.12)))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
