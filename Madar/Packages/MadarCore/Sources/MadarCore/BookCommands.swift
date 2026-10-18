import Foundation

/// §7.6: three reading slots, explicit finishes, and stable collection/number identities.
public enum BookCommand: Codable, Equatable, Sendable {
    case savePaper(id: UUID, title: String, author: String, pages: Int?, shelf: String, replacing: UUID?, isbn13: String?, tocJSON: Data?)
    case importPDF(id: UUID, fileID: UUID, sha256: String, title: String, author: String, language: String)
    case importEPUB(id: UUID, fileID: UUID, sha256: String, title: String, author: String, language: String, shelf: String)
    case shelf(id: UUID, shelf: String, replacing: UUID?)
    case position(id: UUID, page: Int, finished: Bool)
    case readerLocator(id: UUID, locatorJSON: Data)
    case readingSession(id: UUID, bookID: UUID, start: Date, end: Date, activeSeconds: Int, fromPage: Int, toPage: Int, startLocatorJSON: Data, endLocatorJSON: Data, startProgression: Double, endProgression: Double, pagesCounted: Int)
    case hadith(number: Int, edition: String, understood: Bool, day: GregorianDay)
    case savePrivateNote(id: UUID, text: String)
    case deletePrivateNote(id: UUID)
    public static let names: Set<String> = ["book.savePaper", "book.importPDF", "book.importEPUB", "book.moveShelf", "book.setPosition", "book.setLocator", "reading.saveSession", "hadith.mark", "notebook.savePrivate", "notebook.deletePrivate"]
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
        guard let id = text("id").flatMap(UUID.init(uuidString:)) else { return nil }
        switch name {
        case "book.importPDF":
            guard Set(p.keys) == ["id", "fileID", "sha256", "title", "author", "language"],
                  let fileID = text("fileID").flatMap(UUID.init(uuidString:)),
                  let hash = text("sha256"), hash.count == 64, hash.allSatisfy({ "0123456789abcdef".contains($0) }),
                  let title = text("title")?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty, title.count <= 300,
                  let author = text("author"), author.count <= 300,
                  let language = text("language"), ["ar", "en"].contains(language) else { return nil }
            return .importPDF(id: id, fileID: fileID, sha256: hash, title: title, author: author, language: language)
        case "book.importEPUB":
            guard Set(p.keys) == ["id", "fileID", "sha256", "title", "author", "language", "shelf"],
                  let fileID = text("fileID").flatMap(UUID.init(uuidString:)),
                  let hash = text("sha256"), hash.count == 64, hash.allSatisfy({ "0123456789abcdef".contains($0) }),
                  let title = text("title")?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty, title.count <= 300,
                  let author = text("author"), author.count <= 300,
                  let language = text("language"), ["ar", "en"].contains(language),
                  let shelf = text("shelf"), ["reading", "want", "finished"].contains(shelf) else { return nil }
            return .importEPUB(id: id, fileID: fileID, sha256: hash, title: title, author: author, language: language, shelf: shelf)
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
