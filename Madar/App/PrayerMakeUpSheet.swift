import SwiftUI
import MadarCore
import MadarDesign
import MadarPrayer

/// The small lattice arch beside prayer sheet titles.
struct PrayerSheetArch: View {
    @Environment(\.roomTheme) private var theme
    var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            let shape = PrayerHorseshoe().path(in: rect)
            ZStack {
                shape.fill(theme.color("goldSoft"))
                PrayerLatticePattern(spacing: 7).stroke(theme.accent.opacity(0.5), lineWidth: 1).mask { shape.fill() }
                shape.stroke(theme.color("goldMid").opacity(0.7), lineWidth: 1)
            }
        }
    }
}
