import Foundation

/// §7.6: three reading slots, explicit finishes, and stable collection/number identities.
public enum BookCommand: Codable, Equatable, Sendable {
    case savePaper(id: UUID, title: String, author: String, pages: Int?, shelf: String, replacing: UUID?)
    case shelf(id: UUID, shelf: String, replacing: UUID?)
    case position(id: UUID, page: Int, finished: Bool)
    case hadith(number: Int, edition: String, understood: Bool, day: GregorianDay)
    public static let names: Set<String> = ["book.savePaper", "book.moveShelf", "book.setPosition", "hadith.mark"]
    public static func parse(_ name: String, _ p: [String: JSONValue]) -> Self? {
        func text(_ key: String) -> String? { if case .string(let s) = p[key] { s } else { nil } }
        func integer(_ key: String) -> Int? { if case .number(let n) = p[key], n.isFinite, n.rounded() == n, n >= 0, n <= 100000 { Int(n) } else { nil } }
        if name == "hadith.mark" {
            guard Set(p.keys) == ["number","edition","understood","day"], let n = integer("number"), (1...42).contains(n), let edition = text("edition"), !edition.isEmpty, edition.count <= 120, case .bool(let understood) = p["understood"], let day = text("day").flatMap({ try? GregorianDay($0) }) else { return nil }
            return .hadith(number: n, edition: edition, understood: understood, day: day)
        }
        guard let id = text("id").flatMap(UUID.init(uuidString:)) else { return nil }
        switch name {
        case "book.savePaper":
            guard Set(p.keys).isSubset(of: ["id","title","author","pages","shelf","replacing"]), let title = text("title")?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty, title.count <= 300, let author = text("author"), author.count <= 300, let shelf = text("shelf"), ["reading","want","finished"].contains(shelf), p["pages"] == nil || integer("pages").map({ (1...100000).contains($0) }) == true else { return nil }
            guard p["replacing"] == nil || text("replacing").flatMap(UUID.init(uuidString:)) != nil else { return nil }
            return .savePaper(id: id, title: title, author: author, pages: integer("pages"), shelf: shelf, replacing: text("replacing").flatMap(UUID.init(uuidString:)))
        case "book.moveShelf":
            guard Set(p.keys).isSubset(of: ["id","shelf","replacing"]), let shelf = text("shelf"), ["reading","want","finished","old"].contains(shelf), p["replacing"] == nil || text("replacing").flatMap(UUID.init(uuidString:)) != nil else { return nil }
            return .shelf(id: id, shelf: shelf, replacing: text("replacing").flatMap(UUID.init(uuidString:)))
        case "book.setPosition":
            guard Set(p.keys) == ["id","page","finished"], let page = integer("page"), case .bool(let finished) = p["finished"] else { return nil }
            return .position(id: id, page: page, finished: finished)
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
