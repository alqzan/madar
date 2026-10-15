import Foundation
import MadarCore
import MadarCommands
import MadarQuran
import MadarPrayer
import MadarSnapshots

extension AppQuranService {
    func widgetSnapshot() throws -> SnapshotEnvelope<QuranWidgetSnapshot> {
        let value = try snapshot(), today = value.day.date, catalog = try QuranResources.catalog()
        let saved = value.sessions.contains { $0.kind == .hifz && $0.dayKey == today }
        let hasHifz = value.hifz?.portion != nil, hasReview = !value.review.allPages.isEmpty || !value.partialRecent.isEmpty
        let drill = !value.drillBoard.todayQueue.isEmpty || !value.drillBoard.mineQueue.isEmpty
        let title: String, detail: String, route: String
        if !value.drafts.isEmpty { title = "تابع جلستك"; detail = "من الموضع الذي توقفت عنده"; route = "madar://quran" }
        else if let portion = value.hifz?.portion, !saved { title = value.hifz?.balance == .consolidation ? "التالي: التثبيت" : "التالي: الورد"; detail = portionTitle(portion, catalog: catalog); route = "madar://quran/session/hifz" }
        else if hasReview { title = "التالي: المراجعة"; detail = QuranDayCloseCopy.faces(Set(value.review.allPages + value.partialRecent.map(\.page)).count, digits: numerals); route = "madar://quran/session/review" }
        else if drill { title = "التالي: مواضع الخطأ"; detail = "تدريب مواضع تعثّرك"; route = "madar://quran/session/drill" }
        else { title = value.plan == nil ? "ابدأ من القرآن" : "تمّ مسار اليوم"; detail = value.restDay.contains(today) ? "يوم راحة" : "افتح القرآن"; route = "madar://quran" }
        let completed = value.coverage.completedPages.count, juz = value.coverage.completedJuz.count
        let coverage = completed == 0 ? "أول الطريق" : juz > 0 ? count(juz, singular: "جزء واحد", dual: "جزآن", plural: "أجزاء") + (value.coverage.pagesOutsideCompletedJuz.isEmpty ? "" : " و" + QuranDayCloseCopy.faces(value.coverage.pagesOutsideCompletedJuz.count, digits: numerals)) : QuranDayCloseCopy.faces(completed, digits: numerals)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: value.day.timeZoneID) ?? .gmt
        // The Quran home, weekly log and room widget all show the seven days ending today.
        let start = today.adding(days: -6)
        func reviewed(_ day: GregorianDay) -> Int { Set(value.sessions.filter { $0.dayKey == day && [.review, .free, .qiyam].contains($0.kind) }.flatMap { $0.grades.map(\.page) }).count }
        func memorized(_ day: GregorianDay) -> Int { value.completedOn.values.filter { $0 == day }.count }
        let days = (0..<7).map { start.adding(days: $0) }
        let hifzSteps = hasHifz ? (value.hifz?.bridge == nil ? 1 : 2) : 0
        let reviewDone = reviewed(today) > 0 && !hasReview
        let drillDone = value.drillBoard.drilledToday > 0 && !drill
        let payload = QuranWidgetSnapshot(coverage: coverage, fraction: Double(completed) / 604, nextTitle: title, nextDetail: detail, route: route,
            done: (saved ? hifzSteps : 0) + (reviewDone ? 1 : 0) + (drillDone ? 1 : 0), total: hifzSteps + (hasReview || reviewDone ? 1 : 0) + (drill || drillDone ? 1 : 0),
            hifzToday: QuranDayCloseCopy.faces(memorized(today), digits: numerals), reviewToday: QuranDayCloseCopy.faces(reviewed(today), digits: numerals),
            hifzWeek: QuranDayCloseCopy.faces(days.reduce(0) { $0 + memorized($1) }, digits: numerals), reviewWeek: QuranDayCloseCopy.faces(days.reduce(0) { $0 + reviewed($1) }, digits: numerals),
            days: days.map { .init(label: numerals.string($0.day), hifz: Double(memorized($0)), review: Double(reviewed($0)) / 8) })
        let now = clock(), prayerRepository = try PrayerRepository(context: repository().context)
        let place = prayerRepository.place(at: now)
        let civil = GregorianDay.containing(now, in: place.timeZone)
        let options = prayerRepository.activeTrip(at: now) == nil ? prayerRepository.options : prayerRepository.tripOptions
        let prayers = (0...2).compactMap { PrayerTimesEngine.calculate(day: civil.adding(days: $0), place: place, options: options) }
        let boundaries: [Date] = switch value.day.boundary {
        case .fajr: prayers.map(\.fajr)
        case .maghrib: prayers.map(\.maghrib)
        case .midnight: (1...2).map { civil.adding(days: $0).date(in: place.timeZone) }
        }
        let until = min(now.addingTimeInterval(3600), boundaries.filter { $0 > now }.min() ?? now.addingTimeInterval(3600))
        return SnapshotEnvelope(name: "quran", generatedAt: now, validUntil: until, dayKey: value.day.dayKey, tzID: value.day.timeZoneID, privacy: SnapshotPrivacy(), payload: payload)
    }
    func notificationCandidates(prayerDays: [PrayerDay], now: Date) throws -> [NotificationCandidate] {
        let repository = try repository(), guarder = SanctityGuard(prayerDays: prayerDays)
        var result: [NotificationCandidate] = []
        for day in prayerDays {
            for late in [false, true] {
                if late ? !app.bool("quran.lateReminder") : app.string("quran.wirdReminder") == "off" { continue }
                let proposal: Date
                if late { proposal = day.asr }
                else { proposal = switch app.string("quran.wirdReminder") { case "afterAsr": day.asr; case "afterIsha": day.isha; default: day.fajr } }
                let fire = guarder.clamp(proposal)
                guard fire > now, fire <= now.addingTimeInterval(48 * 3600) else { continue }
                let value = try repository.snapshot(at: fire, sessionsThrough: now)
                let needed = late ? value.pages.contains { $0.isDue && !$0.isFar } : Self.needsWird(value)
                if needed { result.append(.init(id: "quran.\(value.day.dayKey).\(late ? "late" : "wird")", room: .quran, dueAt: fire, dayKey: value.day.dayKey)) }
            }
        }
        return result
    }
    static func needsWird(_ value: QuranDataSnapshot) -> Bool {
        let saved = value.sessions.contains { $0.kind == .hifz && $0.dayKey == value.day.date }
        return (value.hifz?.portion != nil && !saved) || !value.review.allPages.isEmpty || !value.partialRecent.isEmpty
    }
}
