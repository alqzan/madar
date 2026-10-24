import Foundation

/// Owner, 21 October 2026: any PDF the owner adds can become a flowing (reflowable) book on the device.
/// The text comes from `PDFBookTextReader` (embedded text first, on-device OCR otherwise); the PDF itself
/// is never rewritten. The EPUB is deterministic (same PDF, same bytes), so a second conversion is caught
/// by the import's duplicate check.
public enum PDFBookEPUB {
    public struct Page: Sendable, Equatable {
        public let text: String
        public let optical: Bool
        public let unreliable: Bool
        /// The printed page label when it differs from the page's position.
        public let label: String?
        public init(text: String, optical: Bool, unreliable: Bool, label: String? = nil) {
            self.text = text; self.optical = optical; self.unreliable = unreliable; self.label = label
        }
        public init(_ page: PDFBookPageText, label: String? = nil) {
            self.init(text: page.text, optical: page.source == .optical, unreliable: page.hasUnreliableArabicMapping, label: label)
        }
    }

    public struct Summary: Sendable, Equatable {
        public let pages: Int, opticalPages: Int, skippedPages: [Int]
    }

    static let pagesPerDocument = 30

    public static func summary(_ pages: [Page]) -> Summary {
        Summary(pages: pages.count, opticalPages: pages.filter(\.optical).count,
                skippedPages: pages.indices.filter { pages[$0].unreliable || paragraphs(pages[$0].text).isEmpty }.map { $0 + 1 })
    }

    public static func build(title: String, author: String, language: String, sourceHash: String,
                             pages: [Page], outline: [PDFBookOutlineItem]) throws -> Data {
        guard !pages.isEmpty else { throw TurathError.unreadable }
        let rtl = language.hasPrefix("ar"), lang = rtl ? "ar" : (language.isEmpty ? "und" : language)
        let chunks = stride(from: 0, to: pages.count, by: pagesPerDocument).map { $0..<min($0 + pagesPerDocument, pages.count) }
        let summary = summary(pages)
        var files: [(String, Data)] = [("mimetype", Data("application/epub+zip".utf8)),
                                       ("META-INF/container.xml", Data(#"<?xml version="1.0" encoding="UTF-8"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"#.utf8))]
        let digits = { (n: Int) in rtl ? TurathEPUB.arabicDigits(String(n)) : String(n) }
        var info = "<section class=\"madar-turath-info\"><h1>\(TurathEPUB.escape(title))</h1>"
        if !author.isEmpty { info += "<p>\(TurathEPUB.escape(author))</p>" }
        info += "<p class=\"madar-source\">حُوِّل هذا الكتاب على جهازك من ملف PDF، وبقي الملف الأصلي في مكتبتك كما هو.</p>"
        if summary.opticalPages > 0 {
            info += "<p class=\"madar-source\">صفحات قُرئت من صورها: \(digits(summary.opticalPages)) من \(digits(summary.pages)). قد تختلف فيها كلمات قليلة عن الأصل.</p>"
        }
        if !summary.skippedPages.isEmpty {
            info += "<p class=\"madar-source\">صفحات لم يُستخرج نصها بدقة: \(digits(summary.skippedPages.count)). مكان كل منها ملاحظة برقمها لتراجعها في PDF.</p>"
        }
        info += "</section>"
        files.append(("OEBPS/info.xhtml", TurathEPUB.xhtml(title: "عن هذه النسخة", body: info)))
        var pageList = ""
        let texts = withoutRunningLines(pages.map(\.text))
        for (n, range) in chunks.enumerated() {
            // Owner, 24 Oct 2026 («ترتيب الفكرات والصفحات»): a paragraph that runs over a page break stays one
            // paragraph, with the page marker inside it, instead of being cut in two at every page.
            var body = "", open = false
            for index in range {
                let page = pages[index], ordinal = index + 1
                let label = page.label.map { rtl ? TurathEPUB.arabicDigits($0) : $0 } ?? digits(ordinal)
                let escaped = TurathEPUB.escape(label)
                let marker = "<span id=\"p-\(ordinal)\" epub:type=\"pagebreak\" role=\"doc-pagebreak\" title=\"\(escaped)\" aria-label=\"\(escaped)\"></span>"
                pageList += "<li><a href=\"c\(n + 1).xhtml#p-\(ordinal)\">\(escaped)</a></li>"
                var list = page.unreliable ? [] : paragraphs(texts[index])
                if list.isEmpty {
                    if open { body += "</p>"; open = false }
                    body += marker + "<p class=\"madar-page-gap\">صفحة \(escaped): لم يُستخرج نصها بدقة؛ راجعها في ملف PDF الأصلي.</p>"
                    continue
                }
                if open {
                    let first = list.removeFirst()
                    body += " " + marker + TurathEPUB.escape(first)
                    if !list.isEmpty || closes(first) { body += "</p>"; open = false }
                } else { body += marker }
                for (k, paragraph) in list.enumerated() {
                    if k == list.count - 1 && !closes(paragraph) { body += "<p>" + TurathEPUB.escape(paragraph); open = true }
                    else { body += "<p>\(TurathEPUB.escape(paragraph))</p>" }
                }
            }
            if open { body += "</p>" }
            files.append(("OEBPS/c\(n + 1).xhtml", TurathEPUB.xhtml(title: title, body: "<section>\(body)</section>")))
        }
        // The PDF's bookmarks become the index; without bookmarks the index lists every tenth page.
        var toc = "<li><a href=\"info.xhtml\">عن هذه النسخة</a></li>"
        let href = { (page: Int) -> String in
            let clamped = min(max(page, 0), pages.count - 1)
            return "c\(clamped / pagesPerDocument + 1).xhtml#p-\(clamped + 1)"
        }
        if outline.isEmpty {
            for start in stride(from: 0, to: pages.count, by: 10) { toc += "<li><a href=\"\(href(start))\">صفحة \(digits(start + 1))</a></li>" }
        } else {
            toc += outline.prefix(2_000).map { "<li><a href=\"\(href($0.page - 1))\">\(TurathEPUB.escape($0.title))</a></li>" }.joined()
        }
        files.append(("OEBPS/nav.xhtml", TurathEPUB.xhtml(title: "الفهرس", body: "<nav epub:type=\"toc\"><h1>الفهرس</h1><ol>\(toc)</ol></nav><nav epub:type=\"page-list\" hidden=\"\"><ol>\(pageList)</ol></nav>")))
        let manifest = "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/><item id=\"info\" href=\"info.xhtml\" media-type=\"application/xhtml+xml\"/>"
            + chunks.indices.map { "<item id=\"c\($0 + 1)\" href=\"c\($0 + 1).xhtml\" media-type=\"application/xhtml+xml\"/>" }.joined()
        let spine = "<itemref idref=\"info\"/>" + chunks.indices.map { "<itemref idref=\"c\($0 + 1)\"/>" }.joined()
        let opf = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><package xmlns=\"http://www.idpf.org/2007/opf\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" version=\"3.0\" unique-identifier=\"bookid\" xml:lang=\"\(lang)\"\(rtl ? " dir=\"rtl\"" : "")><metadata><dc:identifier id=\"bookid\">urn:madar:pdf:\(TurathEPUB.escape(sourceHash))</dc:identifier><dc:title>\(TurathEPUB.escape(title))</dc:title>"
            + (author.isEmpty ? "" : "<dc:creator>\(TurathEPUB.escape(author))</dc:creator>")
            + "<dc:language>\(lang)</dc:language><meta property=\"dcterms:modified\">2000-01-01T00:00:00Z</meta></metadata><manifest>\(manifest)</manifest><spine\(rtl ? " page-progression-direction=\"rtl\"" : "")>\(spine)</spine></package>"
        files.append(("OEBPS/package.opf", Data(opf.utf8)))
        return try StoredZIP.encode(files)
    }

    static let closers: Set<Character> = [".", "!", "?", "؟", ":", "…", "»", "\"", "”", "۔", ")"]
    static func closes(_ paragraph: String) -> Bool { paragraph.last.map { closers.contains($0) } ?? true }

    /// Running headers and footers (the book or chapter title repeated at the top of every page) and bare page
    /// numbers are not part of the text. A line counts as running when, ignoring its digits, it opens or closes
    /// at least three pages and a fifth of them.
    static func withoutRunningLines(_ texts: [String]) -> [String] {
        let pageNumber = try! NSRegularExpression(pattern: #"^[\s\-–—()\[\]{}<>«»ـ]*[0-9٠-٩]{1,4}[\s\-–—()\[\]{}<>«»ـ]*$"#)
        func key(_ line: String) -> String { line.filter { !$0.isNumber && !$0.isWhitespace } }
        func edges(_ lines: [String]) -> [String] { let kept = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }; return Array(kept.prefix(2) + kept.suffix(2)) }
        let split = texts.map { $0.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") }
        var seen: [String: Int] = [:]
        for lines in split { for k in Set(edges(lines).map(key)) where k.count >= 3 { seen[k, default: 0] += 1 } }
        let threshold = max(3, texts.count / 5)
        let running = Set(seen.filter { $0.value >= threshold }.keys)
        return split.map { lines in
            let edge = Set(edges(lines))
            return lines.filter { line in
                let range = NSRange(line.startIndex..., in: line)
                if pageNumber.firstMatch(in: line, range: range) != nil { return false }
                return !(edge.contains(line) && running.contains(key(line)))
            }.joined(separator: "\n")
        }
    }

    /// Joins a page's printed lines into paragraphs. A line ends its paragraph when it is blank, ends with
    /// closing punctuation, or is clearly shorter than the page's typical line (the last line of a paragraph).
    static func paragraphs(_ text: String) -> [String] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
        let lengths = lines.map(\.count).filter { $0 > 0 }.sorted()
        let typical = lengths.count >= 3 ? lengths[lengths.count * 3 / 4] : Int.max
        var out: [String] = [], current: [String] = []
        func flush() { if !current.isEmpty { out.append(current.joined(separator: " ")); current = [] } }
        for line in lines {
            guard !line.isEmpty else { flush(); continue }
            current.append(line)
            if let last = line.last, closers.contains(last) { flush() }
            else if typical != .max, line.count * 10 < typical * 7 { flush() }
        }
        flush()
        return out
    }
}
