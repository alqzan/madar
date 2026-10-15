import Foundation
import MadarCore
import MadarQuran

struct QuranUIYearDay: Identifiable, Sendable {
    var id: String; var date: String; var monthID: String; var month: String; var hifz: Int; var review: Int
}
struct QuranUIYearMonth: Identifiable, Sendable {
    var id: String; var title: String; var hifz: Int; var review: Int
}
struct QuranUIYear: Sendable {
    var days: [QuranUIYearDay]; var months: [QuranUIYearMonth]; var activeDays: Int; var title: String
}
extension AppQuranService {
    func displayDate(_ day: GregorianDay) -> String { app.dateLabels(day).combined }
    func yearLog() throws -> QuranUIYear {
        let value = try snapshot(), today = value.day.date
        let zone = TimeZone(identifier: value.day.timeZoneID) ?? .gmt
        let names = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
        let hifz = Dictionary(grouping: value.completedOn.values, by: { $0 }).mapValues(\.count)
        let review = Dictionary(grouping: value.sessions.filter { [.review, .free, .qiyam].contains($0.kind) }, by: \.dayKey)
            .mapValues { Set($0.flatMap { $0.grades.map(\.page) }).count }
        let days = (-370...0).map { offset -> QuranUIYearDay in
            let key = today.adding(days: offset)
            let h = HijriCalendar.date(for: key.date(in: zone).addingTimeInterval(43200), timeZone: zone,
                source: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(app.number("core.hijriOffset")))
            return QuranUIYearDay(id: key.description, date: displayDate(key), monthID: "\(h.year)-\(h.month)", month: names[h.month - 1] + " " + numerals.string(h.year), hifz: hifz[key] ?? 0, review: review[key] ?? 0)
        }
        var months: [QuranUIYearMonth] = []
        for day in days {
            if months.last?.id != day.monthID { months.append(QuranUIYearMonth(id: day.monthID, title: day.month, hifz: 0, review: 0)) }
            months[months.count - 1].hifz += day.hifz; months[months.count - 1].review += day.review
        }
        let active = Set(value.activities.filter { $0.countsForStreak && $0.dayKey <= today && $0.dayKey >= today.adding(days: -364) }.map(\.dayKey)).count
        return QuranUIYear(days: days, months: Array(months.suffix(12)), activeDays: active, title: "آخر سنة حتى " + displayDate(today))
    }
}
