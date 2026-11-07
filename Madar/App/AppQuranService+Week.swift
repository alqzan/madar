import Foundation
import MadarCore
import MadarData
import MadarQuran
import MadarCommands

struct QuranUIWeekDay: Identifiable, Sendable {
    var id: String; var label: String; var date: String; var hifz: Int; var review: Int; var partialAyahs: Int
    var eligible: Bool; var active: Bool; var rest: Bool; var today: Bool
    var closed: Bool { !rest && hifz >= 1 && review >= 8 }
}
struct QuranUIWeek: Sendable {
    var days: [QuranUIWeekDay]; var closedDays: Int; var eligibleDays: Int; var activeDays: Int
    var hifz: Int; var review: Int; var hifzChange: String; var reviewChange: String; var activeChange: String
}
extension AppQuranService {
    /// The same rolling seven days as the Quran home and its widget. Rest days never enter the denominator.
    func weeklyLog() throws -> QuranUIWeek {
        try weeklyLog(from: snapshot())
    }
    func weeklyLogOffMain(at instant: Date? = nil) async throws -> QuranUIWeek {
        let (snapshots, _, _) = try await snapshotsOffMain(at: instant ?? clock(), hifzLevels: [nil])
        try Task.checkCancellation()
        guard let value = snapshots.first else { throw DataError.invalidValue("Quran week snapshot") }
        let result = try weeklyLog(from: value)
        try Task.checkCancellation()
        return result
    }
    func weeklyLog(from value: QuranDataSnapshot) throws -> QuranUIWeek {
        let today = value.day.date
        let first = value.sessions.filter { $0.kind == .hifz }.map(\.dayKey).min()
        let active = Set(value.activities.filter(\.countsForStreak).map(\.dayKey))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: value.day.timeZoneID) ?? .gmt
        let weekdays = ["أحد", "اثنين", "ثلاثاء", "أربعاء", "خميس", "جمعة", "سبت"]
        let partial = Set(value.coverage.partialRecentPortions.flatMap { $0.memorizedRanges.flatMap { Array($0.first...$0.last) } })
        let digits = self.numerals
        let hijriSource = HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura
        let sightingOffset = Int(app.number("core.hijriOffset"))
        let hifzByDay = Dictionary(grouping: value.completedOn.values, by: \.self).mapValues(\.count)
        let reviewByDay = Dictionary(grouping: value.sessions.filter { [.review, .free, .qiyam].contains($0.kind) }, by: \.dayKey)
            .mapValues { Set($0.flatMap { $0.grades.map(\.page) }).count }
        var credited: [Int: GregorianDay] = [:]
        for session in value.sessions where session.kind == .hifz {
            for ayah in session.ayahs.first...session.ayahs.last where credited[ayah] == nil { credited[ayah] = session.dayKey }
        }
        let partialAyahsByDay = Dictionary(grouping: credited.filter { partial.contains($0.key) }.map(\.value), by: \.self).mapValues(\.count)
        let firstCalendar = FirstCalendar.hijri // Quran room: Hijri always first (owner, 16 and 22 Oct)
        func day(_ key: GregorianDay) -> QuranUIWeekDay {
            let instant = key.date(in: calendar.timeZone).addingTimeInterval(12 * 3600)
            let weekday = weekdays[calendar.component(.weekday, from: instant) - 1]
            let date = DualDate(instant: instant, timeZone: calendar.timeZone,
                source: hijriSource, sightingOffset: sightingOffset)
                .labels(firstCalendar: firstCalendar, numerals: digits.style).combined
            let eligible = first.map { key >= $0 } == true && !value.restDay.contains(key)
            return QuranUIWeekDay(id: key.description, label: key == today ? "اليوم" : weekday, date: weekday + " " + date,
                hifz: hifzByDay[key] ?? 0, review: reviewByDay[key] ?? 0,
                partialAyahs: partialAyahsByDay[key] ?? 0,
                eligible: eligible, active: active.contains(key), rest: value.restDay.contains(key), today: key == today)
        }
        let days = (-6...0).map { day(today.adding(days: $0)) }, previous = (-13 ... -7).map { day(today.adding(days: $0)) }
        func change(_ current: Int, _ prior: Int) -> String {
            if current == prior { return "مثل الأسبوع الماضي" }
            guard prior > 0 else { return "بداية جديدة هذا الأسبوع" }
            let amount = Int((Double(abs(current - prior)) * 100 / Double(prior)).rounded())
            return digits.percent(amount) + (current > prior ? " أكثر من الأسبوع الماضي" : " أقل من الأسبوع الماضي")
        }
        let hifz = days.reduce(0) { $0 + $1.hifz }, review = days.reduce(0) { $0 + $1.review }
        let work = days.filter { $0.eligible && $0.active }.count, previousWork = previous.filter { $0.eligible && $0.active }.count
        return QuranUIWeek(days: days, closedDays: days.filter { $0.eligible && $0.closed }.count, eligibleDays: days.filter(\.eligible).count, activeDays: work,
            hifz: hifz, review: review, hifzChange: change(hifz, previous.reduce(0) { $0 + $1.hifz }), reviewChange: change(review, previous.reduce(0) { $0 + $1.review }), activeChange: change(work, previousWork))
    }
}
