import Foundation
import MadarCore
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
extension AppQuranService {
    func displayDate(_ day: GregorianDay) -> String { app.dateLabels(day, first: .hijri).combined }
    func yearLog(at instant: Date? = nil) throws -> QuranUIYear {
        try yearLog(from: repository().snapshot(at: instant ?? clock()))
    }
    func yearLog(from value: QuranDataSnapshot) throws -> QuranUIYear {
        let today = value.day.date
        let zone = TimeZone(identifier: value.day.timeZoneID) ?? .gmt
        let gregorianNames = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]
        let names = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
        let hifz = Dictionary(grouping: value.completedOn.values, by: { $0 }).mapValues(\.count)
        let review = Dictionary(grouping: value.sessions.filter { [.review, .free, .qiyam].contains($0.kind) }, by: \.dayKey)
            .mapValues { Set($0.flatMap { $0.grades.map(\.page) }).count }
        let days = (-370...0).map { offset -> QuranUIYearDay in
            let key = today.adding(days: offset)
            let h = HijriCalendar.date(for: key.date(in: zone).addingTimeInterval(43200), timeZone: zone,
                source: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(app.number("core.hijriOffset")))
            return QuranUIYearDay(id: key.description, date: displayDate(key), monthID: "\(h.year)-\(h.month)", month: names[h.month - 1] + " " + numerals.string(h.year), hifz: hifz[key] ?? 0, review: review[key] ?? 0,
                                  gregorianMonth: gregorianNames[key.month - 1] + " " + numerals.string(key.year))
        }
        var months: [QuranUIYearMonth] = [], spans: [String: (first: GregorianDay, last: GregorianDay)] = [:]
        for (offset, day) in days.enumerated() {
            let key = today.adding(days: offset - 370)
            if months.last?.id != day.monthID { months.append(QuranUIYearMonth(id: day.monthID, title: day.month, hifz: 0, review: 0)) }
            months[months.count - 1].hifz += day.hifz; months[months.count - 1].review += day.review
            spans[day.monthID] = (spans[day.monthID]?.first ?? key, key)
        }
        for index in months.indices {
            guard let span = spans[months[index].id] else { continue }
            let a = span.first, b = span.last
            months[index].gregorian = a.month == b.month ? gregorianNames[a.month - 1] + " " + numerals.string(a.year)
                : a.year == b.year ? gregorianNames[a.month - 1] + "–" + gregorianNames[b.month - 1] + " " + numerals.string(b.year)
                : gregorianNames[a.month - 1] + " " + numerals.string(a.year) + "–" + gregorianNames[b.month - 1] + " " + numerals.string(b.year)
        }
        let active = Set(value.activities.filter { $0.countsForStreak && $0.dayKey <= today && $0.dayKey >= today.adding(days: -364) }.map(\.dayKey)).count
        return QuranUIYear(days: days, months: Array(months.suffix(12)), activeDays: active, title: "آخر سنة حتى " + displayDate(today))
    }
}
