import Foundation
import MadarCore
import MadarQuran

extension AppQuranService {
    func memorizationAmount(_ value: QuranDailyHifz?, unit: QuranHifzUnit, catalog: QuranResourceCatalog) throws -> String {
        guard let value else { return "" }
        switch value.balance { case .rest: return "راحة"; case .consolidation: return "تثبيت"; case .complete: return "اكتمل"; default: break }
        guard let range = value.portion else { return "" }
        if unit == .ayah { return QuranMemorizationCopy.ayahs(range.last - range.first + 1, digits: numerals) }
        let portions = try QuranPortionEngine.pages(for: range, catalog: catalog)
        let whole = portions.filter(\.wholePage).count
        let partial = Set(portions.filter { !$0.wholePage }.map(\.page))
        let lines = catalog.layout?.pages.filter { partial.contains($0.page) }.reduce(0) { total, page in
            total + page.lines.filter { $0.words.contains { (range.first...range.last).contains($0.ayahID) } }.count
        } ?? 0
        return [whole > 0 ? QuranMemorizationCopy.pages(whole, digits: numerals) : nil,
                lines > 0 ? QuranMemorizationCopy.lines(lines, digits: numerals) : nil].compactMap { $0 }.joined(separator: " و")
    }
}
enum QuranMemorizationCopy {
    static func pages(_ count: Int, digits: MadarNumberFormatter) -> String {
        let formatted = digits.string(count)
        return String(localized: "quran.newHifzPages", defaultValue: "\(count) \(formatted)", table: "Quran", locale: Locale(identifier: "ar"))
    }
    static func lines(_ count: Int, digits: MadarNumberFormatter) -> String {
        let formatted = digits.string(count)
        return String(localized: "quran.newHifzLines", defaultValue: "\(count) \(formatted)", table: "Quran", locale: Locale(identifier: "ar"))
    }
    static func ayahs(_ count: Int, digits: MadarNumberFormatter) -> String {
        let formatted = digits.string(count)
        return String(localized: "quran.planAyahs", defaultValue: "\(count) \(formatted)", table: "Quran", locale: Locale(identifier: "ar"))
    }
}
