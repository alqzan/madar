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
        /// The page as a picture (JPEG), for a page whose content is not text: a cover, a calligraphic
        /// basmala, an ornament or a figure. Shown in place of the text; never for a blank page.
        public let image: Data?
        /// A page with nothing on it. It keeps its page number and adds nothing to the reading.
        public let blank: Bool
        public init(text: String, optical: Bool, unreliable: Bool, label: String? = nil, image: Data? = nil, blank: Bool = false) {
            self.text = text; self.optical = optical; self.unreliable = unreliable; self.label = label; self.image = image; self.blank = blank
        }
        public init(_ page: PDFBookPageText, label: String? = nil, image: Data? = nil, blank: Bool = false) {
            self.init(text: page.text, optical: page.source == .optical, unreliable: page.hasUnreliableArabicMapping, label: label, image: image, blank: blank)
        }
        /// Shown as its picture rather than as text.
        var pictured: Bool { image != nil && (unreliable || PDFBookEPUB.paragraphs(text).isEmpty) }
        var gap: Bool { !blank && image == nil && (unreliable || PDFBookEPUB.paragraphs(text).isEmpty) }
    }

    public struct Summary: Sendable, Equatable {
        public let pages: Int, opticalPages: Int, skippedPages: [Int]
        /// Pages kept as their picture (cover, basmala, ornaments).
        public let picturedPages: Int
        public init(pages: Int, opticalPages: Int, skippedPages: [Int], picturedPages: Int = 0) {
            self.pages = pages; self.opticalPages = opticalPages; self.skippedPages = skippedPages; self.picturedPages = picturedPages
        }
    }
    /// A converted book carries at most this many page pictures; any further pictureless page keeps its honest note.
    public static let maximumPictures = 40

    static let pagesPerDocument = 30

    public static func summary(_ pages: [Page]) -> Summary {
        Summary(pages: pages.count, opticalPages: pages.filter(\.optical).count,
                skippedPages: pages.indices.filter { pages[$0].gap }.map { $0 + 1 },
                picturedPages: pages.filter(\.pictured).count)
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
        if summary.picturedPages > 0 {
            info += "<p class=\"madar-source\">صفحات بلا نص بقيت بصورتها كما في الأصل (الغلاف والزخارف): \(digits(summary.picturedPages)).</p>"
        }
        if !summary.skippedPages.isEmpty {
            info += "<p class=\"madar-source\">صفحات لم يُستخرج نصها بدقة: \(digits(summary.skippedPages.count)). مكان كل منها ملاحظة برقمها لتراجعها في PDF.</p>"
        }
        info += "</section>"
        files.append(("OEBPS/info.xhtml", TurathEPUB.xhtml(title: "عن هذه النسخة", body: info)))
        var pageList = ""
        var pictures: [(String, Data)] = []
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
                if page.pictured, let image = page.image {
                    if open { body += "</p>"; open = false }
                    let name = "images/p\(ordinal).jpg"
                    pictures.append((name, image))
                    body += marker + "<figure class=\"madar-page-picture\"><img src=\"\(name)\" alt=\"صفحة \(escaped) كما في الأصل\"/></figure>"
                    continue
                }
                if page.blank && paragraphs(texts[index]).isEmpty {
                    if open { body += "</p>"; open = false }
                    body += marker
                    continue
                }
                var list = page.unreliable ? [] : paragraphs(texts[index])
                if list.isEmpty {
                    if open { body += "</p>"; open = false }
                    body += marker + "<p class=\"madar-page-gap\">صفحة \(escaped): لم يُستخرج نصها بدقة؛ راجعها في ملف PDF الأصلي.</p>"
                    continue
                }
                // A page that opens on a heading (a short first line) starts afresh; the open paragraph ends.
                if open, let first = list.first, isHeading(first) { body += "</p>"; open = false }
                if open {
                    let first = list.removeFirst()
                    body += " " + marker + TurathEPUB.escape(first)
                    if !list.isEmpty || closes(first) { body += "</p>"; open = false }
                } else { body += marker }
                for (k, paragraph) in list.enumerated() {
                    // Only a page that ends on a full line carries its last paragraph over to the next page.
                    if k == list.count - 1 && !closes(paragraph) && endsOnFullLine(texts[index]) { body += "<p>" + TurathEPUB.escape(paragraph); open = true }
                    else { body += "<p>\(TurathEPUB.escape(paragraph))</p>" }
                }
            }
            if open { body += "</p>" }
            files.append(("OEBPS/c\(n + 1).xhtml", TurathEPUB.xhtml(title: title, body: "<section>\(body)</section>")))
        }
        files += pictures.map { ("OEBPS/" + $0.0, $0.1) }
        // The PDF's bookmarks become the index; without them, the book's printed contents page; without that,
        // every tenth page.
        var toc = "<li><a href=\"info.xhtml\">عن هذه النسخة</a></li>"
        let href = { (page: Int) -> String in
            let clamped = min(max(page, 0), pages.count - 1)
            return "c\(clamped / pagesPerDocument + 1).xhtml#p-\(clamped + 1)"
        }
        let printed = outline.isEmpty ? printedContents(pages.map(\.text)) : []
        if !printed.isEmpty {
            // Owner, 25 Oct 2026 («سحب الفهرس خطأ مع انه موجود واضح»): the book's own printed contents.
            toc += printed.map { "<li><a href=\"\(href($0.page))\">\(TurathEPUB.escape($0.title))</a></li>" }.joined()
        } else if outline.isEmpty {
            for start in stride(from: 0, to: pages.count, by: 10) { toc += "<li><a href=\"\(href(start))\">صفحة \(digits(start + 1))</a></li>" }
        } else {
            toc += outline.prefix(2_000).map { "<li><a href=\"\(href($0.page - 1))\">\(TurathEPUB.escape($0.title))</a></li>" }.joined()
        }
        files.append(("OEBPS/nav.xhtml", TurathEPUB.xhtml(title: "الفهرس", body: "<nav epub:type=\"toc\"><h1>الفهرس</h1><ol>\(toc)</ol></nav><nav epub:type=\"page-list\" hidden=\"\"><ol>\(pageList)</ol></nav>")))
        let manifest = "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/><item id=\"info\" href=\"info.xhtml\" media-type=\"application/xhtml+xml\"/>"
            + chunks.indices.map { "<item id=\"c\($0 + 1)\" href=\"c\($0 + 1).xhtml\" media-type=\"application/xhtml+xml\"/>" }.joined()
            // A pictured first page is the book's cover on the shelf.
            + pictures.enumerated().map { i, picture in
                let cover = i == 0 && picture.0 == "images/p1.jpg" ? " properties=\"cover-image\"" : ""
                return "<item id=\"img\(i + 1)\" href=\"\(picture.0)\" media-type=\"image/jpeg\"\(cover)/>"
            }.joined()
        let spine = "<itemref idref=\"info\"/>" + chunks.indices.map { "<itemref idref=\"c\($0 + 1)\"/>" }.joined()
        let opf = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><package xmlns=\"http://www.idpf.org/2007/opf\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" version=\"3.0\" unique-identifier=\"bookid\" xml:lang=\"\(lang)\"\(rtl ? " dir=\"rtl\"" : "")><metadata><dc:identifier id=\"bookid\">urn:madar:pdf:\(TurathEPUB.escape(sourceHash))</dc:identifier><dc:title>\(TurathEPUB.escape(title))</dc:title>"
            + (author.isEmpty ? "" : "<dc:creator>\(TurathEPUB.escape(author))</dc:creator>")
            + "<dc:language>\(lang)</dc:language><meta property=\"dcterms:modified\">2000-01-01T00:00:00Z</meta></metadata><manifest>\(manifest)</manifest><spine\(rtl ? " page-progression-direction=\"rtl\"" : "")>\(spine)</spine></package>"
        files.append(("OEBPS/package.opf", Data(opf.utf8)))
        return try StoredZIP.encode(files)
    }

    static func isHeading(_ paragraph: String) -> Bool {
        paragraph.count <= 30 && paragraph.split(separator: " ").count <= 5 && !closes(paragraph)
    }

    /// The page's last line is about as long as its typical line (the paragraph runs on), not a short closing line.
    static func endsOnFullLine(_ text: String) -> Bool {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let last = lines.last else { return false }
        let lengths = lines.map(\.count).sorted()
        guard lengths.count >= 3 else { return true }
        return last.count * 10 >= lengths[lengths.count * 3 / 4] * 7
    }

    // MARK: - The book's printed contents

    public struct PrintedEntry: Equatable, Sendable { public let title: String; public let page: Int }

    /// Letters only, without vowel marks, tatweel or the spellings OCR confuses (أ/إ/آ, ى/ي, ة/ه).
    static func letters(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x064B...0x065F, 0x0670, 0x0640: continue
            case 0x0622, 0x0623, 0x0625, 0x0671: out.append("ا")
            case 0x0649, 0x0626: out.append("ي")
            case 0x0629: out.append("ه")
            case 0x0624: out.append("و")
            default: if CharacterSet.letters.contains(scalar) { out.unicodeScalars.append(scalar) }
            }
        }
        return out
    }

    static func similar(_ a: String, _ b: String) -> Bool {
        guard a.count >= 4, b.count >= 4 else { return a == b && !a.isEmpty }
        if a.contains(b) || b.contains(a) { return min(a.count, b.count) * 10 >= max(a.count, b.count) * 6 }
        func pairs(_ s: String) -> [String: Int] {
            let c = Array(s); var out: [String: Int] = [:]
            for i in 0..<(c.count - 1) { out[String(c[i...i + 1]), default: 0] += 1 }
            return out
        }
        let x = pairs(a), y = pairs(b)
        let shared = x.reduce(0) { $0 + min($1.value, y[$1.key] ?? 0) }
        return Double(2 * shared) / Double(a.count + b.count - 2) >= 0.7
    }

    /// The book's own contents page (a scanned book has no PDF bookmarks): each title with the zero-based
    /// page it opens on. Printed page numbers are shifted to file pages by the offset the chapter headings
    /// agree on; an entry without a usable number is placed by its heading. Fewer than three entries: none.
    public static func printedContents(_ texts: [String]) -> [PrintedEntry] {
        let heads: Set<String> = ["الفهرس", "فهرسالموضوعات", "فهرسالمحتويات", "المحتويات", "محتوياتالكتاب"]
        func lines(_ i: Int) -> [String] { texts[i].components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        // OCR can read several numbered titles as one line («١ - البداية ٢ - الطريق»): one title each.
        func titles(_ line: String) -> [String] {
            line.replacingOccurrences(of: #"\s+(?=[٠-٩0-9]{1,3}\s*[-–]\s)"#, with: "\n", options: .regularExpression)
                .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        func number(_ raw: String) -> Int? {
            let digits = raw.compactMap { $0.wholeNumberValue.map(String.init) ?? ($0 == "." || $0 == "٫" ? "." : nil) }.joined()
            guard let first = digits.split(separator: ".").first, !first.isEmpty else { return nil }
            return Int(first)
        }
        // Title lines with their printed numbers, from the contents page and the pages that continue it.
        guard let start = texts.indices.last(where: { i in lines(i).prefix(2).contains { heads.contains(letters($0)) } }) else { return [] }
        var raw: [(title: String, number: Int?)] = []
        var index = start
        while index < texts.count {
            var found = 0, numbers: [Int] = [], run = 0, longestRun = 0
            let first = raw.count
            for line in lines(index).flatMap(titles) where !heads.contains(letters(line)) {
                let name = line.drop { $0 == "-" || $0 == " " }
                let wordy = letters(String(name)).count >= 3
                let tail = line.reversed().prefix { $0.isNumber || $0 == "." || $0 == " " || $0 == "…" }
                if wordy {
                    var title = String(line.dropLast(tail.count)).trimmingCharacters(in: CharacterSet(charactersIn: " .…"))
                    if title.hasPrefix("-") { title = String(title.dropFirst()).trimmingCharacters(in: .whitespaces) }
                    raw.append((title, number(String(tail.reversed())))); found += 1; run = 0
                } else if let n = number(line) {
                    numbers.append(n); run += 1; longestRun = max(longestRun, run)
                    if let last = raw.indices.last, raw[last].number == nil { raw[last].number = n }
                }
            }
            // OCR read the page numbers as their own column: the page's titles take them in order.
            let untitled = raw.indices.filter { $0 >= first && raw[$0].number == nil || ($0 >= first && numbers.contains(raw[$0].number ?? -1) && longestRun >= 3) }
            if longestRun >= 3, abs(untitled.count - numbers.count) <= 1 {
                for (k, n) in zip(untitled, numbers) { raw[k].number = n }
            }
            // A page after the contents that lists fewer than three titles is the book's text, not more contents.
            if index > start && found < 3 { raw.removeSubrange(first...); break }
            index += 1
        }
        let contents = start..<index
        // Read a number OCR padded with leader dots («٥٥٠٠» for ٥٥) back to the plausible page.
        var previous = 0
        for k in raw.indices {
            guard var n = raw[k].number else { continue }
            // …also when it runs past the next title's number («٠٧٠٠» before «١١» is ٧, not ٧٠).
            let next = raw[(k + 1)...].lazy.compactMap(\.number).first { $0 <= texts.count }
            while n > texts.count || n < previous || next.map({ n > $0 }) == true, n >= 10, n % 10 == 0 { n /= 10 }
            if n > texts.count || n < previous { raw[k].number = nil } else { raw[k].number = n; previous = n }
        }
        func headingPage(_ title: String, from: Int, to: Int) -> Int? {
            let key = letters(title.drop { $0.isNumber || $0 == " " || $0 == "-" }.description)
            guard key.count >= 4 else { return nil }
            return (max(0, from)..<min(texts.count, to)).first { i in
                !contents.contains(i) && lines(i).prefix(2).contains { similar(letters($0), key) }
            }
        }
        // The shift between printed and file pages, by vote of the headings found near their printed page.
        var votes: [Int: Int] = [:]
        for entry in raw { if let n = entry.number, let page = headingPage(entry.title, from: n - 4, to: n + 8) { votes[page - (n - 1), default: 0] += 1 } }
        let offset = votes.max { $0.value == $1.value ? abs($0.key) > abs($1.key) : $0.value < $1.value }.flatMap { $0.value >= 2 ? $0.key : nil }
        var out: [PrintedEntry] = []
        for entry in raw {
            let page: Int?
            if let n = entry.number, let offset {
                // A misread number sends a title past its chapter: its heading earlier wins.
                let printed = n - 1 + offset, last = out.last?.page ?? 0
                page = printed > last && headingPage(entry.title, from: printed - 1, to: printed + 2) == nil
                    ? headingPage(entry.title, from: last, to: min(printed, contents.lowerBound)) ?? printed : printed
            }
            else { page = headingPage(entry.title, from: out.last?.page ?? 0, to: contents.lowerBound) }
            guard let page, (0..<texts.count).contains(page), page >= (out.last?.page ?? 0), !entry.title.isEmpty else { continue }
            out.append(PrintedEntry(title: entry.title, page: page))
        }
        return out.count >= 3 ? out : []
    }

    static let closers: Set<Character> = [".", "!", "?", "؟", ":", "…", "»", "\"", "”", "۔", ")"]
    static func closes(_ paragraph: String) -> Bool { paragraph.last.map { closers.contains($0) } ?? true }

    /// Running headers and footers (the book or chapter title repeated at the top of every page) and bare page
    /// numbers are not part of the text. A line counts as running when, ignoring its digits, it opens or closes
    /// at least three pages and a fifth of them.
    static func withoutRunningLines(_ texts: [String]) -> [String] {
        let pageNumber = try! NSRegularExpression(pattern: #"^[\s\-–—()\[\]{}<>«»ـ]*[0-9٠-٩]{1,4}[\s\-–—()\[\]{}<>«»ـ]*$"#)
        func key(_ line: String) -> String { line.filter { !$0.isNumber && !$0.isWhitespace } }
        func edges(_ lines: [String]) -> [String] {
            let kept = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            // A short page is not made entirely of headers. Never treat the
            // second/penultimate body line as an edge merely because it repeats.
            guard kept.count >= 2 else { return [] }
            return Array(kept.prefix(1) + kept.suffix(1))
        }
        let split = texts.map { $0.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") }
        var seen: [String: Int] = [:]
        for lines in split {
            let candidates = edges(lines).filter { !closes($0.trimmingCharacters(in: .whitespaces)) && $0.count <= 120 }
            for k in Set(candidates.map(key)) where k.count >= 3 { seen[k, default: 0] += 1 }
        }
        let threshold = max(3, texts.count / 5)
        let running = Set(seen.filter { $0.value >= threshold }.keys)
        return split.map { lines in
            let edge = Set(edges(lines))
            let kept = lines.filter { line in
                let range = NSRange(line.startIndex..., in: line)
                if edge.contains(line), pageNumber.firstMatch(in: line, range: range) != nil { return false }
                return !(edge.contains(line) && !closes(line.trimmingCharacters(in: .whitespaces)) && running.contains(key(line)))
            }
            // Repetition is evidence, not proof. If it would erase the whole
            // page, preserve its source text rather than manufacture a gap.
            return (kept.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } ? lines : kept).joined(separator: "\n")
        }
    }

    /// Joins a page's printed lines into paragraphs. A line ends its paragraph when it is blank, ends with
    /// closing punctuation, or is clearly shorter than the page's typical line (the last line of a paragraph).
    public static func paragraphs(_ text: String) -> [String] {
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
