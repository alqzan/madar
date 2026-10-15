import Foundation

/// Human date labels only. A stored day key and its timezone are never rewritten by formatting.
public struct MadarDateLabels: Equatable, Sendable {
    public let primary: String
    public let secondary: String
    public init(primary: String, secondary: String) { self.primary = primary; self.secondary = secondary }
    public var combined: String { primary + "، " + secondary }
}
extension DualDate {
    public func labels(firstCalendar: FirstCalendar = .hijri, numerals: NumeralStyle = .hindi, compact: Bool = false, weekday: Bool = false) -> MadarDateLabels {
        let digits = MadarNumberFormatter(style: numerals)
        let hMonths = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
        let gMonths = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]
        let h = digits.string(hijri.day) + " " + hMonths[hijri.month - 1] + (compact ? "" : " " + digits.string(hijri.year) + " هـ")
        let g = digits.string(gregorian.day) + " " + gMonths[gregorian.month - 1] + (compact ? "" : " " + digits.string(gregorian.year) + " م")
        let names = ["الأحد", "الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"]
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let prefix = weekday ? names[calendar.component(.weekday, from: gregorian.date(in: .gmt)) - 1] + " " : ""
        return firstCalendar == .hijri ? .init(primary: prefix + h, secondary: g) : .init(primary: prefix + g, secondary: h)
    }
}
