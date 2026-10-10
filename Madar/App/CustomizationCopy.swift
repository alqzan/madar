import Foundation

enum CustomizationCopy {
    /// The integer chooses the Arabic plural; display digits follow core.numerals.
    static func changes(count: Int, formattedCount: String, bundle: Bundle = .main) -> String {
        String(localized: "customization.changes", defaultValue: "\(count) \(formattedCount)",
               table: "Customization", bundle: bundle, locale: Locale(identifier: "ar"))
    }
}
