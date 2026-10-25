import Foundation
import CoreGraphics
import PDFKit
import Vision
import ImageIO
import UniformTypeIdentifiers
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

    /// `optical: true` reads the page image even when it has a text layer, for pages whose
    /// embedded Arabic is malformed (`hasUnreliableArabicMapping`).
    public func page(at index: Int, optical: Bool = false) throws -> PDFBookPageText {
        let count = try pageCount()
        guard (0..<count).contains(index), let page = document?.page(at: index) else { throw Failure.unreadable }
        return try autoreleasepool {
            try Task.checkCancellation()
            if !optical, let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                let bounds = page.bounds(for: .cropBox)
                let lines = page.selection(for: bounds)?.selectionsByLine().compactMap { selection -> PDFTextReadingOrder.Line? in
                    guard let text = selection.string, !text.isEmpty else { return nil }
                    let box = selection.bounds(for: page)
                    return .init(text: text, bounds: CGRect(x: box.minX, y: bounds.maxY - box.maxY, width: box.width, height: box.height))
                } ?? []
                let ordered = PDFTextReadingOrder.text(lines, rightToLeft: language.hasPrefix("ar"))
                // Some PDFs expose only part of the text as selectable geometry.
                // In that case preserve the complete original layer.
                let characters: (String) -> [Unicode.Scalar] = { $0.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.sorted { $0.value < $1.value } }
                return PDFBookPageText(index: index, text: page.rotation == 0 && !ordered.isEmpty && characters(ordered) == characters(text) ? ordered : text, source: .embedded)
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let supported = try request.supportedRecognitionLanguages()
            let primary = language.hasPrefix("ar") ? "ar-SA" : "en-US"
            guard supported.contains(primary) else { throw Failure.unsupportedLanguage }
            request.recognitionLanguages = [primary] + (primary != "en-US" && supported.contains("en-US") ? ["en-US"] : [])
            let image = try Self.render(page, margin: 0.06)
            try Task.checkCancellation()
            try VNImageRequestHandler(cgImage: image).perform([request])
            try Task.checkCancellation()
            // Preserve each recognized line's characters. Reversing Arabic text
            // corrupts its logical order; the source image stays authoritative.
            let lines = (request.results ?? []).compactMap { observation -> PDFTextReadingOrder.Line? in
                guard let raw = observation.topCandidates(1).first?.string else { return nil }
                let text = language.hasPrefix("ar") ? Self.withoutStraySymbols(raw) : raw
                guard !text.isEmpty else { return nil }
                let box = observation.boundingBox
                return .init(text: text, bounds: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
            }
            let text = PDFTextReadingOrder.text(lines, rightToLeft: language.hasPrefix("ar"))
            return PDFBookPageText(index: index, text: text, source: .optical)
        }
    }

    /// A page as a JPEG picture (long side `maxSide` points), or nil with `blank` true when nothing is
    /// printed on it. Used for pages whose content is not text: a cover, a calligraphic basmala, an ornament.
    public func pagePicture(at index: Int, maxSide: CGFloat = 1400) throws -> (jpeg: Data?, blank: Bool) {
        let count = try pageCount()
        guard (0..<count).contains(index), let page = document?.page(at: index) else { throw Failure.unreadable }
        return try autoreleasepool {
            try Task.checkCancellation()
            let image = try Self.render(page, longSide: maxSide)
            if Self.isBlank(image) { return (nil, true) }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw Failure.cannotRenderPage }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw Failure.cannotRenderPage }
            return (data as Data, false)
        }
    }

    /// Vision reads bold Arabic parentheses as `%`, `#`, `$`, `&` or a lone quote («' شروع العمر '»). Those
    /// marks never occur in Arabic prose, so an Arabic OCR line drops them; no letter is guessed or added.
    static func withoutStraySymbols(_ line: String) -> String {
        guard line.unicodeScalars.contains(where: { (0x0600...0x06FF).contains($0.value) }) else { return line }
        var kept = line.replacingOccurrences(of: #"[%#$&@^~|\\*•]"#, with: " ", options: .regularExpression)
        // A straight quote that opens or closes nothing (no partner on the line) is noise.
        for quote in ["'", "\""] where kept.components(separatedBy: quote).count == 2 {
            kept = kept.replacingOccurrences(of: quote, with: " ")
        }
        return kept.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" ([،,.:؛!؟])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Fewer than one pixel in a thousand noticeably darker than paper: a blank page (scan noise allowed).
    static func isBlank(_ image: CGImage) -> Bool {
        let side = 96
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        var dark = 0
        for i in 0..<(side * side) where pixels[i] < 200 { dark += 1 }
        return dark * 1000 < side * side
    }

    /// The printed page label when the PDF carries one ("iv", "12"), else nil.
    public func pageLabel(at index: Int) throws -> String? {
        _ = try pageCount()
        guard let page = document?.page(at: index), let label = page.label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty, label != String(index + 1) else { return nil }
        return label
    }

    /// The PDF's own bookmarks, depth-first; `page` is one-based (same as the import inspection).
    public func outline() throws -> [PDFBookOutlineItem] {
        _ = try pageCount()
        return document.map(PDFBookFiles.outline(of:)) ?? []
    }

    /// The page drawn so its long side is `longSide` pixels, inside a white margin of `margin` of that side.
    /// `getDrawingTransform` never scales a page up, so the scale is applied separately: before 25 Oct 2026 a
    /// 410×613-point scan reached Vision at its native size in the corner of a large canvas. Measured on the
    /// owner's scanned book (page 9): 2048 px with a 6% margin restores every line, the line-initial alif and the
    /// verse reference; 3000 px and above make Vision miss lines.
    private static func render(_ page: PDFPage, longSide: CGFloat = 2048, margin: CGFloat = 0) throws -> CGImage {
        let box = page.bounds(for: .cropBox)
        guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0,
              let ref = page.pageRef else { throw Failure.cannotRenderPage }
        let turned = abs(page.rotation) % 180 == 90
        let shown = turned ? CGSize(width: box.height, height: box.width) : box.size
        // At most 2048² RGBA pixels plus the margin; one page and one Vision request at a time.
        let scale = longSide / max(shown.width, shown.height), pad = (longSide * margin).rounded()
        let width = max(1, Int((shown.width * scale + 2 * pad).rounded(.up)))
        let height = max(1, Int((shown.height * scale + 2 * pad).rounded(.up)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw Failure.cannotRenderPage }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.translateBy(x: pad, y: pad)
        context.scaleBy(x: scale, y: scale)
        context.concatenate(ref.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: shown), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(ref)
        guard let image = context.makeImage() else { throw Failure.cannotRenderPage }
        return image
    }
}
