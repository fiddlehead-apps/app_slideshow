import SwiftUI

/// Same palette as the web app, light and dark.
extension Color {
    static let bg = dynamic(0xEEF0F3, 0x121418)
    static let surface = dynamic(0xFFFFFF, 0x1C1F25)
    static let ink = dynamic(0x16181D, 0xF1F2F4)
    static let muted = dynamic(0x5D6470, 0x9AA1AD)
    static let line = dynamic(0xD5D9E0, 0x2C3038)
    static let accentInk = dynamic(0xFFFFFF, 0x0E1330)
    static let danger = dynamic(0xC4321F, 0xE5533E)
    static let sun = Color(hex: 0xFFC857)
    static let switchOn = Color(hex: 0x8BA3FF)

    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { t in UIColor(Color(hex: t.userInterfaceStyle == .dark ? dark : light)) })
    }
}

/// The big filled / outlined buttons on the start screen.
struct BigButtonStyle: ButtonStyle {
    var primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.horizontal, 22)
            .foregroundStyle(primary ? Color.accentInk : Color.ink)
            .background(primary ? Color.accent : Color.surface, in: .rect(cornerRadius: 16))
            .overlay {
                if !primary { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.line, lineWidth: 1.5) }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
