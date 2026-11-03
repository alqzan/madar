import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarPrayer
import MadarCommands
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
    let lastTZID: String?
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
    /// Set once a one-time day that keeps counting (`countUpAfter`) has passed: whole days since it.
    var elapsedDays: Int? = nil
    /// The number the ring shows: days left, or days since for a day that keeps counting.
    var count: Int { elapsedDays ?? daysLeft }
}

@MainActor struct AppBahwService {
    let session: AppSession
    var evaluationDate: Date? = nil
    var now: Date { evaluationDate ?? session.prayerNow() }
    var digits: MadarNumberFormatter { .init(style: session.string("core.numerals") == "western" ? .western : .hindi) }
    func prayerLocation() -> (place: ActivePlace, options: PrayerCalculationOptions) {
        guard let repository = try? PrayerRepository(context: ModelContext(session.container)) else { return (session.activePlace, .init()) }
        return (repository.place(at: now), repository.calculationOptions(at: now))
    }
    var greeting: String {
        let location = prayerLocation(), day = GregorianDay.containing(now, in: location.place.timeZone)
        guard let times = PrayerTimesEngine.calculate(day: day, place: location.place, options: location.options) else { return "أهلًا بك" }
        return now >= times.fajr && now < times.dhuhr ? "صباح الخير" : "مساء الخير"
    }
    var calendarDays: MadarCalendarDays {
        .init(zone: prayerLocation().place.timeZone, source: HijriSource(rawValue: session.string("core.hijriSource")) ?? .ummAlQura, offset: Int(session.number("core.hijriOffset")))
    }
    /// The Madar day under `core.dayStart` (RL10: never midnight unless chosen).
    var today: GregorianDay {
        let location = prayerLocation(), place = location.place, civil = GregorianDay.containing(now, in: place.timeZone)
        let days = [civil.adding(days: -1), civil].compactMap { PrayerTimesEngine.calculate(day: $0, place: place, options: location.options) }
        return (try? MadarDay.resolve(instant: now, place: place, boundary: DayBoundary(rawValue: session.string("core.dayStart")) ?? .fajr, prayerDays: days).date) ?? civil
    }

    /// W2's black clock dots show elapsed time, independently of a habit's completion or reminder window.
    func habitOrbitPositions() -> [HabitFrequency: Double] {
        let location = prayerLocation(), place = location.place, day = today
        let boundary = DayBoundary(rawValue: session.string("core.dayStart")) ?? .fajr
        func start(_ key: GregorianDay) -> Date? {
            DiaryFreeze.dayEnd(day: key.adding(days: -1), boundary: boundary, timeZone: place.timeZone,
                nextDay: PrayerTimesEngine.calculate(day: key, place: place, options: location.options))
        }
        guard let from = start(day), let to = start(day.adding(days: 1)), to > from else { return [:] }
        let daily = min(1, max(0, now.timeIntervalSince(from) / to.timeIntervalSince(from)))
        let days = MadarCalendarDays(zone: place.timeZone, source: HijriSource(rawValue: session.string("core.hijriSource")) ?? .ummAlQura, offset: Int(session.number("core.hijriOffset")))
        let hijri = session.string("core.firstCalendar") == "hijri"
        let periods: [(HabitFrequency, MadarPeriod)] = [
            (.weekly, MadarYear.week(day, start: MadarWeekStart(rawValue: session.string("core.weekStart")) ?? .saturday)),
            (.monthly, hijri ? MadarYear.hijriMonth(day, days) : MadarYear.gregorianMonth(day)),
            (.yearly, hijri ? MadarYear.hijriYear(day, days) : MadarYear.gregorianYear(day))
        ]
        var positions: [HabitFrequency: Double] = [.daily: daily]
        for (frequency, period) in periods { positions[frequency] = (Double(period.elapsed) + daily) / Double(period.length) }
        return positions
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
        // §7.2: on Friday the Dhuhr arch reads «الجمعة» here as in the prayer room.
        func name(_ reference: PrayerReference) -> String? {
            snapshot.today.cells.contains { $0.reference == reference && $0.isFriday && reference.prayer == .dhuhr } ? "الجمعة" : names[reference.prayer]
        }
        let arches = snapshot.today.cells.map { cell in
            BahwPrayerModel.Arch(id: cell.reference.prayer.rawValue, name: name(cell.reference) ?? "", time: clock(cell.prayerTime), clock24: clock24(cell.prayerTime), done: [.jamaah, .alone].contains(cell.status), next: cell.reference == upcoming?.reference)
        }
        return .init(arches: arches, done: arches.filter(\.done).count, nextName: upcoming.flatMap { name($0.reference) }, nextTime: clock(upcoming?.time),
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
        let last = lines.max { $0.at < $1.at }
        return .init(count: lines.count, last: last?.at, lastTZID: last?.tzID, photo: page.photo)
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
                                             repeats: MadarUpcomingRule.Repeats(rawValue: row.repeats) ?? .yearly, countFrom: try? GregorianDay(row.countFromDayKey), countUpAfter: row.countUpAfter)
                if let counter = rule.counter(today: day, days) {
                    items.append(.init(id: row.id.uuidString, title: row.title, day: counter.occurrence, daysLeft: counter.daysLeft, closed: counter.closed, hijri: rule.calendar == .hijri, elapsedDays: counter.elapsedDays))
                }
            }
        }
        let seasons: [(String, Int, Int)] = [("رمضان", 9, 1), ("عيد الفطر", 10, 1), ("يوم عرفة", 12, 9), ("عيد الأضحى", 12, 10)]
        for (title, month, date) in seasons {
            let rule = MadarUpcomingRule(calendar: .hijri, month: month, day: date, repeats: .yearly)
            guard let ring = rule.ring(today: day, days), !items.contains(where: { $0.title == title && $0.day == ring.next }) else { continue }
            items.append(.init(id: "season-\(month)-\(date)", title: title, day: ring.next, daysLeft: ring.daysLeft, closed: ring.closed, hijri: true))
        }
        return Array(items.sorted { Self.nearestFirst(($0.elapsedDays, $0.daysLeft, $0.title), ($1.elapsedDays, $1.daysLeft, $1.title)) }.prefix(limit))
    }
    /// Days still ahead come first, nearest first; days that keep counting follow, the most recent first.
    static func nearestFirst(_ a: (Int?, Int, String), _ b: (Int?, Int, String)) -> Bool {
        switch (a.0, b.0) {
        case (nil, .some): return true
        case (.some, nil): return false
        case let (.some(x), .some(y)) where x != y: return x < y
        case (nil, nil) where a.1 != b.1: return a.1 < b.1
        default: return a.2 < b.2
        }
    }
    /// «مضى» wording under a count-up number, agreeing with the count.
    func sinceCount(_ n: Int) -> String {
        n == 1 ? "يوم مضى" : n == 2 ? "يومان مضيا" : dayCount(n) + ((3...10).contains(n % 100) ? " مضت" : " مضى")
    }
    /// «مضى يوم»، «مضى يومان»، «مضت ٥ أيام»، «مضى ٤٠ يومًا»: no digit beside the singular or dual word.
    func sincePhrase(_ n: Int) -> String {
        n == 1 ? "مضى يوم" : n == 2 ? "مضى يومان" : ((3...10).contains(n % 100) ? "مضت " : "مضى ") + digits.string(n) + " " + dayCount(n)
    }
    /// One line for a day: «بعد ٥ أيام» ahead, «اليوم» on it, «مضى ٤٠ يومًا» after it when it keeps counting.
    func countPhrase(daysLeft: Int, elapsed: Int?) -> String {
        if let elapsed { return sincePhrase(elapsed) }
        return daysLeft == 0 ? "اليوم" : daysLeft == 1 ? "بعد يوم" : daysLeft == 2 ? "بعد يومين" : "بعد " + digits.string(daysLeft) + " " + dayCount(daysLeft)
    }

    /// One visual scale for all lobby countdowns; recurrence-cycle progress stays unchanged in the year room.
    func upcomingCloseness(daysLeft: Int) -> Double {
        1 - min(1, max(0, Double(daysLeft) / Double(MadarYear.gregorianYear(today).length)))
    }
    /// «يوم واحد»، «يومان» (after a preposition «يومين»)، «٣ أيام»: one and two take no digit (audit 28 Oct: «بقي ١ يوم»، «٢ يومان»).
    func daysPhrase(_ n: Int, afterPreposition: Bool = false) -> String {
        if n == 1 { return "يوم واحد" }; if n == 2 { return afterPreposition ? "يومين" : "يومان" }
        return digits.string(n) + " " + dayCount(n)
    }
    func dayCount(_ n: Int) -> String {
        if n == 1 { return "يوم" }; if n == 2 { return "يومان" }
        let r = n % 100; return (3...10).contains(r) ? "أيام" : (r <= 2 && n >= 100) ? "يوم" : "يومًا"
    }
    func lineCount(_ n: Int) -> String {
        switch n { case 0: "لا سطور بعد"; case 1: "سطر واحد"; case 2: "سطران"; default: digits.string(n) + ((3...10).contains(n % 100) ? " أسطر" : " سطرًا") }
    }
    func shortDate(_ day: GregorianDay, hijri: Bool) -> String {
        session.dateLabels(day, first: hijri ? .hijri : .gregorian, compact: true).primary
    }

    func time(_ at: Date, zone: String? = nil) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ar_SA@numbers=" + (session.string("core.numerals") == "western" ? "latn" : "arab"))
        formatter.timeZone = zone.flatMap(TimeZone.init(identifier:)) ?? session.activePlace.timeZone; formatter.dateFormat = "h:mm a"
        return formatter.string(from: at)
    }
}


struct BahwSuggestion: Identifiable {
    enum Destination { case prayer, habit(UUID), quran, diary, money, mihbara(book: UUID?) }
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let destination: Destination
}

extension AppBahwService {
    /// Owner 27 Oct: levels add useful in-app steps; they never schedule a notification or write a room's facts.
    func suggestions() -> [BahwSuggestion] {
        guard session.lockController?.canPresent(.app) ?? session.protectedDataAuthorized else { return [] }
        let level = session.string("bahw.smartPresence")
        let includesToday = ["medium", "present"].contains(level)
        var result: [BahwSuggestion] = []
        if let snapshot = try? session.prayerSnapshot(at: now),
           snapshot.today.cells.contains(where: { snapshot.pending.contains($0.reference) && $0.canLog }) {
            result.append(.init(id: "prayer", title: "كيف صلّيت؟", detail: "صلاة تنتظر تسجيلك، متى كنت مستعدًا", symbol: "MadarPrayer", destination: .prayer))
        }
        let readings = (try? HabitRepository(context: ModelContext(session.container)).readings(at: now)) ?? []
        let due = readings.filter { !$0.paused && $0.summary.current?.met != true && ($0.summary.current?.target ?? 0) > 0 && $0.summary.current?.dueDays.contains(today) == true }
        if session.roomEnabled(.habits), let habit = due.first(where: \.isNow) ?? (includesToday ? due.first : nil) {
            result.append(.init(id: "habit", title: habit.name, detail: habit.isNow ? "وقتها الآن" : "خطوة صغيرة مما تبقّى اليوم", symbol: "MadarHabits", destination: .habit(habit.id)))
        }
        if includesToday, session.roomEnabled(.quran), let quran = try? AppQuranService(session: session).widgetSnapshot().payload,
           quran.done < quran.total {
            result.append(.init(id: "quran", title: quran.nextTitle, detail: quran.nextDetail, symbol: "MadarQuran", destination: .quran))
        }
        if level == "present" {
            if session.roomEnabled(.notes), let diary = diary(), diary.count == 0 {
                result.append(.init(id: "notes", title: "سطر من يومك", detail: "ما الذي تحب أن يبقى من هذا اليوم؟", symbol: "MadarDiary", destination: .diary))
            }
            if session.roomEnabled(.mal), let money = try? AppMoneyService(app: session).load(at: now), money.pendingCount > 0 {
                result.append(.init(id: "money", title: "راجع رسائلك البنكية", detail: "رسائل تنتظر قرارك قبل أن تصبح حركات", symbol: "banknote", destination: .money))
            }
            if session.roomEnabled(.mihbara), let book = session.mihbaraWidgetSnapshot(locked: false, at: now).currentBook {
                result.append(.init(id: "mihbara", title: "أكمل «" + book.title + "»", detail: book.currentPage.map { "موضعك محفوظ عند الصفحة " + digits.string($0) } ?? "ابدأ القراءة من رحل المحبرة", symbol: "books.vertical", destination: .mihbara(book: book.id)))
            }
        }
        return result
    }
}
