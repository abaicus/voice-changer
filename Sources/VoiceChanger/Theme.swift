import SwiftUI

enum Theme {
    static let backgroundTop = Color(red: 0.13, green: 0.09, blue: 0.21)
    static let backgroundBottom = Color(red: 0.05, green: 0.04, blue: 0.09)
    static let accentStart = Color(red: 1.0, green: 0.36, blue: 0.62)
    static let accentEnd = Color(red: 0.98, green: 0.62, blue: 0.25)
    static let sidebar = Color.black.opacity(0.22)
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.09)
    static let rowSelected = Color.white.opacity(0.16)
    static let rowHover = Color.white.opacity(0.07)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)
    static let powerOff = Color(red: 0.19, green: 0.15, blue: 0.30)
    static let textTertiary = Color.white.opacity(0.5)
    static let cardRadius: CGFloat = 14
    static let rowRadius: CGFloat = 8
    static let sidebarWidth: CGFloat = 220

    static var accent: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct ThemeBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.backgroundTop, Theme.backgroundBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: [Theme.accentStart.opacity(0.12), .clear], center: .topTrailing, startRadius: 0, endRadius: 520)
        }
    }
}
