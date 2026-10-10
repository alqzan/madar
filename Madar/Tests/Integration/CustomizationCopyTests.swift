import XCTest
import MadarCore
@testable import Madar

final class CustomizationCopyTests: XCTestCase {
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
