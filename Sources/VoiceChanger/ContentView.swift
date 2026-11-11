import SwiftUI
import VoiceChangerKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var tour = OnboardingTour()

    var body: some View {
        HStack(spacing: 0) {
            PresetSidebar().tourAnchor(.presets)
            DetailView()
        }
        .background(ThemeBackground())
        .ignoresSafeArea()
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if !onboardingDone {
                    let rects = anchors.mapValues { $0.map { proxy[$0] }.reduce(CGRect.null) { $0.union($1) } }
                    OnboardingOverlay(isDone: $onboardingDone, tour: tour, targets: rects, size: proxy.size)
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: onboardingDone)
        }
        .onChange(of: onboardingDone, initial: true) { _, done in
            tour.running = !done
            if !done { tour.step = .welcome }
        }
        .background(OverhangingPowerButton(model: model, tour: tour, hidden: !onboardingDone && tour.step != .power))
        .preferredColorScheme(.dark)
        .frame(minWidth: 960, maxWidth: 1120, minHeight: 640, maxHeight: 760)
    }
}

/// A window cannot draw outside its own frame, so the button lives in a borderless child window centred on the bottom edge.
private struct OverhangingPowerButton: NSViewRepresentable {
    let model: AppModel
    let tour: OnboardingTour
    let hidden: Bool

    func makeNSView(context: Context) -> Anchor { Anchor(model: model, tour: tour, hidden: hidden) }
    func updateNSView(_ view: Anchor, context: Context) { view.setHidden(hidden) }

    final class Anchor: NSView {
        private static let side: CGFloat = 128
        private let panel: NSPanel
        private var observers: [NSObjectProtocol] = []
        private var panelHidden: Bool

        init(model: AppModel, tour: OnboardingTour, hidden: Bool) {
            panelHidden = hidden
            panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: Self.side, height: Self.side),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            let host = NSHostingView(rootView: PowerButtonHost().environment(model).environment(tour).preferredColorScheme(.dark))
            host.frame = NSRect(x: 0, y: 0, width: Self.side, height: Self.side)
            panel.contentView = host
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        deinit { detach() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let window else { return }
            if !panelHidden { window.addChildWindow(panel, ordered: .above) }
            for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification] {
                observers.append(
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        self?.reposition()
                    })
            }
            reposition()
        }

        func setHidden(_ newValue: Bool) {
            guard newValue != panelHidden else { return }
            panelHidden = newValue
            if panelHidden {
                panel.parent?.removeChildWindow(panel)
                panel.orderOut(nil)
            } else if let window {
                window.addChildWindow(panel, ordered: .above)
                reposition()
            }
        }

        private func detach() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }

        private func reposition() {
            guard let window else { return }
            var y = window.frame.minY - Self.side / 2
            // In full screen there is nothing below the window, so keep the button on screen.
            if let screen = window.screen { y = max(y, screen.frame.minY) }
            panel.setFrameOrigin(NSPoint(x: window.frame.midX - Self.side / 2, y: y))
        }
    }
}

private struct PowerButtonHost: View {
    @Environment(AppModel.self) private var model
    @Environment(OnboardingTour.self) private var tour
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var highlighted: Bool { tour.running && tour.step == .power }

    var body: some View {
        @Bindable var model = model
        PowerButton(isOn: $model.settings.enabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if highlighted {
                    Circle()
                        .strokeBorder(Theme.accent, lineWidth: 3)
                        .frame(width: 76, height: 76)
                        .scaleEffect(pulse ? 1.12 : 1)
                        .opacity(pulse ? 0.5 : 1)
                        .allowsHitTesting(false)
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
                        }
                }
            }
    }
}

private struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HeroHeader()
                    if !model.status.isEmpty {
                        Label(model.status, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.orange)
                            .font(.callout)
                    }
                    RoutingCard().fixedSize(horizontal: false, vertical: true).tourAnchor(.routing)
                    VStack(spacing: 16) {
                        HStack(spacing: 16) { VoiceCard(); LevelCard() }
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 16) { ToneCard(); EffectsCard() }
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tourAnchor(.controls)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 48)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 28)
    }
}

private struct HeroHeader: View {
    @Environment(AppModel.self) private var model

    private var subtitle: String {
        if model.isStarting || (model.settings.enabled && !model.isRunning) { return "Starting…" }
        guard model.isRunning else { return "Off — press Start to change your voice" }
        if let virtualMic = model.virtualMicDevice {
            return "Live · \(model.activeInputName) → \(virtualMic.name)"
        }
        return "Live · \(model.activeInputName) · no virtual mic selected"
    }

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.card)
                .strokeBorder(Theme.cardStroke)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: model.selectedPreset?.symbolName ?? "slider.horizontal.3")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.selectedPreset?.name ?? "Custom")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if model.isModified {
                        Text("edited")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("Bypass", isOn: $model.settings.bypass)
                .toggleStyle(PillToggleStyle())
                .fixedSize()
                .help("Pass your voice through unchanged, to compare with the effect")
        }
    }
}

private struct RoutingCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Card(title: "Routing", systemImage: "arrow.triangle.branch") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    RoutingColumn(title: "Microphone") {
                        DeviceMenu(
                            title: "Microphone", selection: $model.settings.inputUID,
                            devices: model.inputDevices, emptyName: "System Default")
                        LevelMeter(level: model.inputLevel).frame(height: 16)
                    }
                    RoutingColumn(title: "Virtual mic") {
                        DeviceMenu(
                            title: "Virtual mic", selection: $model.settings.virtualMicUID,
                            devices: model.outputDevices, emptyName: "None")
                        LevelMeter(level: model.outputLevel).frame(height: 16)
                    }
                    RoutingColumn(title: "Monitor") {
                        Group {
                            DeviceMenu(
                                title: "Monitor output", selection: $model.settings.monitorUID,
                                devices: model.monitorDevices, emptyName: "System Default")
                            GradientSlider(title: "Monitor volume", value: $model.settings.monitorVolume, range: 0...1)
                                .frame(height: 16)
                        }
                        .disabled(!model.settings.monitorEnabled)
                    } accessory: {
                        Toggle("Monitor", isOn: $model.settings.monitorEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .tint(Theme.accentStart)
                            .help("Hear your changed voice. Use headphones, or the speakers will feed back into the mic.")
                    }
                }
                if let virtualMic = model.virtualMicDevice {
                    Text("In Discord, Zoom, Google Meet or OBS choose “\(virtualMic.name)” as the microphone.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    Label(
                        "No virtual mic selected, so other apps can't hear the effect. Install BlackHole (brew install blackhole-2ch) and pick it above.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct RoutingColumn<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                accessory
            }
            .frame(height: 20)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension RoutingColumn where Accessory == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, content: content) { EmptyView() }
    }
}

private struct DeviceMenu: View {
    let title: String
    @Binding var selection: String
    let devices: [AudioDevice]
    let emptyName: String
    @Environment(\.isEnabled) private var isEnabled

    private var selectedName: String {
        if selection.isEmpty { return emptyName }
        return devices.first { $0.uid == selection }?.name ?? "Unavailable device"
    }

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                Text(emptyName).tag("")
                ForEach(devices) { Text($0.name).tag($0.uid) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 8) {
                Text(selectedName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Theme.rowRadius).fill(Theme.rowHover))
            .overlay(RoundedRectangle(cornerRadius: Theme.rowRadius).strokeBorder(Theme.cardStroke))
            .contentShape(RoundedRectangle(cornerRadius: Theme.rowRadius))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(title)
        .accessibilityValue(selectedName)
    }
}

private struct VoiceCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let params = $model.settings.params
        Card(title: "Voice", systemImage: "waveform") {
            VStack(spacing: 12) {
                ParamSlider("Pitch", params.pitch, -12...12, unit: .semitones)
                ParamSlider("Formant", params.formant, -8...8, unit: .semitones)
                    .help("Size of the voice: lower sounds like a bigger person, higher like a smaller one")
            }
        }
    }
}

private struct ToneCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let params = $model.settings.params
        Card(title: "Tone", systemImage: "slider.horizontal.3") {
            VStack(spacing: 12) {
                ParamSlider("Bass", params.lowGain, -12...12, unit: .decibels)
                ParamSlider("Mid", params.midGain, -12...12, unit: .decibels)
                ParamSlider("Treble", params.highGain, -12...12, unit: .decibels)
                ParamSlider("Low cut", params.lowCut, 20...1000, unit: .hertz)
                ParamSlider("High cut", params.highCut, 1000...20000, unit: .hertz, neutral: 20000)
            }
        }
    }
}

private struct EffectsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let params = $model.settings.params
        Card(title: "Effects", systemImage: "sparkles") {
            VStack(spacing: 12) {
                ParamSlider("Robot", params.robotMix, 0...1, unit: .percent)
                ParamSlider("Robot tone", params.robotHz, 30...400, unit: .hertz)
                ParamSlider("Distortion", params.distortion, 0...1, unit: .percent)
                ParamSlider("Reverb", params.reverbMix, 0...1, unit: .percent)
                ParamSlider("Room size", params.reverbSize, 0...1, unit: .percent)
            }
        }
    }
}

private struct LevelCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let params = $model.settings.params
        Card(title: "Level", systemImage: "speaker.wave.2.fill") {
            VStack(spacing: 12) {
                ParamSlider("Noise gate", params.gateThreshold, -80...(-20), unit: .gate)
                    .help("Mutes the mic while you are quieter than this level")
                ParamSlider("Output gain", params.outputGain, -24...24, unit: .decibels)
            }
        }
    }
}
