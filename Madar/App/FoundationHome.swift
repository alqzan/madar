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
