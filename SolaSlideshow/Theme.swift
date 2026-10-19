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

/// Two tilted photo prints, the motif of the app icon.
struct PrintsIllustration: View {
    var body: some View {
        Canvas { ctx, _ in
            var back = ctx
            back.concatenate(Self.rotation(9, around: CGPoint(x: 100, y: 80)))
            back.fill(Path(roundedRect: CGRect(x: 30, y: 28, width: 140, height: 104), cornerRadius: 8), with: .color(.line))

            var front = ctx
            front.concatenate(Self.rotation(-6, around: CGPoint(x: 92, y: 74)))
            let frame = Path(roundedRect: CGRect(x: 22, y: 22, width: 140, height: 104), cornerRadius: 8)
            front.fill(frame, with: .color(.surface))
            front.stroke(frame, with: .color(.line), lineWidth: 1.5)
            front.fill(Path(roundedRect: CGRect(x: 32, y: 32, width: 120, height: 84), cornerRadius: 3), with: .color(.ink))
            front.fill(Path(ellipseIn: CGRect(x: 117, y: 45, width: 18, height: 18)), with: .color(.sun))
            var hill = Path()
            hill.addLines([CGPoint(x: 32, y: 116), CGPoint(x: 66, y: 76), CGPoint(x: 90, y: 102),
                           CGPoint(x: 108, y: 86), CGPoint(x: 152, y: 116)])
            hill.closeSubpath()
            front.fill(hill, with: .color(.accent))
        }
        .frame(width: 190, height: 150)
        .accessibilityHidden(true)
    }

    private static func rotation(_ degrees: Double, around p: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: p.x, y: p.y)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -p.x, y: -p.y)
    }
}
