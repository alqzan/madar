import Foundation
import MadarCore
import MadarCommands
import MadarQuran
import MadarPrayer
import MadarSnapshots

struct PlannedQuranReminderDetail {
    let line: String?
}

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
        else {
            // OR-20: a finished day still points somewhere: one surah from what the user holds, rotating by day, to read in prayer.
            let held = Array(Set(value.coverage.completedPages.compactMap { catalog.ayahs(on: $0).first?.surahID })).sorted()
            let surah = held.isEmpty ? nil : catalog.ayahs.first { $0.surahID == held[(today.year * 372 + today.month * 31 + today.day) % held.count] }?.surahNameArabic
            title = value.plan == nil ? "ابدأ من القرآن" : "تمّ مسار اليوم"
            detail = value.restDay.contains(today) ? "يوم راحة" : value.plan != nil && surah != nil ? "اقرأ في صلاتك من " + surah! : "افتح القرآن"
            route = "madar://quran"
        }
        let completed = value.coverage.completedPages.count, juz = value.coverage.completedJuz.count
        let coverage = completed == 0 ? "أول الطريق" : juz > 0 ? count(juz, singular: "جزء واحد", dual: "جزآن", plural: "أجزاء") + (value.coverage.pagesOutsideCompletedJuz.isEmpty ? "" : " و" + QuranDayCloseCopy.faces(value.coverage.pagesOutsideCompletedJuz.count, digits: numerals)) : QuranDayCloseCopy.faces(completed, digits: numerals)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: value.day.timeZoneID) ?? .gmt
        // The Quran home, weekly log and room widget all show the seven days ending today.
        let start = today.adding(days: -6)
        func reviewed(_ day: GregorianDay) -> Int { Set(value.sessions.filter { $0.dayKey == day && [.review, .free, .qiyam].contains($0.kind) }.flatMap { $0.grades.map(\.page) }).count }
        func memorized(_ day: GregorianDay) -> Int { value.completedOn.values.filter { $0 == day }.count }
        let days = (0..<7).map { start.adding(days: $0) }
        let reviewedFaces = Set(value.sessions.filter { $0.dayKey == today && [.review, .free, .qiyam].contains($0.kind) }.flatMap { $0.grades.map(\.page) })
        let reviewFaces = reviewedFaces.union(value.review.allPages).union(value.partialRecent.map(\.page))
        let reviewProgress = reviewFaces.isEmpty ? nil : numerals.string(reviewedFaces.count) + " من " + numerals.string(reviewFaces.count)
        let hifzSteps = hasHifz ? 1 : 0
        let reviewDone = reviewed(today) > 0 && !hasReview
        let drillDone = value.drillBoard.drilledToday > 0 && !drill
        let done = (saved ? hifzSteps : 0) + (reviewDone ? 1 : 0) + (drillDone ? 1 : 0), total = hifzSteps + (hasReview || reviewDone ? 1 : 0) + (drill || drillDone ? 1 : 0)
        let dayLine = total == 0 ? nil : done >= total ? "أتممت خطوات اليوم كلها" : done > 0 ? "أتممت " + numerals.string(done) + " من " + numerals.string(total)
            : total == 1 ? "خطوة واحدة اليوم" : total == 2 ? "خطوتان اليوم" : numerals.string(total) + " خطوات اليوم"
        let payload = QuranWidgetSnapshot(coverage: coverage, fraction: Double(completed) / 604, nextTitle: title, nextDetail: detail, route: route,
            done: done, total: total,
            hifzToday: QuranDayCloseCopy.faces(memorized(today), digits: numerals), reviewToday: QuranDayCloseCopy.faces(reviewed(today), digits: numerals),
            hifzWeek: QuranDayCloseCopy.faces(days.reduce(0) { $0 + memorized($1) }, digits: numerals), reviewWeek: QuranDayCloseCopy.faces(days.reduce(0) { $0 + reviewed($1) }, digits: numerals),
            days: days.map { .init(label: numerals.string($0.day), hifz: Double(memorized($0)), review: Double(reviewed($0)) / 8) }, dayLine: dayLine, reviewProgress: reviewProgress)
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
        // Keep only the details prepared by this session's latest plan.
        app.plannedQuranReminderDetails.removeAll()
        let repository = try repository(), guarder = SanctityGuard(prayerDays: prayerDays)
        var result: [NotificationCandidate] = []
        var details: [String: PlannedQuranReminderDetail] = [:]
        for day in prayerDays {
            // Owner, 17 Nov 2026: the wird is asked after Fajr, and if it is still not done, asked once more after Isha («again»).
            for kind in ["wird", "again", "late"] {
                let late = kind == "late", choice = app.string("quran.wirdReminder")
                if late ? !app.bool("quran.lateReminder") : choice == "off" { continue }
                if kind == "again" && choice != "afterFajr" { continue }
                let proposal: Date
                if late { proposal = day.asr }
                else if kind == "again" { proposal = day.isha }
                else { proposal = switch choice { case "afterAsr": day.asr; case "afterIsha": day.isha; default: day.fajr } }
                let fire = guarder.clamp(proposal)
                guard fire > now, fire <= now.addingTimeInterval(48 * 3600) else { continue }
                let value = try repository.snapshot(at: fire, sessionsThrough: now)
                let needed = late ? value.pages.contains { $0.isDue && !$0.isFar } : Self.needsWird(value)
                if needed {
                    let id = "quran.\(value.day.dayKey).\(kind)"
                    result.append(.init(id: id, room: .quran, dueAt: fire, dayKey: value.day.dayKey))
                    // The words the reminder will say come from the snapshot already read here, not from a second read per request.
                    details[id] = PlannedQuranReminderDetail(line: reminderDetail(value, late: late))
                }
            }
        }
        app.plannedQuranReminderDetails = details
        return result
    }
    /// What a Quran reminder names at the moment it fires (notifications audit, 23 Nov): the day's hifz portion, else the faces
    /// waiting for review; the late reminder names the faces due before they drift. Nil keeps the gentle wording alone.
    func reminderDetail(at fire: Date, late: Bool) -> String? {
        guard let value = try? repository().snapshot(at: fire, sessionsThrough: clock()) else { return nil }
        return reminderDetail(value, late: late)
    }
    func reminderDetail(_ value: QuranDataSnapshot, late: Bool) -> String? {
        if late {
            let due = value.pages.filter { $0.isDue && !$0.isFar }.count
            let drift = due == 1 ? " قبل أن يبعد عنك" : due == 2 ? " قبل أن يبعدا عنك" : " قبل أن تبعد عنك"
            return due > 0 ? QuranDayCloseCopy.faces(due, digits: numerals) + " في مراجعتك" + drift : nil
        }
        let saved = value.sessions.contains { $0.kind == .hifz && $0.dayKey == value.day.date }
        if let portion = value.hifz?.portion, !saved, let catalog = try? QuranResources.catalog() {
            let title = portionTitle(portion, catalog: catalog)
            if !title.isEmpty { return (value.hifz?.balance == .consolidation ? "تثبيت اليوم: " : "ورد اليوم: ") + title }
        }
        let review = Set(value.review.allPages + value.partialRecent.map(\.page)).count
        return review > 0 ? "مراجعة اليوم: " + QuranDayCloseCopy.faces(review, digits: numerals) : nil
    }
    static func needsWird(_ value: QuranDataSnapshot) -> Bool {
        let saved = value.sessions.contains { $0.kind == .hifz && $0.dayKey == value.day.date }
        return (value.hifz?.portion != nil && !saved) || !value.review.allPages.isEmpty || !value.partialRecent.isEmpty
    }
}
