import SwiftUI

/// Diamond lattice of 1-point lines (§5: «إطار سبكة معيّنات ١ نقطة»).
struct PrayerLatticePattern: Shape {
    let spacing: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x <= rect.maxX + rect.height {
            path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x + rect.height, y: rect.maxY))
            path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x - rect.height, y: rect.maxY))
            x += spacing
        }
        return path
    }
}
