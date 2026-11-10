import SwiftUI
import MadarCore
import MadarDesign

struct FoundationPrayerTimeRow: Identifiable, Equatable {
    let prayer: Prayer
    let title: String
    let clock: String
    var id: Prayer { prayer }
    var accessibilityLabel: String { "\(title)، \(clock)" }
}

/// A read-only presentation of the active place's civil day; stored room day keys are untouched.
struct FoundationPrayerTimesPresentation {
    let day: GregorianDay
    let prayerDay: PrayerDay?
    let rows: [FoundationPrayerTimeRow]

    init(instant: Date, place: ActivePlace, options: PrayerCalculationOptions = .init(), numerals: NumeralStyle = .hindi) {
        day = GregorianDay.containing(instant, in: place.timeZone)
        let calculated = PrayerTimesEngine.calculate(day: day, place: place, options: options)
        prayerDay = calculated
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        let formatter = MadarNumberFormatter(style: numerals)
        rows = calculated.map { times in
            Prayer.allCases.map { prayer in
                let title = switch prayer { case .fajr: "الفجر"; case .dhuhr: "الظهر"; case .asr: "العصر"; case .maghrib: "المغرب"; case .isha: "العشاء" }
                let components = calendar.dateComponents([.hour, .minute], from: times.time(for: prayer))
                let clock = String(format: "%02d:%02d", locale: Locale(identifier: "en_US_POSIX"), components.hour ?? 0, components.minute ?? 0)
                return FoundationPrayerTimeRow(prayer: prayer, title: title, clock: formatter.localized(clock))
            }
        } ?? []
    }
}

private struct FoundationPrayerTimesCard: View {
    let rows: [FoundationPrayerTimeRow]
    let cityName: String
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        MadarCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("مواقيت اليوم").font(MadarTypography.cardTitle()).accessibilityAddTraits(.isHeader)
                    Text(cityName).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
                ForEach(rows) { row in
                    Group {
                        if dynamicType.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 4) { Text(row.title); clock(row) }
                        } else {
                            HStack { Text(row.title); Spacer(); clock(row) }
                        }
                    }
                    .font(MadarTypography.body()).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.accessibilityLabel)
                    .accessibilityIdentifier("foundation-prayer-time-\(row.prayer.rawValue)")
                }
            }
        }
    }
    private func clock(_ row: FoundationPrayerTimeRow) -> some View {
        Text("\u{2068}\(row.clock)\u{2069}").monospacedDigit().fixedSize(horizontal: false, vertical: true)
    }
}
