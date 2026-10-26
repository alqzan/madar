import Foundation

/// §7.6: three reading slots, explicit finishes, and stable collection/number identities.
public enum BookCommand: Codable, Equatable, Sendable {
    case savePaper(id: UUID, title: String, author: String, pages: Int?, shelf: String, replacing: UUID?, isbn13: String?, tocJSON: Data?)
    case updatePaper(id: UUID, title: String, author: String, pages: Int?, position: Int, isbn13: String?, tocJSON: Data?)
    case importPDF(id: UUID, fileID: UUID, sha256: String, title: String, author: String, language: String)
    case importEPUB(id: UUID, fileID: UUID, sha256: String, title: String, author: String, language: String, shelf: String, turathID: Int? = nil)
    case deleteBook(id: UUID)
    case shelf(id: UUID, shelf: String, replacing: UUID?)
    /// Owner, 21 Oct 2026: rename a file book (EPUB or PDF) after import; paper books edit through `updatePaper`.
    case rename(id: UUID, title: String, author: String)
    case position(id: UUID, page: Int, finished: Bool)
    case readerLocator(id: UUID, locatorJSON: Data)
    case readingSession(id: UUID, bookID: UUID, start: Date, end: Date, activeSeconds: Int, fromPage: Int, toPage: Int, startLocatorJSON: Data, endLocatorJSON: Data, startProgression: Double, endProgression: Double, pagesCounted: Int)
    case hadith(number: Int, edition: String, understood: Bool, day: GregorianDay)
    case savePrivateNote(id: UUID, text: String)
    case deletePrivateNote(id: UUID)
    /// A paragraph or passage marked in a file book; `color` is a `readerThemes.highlightNames` id.
    case saveHighlight(id: UUID, bookID: UUID, locatorJSON: Data, color: String, pageLabel: String?)
    case deleteHighlight(id: UUID)
    /// «دوّن ملاحظة»: a note tied to the place in the book it was written at (link `page`).
    case savePageNote(id: UUID, bookID: UUID, text: String, locatorJSON: Data, page: Int?)
    /// «أضف إلى كلماتي»: one saved word with its source paragraph and reading position.
    case saveUserWord(id: UUID, word: String, language: String, bookID: UUID, bookTitle: String, locatorJSON: Data, context: String)
    public static let highlightColors: Set<String> = ["yellow", "green", "rose"]
    public static let names: Set<String> = ["book.savePaper", "book.updatePaper", "book.importPDF", "book.importEPUB", "book.delete", "book.moveShelf", "book.rename", "book.setPosition", "book.setLocator", "reading.saveSession", "hadith.mark", "notebook.savePrivate", "notebook.deletePrivate", "highlight.save", "highlight.delete", "notebook.savePage", "word.save"]
    public var isUndoable: Bool {
        if case .readingSession = self { return false }
        return true
    }
    public static func parse(_ name: String, _ p: [String: JSONValue]) -> Self? {
        func text(_ key: String) -> String? { if case .string(let s) = p[key] { s } else { nil } }
        func integer(_ key: String, max: Double = 100000) -> Int? { if case .number(let n) = p[key], n.isFinite, n.rounded() == n, n >= 0, n <= max { Int(n) } else { nil } }
        func progression(_ key: String) -> Double? { if case .number(let n) = p[key], n.isFinite, (0...1).contains(n) { n } else { nil } }
        func date(_ key: String) -> Date? {
            guard let value = text(key) else { return nil }
            let formats: [ISO8601DateFormatter.Options] = [.withInternetDateTime, [.withInternetDateTime, .withFractionalSeconds]]
            for format in formats {
                let formatter = ISO8601DateFormatter(); formatter.formatOptions = format
                if let result = formatter.date(from: value) { return result }
            }
            return nil
        }
        func locatorData(_ key: String) -> Data? {
            guard let value = text(key), value.utf8.count <= 16_384,
                  let data = value.data(using: .utf8),
                  case .object(let object)? = try? JSONDecoder().decode(JSONValue.self, from: data),
                  case .string(let href)? = object["href"], !href.isEmpty, href.utf8.count <= 1024,
                  !href.hasPrefix("/"), !href.contains(":"), !href.contains("\\"),
                  !href.split(separator: "/").contains(".."),
                  case .string(let type)? = object["type"], !type.isEmpty, type.utf8.count <= 128 else { return nil }
            return data
        }
        if name == "notebook.savePrivate" {
            guard Set(p.keys) == ["id", "text"], let id = text("id").flatMap(UUID.init(uuidString:)), let value = text("text"), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 2000 else { return nil }
            return .savePrivateNote(id: id, text: value)
        }
        if name == "notebook.deletePrivate" {
            guard Set(p.keys) == ["id"], let id = text("id").flatMap(UUID.init(uuidString:)) else { return nil }
            return .deletePrivateNote(id: id)
        }
        if name == "hadith.mark" {
            guard Set(p.keys) == ["number","edition","understood","day"], let n = integer("number"), (1...42).contains(n), let edition = text("edition"), !edition.isEmpty, edition.count <= 120, case .bool(let understood) = p["understood"], let day = text("day").flatMap({ try? GregorianDay($0) }) else { return nil }
            return .hadith(number: n, edition: edition, understood: understood, day: day)
        }
        if name == "word.save" {
            guard Set(p.keys) == ["id", "word", "language", "bookID", "bookTitle", "locator", "context"],
                  let id = text("id").flatMap(UUID.init(uuidString:)),
                  let word = text("word")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !word.isEmpty, word.count <= 120, word.split(whereSeparator: \.isWhitespace).count == 1,
                  let language = text("language"), ["ar", "en"].contains(language),
                  let bookID = text("bookID").flatMap(UUID.init(uuidString:)),
                  let bookTitle = text("bookTitle"), !bookTitle.isEmpty, bookTitle.count <= 300,
                  let locator = locatorData("locator"),
                  let context = text("context")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !context.isEmpty, context.count <= 4000 else { return nil }
            return .saveUserWord(id: id, word: word, language: language, bookID: bookID, bookTitle: bookTitle, locatorJSON: locator, context: context)
        }
        guard let id = text("id").flatMap(UUID.init(uuidString:)) else { return nil }
        switch name {
        case "highlight.save":
            guard Set(p.keys).isSubset(of: ["id", "bookID", "locator", "color", "pageLabel"]), Set(["id", "bookID", "locator", "color"]).isSubset(of: Set(p.keys)),
                  let bookID = text("bookID").flatMap(UUID.init(uuidString:)), let locator = locatorData("locator"),
                  let color = text("color"), highlightColors.contains(color) else { return nil }
            let label = text("pageLabel")
            guard p["pageLabel"] == nil || (label.map { !$0.isEmpty && $0.count <= 40 } ?? false) else { return nil }
            return .saveHighlight(id: id, bookID: bookID, locatorJSON: locator, color: color, pageLabel: label)
        case "highlight.delete":
            guard Set(p.keys) == ["id"] else { return nil }
            return .deleteHighlight(id: id)
        case "notebook.savePage":
            guard Set(p.keys).isSubset(of: ["id", "bookID", "text", "locator", "page"]), Set(["id", "bookID", "text", "locator"]).isSubset(of: Set(p.keys)),
                  let bookID = text("bookID").flatMap(UUID.init(uuidString:)), let locator = locatorData("locator"),
                  let value = text("text"), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 2000 else { return nil }
            let page = integer("page")
            guard p["page"] == nil || page.map({ $0 > 0 }) == true else { return nil }
            return .savePageNote(id: id, bookID: bookID, text: value, locatorJSON: locator, page: page)
        case "book.importPDF":
            guard Set(p.keys) == ["id", "fileID", "sha256", "title", "author", "language"],
                  let fileID = text("fileID").flatMap(UUID.init(uuidString:)),
                  let hash = text("sha256"), hash.count == 64, hash.allSatisfy({ "0123456789abcdef".contains($0) }),
                  let title = text("title")?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty, title.count <= 300,
                  let author = text("author"), author.count <= 300,
                  let language = text("language"), ["ar", "en"].contains(language) else { return nil }
            return .importPDF(id: id, fileID: fileID, sha256: hash, title: title, author: author, language: language)
        case "book.importEPUB":
            guard Set(p.keys).isSubset(of: ["id", "fileID", "sha256", "title", "author", "language", "shelf", "turathID"]),
                  Set(["id", "fileID", "sha256", "title", "author", "language", "shelf"]).isSubset(of: Set(p.keys)),
                  let fileID = text("fileID").flatMap(UUID.init(uuidString:)),
                  let hash = text("sha256"), hash.count == 64, hash.allSatisfy({ "0123456789abcdef".contains($0) }),
                  let title = text("title")?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty, title.count <= 300,
                  let author = text("author"), author.count <= 300,
                  let language = text("language"), ["ar", "en"].contains(language),
                  let shelf = text("shelf"), ["reading", "want", "finished"].contains(shelf) else { return nil }
            let turathID: Int?
            if p["turathID"] == nil { turathID = nil }
            else if let value = integer("turathID", max: 2_000_000_000), value > 0 { turathID = value }
            else { return nil }
            return .importEPUB(id: id, fileID: fileID, sha256: hash, title: title, author: author, language: language, shelf: shelf, turathID: turathID)
        case "book.delete":
            guard Set(p.keys) == ["id"] else { return nil }
            return .deleteBook(id: id)
        case "book.updatePaper":
            guard Set(p.keys) == ["id", "title", "author", "pages", "position", "isbn13", "tocJSON"],
                  let title = text("title")?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty, title.count <= 300,
                  let author = text("author"), author.count <= 300,
                  let position = integer("position") else { return nil }
            let pages: Int?
            if case .null = p["pages"] { pages = nil }
            else if let value = integer("pages"), value > 0 { pages = value }
            else { return nil }
            let isbn13: String?
            switch p["isbn13"] {
            case .null: isbn13 = nil
            case .string(let raw):
                guard let value = PaperBookIndex.normalizedISBN13(raw) else { return nil }
                isbn13 = value
            default: return nil
            }
            let tocJSON: Data?
            switch p["tocJSON"] {
            case .null: tocJSON = nil
            case .string(let raw):
                guard raw.utf8.count <= PaperBookIndex.maximumEncodedBytes,
                      let data = raw.data(using: .utf8),
                      PaperBookIndex.decode(data, pages: pages) != nil else { return nil }
                tocJSON = data
            default: return nil
            }
            return .updatePaper(id: id, title: title, author: author, pages: pages, position: position, isbn13: isbn13, tocJSON: tocJSON)
        case "book.savePaper":
            guard Set(p.keys).isSubset(of: ["id","title","author","pages","shelf","replacing","isbn13","tocJSON"]), let title = text("title")?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty, title.count <= 300, let author = text("author"), author.count <= 300, let shelf = text("shelf"), ["reading","want","finished"].contains(shelf), p["pages"] == nil || integer("pages").map({ (1...100000).contains($0) }) == true else { return nil }
            guard p["replacing"] == nil || text("replacing").flatMap(UUID.init(uuidString:)) != nil else { return nil }
            guard p["isbn13"] == nil || text("isbn13") != nil,
                  p["tocJSON"] == nil || text("tocJSON") != nil else { return nil }
            let isbn13: String?
            if let raw = text("isbn13") {
                guard let normalized = PaperBookIndex.normalizedISBN13(raw) else { return nil }
                isbn13 = normalized
            } else { isbn13 = nil }
            let tocJSON: Data?
            if let raw = text("tocJSON") {
                guard raw.utf8.count <= PaperBookIndex.maximumEncodedBytes,
                      let data = raw.data(using: .utf8),
                      PaperBookIndex.decode(data, pages: integer("pages")) != nil else { return nil }
                tocJSON = data
            } else { tocJSON = nil }
            return .savePaper(id: id, title: title, author: author, pages: integer("pages"), shelf: shelf, replacing: text("replacing").flatMap(UUID.init(uuidString:)), isbn13: isbn13, tocJSON: tocJSON)
        case "book.moveShelf":
            guard Set(p.keys).isSubset(of: ["id","shelf","replacing"]), let shelf = text("shelf"), ["reading","want","finished","old"].contains(shelf), p["replacing"] == nil || text("replacing").flatMap(UUID.init(uuidString:)) != nil else { return nil }
            return .shelf(id: id, shelf: shelf, replacing: text("replacing").flatMap(UUID.init(uuidString:)))
        case "book.rename":
            guard Set(p.keys) == ["id", "title", "author"],
                  let title = text("title")?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty, title.count <= 300,
                  let author = text("author")?.trimmingCharacters(in: .whitespacesAndNewlines), author.count <= 300 else { return nil }
            return .rename(id: id, title: title, author: author)
        case "book.setPosition":
            guard Set(p.keys) == ["id","page","finished"], let page = integer("page"), case .bool(let finished) = p["finished"] else { return nil }
            return .position(id: id, page: page, finished: finished)
        case "book.setLocator":
            guard Set(p.keys) == ["id", "locator"], let locator = locatorData("locator") else { return nil }
            return .readerLocator(id: id, locatorJSON: locator)
        case "reading.saveSession":
            let required: Set<String> = ["id", "bookID", "start", "end", "activeSeconds", "fromPage", "toPage", "startLocator", "endLocator", "startProgression", "endProgression", "pagesCounted"]
            guard Set(p.keys) == required,
                  let sessionBookID = text("bookID").flatMap(UUID.init(uuidString:)),
                  let start = date("start"), let end = date("end"), end >= start,
                  let activeSeconds = integer("activeSeconds", max: 86_400), activeSeconds >= 60,
                  let fromPage = integer("fromPage"), let toPage = integer("toPage"),
                  toPage >= fromPage,
                  let startLocator = locatorData("startLocator"), let endLocator = locatorData("endLocator"),
                  let startProgression = progression("startProgression"), let endProgression = progression("endProgression"),
                  let pagesCounted = integer("pagesCounted") else { return nil }
            return .readingSession(id: id, bookID: sessionBookID, start: start, end: end, activeSeconds: activeSeconds, fromPage: fromPage, toPage: toPage, startLocatorJSON: startLocator, endLocatorJSON: endLocator, startProgression: startProgression, endProgression: endProgression, pagesCounted: pagesCounted)
        default: return nil
        }
    }
}

public struct PaperBookPosition: Codable, Equatable, Sendable {
    public var page: Int
    public init(page: Int) { self.page = page }
}

public enum MihbaraReading {
    public static func nextHadith(numbers: [Int], read: Set<Int>, readToday: Set<Int>, count: Int) -> [Int] {
        let remaining = max(0, min(3, max(1, count)) - readToday.count)
        return Array(Set(numbers).subtracting(read).sorted().prefix(remaining))
    }
    public static func canRead(id: UUID, reading: Set<UUID>, replacing: UUID?) -> Bool {
        reading.contains(id) || reading.count < 3 || replacing.map { $0 != id && reading.contains($0) } == true
    }
    public static func progress(page: Int?, pages: Int?) -> Double? {
        guard let page, let pages, pages > 0 else { return nil }
        return min(1, max(0, Double(page) / Double(pages)))
    }
}
