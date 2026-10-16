import Foundation
import MadarCore
import MadarCommands
import MadarQuran

extension AppQuranService {
    /// §7.4 Q07: both strength caches are evaluated on today's stored Madar day.
    /// Filtering facts is read-only; no day-close record or second session is written.
    func dayClose() throws -> QuranUIDayClose {
        let now = clock(), repository = try repository(), catalog = try QuranResources.catalog()
        let after = try repository.snapshot(at: now), day = after.day.date
        let before = try repository.snapshot(at: now, excludingSessionDay: day)
        let today = after.sessions.filter { $0.dayKey == day }
        let reviewed = Set(today.filter { [.review, .free, .qiyam].contains($0.kind) }.flatMap { $0.grades.map(\.page) })
        func mean(_ pages: [QuranPlanningPage]) -> Int? {
            QuranProgressEngine.meanStrength(pages).map { Int($0.rounded()) }
        }
        let surahs = Set(reviewed.flatMap { catalog.ayahs(on: $0).map(\.surahID) })
        let strengths = surahs.sorted().compactMap { id -> QuranUIDayCloseStrength? in
            guard let first = catalog.ayahs.first(where: { $0.surahID == id }) else { return nil }
            let pages = reviewed.filter { catalog.ayahs(on: $0).contains { $0.surahID == id } }
            return QuranUIDayCloseStrength(id: id, title: first.surahNameArabic,
                before: mean(before.pages.filter { pages.contains($0.page) }), after: mean(after.pages.filter { pages.contains($0.page) }))
        }
        // Move one civil day in the stored timezone; the repository resolves core.dayStart again.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: after.day.timeZoneID) ?? .gmt
        let nextInstant = calendar.date(byAdding: .day, value: 1, to: now)!
        let next = try repository.snapshot(at: nextInstant, sessionsThrough: now)
        let hifz: String
        if let portion = next.hifz?.portion {
            hifz = (next.hifz?.balance == .consolidation ? "تثبيت: " : "الحفظ: ") + portionTitle(portion, catalog: catalog)
        } else {
            hifz = next.restDay.contains(next.day.date) ? "يوم راحة، مراجعة فقط" : next.plan == nil ? "لا خطة حفظ بعد" : "لا حفظ جديد"
        }
        let nextReview = Set(next.review.allPages + next.partialRecent.map(\.page)).count
        let tomorrow = hifz + "، المراجعة: " + QuranDayCloseCopy.faces(nextReview, digits: numerals)
        let savedHifz = Set(today.filter { $0.kind == .hifz }.flatMap { Array($0.ayahs.first...$0.ayahs.last) })
        let hifzComplete = before.hifz?.portion.map { Set($0.first...$0.last).isSubset(of: savedHifz) } ?? true
        let reviewComplete = after.review.allPages.isEmpty && after.partialRecent.isEmpty
        let drillsComplete = after.drillBoard.todayQueue.isEmpty && after.drillBoard.mineQueue.isEmpty
        let complete = !today.isEmpty && before.plan != nil && hifzComplete && reviewComplete && drillsComplete
        let streak = QuranProgressEngine.streak(activities: after.activities, through: day, restDay: after.restDay)
        let dayInstant = day.date(in: calendar.timeZone).addingTimeInterval(12 * 3600)
        let firstCalendar = FirstCalendar.hijri // Quran room: Hijri always first (owner, 16 Oct)
        let date = DualDate(instant: dayInstant, timeZone: calendar.timeZone,
            source: HijriSource(rawValue: app.values["core.hijriSource"]?.string ?? "ummAlQura") ?? .ummAlQura,
            sightingOffset: Int(app.values["core.hijriOffset"]?.number ?? 0))
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ar_SA-u-nu-latn")
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = "EEEE"
        let weekday = formatter.string(from: dayInstant)
        formatter.dateFormat = "d MMMM yyyy"
        let dateTitle = date.labels(firstCalendar: firstCalendar, numerals: numerals.style).combined
        return QuranUIDayClose(title: complete ? "أتممت يومك" : "حصيلة يومك", dateAndStreak: weekday + " " + dateTitle + "، سلسلتك " + PrayerCopy.days(streak.days, digits: numerals),
            beforeFaces: before.coverage.completedPages.count, afterFaces: after.coverage.completedPages.count,
            addedFaces: after.coverage.completedPages.subtracting(before.coverage.completedPages).count,
            addedAyahs: after.coverage.coveredAyahs.subtracting(before.coverage.coveredAyahs).count,
            reviewedFaces: reviewed.count, strengthBefore: mean(before.pages), strengthAfter: mean(after.pages),
            strengths: strengths, tomorrow: tomorrow, isKhatm: after.coverage.isKhatm)
    }
}

/// RU3: plural selection and the owner's digit preference are separate catalog arguments.
enum QuranDayCloseCopy {
    static func faces(_ count: Int, digits: MadarNumberFormatter) -> String {
        let formatted = digits.string(count)
        return String(localized: "quran.faces", defaultValue: "\(count) \(formatted)", table: "Quran", locale: Locale(identifier: "ar"))
    }
    static func ayahs(_ count: Int, digits: MadarNumberFormatter) -> String {
        let formatted = digits.string(count)
        return String(localized: "quran.memorizedAyahs", defaultValue: "\(count) \(formatted)", table: "Quran", locale: Locale(identifier: "ar"))
    }
}
