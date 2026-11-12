import Testing
@testable import MadarCore

/// Owner 12 Nov: a voice note must keep the whole take. Expected strings are written by hand from the rule, not from the code.
@Suite struct DiaryTranscriptJoinTests {
    @Test func piecesAreJoinedWithOneSpaceAndNothingIsLost() {
        var text = ""
        for piece in ["السلام عليكم", "ذهبت إلى السوق", "والحمد لله"] { DiaryTranscriptJoin.append(piece, to: &text) }
        #expect(text == "السلام عليكم ذهبت إلى السوق والحمد لله")
    }
    @Test func directionMarksAndBlankPiecesAreDropped() {
        var text = ""
        for piece in ["\u{200F}أول جملة ", "  ", "\u{200F}", "\n آخر جملة"] { DiaryTranscriptJoin.append(piece, to: &text) }
        #expect(text == "أول جملة آخر جملة")
    }
    @Test func pieceWithoutLeadingSpaceIsNotGluedToThePreviousWord() {
        var text = "first"
        DiaryTranscriptJoin.append("second", to: &text)
        #expect(text == "first second")
    }
}
