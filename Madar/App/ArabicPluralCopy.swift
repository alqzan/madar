import Foundation
import MadarCore
import MadarDesign

// Arabic plural copy (RU3: String Catalog variants in Prayer.xcstrings, digits follow core.numerals).

enum PrayerCopy {
    // Argument 1 chooses the Arabic plural; argument 2 is the count in core.numerals digits.
    static func hours(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.hours", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func minutes(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.minutes", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func days(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.days", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func remaining(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.remaining", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func pending(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.pending", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func unconfirmed(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.unconfirmed", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func rakaat(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.rakaat", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    /// «بعد ساعة و١٤ دقيقة».
    static func after(seconds: TimeInterval, digits: MadarNumberFormatter) -> String {
        let total = max(0, Int(seconds / 60))
        let hours = total / 60, minutes = total % 60
        if total == 0 { return "الآن" }
        if hours == 0 { return "بعد " + self.minutes(minutes, digits: digits) }
        return "بعد " + self.hours(hours, digits: digits) + (minutes > 0 ? " و" + self.minutes(minutes, digits: digits) : "")
    }
    /// RL7: two fields, «بعد ١:١٤».
    static func countdown(until date: Date, now: Date, digits: MadarNumberFormatter) -> String? {
        guard date > now else { return nil }
        let total = Int(date.timeIntervalSince(now) / 60)
        let minutes = total % 60
        return "بعد " + digits.string(total / 60) + ":" + (minutes < 10 ? digits.string(0) : "") + digits.string(minutes)
    }
}
