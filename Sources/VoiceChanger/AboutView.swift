import SwiftUI

struct AboutView: View {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("onboardingDone") private var onboardingDone = false

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .padding(.bottom, 4)
            Text("Voice Changer")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Version \(AppInfo.version)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .padding(.bottom, 12)
            Text("A real-time voice changer for macOS that sends your changed voice to a virtual microphone.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            Text("Needs [BlackHole](\(AppInfo.blackHole.absoluteString)) as the virtual microphone.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .tint(Theme.accentEnd)
                .padding(.bottom, 16)

            HStack(spacing: 8) {
                linkButton("GitHub", systemImage: "chevron.left.forwardslash.chevron.right", url: AppInfo.repo)
                linkButton("Website", systemImage: "globe", url: AppInfo.website)
                linkButton("License", systemImage: "doc.text", url: AppInfo.license)
            }
            .padding(.bottom, 8)

            Button {
                onboardingDone = false
                openWindow(id: "main")
                NSApp.activate()
            } label: {
                Label("Welcome Guide", systemImage: "questionmark.circle").lineLimit(1).fixedSize()
            }
            .buttonStyle(PillButtonStyle())
            .padding(.bottom, 18)

            Text("Free and open source under the GPL-3.0 license.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .padding(.bottom, 4)
            Text("Pitch and formant shifting by [Signalsmith Stretch](\(AppInfo.signalsmith.absoluteString)) (MIT).")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .tint(Theme.accentEnd)
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .background(ThemeBackground().ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func linkButton(_ title: String, systemImage: String, url: URL) -> some View {
        Link(destination: url) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(PillButtonStyle())
    }
}
