import SwiftUI
import MadarCore
import MadarDesign

struct MadarDateLabel: View {
    @Environment(\.roomTheme) private var theme
    let labels: MadarDateLabels
    var primaryFont: Font = MadarTypography.caption()
    var secondaryFont: Font = MadarTypography.fine()
    init(_ labels: MadarDateLabels, primaryFont: Font = MadarTypography.caption(), secondaryFont: Font = MadarTypography.fine()) {
        self.labels = labels; self.primaryFont = primaryFont; self.secondaryFont = secondaryFont
    }
    init(_ combined: String) {
        let pieces = combined.components(separatedBy: "، ")
        self.init(.init(primary: pieces.first ?? combined, secondary: pieces.dropFirst().joined(separator: "، ")))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(labels.primary).font(primaryFont)
            if !labels.secondary.isEmpty { Text(labels.secondary).font(secondaryFont).foregroundStyle(theme.secondaryInk) }
        }.fixedSize(horizontal: false, vertical: true)
    }
}
extension AppSession {
    func dateLabels(_ day: GregorianDay, first: FirstCalendar? = nil, compact: Bool = false, weekday: Bool = false) -> MadarDateLabels {
        DualDate(instant: day.date(in: activePlace.timeZone).addingTimeInterval(12 * 3600), timeZone: activePlace.timeZone,
            source: HijriSource(rawValue: string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(number("core.hijriOffset")))
            .labels(firstCalendar: first ?? FirstCalendar(rawValue: string("core.firstCalendar")) ?? .hijri,
                    numerals: string("core.numerals") == "western" ? .western : .hindi, compact: compact, weekday: weekday)
    }
    func yearLabels(_ year: Int) -> MadarDateLabels {
        guard let first = try? GregorianDay(year: year, month: 1, day: 1), let last = try? GregorianDay(year: year, month: 12, day: 31) else { return .init(primary: "", secondary: "") }
        let start = dateLabels(first, first: .gregorian).secondary.split(separator: " ").suffix(2).joined(separator: " ")
        let end = dateLabels(last, first: .gregorian).secondary.split(separator: " ").suffix(2).joined(separator: " ")
        let h = start == end ? start : start + " – " + end
        let g = digits(year) + " م"
        return string("core.firstCalendar") == "gregorian" ? .init(primary: g, secondary: h) : .init(primary: h, secondary: g)
    }
}
extension AppDiaryService {
    func dateLabels(_ day: GregorianDay, first: FirstCalendar? = nil) -> MadarDateLabels { app.dateLabels(day, first: first) }
    func bothDates(_ day: GregorianDay, calendar: FirstCalendar? = nil) -> String { dateLabels(day, first: calendar).combined }
}
