import XCTest
@testable import Madar

/// Finding 3 (12 Nov): reading the shared draft into the composer must never wipe words typed after the field appeared.
final class DiaryComposerDraftMergeTests: XCTestCase {
    func testStoredDraftIsAppliedWhenNothingWasTyped() {
        XCTAssertEqual(DiaryInlineComposer.merged(stored: "مسودة قديمة", typed: nil), "مسودة قديمة")
        XCTAssertEqual(DiaryInlineComposer.merged(stored: "مسودة قديمة", typed: ""), "مسودة قديمة")
    }
    func testTypedWordsSurviveAnEmptyOrWhitespaceDraft() {
        XCTAssertEqual(DiaryInlineComposer.merged(stored: "", typed: "كتبتُ بسرعة"), "كتبتُ بسرعة")
        XCTAssertEqual(DiaryInlineComposer.merged(stored: "  \n", typed: "كتبتُ بسرعة"), "كتبتُ بسرعة")
    }
    func testTypedWordsFollowAStoredDraftInsteadOfReplacingIt() {
        XCTAssertEqual(DiaryInlineComposer.merged(stored: "الأول", typed: "الثاني"), "الأول\nالثاني")
        XCTAssertEqual(DiaryInlineComposer.merged(stored: "نفسه", typed: "نفسه"), "نفسه")
    }
}
