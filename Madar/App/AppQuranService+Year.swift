import Foundation
import MadarCore
import MadarData
import MadarCommands
import MadarQuran

struct QuranUIYearDay: Identifiable, Sendable {
    var id: String; var date: String; var monthID: String; var month: String; var hifz: Int; var review: Int
    /// Both calendars always (owner, 15 Oct): the Gregorian month under the Hijri one.
    var gregorianMonth: String = ""
}
struct QuranUIYearMonth: Identifiable, Sendable {
    var id: String; var title: String; var hifz: Int; var review: Int
    /// The Gregorian months the Hijri month spans, e.g. «سبتمبر–أكتوبر ٢٠٢٦».
    var gregorian: String = ""
}
struct QuranUIYear: Sendable {
    var days: [QuranUIYearDay]; var months: [QuranUIYearMonth]; var activeDays: Int; var title: String
}
private struct QuranYearProjectionConfiguration: Sendable {
    let hijriSource: HijriSource
    let sightingOffset: Int
    let displayTimeZone: TimeZone
    let numerals: MadarNumberFormatter
}

extension AppQuranService {
    func displayDate(_ day: GregorianDay) -> String { app.dateLabels(day, first: .hijri).combined }
    func yearLog(at instant: Date? = nil) throws -> QuranUIYear {
        try yearLog(from: repository().snapshot(at: instant ?? clock()))
    }
    func yearLog(from value: QuranDataSnapshot) throws -> QuranUIYear {
        try Self.projectYearLog(from: value, configuration: yearProjectionConfiguration)
    }
    func yearLogOffMain(at instant: Date? = nil) async throws -> QuranUIYear {
        let (snapshots, _, _) = try await snapshotsOffMain(at: instant ?? clock(), hifzLevels: [nil])
        guard let snapshot = snapshots.first else { throw DataError.invalidValue("Quran year snapshot") }
        return try await yearLogOffMain(from: snapshot)
    }
    func yearLogOffMain(from value: QuranDataSnapshot) async throws -> QuranUIYear {
        let configuration = yearProjectionConfiguration
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = try Self.projectYearLog(from: value, configuration: configuration)
            try Task.checkCancellation()
            return result
        }
        let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        return result
    }
    func yearDaysOffMain(from value: QuranDataSnapshot, count: Int) async throws -> [QuranUIYearDay] {
        guard count > 0 else { return [] }
        let configuration = yearProjectionConfiguration
        let lowerOffset = -(min(371, count) - 1)
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = try Self.projectYearDays(from: value, offsets: lowerOffset...0, configuration: configuration)
            try Task.checkCancellation()
            return result
        }
        let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        return result
    }

    private var yearProjectionConfiguration: QuranYearProjectionConfiguration {
        QuranYearProjectionConfiguration(
            hijriSource: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura,
            sightingOffset: Int(app.number("core.hijriOffset")),
            displayTimeZone: app.activePlace.timeZone,
            numerals: numerals)
    }

    nonisolated private static func projectYearDays(
        from value: QuranDataSnapshot,
        offsets: ClosedRange<Int>,
        configuration: QuranYearProjectionConfiguration
    ) throws -> [QuranUIYearDay] {
        let today = value.day.date
        let zone = TimeZone(identifier: value.day.timeZoneID) ?? .gmt
        let gregorianNames = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]
        let names = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
        let hifz = Dictionary(grouping: value.completedOn.values, by: { $0 }).mapValues(\.count)
        let review = Dictionary(grouping: value.sessions.filter { [.review, .free, .qiyam].contains($0.kind) }, by: \.dayKey)
            .mapValues { Set($0.flatMap { $0.grades.map(\.page) }).count }
        return try offsets.map { offset in
            try Task.checkCancellation()
            let key = today.adding(days: offset)
            let hijri = HijriCalendar.date(for: key.date(in: zone).addingTimeInterval(43_200), timeZone: zone,
                source: configuration.hijriSource, sightingOffset: configuration.sightingOffset)
            let displayed = DualDate(
                instant: key.date(in: configuration.displayTimeZone).addingTimeInterval(43_200),
                timeZone: configuration.displayTimeZone, source: configuration.hijriSource,
                sightingOffset: configuration.sightingOffset)
                .labels(firstCalendar: .hijri, numerals: configuration.numerals.style).combined
            return QuranUIYearDay(
                id: key.description, date: displayed, monthID: "\(hijri.year)-\(hijri.month)",
                month: names[hijri.month - 1] + " " + configuration.numerals.string(hijri.year),
                hifz: hifz[key] ?? 0, review: review[key] ?? 0,
                gregorianMonth: gregorianNames[key.month - 1] + " " + configuration.numerals.string(key.year))
        }
    }

    nonisolated private static func projectYearLog(
        from value: QuranDataSnapshot,
        configuration: QuranYearProjectionConfiguration
    ) throws -> QuranUIYear {
        let today = value.day.date
        let gregorianNames = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]
        let days = try projectYearDays(from: value, offsets: -370...0, configuration: configuration)
        var months: [QuranUIYearMonth] = [], spans: [String: (first: GregorianDay, last: GregorianDay)] = [:]
        for (offset, day) in days.enumerated() {
            let key = today.adding(days: offset - 370)
            if months.last?.id != day.monthID { months.append(QuranUIYearMonth(id: day.monthID, title: day.month, hifz: 0, review: 0)) }
            months[months.count - 1].hifz += day.hifz
            months[months.count - 1].review += day.review
            spans[day.monthID] = (spans[day.monthID]?.first ?? key, key)
        }
        for index in months.indices {
            guard let span = spans[months[index].id] else { continue }
            let a = span.first, b = span.last
            months[index].gregorian = a.month == b.month ? gregorianNames[a.month - 1] + " " + configuration.numerals.string(a.year)
                : a.year == b.year ? gregorianNames[a.month - 1] + "–" + gregorianNames[b.month - 1] + " " + configuration.numerals.string(b.year)
                : gregorianNames[a.month - 1] + " " + configuration.numerals.string(a.year) + "–" + gregorianNames[b.month - 1] + " " + configuration.numerals.string(b.year)
        }
        let active = Set(value.activities.filter { $0.countsForStreak && $0.dayKey <= today && $0.dayKey >= today.adding(days: -364) }.map(\.dayKey)).count
        let titleDate = DualDate(
            instant: today.date(in: configuration.displayTimeZone).addingTimeInterval(43_200),
            timeZone: configuration.displayTimeZone, source: configuration.hijriSource,
            sightingOffset: configuration.sightingOffset)
            .labels(firstCalendar: .hijri, numerals: configuration.numerals.style).combined
        return QuranUIYear(days: days, months: Array(months.suffix(12)), activeDays: active, title: "آخر سنة حتى " + titleDate)
    }
}
