import SwiftUI
import SwiftData
import MadarCore
import MadarPrayer
import MadarDesign

/// A heading's text, ready to draw (period name and that prayer's time in the place in effect that day).
struct DiaryPeriodLabel: Equatable {
    let title: String
    let time: String?
}

extension AppDiaryService {
    /// Quiet prayer-period headings for a page's flow, keyed by the id of the first line under each. Nothing is stored:
    /// times come from the prayer engine for that day and the place in effect then (a trip's place on travel days).
    func periodLabels(for page: DiaryDisplayDay) -> [String: DiaryPeriodLabel] {
        let flow = page.lines.filter { $0.kind != "intention" }
        guard !flow.isEmpty, let repository = try? PrayerRepository(context: ModelContext(app.container)) else { return [:] }
        let noon = page.day.date(in: app.activePlace.timeZone).addingTimeInterval(12 * 3600)
        let place = repository.place(at: noon)
        guard let times = PrayerTimesEngine.calculate(day: page.day, place: place, options: repository.calculationOptions(at: noon)) else { return [:] }
        let boundary = DayBoundary(rawValue: app.string("core.dayStart")) ?? .fajr
        let headings = DiaryPrayerPeriods.headings(for: flow.map(\.at), times: times, preFajrExists: boundary != .fajr)
        var result: [String: DiaryPeriodLabel] = [:]
        for heading in headings {
            result[flow[heading.index].id] = .init(title: heading.period.title, time: heading.time.map { time($0, zone: place.timeZoneID) })
        }
        return result
    }
}

extension AppDiaryService {
    /// True once Isha has begun on `day` in the place in effect (the quiet link to the night review appears then).
    func ishaPassed(on day: GregorianDay) -> Bool {
        guard let repository = try? PrayerRepository(context: ModelContext(app.container)) else { return false }
        let noon = day.date(in: app.activePlace.timeZone).addingTimeInterval(12 * 3600)
        guard let times = PrayerTimesEngine.calculate(day: day, place: repository.place(at: noon), options: repository.calculationOptions(at: noon)) else { return false }
        return clock() >= times.isha
    }
}

struct DiaryPeriodHeadingRow: View {
    let label: DiaryPeriodLabel
    @Environment(\.roomTheme) private var theme
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label.time ?? "").font(DiaryType.label).lineLimit(1).minimumScaleFactor(0.92)
                .foregroundStyle(theme.color("ink3Text")).frame(width: DiaryDayMetrics.timeColumn, alignment: .center)
            Text(label.title).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 6).padding(.trailing, 18).padding(.top, 14).padding(.bottom, 2)
        .accessibilityElement(children: .ignore).accessibilityLabel(label.title + (label.time.map { "، " + $0 } ?? ""))
        .accessibilityIdentifier("diary-period-heading")
    }
}
