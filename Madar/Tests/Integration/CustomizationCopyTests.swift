import XCTest
import MadarCore
@testable import Madar

final class CustomizationCopyTests: XCTestCase {
    func test_fixPrevious_M0S2_RA1_RestoreReplaceWarningIsLocalOnly() {
        let replacement = BackupCopy.restoreConfirmation(mode: .replace, keyConfigured: true)
        XCTAssertEqual(replacement, "سيُستبدل محتوى مدار على هذا الجهاز. تُحفظ نسخة أمان أولًا، وتُحذف السجلات غير الموجودة في النسخة حذفًا قابلًا للاسترجاع الصريح.")
        XCTAssertFalse(replacement.contains("كل أجهزتك"))

        let keyWarning = BackupCopy.restoreConfirmation(mode: .replace, keyConfigured: false)
        XCTAssertTrue(keyWarning.contains("كلمة مرور النسخة المختارة"))
        XCTAssertTrue(keyWarning.contains("على هذا الجهاز"))

        XCTAssertEqual(
            BackupCopy.restoreConfirmation(mode: .merge, keyConfigured: true),
            "تُدمج السجلات حسب هوياتها، ولا يعيد الدمج سجلًّا محذوفًا إلا باسترجاع صريح."
        )
    }

    func test_fixPrevious_M0T13_RU3_BackupRecordPluralCategories() {
        // Golden Arabic grammar follows RU3, not production/catalog output.
        let fixtures: [(Int, String, String, String, String)] = [
            (0, "لم تُستعد أي سجلات.", "لم تُترك أي سجلات دون تطبيق.", "لم تُستعد أي سجلات.", "لم تُترك أي سجلات دون تطبيق."),
            (1, "استُعيد سجل واحد.", "لم يُطبّق سجل واحد.", "استُعيد سجل واحد.", "لم يُطبّق سجل واحد."),
            (2, "استُعيد سجلان.", "لم يُطبّق سجلان.", "استُعيد سجلان.", "لم يُطبّق سجلان."),
            (3, "استُعيدت \u{2068}٣\u{2069} سجلات.", "لم تُطبّق \u{2068}٣\u{2069} سجلات.", "استُعيدت \u{2068}3\u{2069} سجلات.", "لم تُطبّق \u{2068}3\u{2069} سجلات."),
            (11, "استُعيد \u{2068}١١\u{2069} سجلًّا.", "لم يُطبّق \u{2068}١١\u{2069} سجلًّا.", "استُعيد \u{2068}11\u{2069} سجلًّا.", "لم يُطبّق \u{2068}11\u{2069} سجلًّا."),
            (100, "استُعيد \u{2068}١٠٠\u{2069} سجل.", "لم يُطبّق \u{2068}١٠٠\u{2069} سجل.", "استُعيد \u{2068}100\u{2069} سجل.", "لم يُطبّق \u{2068}100\u{2069} سجل.")
        ]
        for (count, hindiRestored, hindiSkipped, westernRestored, westernSkipped) in fixtures {
            for (style, restored, skipped) in [(NumeralStyle.hindi, hindiRestored, hindiSkipped), (.western, westernRestored, westernSkipped)] {
                let digits = MadarNumberFormatter(style: style).string(count)
                let actualRestored = BackupCopy.restored(count: count, formattedCount: digits)
                let actualSkipped = BackupCopy.skipped(count: count, formattedCount: digits)
                XCTAssertEqual(actualRestored, restored)
                XCTAssertEqual(actualSkipped, skipped)
                XCTAssertFalse(actualRestored.contains("·"))
                XCTAssertFalse(actualSkipped.contains("·"))
            }
        }
    }

    func test_fixPrevious_M0T13_BackupNumeralRedrawPreservesRestoreFactsAndWarnings() {
        let result = BackupRestoreResult(restoredCount: 3, skippedCount: 11, warnings: ["تنبيه 123"])
        let expected: [(NumeralStyle, String)] = [
            (.hindi, "اكتملت الاستعادة. استُعيدت ٣ سجلات. لم يُطبّق ١١ سجلًّا.\nتنبيه 123"),
            (.western, "اكتملت الاستعادة. استُعيدت 3 سجلات. لم يُطبّق 11 سجلًّا.\nتنبيه 123")
        ]
        for (style, text) in expected {
            // Compare full readable copy while catalog interpolation retains bidi isolates.
            let actual = BackupCopy.restoreSummary(result, numerals: style)
                .filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
            XCTAssertEqual(actual, text)
        }
        // Nothing skipped: the summary names only what was restored.
        let clean = BackupCopy.restoreSummary(BackupRestoreResult(restoredCount: 3, skippedCount: 0, warnings: []), numerals: .hindi)
            .filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
        XCTAssertEqual(clean, "اكتملت الاستعادة. استُعيدت ٣ سجلات.")
        XCTAssertEqual(result.restoredCount, 3)
        XCTAssertEqual(result.skippedCount, 11)
        XCTAssertEqual(result.warnings, ["تنبيه 123"], "Appearance must not relocalize warning payloads.")
    }

    func test_M0S2_RU3_ArabicPluralCategoriesHonorNumerals() {
        // Explicit linguistic expectations, independent of the catalog or production output.
        // Read the shipped app bundle so a missing resource fails this hosted regression.
        // String(localized:) isolates interpolated strings with FSI/PDI for Arabic RTL.
        let fixtures: [(Int, String, String)] = [
            (0, "كما اتفقنا", "كما اتفقنا"),
            (1, "تعديل واحد عن المتفق عليه", "تعديل واحد عن المتفق عليه"),
            (2, "تعديلان عن المتفق عليه", "تعديلان عن المتفق عليه"),
            (3, "\u{2068}٣\u{2069} تعديلات عن المتفق عليه", "\u{2068}3\u{2069} تعديلات عن المتفق عليه"),
            (11, "\u{2068}١١\u{2069} تعديلًا عن المتفق عليه", "\u{2068}11\u{2069} تعديلًا عن المتفق عليه"),
            (100, "\u{2068}١٠٠\u{2069} تعديل عن المتفق عليه", "\u{2068}100\u{2069} تعديل عن المتفق عليه")
        ]
        for (count, hindi, western) in fixtures {
            for (style, expected) in [(NumeralStyle.hindi, hindi), (.western, western)] {
                let formattedCount = MadarNumberFormatter(style: style).string(count)
                let actual = CustomizationCopy.changes(count: count, formattedCount: formattedCount)
                XCTAssertEqual(actual, expected, "count=\(count), numerals=\(style)")
                XCTAssertFalse(actual.contains("·"), "RU1: no numeric middle-dot separators")
            }
        }
    }
}
