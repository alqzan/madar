import XCTest
import SwiftUI
@testable import Madar

/// Rich writing is stored as Markdown: these check the pure conversion both ways. Expected strings are written by hand from the Markdown rules.
final class DiaryRichTextTests: XCTestCase {
    private func roundTrip(_ markdown: String) -> String {
        DiaryRichText.markdown(from: DiaryRichText.attributed(fromMarkdown: markdown))
    }
    func testPlainTextHasNoMarks() {
        XCTAssertEqual(roundTrip("نص عادي بلا تنسيق"), "نص عادي بلا تنسيق")
        XCTAssertEqual(String(DiaryRichText.attributed(fromMarkdown: "نص عادي").characters), "نص عادي")
    }
    func testBoldAndItalicArabicRoundTrip() {
        XCTAssertEqual(roundTrip("مساء **هادئ** جدًا"), "مساء **هادئ** جدًا")
        XCTAssertEqual(roundTrip("كان *يومًا* طويلًا"), "كان *يومًا* طويلًا")
        XCTAssertEqual(roundTrip("***معًا*** ثم **عريض** ثم *مائل*"), "***معًا*** ثم **عريض** ثم *مائل*")
    }
    func testMarkersAreNeverInTheFormattedText() {
        let text = DiaryRichText.attributed(fromMarkdown: "## عنوان\nنص **عريض** و*مائل*")
        let characters = String(text.characters)
        XCTAssertEqual(characters, "عنوان\nنص عريض ومائل")
        XCTAssertFalse(characters.contains("*") || characters.contains("#"))
    }
    func testHeadingAndListLines() {
        XCTAssertEqual(roundTrip("## عنوان اليوم\nنص"), "## عنوان اليوم\nنص")
        XCTAssertEqual(roundTrip("• بند\n• بند **ثانٍ**"), "• بند\n• بند **ثانٍ**")
    }
    func testBoldLandsOnTheRightCharacters() {
        let text = DiaryRichText.attributed(fromMarkdown: "ab **cd** ef")
        let boldRuns = text.runs.filter { DiaryRichText.style(of: $0.inlinePresentationIntent, font: $0.font).bold }
        XCTAssertEqual(boldRuns.map { String(text[$0.range].characters) }, ["cd"])
    }
    func testWhitespaceStaysOutsideTheMarks() {
        var text = AttributedString("كلمة ")
        var container = AttributeContainer(); DiaryRichText.apply(.init(bold: true), to: &container)
        text.mergeAttributes(container)
        XCTAssertEqual(DiaryRichText.markdown(from: text), "**كلمة** ")
    }
    func testLiteralMarkdownCharactersAreEscapedAndSurvive() {
        let text = AttributedString("٥ * ٣ و _س_")
        let markdown = DiaryRichText.markdown(from: text)
        XCTAssertEqual(markdown, "٥ \\* ٣ و \\_س\\_")
        XCTAssertEqual(String(DiaryRichText.attributed(fromMarkdown: markdown).characters), "٥ * ٣ و _س_")
    }
    func testHeadingDoesNotAlsoBecomeBold() {
        var text = AttributedString("عنوان")
        var container = AttributeContainer(); DiaryRichText.apply(.init(heading: true), to: &container)
        text.mergeAttributes(container)
        XCTAssertEqual(DiaryRichText.markdown(from: text), "## عنوان")
    }
    func testEmptyStaysEmpty() {
        XCTAssertEqual(DiaryRichText.markdown(from: AttributedString()), "")
        XCTAssertEqual(String(DiaryRichText.attributed(fromMarkdown: "").characters), "")
    }
}
