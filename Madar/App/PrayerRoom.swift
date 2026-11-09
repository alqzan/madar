import SwiftUI
import Observation
import MadarCore
import MadarDesign

// A display projection of the prayer engine. Dates, eligibility and statistics are
// resolved by the service in the active place's time zone, never inferred by UI.

struct PrayerStar: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); let center = CGPoint(x: rect.midX, y: rect.midY); let radius = min(rect.width, rect.height) / 2
        for n in 0..<16 { let angle = Double(n) * .pi / 8 - .pi / 2; let r = radius * (n.isMultiple(of: 2) ? 1 : 0.44); let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r); if n == 0 { p.move(to: point) } else { p.addLine(to: point) } }; p.closeSubpath(); return p
    }
}
struct PrayerHorseshoe: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.minY + radius)
        let shoulder = center.y + radius * 0.5
        let left = rect.minX + rect.width * 0.067
        let right = rect.maxX - rect.width * 0.067

        path.move(to: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: left, y: shoulder))
        path.addArc(center: center, radius: radius, startAngle: .degrees(150), endAngle: .degrees(390), clockwise: false)
        path.addLine(to: CGPoint(x: right, y: rect.maxY))
        // The fill closes this contour implicitly; the stroke stays open where the feet meet the waterline.
        return path
    }
}
