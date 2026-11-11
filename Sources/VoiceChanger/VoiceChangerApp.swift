import SwiftUI
import VoiceChangerKit

@main
struct VoiceChangerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Voice Changer", id: "main") {
            ContentView()
                .environment(model)
                .background(WindowChrome())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 960, height: 692)
        .commands {
            AboutCommand()
            WelcomeGuideCommand()
        }

        Window("About Voice Changer", id: AppInfo.aboutWindowID) {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra("Voice Changer", systemImage: model.settings.enabled ? "waveform.circle.fill" : "waveform.circle") {
            MenuBarView()
                .environment(model)
        }
    }
}

struct AboutCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Voice Changer") {
                openWindow(id: AppInfo.aboutWindowID)
                NSApp.activate()
            }
        }
    }
}

struct WelcomeGuideCommand: Commands {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("onboardingDone") private var onboardingDone = false

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Welcome Guide") {
                onboardingDone = false
                openWindow(id: "main")
                NSApp.activate()
            }
        }
    }
}

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        Toggle("Voice Changer On", isOn: $model.settings.enabled)
        Toggle("Monitor (Hear Myself)", isOn: $model.settings.monitorEnabled)
        Toggle("Bypass Effects", isOn: $model.settings.bypass)
        Divider()
        Picker("Preset", selection: Binding(
            get: { model.settings.selectedPresetID },
            set: { id in model.allPresets.first { $0.id == id }.map(model.select) }
        )) {
            ForEach(model.allPresets) { Text($0.name).tag($0.id) }
        }
        .pickerStyle(.inline)
        Divider()
        Button("Open Voice Changer") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button("About Voice Changer") {
            openWindow(id: AppInfo.aboutWindowID)
            NSApp.activate()
        }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
