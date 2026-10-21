import Foundation
import CoreGraphics
import PDFKit
import Vision
import MadarCore

public struct PDFBookPageText: Equatable, Sendable, Identifiable {
    public enum Source: Sendable { case embedded, optical }
    public let index: Int
    public let text: String
    public let source: Source
    public let normalizedText: String
    public var id: Int { index }

    init(index: Int, text: String, source: Source) {
        self.index = index; self.text = text; self.source = source
        normalizedText = Self.normalize(text)
    }

    public static func normalize(_ text: String) -> String {
        DiarySearchParser.normalize(text.precomposedStringWithCompatibilityMapping)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// PDFKit can expose an unmapped glyph as an ASCII character inside an
    /// Arabic word. Such text remains searchable where possible, but is unsafe
    /// to show as a quotation from the source page.
    public var hasUnreliableArabicMapping: Bool {
        guard source == .embedded else { return false }
        let scalars = Array(text.unicodeScalars)
        guard scalars.count >= 3 else { return false }
        return (1..<(scalars.count - 1)).contains { index in
            Self.isArabicLetter(scalars[index - 1])
                && scalars[index].value < 128
                && (CharacterSet.alphanumerics.contains(scalars[index]) || CharacterSet.punctuationCharacters.contains(scalars[index]))
                && Self.isArabicLetter(scalars[index + 1])
        }
    }

    private static func isArabicLetter(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        let isArabicBlock = (0x0600...0x06FF).contains(value)
            || (0x0750...0x077F).contains(value)
            || (0x08A0...0x08FF).contains(value)
            || (0xFB50...0xFDFF).contains(value)
            || (0xFE70...0xFEFF).contains(value)
        return isArabicBlock && CharacterSet.letters.contains(scalar)
    }

    public func contains(_ query: String) -> Bool {
        let needle = Self.normalize(query)
        return !needle.isEmpty && normalizedText.contains(needle)
    }

    /// A short window around the first match, preserving the extracted spelling
    /// and marks. Search normalization must never become the displayed quotation.
    public func excerpt(matching query: String) -> String? {
        guard !hasUnreliableArabicMapping else { return nil }
        let needle = Self.normalize(query)
        guard !needle.isEmpty, let match = normalizedText.range(of: needle) else { return nil }
        let first = normalizedText[..<match.lowerBound].filter { $0 == " " }.count
        let last = normalizedText[..<match.upperBound].filter { $0 == " " }.count
        let words = text.split(whereSeparator: \.isWhitespace).filter { !Self.normalize(String($0)).isEmpty }
        let lower = max(0, first - 6)
        let upper = min(words.count, last + 10)
        guard lower < upper else { return nil }
        return (lower > 0 ? "… " : "") + words[lower..<upper].joined(separator: " ")
            + (upper < words.count ? " …" : "")
    }
}

/// An ephemeral, page-at-a-time index. PDFKit and Vision stay on this actor's
/// executor; neither the original PDF nor the owner's records are rewritten.
public actor PDFBookTextReader {
    public enum Failure: Error { case unreadable, unsupportedLanguage, cannotRenderPage }
    private let data: Data
    private let language: String
    private var document: PDFDocument?

    public init(data: Data, language: String) {
        self.data = data
        self.language = language
    }

    public func pageCount() throws -> Int {
        try Task.checkCancellation()
        if let document { return document.pageCount }
        guard !data.isEmpty, data.count <= PDFBookFiles.maximumBytes,
              let opened = PDFDocument(data: data), !opened.isLocked,
              (1...PDFBookFiles.maximumPages).contains(opened.pageCount) else { throw Failure.unreadable }
        document = opened
        return opened.pageCount
    }

    public func page(at index: Int) throws -> PDFBookPageText {
        let count = try pageCount()
        guard (0..<count).contains(index), let page = document?.page(at: index) else { throw Failure.unreadable }
        return try autoreleasepool {
            try Task.checkCancellation()
            if let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return PDFBookPageText(index: index, text: text, source: .embedded)
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let supported = try request.supportedRecognitionLanguages()
            let primary = language.hasPrefix("ar") ? "ar-SA" : "en-US"
            guard supported.contains(primary) else { throw Failure.unsupportedLanguage }
            request.recognitionLanguages = [primary] + (primary != "en-US" && supported.contains("en-US") ? ["en-US"] : [])
            let image = try Self.render(page)
            try Task.checkCancellation()
            try VNImageRequestHandler(cgImage: image).perform([request])
            try Task.checkCancellation()
            // Preserve each recognized line's characters. Reversing Arabic text
            // corrupts its logical order; the source image stays authoritative.
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            return PDFBookPageText(index: index, text: text, source: .optical)
        }
    }

    private static func render(_ page: PDFPage) throws -> CGImage {
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0,
              let ref = page.pageRef else { throw Failure.cannotRenderPage }
        // At most 2048² RGBA pixels; one page and one Vision request at a time.
        let scale = 2048 / max(bounds.width, bounds.height)
        let width = max(1, Int((bounds.width * scale).rounded(.up)))
        let height = max(1, Int((bounds.height * scale).rounded(.up)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw Failure.cannotRenderPage }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(rect)
        context.concatenate(ref.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(ref)
        guard let image = context.makeImage() else { throw Failure.cannotRenderPage }
        return image
    }
}
