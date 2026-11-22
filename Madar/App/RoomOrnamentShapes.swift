import SwiftUI

// Ornament shapes shared by the habits room, the money reconcile screen and the lobby blocks.

struct PrayerStar: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); let center = CGPoint(x: rect.midX, y: rect.midY); let radius = min(rect.width, rect.height) / 2
        for n in 0..<16 { let angle = Double(n) * .pi / 8 - .pi / 2; let r = radius * (n.isMultiple(of: 2) ? 1 : 0.44); let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r); if n == 0 { p.move(to: point) } else { p.addLine(to: point) } }; p.closeSubpath(); return p
    }
}
