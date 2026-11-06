import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarQuran
import MadarCommands

/// §7.1 «الأيام القادمة» automatic sources: the salary (Money), the end of the juz being memorised (Quran), the trip
/// under way (travel), and the seasons. Each room owns its date; the lobby only reads it. Read once per store write and
/// Madar day, never on each frame (FB-31: no freezes).
extension AppBahwService {
    private static var automaticCache: (key: String, value: [BahwUpcomingItem])?

    func automaticUpcoming() -> [BahwUpcomingItem] {
        let key = "\(session.storeGeneration):\(today):\(session.prayerRevision)"
        if let cached = Self.automaticCache, cached.key == key { return cached.value }
        var items: [BahwUpcomingItem] = []
        if session.roomEnabled(.mal), let salary = salaryItem() { items.append(salary) }
        if session.roomEnabled(.quran), let juz = juzItem() { items.append(juz) }
        if let trip = tripItem() { items.append(trip) }
        Self.automaticCache = (key, items)
        return items
    }

    /// The next salary day is the Money room's own forecast (`salaryForecastDays`), on the cycle's calendar.
    private func salaryItem() -> BahwUpcomingItem? {
        let context = ModelContext(session.container), now = now
        guard let cycle = try? MoneyRepository(context: context).cycle(at: now),
              let next = try? AppMoneyService(app: session).salaryForecastDays(cycle: cycle, today: today, zone: prayerLocation().place.timeZone).first else { return nil }
        let span = max(1, MadarCalendarDays.distance(from: cycle.startDay, to: next)), left = MadarCalendarDays.distance(from: today, to: next)
        return .init(id: "auto-salary", title: "الراتب", day: next, daysLeft: left, closed: min(1, max(0, 1 - Double(left) / Double(span))),
                     hijri: session.string("mal.cycleCalendar") == "hijri")
    }

    /// The juz holding the first unmemorised ayah from the plan's start, at the 28-day pace of «رحلتك». No pace, no guess.
    private func juzItem() -> BahwUpcomingItem? {
        guard let value = try? AppQuranService(session: session).snapshot(), let plan = value.plan, !value.coverage.isKhatm,
              let catalog = try? QuranResources.catalog(), let segments = try? catalog.juzCycleSegments(),
              let next = QuranProgressEngine.nextJuz(frontierAyah: try? value.coverage.frontier(from: plan.plan.startAyah), coverage: value.coverage,
                                                     pages: Self.coveragePages(catalog), juzSegments: segments) else { return nil }
        let day = value.day.date
        guard let rate = QuranProgressEngine.pace(activities: value.activities, completedOn: value.completedOn, through: day, restDay: value.restDay).pagesPerHifzDay else { return nil }
        let start = value.sessions.contains { $0.kind == .hifz && $0.dayKey == day } ? day.adding(days: 1) : day
        guard case .estimated(let end) = QuranProgressEngine.forecast(remainingPages: Double(next.remainingPages), dailyPages: rate, startingOn: start, restDay: value.restDay) else { return nil }
        let left = MadarCalendarDays.distance(from: today, to: end)
        guard left >= 0 else { return nil }
        // Short enough for a ring caption: «تمام الجزء ١٥», not «تمام الجزء الخامس عشر» cut off.
        let title = "تمام الجزء " + digits.string(next.juz)
        // The ring closes as the juz fills: pages done out of the juz's pages.
        let span = segments.first { $0.number == next.juz }.map { $0.ayahs.first...$0.ayahs.last }
        let total = span.map { span in Self.coveragePages(catalog).filter { $0.ayahIDs.contains { span.contains($0) } }.count } ?? 0
        return .init(id: "auto-juz-\(next.juz)", title: title, day: end, daysLeft: left, closed: total > 0 ? Double(total - next.remainingPages) / Double(total) : 0, hijri: true)
    }

    /// A trip under way keeps counting from the arrival day: «في إسطنبول، مضى ٣ أيام».
    private func tripItem() -> BahwUpcomingItem? {
        guard let trip = (try? session.prayerSnapshot(at: now))?.activeTrip, !trip.city.isEmpty else { return nil }
        let arrival = GregorianDay.containing(trip.start, in: trip.place.timeZone), elapsed = MadarCalendarDays.distance(from: arrival, to: today)
        guard elapsed >= 0 else { return nil }
        return .init(id: "auto-trip-\(trip.id.uuidString)", title: "في " + trip.city, day: arrival, daysLeft: 0, closed: 1,
                     hijri: session.string("core.firstCalendar") == "hijri", elapsedDays: elapsed > 0 ? elapsed : nil)
    }

    /// The Mushaf layout never changes, so its page→ayah sets are built once per process.
    private static var pagesCache: [QuranCoveragePage]?
    private static func coveragePages(_ catalog: QuranResourceCatalog) -> [QuranCoveragePage] {
        if let pagesCache { return pagesCache }
        let pages = (catalog.layout?.pages ?? []).compactMap { try? QuranCoveragePage(number: $0.page, ayahIDs: Set($0.lines.flatMap(\.words).map(\.ayahID))) }
        pagesCache = pages
        return pages
    }
}
