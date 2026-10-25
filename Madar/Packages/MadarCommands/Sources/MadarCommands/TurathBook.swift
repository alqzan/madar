import Foundation

/// M6-T01: one book in the Turath catalogue (`files.turath.io/data-v3.json`), which carries the Shamela corpus.
public struct TurathCatalogueBook: Sendable, Identifiable, Hashable {
    public let id: Int
    public let title: String
    public let author: String
    public let authorDeath: Int?
    public let category: String
    public let pageCount: Int
    public let sizeBytes: Int
    public var link: URL { URL(string: "https://app.turath.io/book/\(id)")! }
    /// The shared Shamela catalogue id opens the corresponding public book page.
    public var shamelaLink: URL { URL(string: "https://shamela.ws/book/\(id)")! }
}

public enum TurathCatalogue {
    public static let catalogueURL = URL(string: "https://files.turath.io/data-v3.json")!
    public static func bookURL(_ id: Int) -> URL { URL(string: "https://files.turath.io/books-v3/\(id).json")! }

    private struct Raw: Decodable {
        struct Category: Decodable { let id: Int; let name: String }
        struct Author: Decodable { let id: Int; let name: String; let death: Int? }
        struct Book: Decodable { let id: Int; let name: String; let author_id: Int?; let cat_id: Int?; let size: Int?; let page_count: Int? }
        let cats: [String: Category]; let authors: [String: Author]; let books: [String: Book]
    }

    public static func decode(_ data: Data) throws -> [TurathCatalogueBook] {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        var authors: [Int: Raw.Author] = [:], cats: [Int: String] = [:]
        for a in raw.authors.values { authors[a.id] = a }
        for c in raw.cats.values { cats[c.id] = c.name }
        return raw.books.values.map { b in
            let a = b.author_id.flatMap { authors[$0] }
            return TurathCatalogueBook(id: b.id, title: b.name, author: a?.name ?? "", authorDeath: a?.death.flatMap { $0 > 0 && $0 < 99_999 ? $0 : nil },
                                       category: b.cat_id.flatMap { cats[$0] } ?? "", pageCount: b.page_count ?? 0, sizeBytes: b.size ?? 0)
        }.sorted { $0.id < $1.id }
    }

    /// Arabic search folds diacritics, tatweel and letter variants, so «صيد الخاطِر» and «صيد الخاطر» meet.
    public static func normalize(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for s in text.unicodeScalars {
            switch s.value {
            case 0x064B...0x065F, 0x0670, 0x0640, 0x06D6...0x06ED: continue
            case 0x0622, 0x0623, 0x0625, 0x0671: out.append("ا")
            case 0x0629: out.append("ه")
            case 0x0649: out.append("ي")
            case 0x0624: out.append("و")
            case 0x0626: out.append("ي")
            default: out.append(s)
            }
        }
        return String(out).lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Every query word must appear in the title or the author; title matches rank first, then shorter titles.
    public static func search(_ books: [TurathCatalogueBook], query: String, limit: Int = 50) -> [TurathCatalogueBook] {
        let words = normalize(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        var scored: [(Int, TurathCatalogueBook)] = []
        for book in books {
            let title = normalize(book.title), author = normalize(book.author)
            guard words.allSatisfy({ title.contains($0) || author.contains($0) }) else { continue }
            let phrase = words.joined(separator: " ")
            let score = (title.hasPrefix(phrase) ? 0 : title.contains(phrase) ? 1 : words.allSatisfy { title.contains($0) } ? 2 : 3) * 10_000 + min(title.count, 9_999)
            scored.append((score, book))
        }
        return scored.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.id < $1.1.id }.prefix(limit).map(\.1)
    }
}

/// A downloaded `books-v3/{id}.json`. Its metadata keys are obfuscated, so values are found by shape, never by key.
public struct TurathBookDocument: Sendable, Equatable {
    public struct Page: Sendable, Equatable { public let text: String; public let volume: String; public let page: Int? }
    public struct Heading: Sendable, Equatable { public let title: String; public let level: Int; public let pageIndex: Int }
    public let id: Int
    public let title: String
    public let author: String
    public let info: String
    public let headings: [Heading]
    public let pages: [Page]
    public let stamp: Int?
    public var shamelaLink: URL { URL(string: "https://shamela.ws/book/\(id)")! }

    public static func decode(_ data: Data, catalogue book: TurathCatalogueBook) throws -> TurathBookDocument {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawPages = root["pages"] as? [[String: Any]], !rawPages.isEmpty else { throw TurathError.unreadable }
        let pages = rawPages.map { p in
            Page(text: p["text"] as? String ?? "", volume: (p["vol"] as? String) ?? (p["vol"] as? Int).map(String.init) ?? "",
                 page: (p["page"] as? Int) ?? (p["page"] as? String).flatMap { Int($0) })
        }
        var info = "", headings: [Heading] = [], stamp: Int?
        for (key, value) in root where key != "pages" {
            guard let dict = value as? [String: Any] else { continue }
            for inner in dict.values {
                if let text = inner as? String, text.hasPrefix("الكتاب:") { info = text }
                if let n = inner as? Int, n > 1_000_000_000, n < 4_000_000_000 { stamp = n }
                if let list = inner as? [[String: Any]], list.first?["title"] != nil, list.first?["page"] != nil {
                    headings = list.compactMap { h in
                        guard let t = h["title"] as? String, let p = h["page"] as? Int else { return nil }
                        return Heading(title: t.trimmingCharacters(in: .whitespacesAndNewlines), level: max(1, h["level"] as? Int ?? 1), pageIndex: p)
                    }
                }
            }
        }
        return TurathBookDocument(id: book.id, title: book.title, author: book.author, info: info, headings: headings, pages: pages, stamp: stamp)
    }
}

public enum TurathError: Error, Equatable { case unreadable, tooLarge }

/// Builds a deterministic EPUB 3 (same input, same bytes) so the import's duplicate check recognises a re-download.
public enum TurathEPUB {
    static let pagesPerDocument = 30

    public static func build(_ book: TurathBookDocument) throws -> Data {
        let multiVolume = Set(book.pages.map(\.volume)).count > 1
        let chunks = stride(from: 0, to: book.pages.count, by: pagesPerDocument).map { $0..<min($0 + pagesPerDocument, book.pages.count) }
        var files: [(String, Data)] = [("mimetype", Data("application/epub+zip".utf8)),
                                       ("META-INF/container.xml", Data(#"<?xml version="1.0" encoding="UTF-8"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"#.utf8))]
        var pageList = "", titleIDs: [Int: String] = [:]
        // The info page carries edition, editor and publisher with the source, ahead of the text.
        let infoBody = book.info.split(separator: "\n").map { "<p>\(escape(String($0)))</p>" }.joined()
        files.append(("OEBPS/info.xhtml", xhtml(title: "بيانات الكتاب", body: "<section class=\"madar-turath-info\"><h1>\(escape(book.title))</h1>\(infoBody)<p class=\"madar-source\">المصدر: تراث · <a href=\"https://app.turath.io/book/\(book.id)\">app.turath.io/book/\(book.id)</a></p><p class=\"madar-source\"><a href=\"\(book.shamelaLink.absoluteString)\">افتح هذا الكتاب في موقع المكتبة الشاملة</a></p></section>")))
        for (n, range) in chunks.enumerated() {
            var body = ""
            for index in range {
                let page = book.pages[index], ordinal = index + 1
                let label = page.page.map { multiVolume ? "\(arabicDigits(page.volume))/\(arabicDigits(String($0)))" : arabicDigits(String($0)) }
                if let label {
                    body += "<span id=\"p-\(ordinal)\" epub:type=\"pagebreak\" role=\"doc-pagebreak\" title=\"\(label)\" aria-label=\"\(label)\"></span>"
                    pageList += "<li><a href=\"c\(n + 1).xhtml#p-\(ordinal)\">\(label)</a></li>"
                } else { body += "<span id=\"p-\(ordinal)\"></span>" }
                body += render(page.text, file: "c\(n + 1).xhtml", titleIDs: &titleIDs)
            }
            files.append(("OEBPS/c\(n + 1).xhtml", xhtml(title: book.title, body: "<section>\(body)</section>")))
        }
        // Heading N in the index is the N-th inline title span; fall back to the page anchor when a span is missing.
        var toc = "<li><a href=\"info.xhtml\">بيانات الكتاب</a></li>"
        var depth = 1
        for (i, h) in book.headings.enumerated() {
            let level = min(max(h.level, 1), depth + 1)
            let page = min(max(h.pageIndex, 1), max(book.pages.count, 1))
            let href = titleIDs[i + 1].map { "\($0)#toc-\(i + 1)" } ?? "c\((page - 1) / pagesPerDocument + 1).xhtml#p-\(page)"
            if level > depth { toc.removeLast(5); toc += "<ol>" } else { for _ in 0..<(depth - level) { toc += "</ol></li>" } }
            toc += "<li><a href=\"\(href)\">\(escape(h.title.isEmpty ? "—" : h.title))</a></li>"
            depth = level
        }
        for _ in 1..<depth { toc += "</ol></li>" }
        files.append(("OEBPS/nav.xhtml", xhtml(title: "الفهرس", body: "<nav epub:type=\"toc\"><h1>الفهرس</h1><ol>\(toc)</ol></nav>" + (pageList.isEmpty ? "" : "<nav epub:type=\"page-list\" hidden=\"\"><ol>\(pageList)</ol></nav>"))))
        let modified = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(book.stamp ?? 0)))
        let manifest = "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/><item id=\"info\" href=\"info.xhtml\" media-type=\"application/xhtml+xml\"/>"
            + chunks.indices.map { "<item id=\"c\($0 + 1)\" href=\"c\($0 + 1).xhtml\" media-type=\"application/xhtml+xml\"/>" }.joined()
        let spine = "<itemref idref=\"info\"/>" + chunks.indices.map { "<itemref idref=\"c\($0 + 1)\"/>" }.joined()
        let opf = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><package xmlns=\"http://www.idpf.org/2007/opf\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" version=\"3.0\" unique-identifier=\"bookid\" xml:lang=\"ar\" dir=\"rtl\"><metadata><dc:identifier id=\"bookid\">urn:turath:\(book.id)</dc:identifier><dc:title>\(escape(book.title))</dc:title>"
            + (book.author.isEmpty ? "" : "<dc:creator>\(escape(book.author))</dc:creator>")
            + "<dc:language>ar</dc:language><dc:source>https://app.turath.io/book/\(book.id)</dc:source><dc:publisher>تراث (turath.io)</dc:publisher><meta property=\"dcterms:modified\">\(modified)</meta></metadata><manifest>\(manifest)</manifest><spine page-progression-direction=\"rtl\">\(spine)</spine></package>"
        files.append(("OEBPS/package.opf", Data(opf.utf8)))
        return try StoredZIP.encode(files)
    }

    /// One Turath page: lines become paragraphs, inline title spans become anchored headings,
    /// and the part after the `_____` rule becomes the page's notes block.
    static func render(_ text: String, file: String, titleIDs: inout [Int: String]) -> String {
        let parts = text.components(separatedBy: "\n")
        var body: [String] = [], notes: [String] = [], inNotes = false
        for line in parts {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 5, trimmed.allSatisfy({ $0 == "_" }) { inNotes = true; continue }
            guard !trimmed.isEmpty else { continue }
            let html = inline(trimmed, file: file, titleIDs: &titleIDs)
            if inNotes { notes.append("<p>\(html.text)</p>") }
            else if html.isTitle { body.append("<h2>\(html.text)</h2>") }
            else { body.append("<p>\(html.text)</p>") }
        }
        return body.joined() + (notes.isEmpty ? "" : "<div class=\"madar-page-notes\" role=\"doc-endnotes\">\(notes.joined())</div>")
    }

    private static let titleSpan = try! NSRegularExpression(pattern: #"<span data-type=["']?title["']? id=["']?toc-(\d+)["']?>(.*?)</span>"#, options: [.dotMatchesLineSeparators])

    private static func inline(_ line: String, file: String, titleIDs: inout [Int: String]) -> (text: String, isTitle: Bool) {
        let ns = line as NSString
        var out = "", cursor = 0, titleLength = 0
        for m in titleSpan.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            out += escape(strip(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))))
            let n = Int(ns.substring(with: m.range(at: 1))) ?? 0, inner = strip(ns.substring(with: m.range(at: 2)))
            if titleIDs[n] == nil { titleIDs[n] = file; out += "<span id=\"toc-\(n)\" class=\"madar-title\">\(escape(inner))</span>" }
            else { out += "<span class=\"madar-title\">\(escape(inner))</span>" }
            titleLength += inner.count; cursor = m.range.location + m.range.length
        }
        let rest = strip(ns.substring(from: cursor))
        out += escape(rest)
        let plain = strip(line).trimmingCharacters(in: .whitespaces)
        return (out, titleLength > 0 && titleLength * 2 >= plain.count)
    }

    /// Drops any other markup so only text reaches the XHTML.
    private static func strip(_ text: String) -> String {
        text.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
    }

    static func escape(_ text: String) -> String {
        var out = ""
        for c in text {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default:
                // XML 1.0 forbids most control characters.
                if let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1, v < 0x20, v != 0x09 { continue }
                out.append(c)
            }
        }
        return out
    }

    static func arabicDigits(_ text: String) -> String {
        let digits = Array("٠١٢٣٤٥٦٧٨٩")
        return String(text.map { c in c.isASCII ? c.wholeNumberValue.map { digits[$0] } ?? c : c })
    }

    static func xhtml(title: String, body: String) -> Data {
        Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?><html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\" xml:lang=\"ar\" lang=\"ar\" dir=\"rtl\"><head><title>\(escape(title))</title>"
              + "<style>.madar-title{font-weight:bold}h2{font-size:1.15em;margin:1.2em 0 .5em}.madar-page-notes{font-size:.82em;opacity:.85;border-top:1px solid currentColor;margin-top:.8em;padding-top:.4em}.madar-page-notes p{margin:.2em 0}.madar-source{font-size:.85em;margin-top:2em}.madar-page-picture{margin:1em 0;text-align:center;page-break-inside:avoid;break-inside:avoid}.madar-page-picture img{max-width:100%;max-height:85vh;height:auto}</style>"
              + "</head><body>\(body)</body></html>").utf8)
    }
}

/// A stored-only ZIP in the exact order given, with fixed timestamps (the EPUB `mimetype` must come first).
enum StoredZIP {
    static func encode(_ files: [(String, Data)]) throws -> Data {
        guard files.count < 65_535 else { throw TurathError.tooLarge }
        var output = Data(), central = Data()
        for (path, bytes) in files {
            let name = Data(path.utf8), crc = crc32(bytes), offset = output.count
            guard output.count + bytes.count < Int(UInt32.max) - 1_000_000 else { throw TurathError.tooLarge }
            output += le(0x04034b50, 4) + le(20, 2) + le(0x800, 2) + le(0, 2) + le(0, 2) + le(33, 2)
            output += le(UInt64(crc), 4) + le(UInt64(bytes.count), 4) + le(UInt64(bytes.count), 4) + le(UInt64(name.count), 2) + le(0, 2) + name + bytes
            central += le(0x02014b50, 4) + le(20, 2) + le(20, 2) + le(0x800, 2) + le(0, 2) + le(0, 2) + le(33, 2)
            central += le(UInt64(crc), 4) + le(UInt64(bytes.count), 4) + le(UInt64(bytes.count), 4)
            central += le(UInt64(name.count), 2) + le(0, 2) + le(0, 2) + le(0, 2) + le(0, 2) + le(0, 4) + le(UInt64(offset), 4) + name
        }
        let start = output.count
        output += central
        output += le(0x06054b50, 4) + le(0, 2) + le(0, 2) + le(UInt64(files.count), 2) + le(UInt64(files.count), 2)
        output += le(UInt64(central.count), 4) + le(UInt64(start), 4) + le(0, 2)
        return output
    }
    private static func le(_ value: UInt64, _ count: Int) -> Data { Data((0..<count).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
    private static let table: [UInt32] = (0..<256).map { v in
        var c = UInt32(v)
        for _ in 0..<8 { c = (c >> 1) ^ (c & 1 == 1 ? 0xedb88320 : 0) }
        return c
    }
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc = (crc >> 8) ^ table[Int((crc ^ UInt32(byte)) & 0xff)] }
        return crc ^ 0xffffffff
    }
}
