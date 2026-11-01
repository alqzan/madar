import SwiftUI
import MadarCore
import MadarDesign
import MadarPrayer

struct PrayerNightFootprint: View {
    let nights: [PrayerNight]
    let last: GregorianDay
    @Environment(\.roomTheme) private var theme

    var body: some View {
        let byDay = Dictionary(nights.map { ($0.night, $0) }, uniquingKeysWith: { $1 })
        HStack(spacing: 3) {
            ForEach(0..<30, id: \.self) { offset in
                let night = byDay[last.adding(days: offset - 29)]
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color(night))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(_ night: PrayerNight?) -> Color {
        guard let night, night.rakaat > 0 || night.witr else { return theme.ink.opacity(0.1) }
        return night.rakaat >= 8 ? theme.accent : theme.color("goldMid")
    }
}
