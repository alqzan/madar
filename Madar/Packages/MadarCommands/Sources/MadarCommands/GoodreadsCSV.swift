import Foundation
import CryptoKit
import MadarCore
import MadarData

public enum GoodreadsCSVError: Error, LocalizedError, Equatable, Sendable {
    case tooLarge
    case invalidUTF8
    case malformed
    case missingColumns([String])
    case noBooks
    case invalidBook(row: Int)
    case invalidReadCount(row: Int)
    case invalidRating(row: Int)
    case invalidReview(row: Int)
    case invalidPrivateNote(row: Int)
    case duplicateIdentity(row: Int)
    case invalidShelf(row: Int, value: String)
    case duplicateBookID(String)

    public var errorDescription: String? {
        switch self {
        case .tooLarge: "ملف Goodreads أكبر من الحد المسموح (٢٠ م.ب.)."
        case .invalidUTF8: "احفظ تصدير Goodreads بترميز UTF-8 ثم اختره مرة أخرى."
        case .malformed: "تعذّرت قراءة CSV؛ راجع علامات التنصيص والفواصل في الملف."
        case .missingColumns(let names): "الأعمدة المطلوبة غير موجودة: " + names.joined(separator: "، ")
        case .noBooks: "لم أجد كتبًا في هذا الملف."
        case .invalidBook(let row): "بيانات الكتاب في الصف \(row) غير مكتملة."
        case .invalidReadCount(let row): "عدد مرات القراءة غير صالح في الصف \(row)."
        case .invalidRating(let row): "التقييم غير صالح في الصف \(row)."
        case .invalidReview(let row): "المراجعة طويلة جدًا في الصف \(row)."
        case .invalidPrivateNote(let row): "الملاحظة الخاصة أطول من حد الدفتر في الصف \(row)."
        case .duplicateIdentity(let row): "تكرر كتاب بلا معرّف Goodreads في الصف \(row)، فلم أضفه مرتين."
        case .invalidShelf(let row, let value): "حالة Goodreads «\(value)» غير مدعومة في الصف \(row)."
        case .duplicateBookID(let id): "ظهر معرّف Goodreads نفسه أكثر من مرة: \(id)."
        }
    }
}

public struct GoodreadsCSVEntry: Equatable, Sendable {
    public let rowKey: String
    public let goodreadsID: String?
    public let title: String
    public let author: String
    public let isbn13: String?
    public let exclusiveShelf: String
    public let dateRead: Date?
    public let dateReadText: String
    public let rating: Int?
    public let readCount: Int
    public let review: String?
    public let privateNote: String?
    public let pages: Int?
    public let language: String
    /// Unmapped export columns, retained with the import link; review and private notes are stored in their owning records.
    public let archivedFields: [String: String]

    public var stableSourceID: String { goodreadsID ?? rowKey }
    public var deterministicBookID: UUID { StableIdentity.uuid(for: "goodreads:\(stableSourceID)") }
}

public struct GoodreadsBookCandidate: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let author: String
    public let isbn13: String?
    public let sourceGoodreadsID: String?
    public let shelf: String

    public init(id: UUID, title: String, author: String, isbn13: String?, sourceGoodreadsID: String?, shelf: String) {
        self.id = id; self.title = title; self.author = author; self.isbn13 = isbn13
        self.sourceGoodreadsID = sourceGoodreadsID; self.shelf = shelf
    }
}

public struct GoodreadsPreviewRow: Equatable, Sendable {
    public let entry: GoodreadsCSVEntry
    public let targetShelf: String
    public let targetBookID: UUID?
    public let suggestions: [GoodreadsBookCandidate]
}

public struct GoodreadsPreview: Equatable, Sendable {
    public let rows: [GoodreadsPreviewRow]
    public var createCount: Int { rows.filter { $0.targetBookID == nil }.count }
    public var updateCount: Int { rows.count - createCount }
    public var suggestionCount: Int { rows.filter { !$0.suggestions.isEmpty && $0.targetBookID == nil }.count }
    public var readingCount: Int { rows.filter { $0.targetShelf == "reading" }.count }
}

public enum GoodreadsCSV {
    public static let maximumBytes = 20 * 1024 * 1024
    public static let maximumRows = 5_000
    public static let defaultCutoffYear = 2024

    private static let mappedHeaders: Set<String> = [
        "book id", "title", "author", "additional authors", "isbn", "isbn13", "my rating",
        "exclusive shelf", "date read", "read count", "my review", "private notes", "number of pages", "language"
    ]

    public static func parse(_ data: Data) throws -> [GoodreadsCSVEntry] {
        guard data.count <= maximumBytes else { throw GoodreadsCSVError.tooLarge }
        guard var text = String(data: data, encoding: .utf8) else { throw GoodreadsCSVError.invalidUTF8 }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let rows = try parseRows(text)
        guard let rawHeaders = rows.first, !rawHeaders.isEmpty else { throw GoodreadsCSVError.noBooks }
        let headers = rawHeaders.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let normalizedHeaders = headers.map { $0.lowercased() }
        guard Set(normalizedHeaders).count == normalizedHeaders.count else { throw GoodreadsCSVError.malformed }
        let required = ["book id", "title", "author", "exclusive shelf"]
        let missing = required.filter { !normalizedHeaders.contains($0) }
        guard missing.isEmpty else { throw GoodreadsCSVError.missingColumns(missing) }
        let positions = Dictionary(uniqueKeysWithValues: normalizedHeaders.enumerated().map { ($1, $0) })
        func index(_ name: String) -> Int? { positions[name] }
        func value(_ row: [String], _ name: String) -> String {
            guard let index = index(name), row.indices.contains(index) else { return "" }
            return row[index]
        }

        var entries: [GoodreadsCSVEntry] = []
        var bookIDs = Set<String>()
        var rowKeys = Set<String>()
        for (offset, sourceRow) in rows.dropFirst().enumerated() {
            if sourceRow.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
            guard entries.count < maximumRows else { throw GoodreadsCSVError.tooLarge }
            guard sourceRow.count <= headers.count else { throw GoodreadsCSVError.malformed }
            var row = sourceRow
            if row.count < headers.count { row.append(contentsOf: repeatElement("", count: headers.count - row.count)) }
            let rowNumber = offset + 2
            let title = value(row, "title").trimmingCharacters(in: .whitespacesAndNewlines)
            let mainAuthor = value(row, "author").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 300, mainAuthor.count <= 300 else { throw GoodreadsCSVError.invalidBook(row: rowNumber) }
            let extras = value(row, "additional authors").trimmingCharacters(in: .whitespacesAndNewlines)
            let author = [mainAuthor, extras].filter { !$0.isEmpty }.joined(separator: ", ")
            guard author.count <= 600 else { throw GoodreadsCSVError.invalidBook(row: rowNumber) }

            let idText = value(row, "book id").trimmingCharacters(in: .whitespacesAndNewlines)
            let id = idText.isEmpty ? nil : idText
            guard idText.count <= 128 else { throw GoodreadsCSVError.invalidBook(row: rowNumber) }
            if let id, !bookIDs.insert(id).inserted { throw GoodreadsCSVError.duplicateBookID(id) }
            let exclusiveShelf = value(row, "exclusive shelf").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard ["read", "to-read", "currently-reading"].contains(exclusiveShelf) else {
                throw GoodreadsCSVError.invalidShelf(row: rowNumber, value: exclusiveShelf)
            }
            let countText = value(row, "read count").trimmingCharacters(in: .whitespacesAndNewlines)
            let readCount = countText.isEmpty ? 0 : (Int(countText).flatMap { $0 >= 0 ? $0 : nil } ?? -1)
            guard readCount >= 0 else { throw GoodreadsCSVError.invalidReadCount(row: rowNumber) }
            let ratingText = value(row, "my rating").trimmingCharacters(in: .whitespacesAndNewlines)
            let rating: Int?
            if ratingText.isEmpty || ratingText == "0" { rating = nil }
            else if let parsed = Int(ratingText), (1...5).contains(parsed) { rating = parsed }
            else { throw GoodreadsCSVError.invalidRating(row: rowNumber) }

            let isbn13 = normalizeISBN13(value(row, "isbn13")) ?? normalizeISBN13(value(row, "isbn"))
            let dateText = value(row, "date read").trimmingCharacters(in: .whitespacesAndNewlines)
            let dateRead = parseDate(dateText)
            let pagesText = value(row, "number of pages").trimmingCharacters(in: .whitespacesAndNewlines)
            let pages = Int(pagesText).flatMap { (1...100_000).contains($0) ? $0 : nil }
            let language = language(value(row, "language"), title: title)
            let rawValues = Dictionary(uniqueKeysWithValues: headers.enumerated().compactMap { position, header in
                mappedHeaders.contains(header.lowercased()) ? nil : (header, row[position])
            })
            let identity = id.map { "id:\($0)" } ?? "book:\(normalize(title))|\(normalize(author))|\(isbn13 ?? "")"
            let rowKey = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
            guard rowKeys.insert(rowKey).inserted else { throw GoodreadsCSVError.duplicateIdentity(row: rowNumber) }
            let reviewText = value(row, "my review")
            let noteText = value(row, "private notes")
            guard reviewText.count <= 20_000 else { throw GoodreadsCSVError.invalidReview(row: rowNumber) }
            guard noteText.count <= 2_000 else { throw GoodreadsCSVError.invalidPrivateNote(row: rowNumber) }
            entries.append(.init(rowKey: rowKey, goodreadsID: id, title: title, author: author, isbn13: isbn13,
                                 exclusiveShelf: exclusiveShelf, dateRead: dateRead, dateReadText: dateText,
                                 rating: rating, readCount: readCount, review: reviewText.isEmpty ? nil : reviewText,
                                 privateNote: noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : noteText,
                                 pages: pages, language: language, archivedFields: rawValues))
        }
        guard !entries.isEmpty else { throw GoodreadsCSVError.noBooks }
        return entries
    }

    public static func preview(
        entries: [GoodreadsCSVEntry], existing: [GoodreadsBookCandidate], cutoffYear: Int = defaultCutoffYear,
        missingDateShelf: String = "old", selectedMatches: [String: UUID] = [:]
    ) -> GoodreadsPreview {
        let cutoff = min(2100, max(1900, cutoffYear))
        let missingShelf = ["old", "finished"].contains(missingDateShelf) ? missingDateShelf : "old"
        let bySourceID = Dictionary(grouping: existing.compactMap { candidate -> (String, GoodreadsBookCandidate)? in
            candidate.sourceGoodreadsID.map { ($0, candidate) }
        }, by: \.0).mapValues { $0.map(\.1) }
        let byID = Dictionary(grouping: existing, by: \.id)
        let byISBN = Dictionary(grouping: existing.compactMap { candidate -> (String, GoodreadsBookCandidate)? in
            candidate.isbn13.map { ($0, candidate) }
        }, by: \.0).mapValues { $0.map(\.1) }
        let byTitleAuthor = Dictionary(grouping: existing, by: { normalize($0.title) + "\u{0}" + normalize($0.author) })
        var readingIDs = Set(existing.filter { $0.shelf == "reading" }.map(\.id))
        var rows: [GoodreadsPreviewRow] = []
        for entry in entries {
            let sourceMatch = entry.goodreadsID.flatMap { bySourceID[$0]?.first }
                ?? byID[entry.deterministicBookID]?.first
            let suggestions: [GoodreadsBookCandidate]
            if sourceMatch != nil {
                suggestions = []
            } else {
                let isbnMatches = entry.isbn13.map { isbn in byISBN[isbn, default: []].filter { $0.sourceGoodreadsID == nil } } ?? []
                if !isbnMatches.isEmpty { suggestions = isbnMatches }
                else {
                    let key = normalize(entry.title) + "\u{0}" + normalize(entry.author)
                    suggestions = byTitleAuthor[key, default: []].filter { $0.sourceGoodreadsID == nil }
                }
            }
            let chosenID = sourceMatch?.id ?? selectedMatches[entry.rowKey].flatMap { id in suggestions.contains(where: { $0.id == id }) ? id : nil }
            let requestedShelf: String
            switch entry.exclusiveShelf {
            case "read":
                if let dateRead = entry.dateRead {
                    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                    requestedShelf = (calendar.component(.year, from: dateRead) < cutoff) ? "old" : "finished"
                } else { requestedShelf = missingShelf }
            case "to-read": requestedShelf = "want"
            default: requestedShelf = "reading"
            }
            let shelf: String
            if requestedShelf == "reading" {
                if let chosenID, readingIDs.contains(chosenID) { shelf = "reading" }
                else if readingIDs.count < 3 {
                    shelf = "reading"; readingIDs.insert(chosenID ?? entry.deterministicBookID)
                } else { shelf = "want" }
            } else {
                shelf = requestedShelf
                if let chosenID { readingIDs.remove(chosenID) }
            }
            let sortedSuggestions = suggestions.sorted {
                let left = normalize($0.title), right = normalize($1.title)
                return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
            }
            rows.append(.init(entry: entry, targetShelf: shelf, targetBookID: chosenID, suggestions: sortedSuggestions))
        }
        return GoodreadsPreview(rows: rows)
    }

    public static func normalizeISBN13(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("=\""), value.hasSuffix("\"") { value = String(value.dropFirst(2).dropLast()) }
        value = value.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        let digits = value.uppercased()
        if digits.count == 13, digits.allSatisfy(\.isNumber), validISBN13(digits) { return digits }
        guard digits.count == 10, let check = digits.last,
              digits.dropLast().allSatisfy(\.isNumber), check.isNumber || check == "X",
              validISBN10(digits) else { return nil }
        let firstTwelve = "978" + digits.dropLast()
        let checksum = firstTwelve.enumerated().reduce(0) { $0 + (Int(String($1.element)) ?? 0) * ($1.offset.isMultiple(of: 2) ? 1 : 3) }
        return firstTwelve + String((10 - checksum % 10) % 10)
    }

    private static func parseDate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        let separator: Character = raw.contains("/") ? "/" : "-"
        let parts = raw.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let first = Int(parts[0]), let second = Int(parts[1]), let third = Int(parts[2]) else { return nil }
        let year: Int, month: Int, day: Int
        if parts[0].count == 4 { year = first; month = second; day = third }
        else { year = third; month = first; day = second }
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents(); components.year = year; components.month = month; components.day = day; components.hour = 12
        guard let date = calendar.date(from: components) else { return nil }
        let verified = calendar.dateComponents([.year, .month, .day], from: date)
        guard verified.year == year, verified.month == month, verified.day == day else { return nil }
        return date
    }

    private static func language(_ raw: String, title: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "en", "eng", "english": return "en"
        case "ar", "ara", "arabic": return "ar"
        default:
            let hasArabic = title.unicodeScalars.contains { (0x0600...0x06FF).contains(Int($0.value)) }
            let hasLatin = title.unicodeScalars.contains { CharacterSet.letters.contains($0) && (0x0041...0x024F).contains(Int($0.value)) }
            return hasLatin && !hasArabic ? "en" : "ar"
        }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    private static func validISBN13(_ value: String) -> Bool {
        guard value.count == 13, value.allSatisfy(\.isNumber) else { return false }
        let sum = value.prefix(12).enumerated().reduce(0) { $0 + (Int(String($1.element)) ?? 0) * ($1.offset.isMultiple(of: 2) ? 1 : 3) }
        return (10 - sum % 10) % 10 == Int(String(value.last!))
    }

    private static func validISBN10(_ value: String) -> Bool {
        let values = Array(value.uppercased())
        return values.count == 10 && values.enumerated().reduce(0) { partial, item in
            let digit = item.element == "X" ? 10 : (item.element.wholeNumberValue ?? -100)
            return partial + digit * (10 - item.offset)
        }.isMultiple(of: 11)
    }

    private static func parseRows(_ text: String) throws -> [[String]] {
        let chars = Array(text)
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closedQuote = false, index = 0
        func finishField() { row.append(field); field = ""; closedQuote = false }
        func finishRow() { finishField(); rows.append(row); row = [] }
        while index < chars.count {
            let char = chars[index]
            if quoted {
                if char == "\"" {
                    if index + 1 < chars.count, chars[index + 1] == "\"" { field.append("\""); index += 1 }
                    else { quoted = false; closedQuote = true }
                } else { field.append(char) }
            } else if closedQuote, char != ",", char != "\r\n", char != "\r", char != "\n", char != " ", char != "\t" {
                throw GoodreadsCSVError.malformed
            } else {
                switch char {
                case "\"":
                    guard field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !closedQuote else { throw GoodreadsCSVError.malformed }
                    field = ""; quoted = true
                case ",": finishField()
                case "\r\n": finishRow()
                case "\r":
                    finishRow()
                case "\n": finishRow()
                default:
                    if !closedQuote { field.append(char) }
                }
            }
            index += 1
        }
        guard !quoted else { throw GoodreadsCSVError.malformed }
        if !field.isEmpty || !row.isEmpty || closedQuote { finishRow() }
        return rows
    }
}

public struct GoodreadsCSVStage: Sendable {
    public let id: UUID
    public let sha256: String
    public let sizeBytes: Int
    public let fileName: String
}

public enum GoodreadsCSVFiles {
    public static let maximumBytes = GoodreadsCSV.maximumBytes

    public static func stage(source: URL, id: UUID, root: URL) throws -> GoodreadsCSVStage {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let sourceSize = values.fileSize, sourceSize > 0, sourceSize <= maximumBytes else { throw GoodreadsCSVError.tooLarge }
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        guard data.count == sourceSize, data.count <= maximumBytes else { throw GoodreadsCSVError.tooLarge }
        _ = try GoodreadsCSV.parse(data)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = stagedURL(id: id, root: root)
        try data.write(to: destination, options: .atomic)
        #if os(iOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        #endif
        return .init(id: id, sha256: Self.sha256(data), sizeBytes: data.count, fileName: source.lastPathComponent)
    }

    public static func read(id: UUID, root: URL, expectedHash: String? = nil) throws -> (Data, String) {
        let file = stagedURL(id: id, root: root)
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximumBytes else { throw GoodreadsCSVError.tooLarge }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let hash = Self.sha256(data)
        guard data.count == size, expectedHash == nil || expectedHash == hash else { throw GoodreadsCSVError.malformed }
        return (data, hash)
    }

    public static func stagedURL(id: UUID, root: URL) -> URL { root.appendingPathComponent("goodreads-\(id.uuidString).csv", isDirectory: false) }
    public static func discard(id: UUID, root: URL) { try? FileManager.default.removeItem(at: stagedURL(id: id, root: root)) }
    public static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
