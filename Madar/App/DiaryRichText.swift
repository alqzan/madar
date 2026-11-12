import SwiftUI
import Foundation
import MadarCore

/// Rich writing for the diary: the field shows bold, italic and headings formatted while writing, and the page is stored as the Markdown the
/// rest of the app already reads (`Entry.textFormat`, `DayOneMarkdown.hasEditorMarks`). This is the pure conversion between the two.
enum DiaryRichText {
    static let baseSize: CGFloat = 19
    static let headingSize: CGFloat = 24
    static var regular: Font { .custom("thmanyahseriftext-Regular", size: baseSize) }
    static var bold: Font { .custom("thmanyahseriftext-Bold", size: baseSize) }
    static var italic: Font { regular.italic() }
    static var boldItalic: Font { bold.italic() }
    static var heading: Font { .custom("thmanyahserifdisplay-Bold", size: headingSize) }

    struct Style: Equatable { var bold = false, italic = false, heading = false }

    static func font(_ style: Style) -> Font {
        if style.heading { return heading }
        switch (style.bold, style.italic) {
        case (true, true): return boldItalic
        case (true, false): return bold
        case (false, true): return italic
        default: return regular
        }
    }
    static func style(of intent: InlinePresentationIntent?, font: Font?) -> Style {
        var style = Style()
        if let intent {
            style.bold = intent.contains(.stronglyEmphasized)
            style.italic = intent.contains(.emphasized)
        }
        if let font {
            if font == heading { style.heading = true }
            else if font == boldItalic { style.bold = true; style.italic = true }
            else if font == bold { style.bold = true }
            else if font == italic { style.italic = true }
        }
        return style
    }
    /// Applies a style to a run: the font that shows it and the intent that records it.
    static func apply(_ style: Style, to container: inout AttributeContainer) {
        container.font = font(style)
        var intent: InlinePresentationIntent = []
        if style.bold && !style.heading { intent.insert(.stronglyEmphasized) }
        if style.italic && !style.heading { intent.insert(.emphasized) }
        container.inlinePresentationIntent = intent.isEmpty ? nil : intent
    }

    // MARK: Markdown → formatted text

    static func attributed(fromMarkdown markdown: String) -> AttributedString {
        var result = AttributedString()
        let lines = markdown.components(separatedBy: "\n")
        for (index, rawLine) in lines.enumerated() {
            var line = rawLine
            var headingLine = false
            if line.hasPrefix("## ") { headingLine = true; line = String(line.dropFirst(3)) }
            var piece = (try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(line)
            for run in piece.runs {
                var style = Self.style(of: run.inlinePresentationIntent, font: nil)
                style.heading = headingLine
                var container = AttributeContainer()
                apply(style, to: &container)
                piece[run.range].mergeAttributes(container)
            }
            // The Markdown parser may leave link/code attributes; the field only knows weight, slant and heading.
            piece.link = nil
            result.append(piece)
            if index < lines.count - 1 {
                var newline = AttributedString("\n")
                var container = AttributeContainer(); apply(Style(), to: &container)
                newline.mergeAttributes(container)
                result.append(newline)
            }
        }
        return result
    }

    // MARK: Formatted text → Markdown

    static func markdown(from text: AttributedString) -> String {
        // One flag set per character, then each line is written on its own.
        var characters: [(Character, Style)] = []
        for run in text.runs {
            let runStyle = style(of: run.inlinePresentationIntent, font: run.font)
            for character in text[run.range].characters { characters.append((character, runStyle)) }
        }
        var lines: [[(Character, Style)]] = [[]]
        for item in characters {
            if item.0 == "\n" { lines.append([]) } else { lines[lines.count - 1].append(item) }
        }
        return lines.map(markdownLine).joined(separator: "\n")
    }

    private static func markdownLine(_ line: [(Character, Style)]) -> String {
        let visible = line.filter { !$0.0.isWhitespace }
        if !visible.isEmpty, visible.allSatisfy({ $0.1.heading }) {
            return "## " + escaped(String(line.map(\.0)))
        }
        // Groups of characters with the same emphasis; whitespace at a group's edges stays outside the marks.
        var output = ""
        var index = 0
        while index < line.count {
            let style = Style(bold: line[index].1.bold, italic: line[index].1.italic)
            var end = index
            while end < line.count, line[end].1.bold == style.bold, line[end].1.italic == style.italic { end += 1 }
            let chunk = String(line[index..<end].map(\.0))
            let trimmed = chunk.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || (!style.bold && !style.italic) {
                output += escaped(chunk)
            } else {
                let lead = String(chunk.prefix(while: { $0 == " " || $0 == "\t" }))
                let tail = String(chunk.reversed().prefix(while: { $0 == " " || $0 == "\t" }))
                let mark = style.bold && style.italic ? "***" : style.bold ? "**" : "*"
                output += lead + mark + escaped(trimmed) + mark + tail
            }
            index = end
        }
        return output
    }

    /// Characters the Markdown reader would take as syntax stay literal.
    private static func escaped(_ text: String) -> String {
        var out = ""
        for character in text {
            if "\\*_`[]".contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }

    /// True when the stored words carry formatting (the collapsed field must not show them as raw characters).
    static func hasFormatting(_ markdown: String) -> Bool { DayOneMarkdown.hasEditorMarks(markdown) }
}
