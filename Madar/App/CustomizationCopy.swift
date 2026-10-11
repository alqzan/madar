import Foundation
import MadarCore

enum CustomizationCopy {
    /// The integer chooses the Arabic plural; display digits follow core.numerals.
    static func changes(count: Int, formattedCount: String, bundle: Bundle = .main) -> String {
        String(localized: "customization.changes", defaultValue: "\(count) \(formattedCount)",
               table: "Customization", bundle: bundle, locale: Locale(identifier: "ar"))
    }
}

enum BackupCopy {
    static func restored(count: Int, formattedCount: String, bundle: Bundle = .main) -> String {
        String(localized: "backup.restored", defaultValue: "\(count) \(formattedCount)",
               table: "Customization", bundle: bundle, locale: Locale(identifier: "ar"))
    }

    static func skipped(count: Int, formattedCount: String, bundle: Bundle = .main) -> String {
        String(localized: "backup.skipped", defaultValue: "\(count) \(formattedCount)",
               table: "Customization", bundle: bundle, locale: Locale(identifier: "ar"))
    }

    static func restoreSummary(_ result: BackupRestoreResult, numerals: NumeralStyle) -> String {
        let formatter = MadarNumberFormatter(style: numerals)
        let restored = restored(count: result.restoredCount, formattedCount: formatter.string(result.restoredCount))
        let skipped = skipped(count: result.skippedCount, formattedCount: formatter.string(result.skippedCount))
        let summary = String(localized: "backup.restoreSummary", defaultValue: "اكتملت الاستعادة. \(restored) \(skipped)",
                             table: "Customization", locale: Locale(identifier: "ar"))
        return ([summary] + result.warnings).joined(separator: "\n")
    }
}
