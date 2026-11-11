import AVFoundation
import AppKit
import SwiftUI
import VoiceChangerKit

enum TourStep: Int, CaseIterable {
    case welcome, blackHole, microphone, presets, routing, monitor, controls, power

    var target: TourTarget? {
        switch self {
        case .presets: .presets
        case .routing: .routing
        case .monitor: .routing
        case .controls: .controls
        default: nil
        }
    }

    var isCard: Bool { rawValue <= TourStep.microphone.rawValue }
    var isLast: Bool { self == .power }
}

enum TourTarget: Hashable {
    case presets, routing, controls
}

@Observable
final class OnboardingTour {
    var step = TourStep.welcome
    var running = false
}

struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [TourTarget: [Anchor<CGRect>]] = [:]
    static func reduce(value: inout [TourTarget: [Anchor<CGRect>]], nextValue: () -> [TourTarget: [Anchor<CGRect>]]) {
        value.merge(nextValue()) { $0 + $1 }
    }
}

extension View {
    func tourAnchor(_ target: TourTarget) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [target: [$0]] }
    }
}

private struct SpotlightShape: Shape {
    var cutout: CGRect

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(cutout.origin.x, cutout.origin.y), .init(cutout.size.width, cutout.size.height)) }
        set { cutout = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: cutout, cornerSize: CGSize(width: 14, height: 14))
        return path
    }
}

struct OnboardingOverlay: View {
    @Binding var isDone: Bool
    let tour: OnboardingTour
    let targets: [TourTarget: CGRect]
    let size: CGSize

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var copied = false

    private let installCommand = "brew install blackhole-2ch"
    private let calloutWidth: CGFloat = 340
    private let gap: CGFloat = 12
    private let margin: CGFloat = 16
    @State private var calloutHeight: CGFloat = 160

    private var blackHole: AudioDevice? { model.outputDevices.first { $0.name.contains("BlackHole") } }
    private var step: TourStep { tour.step }

    private var cutout: CGRect {
        guard let target = step.target, let rect = targets[target], !rect.isNull else {
            return CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0)
        }
        return rect.insetBy(dx: -6, dy: -6).intersection(CGRect(x: 6, y: 6, width: size.width - 12, height: size.height - 12))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SpotlightShape(cutout: cutout)
                .fill(Color.black.opacity(0.7), style: FillStyle(eoFill: true))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.accent, lineWidth: 2)
                        .frame(width: cutout.width, height: cutout.height)
                        .position(x: cutout.midX, y: cutout.midY)
                        .opacity(step.target == nil ? 0 : 1)
                )
                .overlay(Color.clear.contentShape(Rectangle()).onTapGesture {})
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: step)

            if step.isCard {
                card
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(step)
                    .transition(.opacity)
            } else {
                callout
                    .id(step)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
        .onChange(of: blackHole?.uid, initial: true) { _, uid in
            if let uid, model.settings.virtualMicUID.isEmpty { model.settings.virtualMicUID = uid }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }

    // MARK: Centred cards

    private var card: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) { cardContent }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, 20)
            VStack(spacing: 14) {
                dots
                buttons
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.backgroundBottom))
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.cardStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var cardContent: some View {
        switch step {
        case .welcome:
            cardLayout(symbol: nil, title: "Welcome to Voice Changer") {
                Text("Voice Changer changes your voice live and sends it to any app as a microphone.").bodyText()
                Text("This quick tour gets you set up.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
            }
        case .blackHole:
            cardLayout(symbol: "arrow.down.circle.fill", title: "Install BlackHole") {
                Text("BlackHole is the virtual microphone other apps listen to. It is required.").bodyText()
                blackHoleStatus
            }
        default:
            cardLayout(symbol: "mic.fill", title: "Microphone access") {
                Text("Voice Changer needs permission to hear your microphone.").bodyText()
                micStatusView
            }
        }
    }

    private func cardLayout<Body: View>(symbol: String?, title: String, @ViewBuilder body: () -> Body) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let symbol {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.accent)
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: symbol)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(Color.white)
                        }
                } else {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                }
            }
            .padding(.bottom, 8)
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            body()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func okLabel(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.green)
    }

    @ViewBuilder private var blackHoleStatus: some View {
        if blackHole != nil {
            okLabel("BlackHole 2ch is installed")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Not found yet", systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.orange)
                HStack(spacing: 10) {
                    Text(installCommand)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button(copied ? "Copied" : "Copy") { copyCommand() }
                        .buttonStyle(PillButtonStyle())
                        .fixedSize()
                }
                .padding(.vertical, 8)
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .background(RoundedRectangle(cornerRadius: Theme.rowRadius).fill(Color.black.opacity(0.3)))
                HStack {
                    Link(destination: AppInfo.blackHole) {
                        Label("BlackHole on GitHub", systemImage: "arrow.up.right.square").fixedSize()
                    }
                    .buttonStyle(PillButtonStyle())
                    .fixedSize()
                    Text("This updates by itself once it is installed.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    @ViewBuilder private var micStatusView: some View {
        switch micStatus {
        case .authorized:
            okLabel("Microphone access is allowed")
        case .notDetermined:
            Button("Allow Microphone") {
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    DispatchQueue.main.async { micStatus = AVCaptureDevice.authorizationStatus(for: .audio) }
                }
            }
            .buttonStyle(PillButtonStyle(prominent: true))
            .fixedSize()
        default:
            VStack(alignment: .leading, spacing: 10) {
                Label("Microphone access is off", systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.orange)
                Text("Enable Voice Changer in System Settings › Privacy & Security › Microphone.").bodyText()
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(PillButtonStyle())
                .fixedSize()
            }
        }
    }

    // MARK: Spotlight callout

    private var copy: (title: String, body: String) {
        switch step {
        case .presets:
            ("Pick a voice", "Built-in presets on top, your own below.")
        case .routing:
            (
                "Routing",
                "Your microphone goes in, BlackHole 2ch goes out. In Discord, Zoom, Google Meet or OBS choose “BlackHole 2ch” as the microphone."
            )
        case .monitor:
            ("Hear yourself", "Turn on Monitor to hear yourself. Use headphones.")
        case .controls:
            ("Shape the voice", "Shape the voice with the sliders, then Save as New Preset.")
        default:
            ("Start", "Press play to start. That's it.")
        }
    }

    private var callout: some View {
        let content = copy
        return VStack(alignment: .leading, spacing: 8) {
            Text(content.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(content.body).bodyText()
            VStack(spacing: 14) {
                dots
                buttons
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: calloutWidth)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.backgroundBottom))
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 6)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { calloutHeight = $0 }
        .modifier(CalloutPlacement(origin: calloutOrigin, bottomCentred: step == .power, size: size))
    }

    private var calloutOrigin: CGPoint {
        let w = calloutWidth, h = calloutHeight
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, margin), size.width - w - margin) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, margin), size.height - h - margin) }
        guard let target = step.target, let rect = targets[target], !rect.isNull else {
            return CGPoint(x: clampX((size.width - w) / 2), y: clampY((size.height - h) / 2))
        }
        let r = rect.insetBy(dx: -6, dy: -6)
        if r.maxX + gap + w + margin <= size.width { return CGPoint(x: r.maxX + gap, y: clampY(r.minY)) }
        if r.minX - gap - w - margin >= 0 { return CGPoint(x: r.minX - gap - w, y: clampY(r.minY)) }
        if r.maxY + gap + h + margin <= size.height { return CGPoint(x: clampX(r.minX), y: r.maxY + gap) }
        if r.minY - gap - h - margin >= 0 { return CGPoint(x: clampX(r.minX), y: r.minY - gap - h) }
        return CGPoint(x: clampX(r.midX - w / 2), y: clampY(r.midY - h / 2))
    }

    // MARK: Navigation

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(TourStep.allCases, id: \.self) { item in
                Capsule()
                    .fill(item == step ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.25)))
                    .frame(width: item == step ? 18 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("Step \(step.rawValue + 1) of \(TourStep.allCases.count)")
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button("Skip") { isDone = true }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .opacity(step.isLast ? 0 : 1)
                .disabled(step.isLast)
            Spacer()
            Button("Back") { go(step.rawValue - 1) }
                .buttonStyle(PillButtonStyle())
                .frame(width: 70)
                .opacity(step == .welcome ? 0 : 1)
                .disabled(step == .welcome)
            Button(step.isLast ? "Get Started" : step.isCard ? "Continue" : "Next") {
                if step.isLast { isDone = true } else { go(step.rawValue + 1) }
            }
            .buttonStyle(PillButtonStyle(prominent: true))
            .frame(width: 100)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func go(_ index: Int) {
        if let next = TourStep(rawValue: index) { tour.step = next }
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(installCommand, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}

private struct CalloutPlacement: ViewModifier {
    let origin: CGPoint
    let bottomCentred: Bool
    let size: CGSize

    func body(content: Content) -> some View {
        if bottomCentred {
            content
                .frame(width: size.width, height: size.height, alignment: .bottom)
                .padding(.bottom, 0)
                .offset(y: -44)
        } else {
            content
                .fixedSize()
                .offset(x: origin.x, y: origin.y)
        }
    }
}

private extension Text {
    func bodyText() -> some View {
        font(.system(size: 13))
            .lineSpacing(4)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
