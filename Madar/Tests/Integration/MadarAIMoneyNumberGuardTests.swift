import XCTest
@testable import Madar

final class MadarAIMoneyNumberGuardTests: XCTestCase {
    func testGeneratedMoneyAnswersRejectDigitAndSpelledNumbersInEnglishAndArabic() {
        XCTAssertTrue(MadarAIInsightGenerator.containsUnsupportedMoneyNumber("You spent five hundred dollars"))
        XCTAssertTrue(MadarAIInsightGenerator.containsUnsupportedMoneyNumber("about twenty percent higher"))
        XCTAssertTrue(MadarAIInsightGenerator.containsUnsupportedMoneyNumber("ارتفع الإنفاق بنحو عشرة بالمئة"))
        XCTAssertTrue(MadarAIInsightGenerator.containsUnsupportedMoneyNumber("صرف ٢٥٠ ريالًا"))
    }

    func testQualitativeMoneyAnswerWithoutNumericClaimsIsAllowed() {
        XCTAssertFalse(MadarAIInsightGenerator.containsUnsupportedMoneyNumber("المطاعم هي التصنيف الأبرز مقارنة بالفترة السابقة"))
    }
}
