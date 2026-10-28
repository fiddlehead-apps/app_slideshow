import SwiftUI

/// Slim line drawing in the style of the app icon. Coordinates are those of the
/// 1024 px icon canvas (tools/make_icon.py); `area` is the part of it to show.
struct LineArt: View {
    let area: CGRect
    let width: CGFloat
    var lineWidth: CGFloat = 3.5
    var color: Color = .accent
    let draw: (inout Path) -> Void

    var body: some View {
        let scale = width / area.width
        Canvas { ctx, _ in
            var path = Path()
            draw(&path)
            let fit = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -area.minX, y: -area.minY)
            ctx.stroke(path.applying(fit), with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: width, height: area.height * scale)
        .accessibilityHidden(true)
    }
}

extension Path {
    /// Fiddlehead curl starting at `start`, leaving in direction `heading`
    /// (degrees, 0 = up, clockwise). Same construction as the curl in the app icon.
    mutating func addFiddlehead(at start: CGPoint, heading: Double, radius: Double, turns: Int = 3, left: Bool = false) {
        let h = heading * .pi / 180, flip: Double = left ? -1 : 1
        func place(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: start.x + flip * x * cos(h) - y * sin(h), y: start.y + flip * x * sin(h) + y * cos(h))
        }
        move(to: start)
        var from = 0.0
        for (i, f) in [1, 0.64, 0.33, 0.12].prefix(turns).enumerated() {
            let r = radius * f
            let (cx, a0) = i % 2 == 0 ? (from + r, Double.pi) : (from - r, 0)
            for k in 1...40 {
                let a = a0 + .pi * Double(k) / 40
                addLine(to: place(cx + r * cos(a), r * sin(a)))
            }
            from = cx - r * cos(a0)
        }
    }
}

private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

/// Two photo prints; the ridge rises and curls into the sun. The motif of the app icon.
struct PrintsIllustration: View {
    var body: some View {
        LineArt(area: CGRect(x: 210, y: 210, width: 604, height: 540), width: 190) { p in
            // back print, peeking out top right
            p.move(to: pt(306, 292))
            p.addLine(to: pt(306, 262))
            p.addQuadCurve(to: pt(336, 232), control: pt(306, 232))
            p.addLine(to: pt(762, 232))
            p.addQuadCurve(to: pt(792, 262), control: pt(792, 232))
            p.addLine(to: pt(792, 628))
            p.addQuadCurve(to: pt(762, 658), control: pt(792, 658))
            p.addLine(to: pt(732, 658))
            // front print
            p.addRoundedRect(in: CGRect(x: 232, y: 292, width: 500, height: 436), cornerSize: CGSize(width: 30, height: 30))
            // ridge that becomes the sun
            p.move(to: pt(232, 668))
            p.addLines([pt(232, 668), pt(352, 548), pt(436, 632), pt(500, 568), pt(548, 616)])
            p.addCurve(to: pt(630, 486), control1: pt(600, 580), control2: pt(628, 540))
            p.addFiddlehead(at: pt(630, 486), heading: 0, radius: 66, left: true)
        }
    }
}
