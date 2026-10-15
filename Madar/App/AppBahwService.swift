import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarPrayer
import MadarSnapshots

/// §7.1 lobby read models. Every number is read from the room that owns it; the lobby stores only its layout.
struct BahwPrayerModel: Equatable {
    struct Arch: Identifiable, Equatable { let id: String; let name: String; let time: String; let clock24: String; let done: Bool; let next: Bool }
    let arches: [Arch]
    let done: Int
    let nextName: String?
    let nextTime: String?
    let nextAfter: String?
}
struct BahwQuranModel: Equatable {
    let coverage: String
    let next: String
    let days: [QuranWidgetSnapshot.Day]
}
struct BahwDiaryModel: Equatable {
    let count: Int
    let last: Date?
    let photo: Data?
}
struct BahwYearModel: Equatable {
    let hijri: MadarPeriod
    let gregorian: MadarPeriod
    let hijriYear: Int
    let gregorianYear: Int
    let hijriMonthIndex: Int
    let gregorianMonthIndex: Int
    let ramadanIn: Int?
    let landmarks: [MadarLandmark]
}
struct BahwUpcomingItem: Identifiable, Equatable {
    let id: String
    let title: String
    let day: GregorianDay
    let daysLeft: Int
    let closed: Double
    let hijri: Bool
}

@MainActor struct AppBahwService {
    let session: AppSession
    var evaluationDate: Date? = nil
    var now: Date { evaluationDate ?? session.prayerNow() }
    var digits: MadarNumberFormatter { .init(style: session.string("core.numerals") == "western" ? .western : .hindi) }
    var calendarDays: MadarCalendarDays {
        .init(zone: session.activePlace.timeZone, source: HijriSource(rawValue: session.string("core.hijriSource")) ?? .ummAlQura, offset: Int(session.number("core.hijriOffset")))
    }
    /// The Madar day under `core.dayStart` (RL10: never midnight unless chosen).
    var today: GregorianDay {
        let place = session.activePlace, civil = GregorianDay.containing(now, in: place.timeZone)
        let days = [civil.adding(days: -1), civil].compactMap { PrayerTimesEngine.calculate(day: $0, place: place) }
        return (try? MadarDay.resolve(instant: now, place: place, boundary: DayBoundary(rawValue: session.string("core.dayStart")) ?? .fajr, prayerDays: days).date) ?? civil
    }

    func prayer() -> BahwPrayerModel? {
        guard let snapshot = try? session.prayerSnapshot(at: now) else { return nil }
        let names: [Prayer: String] = [.fajr: "الفجر", .dhuhr: "الظهر", .asr: "العصر", .maghrib: "المغرب", .isha: "العشاء"]
        let zone = snapshot.next?.place.timeZone ?? session.activePlace.timeZone, instant = now
        let upcoming = snapshot.next
        func clock(_ date: Date?) -> String {
            guard let date else { return "" }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            let parts = calendar.dateComponents([.hour, .minute], from: date), hour = (parts.hour ?? 0) % 12 == 0 ? 12 : (parts.hour ?? 0) % 12
            return digits.string(hour) + ":" + ((parts.minute ?? 0) < 10 ? digits.string(0) : "") + digits.string(parts.minute ?? 0)
        }
        func clock24(_ date: Date?) -> String {
            guard let date else { return "" }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return digits.localized(String(format: "%02d:%02d", locale: Locale(identifier: "en_US_POSIX"), parts.hour ?? 0, parts.minute ?? 0))
        }
        let arches = snapshot.today.cells.map { cell in
            BahwPrayerModel.Arch(id: cell.reference.prayer.rawValue, name: names[cell.reference.prayer] ?? "", time: clock(cell.prayerTime), clock24: clock24(cell.prayerTime), done: [.jamaah, .alone].contains(cell.status), next: cell.reference == upcoming?.reference)
        }
        return .init(arches: arches, done: arches.filter(\.done).count, nextName: upcoming.flatMap { names[$0.reference.prayer] }, nextTime: clock(upcoming?.time),
                     nextAfter: upcoming.map { $0.time }.map { PrayerCopy.after(seconds: $0.timeIntervalSince(instant), digits: digits) })
    }
    func quran() -> BahwQuranModel? {
        guard let value = try? AppQuranService(session: session).widgetSnapshot().payload else { return nil }
        return .init(coverage: value.coverage, next: value.nextTitle, days: value.days)
    }
    func diary() -> BahwDiaryModel? {
        let service = AppDiaryService(app: session)
        guard let page = try? service.day(today) else { return nil }
        let lines = page.lines.filter { ["normal", "late", "margin"].contains($0.kind) }
        return .init(count: lines.count, last: lines.map(\.at).max(), photo: page.photo)
    }
    func year() -> BahwYearModel {
        let days = calendarDays, day = today
        return .init(hijri: MadarYear.hijriYear(day, days), gregorian: MadarYear.gregorianYear(day), hijriYear: days.hijri(day).year, gregorianYear: day.year,
                     hijriMonthIndex: days.hijri(day).month - 1, gregorianMonthIndex: day.month - 1, ramadanIn: MadarYear.ramadanIn(day, days), landmarks: MadarYear.landmarks(day, days))
    }
    /// User days (stored rules) and the seasons as read models; a user day with the same title and date hides the automatic one.
    func upcoming(limit: Int) -> [BahwUpcomingItem] {
        let days = calendarDays, day = today
        var items: [BahwUpcomingItem] = []
        if let rows = try? ModelContext(session.container).fetch(FetchDescriptor<UpcomingDay>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil })) {
            for row in rows {
                let rule = MadarUpcomingRule(calendar: row.calendar == "hijri" ? .hijri : .gregorian, year: row.year, month: row.month, day: row.day,
                                             repeats: MadarUpcomingRule.Repeats(rawValue: row.repeats) ?? .yearly, countFrom: try? GregorianDay(row.countFromDayKey))
                if let ring = rule.ring(today: day, days) { items.append(.init(id: row.id.uuidString, title: row.title, day: ring.next, daysLeft: ring.daysLeft, closed: ring.closed, hijri: rule.calendar == .hijri)) }
            }
        }
        let seasons: [(String, Int, Int)] = [("رمضان", 9, 1), ("عيد الفطر", 10, 1), ("يوم عرفة", 12, 9), ("عيد الأضحى", 12, 10)]
        for (title, month, date) in seasons {
            let rule = MadarUpcomingRule(calendar: .hijri, month: month, day: date, repeats: .yearly)
            guard let ring = rule.ring(today: day, days), !items.contains(where: { $0.title == title && $0.day == ring.next }) else { continue }
            items.append(.init(id: "season-\(month)-\(date)", title: title, day: ring.next, daysLeft: ring.daysLeft, closed: ring.closed, hijri: true))
        }
        return Array(items.sorted { $0.daysLeft == $1.daysLeft ? $0.title < $1.title : $0.daysLeft < $1.daysLeft }.prefix(limit))
    }

    /// One visual scale for all lobby countdowns; recurrence-cycle progress stays unchanged in the year room.
    func upcomingCloseness(daysLeft: Int) -> Double {
        1 - min(1, max(0, Double(daysLeft) / Double(MadarYear.gregorianYear(today).length)))
    }
    func dayCount(_ n: Int) -> String {
        if n == 1 { return "يوم" }; if n == 2 { return "يومان" }
        let r = n % 100; return (3...10).contains(r) ? "أيام" : (r <= 2 && n >= 100) ? "يوم" : "يومًا"
    }
    func lineCount(_ n: Int) -> String {
        switch n { case 0: "لا سطور بعد"; case 1: "سطر واحد"; case 2: "سطران"; default: digits.string(n) + ((3...10).contains(n % 100) ? " أسطر" : " سطرًا") }
    }
    func shortDate(_ day: GregorianDay, hijri: Bool) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ar_SA@numbers=" + (session.string("core.numerals") == "western" ? "latn" : "arab"))
        formatter.calendar = Calendar(identifier: hijri ? .islamicUmmAlQura : .gregorian); formatter.timeZone = session.activePlace.timeZone; formatter.dateFormat = "d MMMM"
        let noon = day.date(in: session.activePlace.timeZone).addingTimeInterval(12 * 3600)
        return formatter.string(from: hijri && session.string("core.hijriSource") == "sighting" ? noon.addingTimeInterval(session.number("core.hijriOffset") * 86_400) : noon)
    }
    func time(_ at: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ar_SA@numbers=" + (session.string("core.numerals") == "western" ? "latn" : "arab"))
        formatter.timeZone = session.activePlace.timeZone; formatter.dateFormat = "h:mm a"
        return formatter.string(from: at)
    }
}
