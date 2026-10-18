import Foundation
import CryptoKit

// N01 (§7.3) as amended by RD8: Day One «JSON export» ZIP → a value-type plan. No store access here.
// Field names follow Day One's JSON export: one `<Journal>.json` per journal with `entries`, media files named by
// their md5 in photos/ audios/ videos/ pdfs/, and inline references `dayone-moment://<identifier>` (photos) or
// `dayone-moment:/<kind>/<identifier>` (audio, video, PDF) inside the Markdown text.

public enum DayOneImportError: Error, Equatable, Sendable {
    case noJournal
    case archive(ZIPReaderError)
}

public struct DayOneMediaRef: Codable, Equatable, Hashable, Sendable {
    /// Media.kind: photo | audio | video | doc
    public let kind: String
    public let identifier: String?
    public let md5: String?
    public let fileExtension: String
    public let durationS: Int?
    /// Archive member path when the file exists in the ZIP; nil = missing (recorded, never invented).
    public let path: String?
    public let size: Int
    /// True when the Markdown text references it in place.
    public let inline: Bool
    /// Media.sourceID: the md5 Day One names the file by, else the identifier.
    public var key: String { md5.flatMap { $0.isEmpty ? nil : $0 } ?? identifier ?? "" }
    public var found: Bool { path != nil }
    public var contentType: String { DayOneParser.mime(fileExtension, kind: kind) }
}

public struct DayOneEntryPlan: Codable, Equatable, Sendable {
    public let sourceID: String
    public let journal: String
    /// Day One creationDate (the event time). Stored as Entry.eventAt.
    public let createdAt: Date
    public let modifiedAt: Date?
    /// The entry's own zone from the export; nil when absent or not a valid identifier.
    public let timeZoneID: String?
    /// Day One all-day entries, or a local 00:00:00 creation time, carry a date without a time.
    public let dateOnly: Bool
    /// Markdown exactly as exported (Entry.textFormat = markdown).
    public let text: String
    public let tags: [String]
    public let starred: Bool
    public let place: String?
    public let latitude: Double?
    public let longitude: Double?
    /// Inline references first in reading order, then the rest in export order.
    public let media: [DayOneMediaRef]
    /// SHA-256 of the entry object re-serialised with sorted keys (key order and whitespace do not matter).
    public let hash: String
}

public struct DayOneSkip: Codable, Equatable, Sendable, Error {
    public enum Reason: String, Codable, Sendable { case noIdentity, noDate, empty, duplicateInFile, madarExport }
    public let journal: String
    public let sourceID: String?
    public let reason: Reason
}

public struct DayOneJournalFile: Codable, Equatable, Sendable {
    public let name: String
    public let path: String
    public let size: Int
}

public struct DayOnePlan: Sendable {
    public let entries: [DayOneEntryPlan]
    public let skipped: [DayOneSkip]
    public let journals: [DayOneJournalFile]
    /// Distinct media across entries (one file can serve several entries), keyed by Media.sourceID.
    public var media: [DayOneMediaRef] {
        var seen = Set<String>(); var result: [DayOneMediaRef] = []
        for item in entries.flatMap(\.media) where seen.insert(item.kind + ":" + item.key).inserted { result.append(item) }
        return result
    }
}

public enum DayOneParser {
    public static func plan(_ zip: ZIPReader) throws -> DayOnePlan {
        let files = zip.members.filter { !$0.isDirectory && !$0.path.hasPrefix("__MACOSX/") && !($0.path.split(separator: "/").last ?? "").hasPrefix("._") }
        // Lookup by file stem, lower-cased: Day One names media files by md5.
        var byStem: [String: [ZIPReader.Member]] = [:]
        for file in files {
            let name = String(file.path.split(separator: "/").last ?? "")
            let stem = name.contains(".") ? String(name[..<name.lastIndex(of: ".")!]) : name
            byStem[stem.lowercased(), default: []].append(file)
        }
        var entries: [DayOneEntryPlan] = [], skipped: [DayOneSkip] = [], journals: [DayOneJournalFile] = []
        var seen = Set<String>()
        for file in files.filter({ $0.path.lowercased().hasSuffix(".json") }).sorted(by: { $0.path < $1.path }) {
            let bytes: Data
            do { bytes = try zip.read(file) } catch let error as ZIPReaderError { throw DayOneImportError.archive(error) }
            guard let root = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], let list = root["entries"] as? [Any] else { continue }
            let journalName = String((file.path.split(separator: "/").last ?? "").dropLast(5))
            journals.append(.init(name: journalName, path: file.path, size: file.size))
            for case let object as [String: Any] in list {
                let parsed = entry(object, journal: journalName, byStem: byStem)
                switch parsed {
                case .failure(let skip): skipped.append(skip)
                case .success(let plan):
                    if !seen.insert(plan.sourceID).inserted { skipped.append(.init(journal: journalName, sourceID: plan.sourceID, reason: .duplicateInFile)); continue }
                    entries.append(plan)
                }
            }
        }
        guard !journals.isEmpty else { throw DayOneImportError.noJournal }
        return .init(entries: entries, skipped: skipped, journals: journals)
    }

    static func entry(_ object: [String: Any], journal: String, byStem: [String: [ZIPReader.Member]]) -> Result<DayOneEntryPlan, DayOneSkip> {
        guard let uuid = (object["uuid"] as? String)?.trimmingCharacters(in: .whitespaces), !uuid.isEmpty else {
            return .failure(.init(journal: journal, sourceID: nil, reason: .noIdentity))
        }
        guard let created = date(object["creationDate"]) else { return .failure(.init(journal: journal, sourceID: uuid, reason: .noDate)) }
        let zoneID = (object["timeZone"] as? String).flatMap { TimeZone(identifier: $0) != nil ? $0 : nil }
        // Madar's own V10 JSON export uses a deterministic id per day; importing it back would duplicate the diary.
        if let zoneID, let zone = TimeZone(identifier: zoneID) {
            let day = GregorianDay.containing(created, in: zone).description
            let own = SHA256.hash(data: Data(("madar.diary.day." + day).utf8)).prefix(16).map { String(format: "%02X", $0) }.joined()
            if uuid == own { return .failure(.init(journal: journal, sourceID: uuid, reason: .madarExport)) }
        }
        var text = object["text"] as? String ?? ""
        if text.isEmpty, let rich = object["richText"] as? String, let data = rich.data(using: .utf8),
           let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let contents = value["contents"] as? [[String: Any]] {
            text = contents.compactMap { $0["text"] as? String }.joined()
        }
        let inline = DayOneMarkdown.inlineIdentifiers(text)
        var refs: [DayOneMediaRef] = []
        for (field, kind, folder) in [("photos", "photo", "photos"), ("audios", "audio", "audios"), ("videos", "video", "videos"), ("pdfAttachments", "doc", "pdfs")] {
            let items = (object[field] as? [[String: Any]] ?? []).enumerated().sorted { ($0.element["orderInEntry"] as? Int ?? $0.offset) < ($1.element["orderInEntry"] as? Int ?? $1.offset) }.map(\.element)
            for item in items {
                let identifier = item["identifier"] as? String, md5 = item["md5"] as? String
                let candidates = [md5, identifier].compactMap { $0?.lowercased() }.flatMap { byStem[$0] ?? [] }
                let file = candidates.first { $0.path.lowercased().hasPrefix(folder + "/") || $0.path.lowercased().contains("/" + folder + "/") } ?? candidates.first
                let fileExtension = ((item["type"] as? String) ?? (item["format"] as? String) ?? file.map { String($0.path.split(separator: ".").last ?? "") } ?? "").lowercased()
                let duration = (item["duration"] as? Double).map { Int($0.rounded()) } ?? item["duration"] as? Int
                refs.append(.init(kind: kind, identifier: identifier, md5: md5, fileExtension: fileExtension, durationS: duration, path: file?.path, size: file?.size ?? 0,
                                  inline: identifier.map(inline.contains) ?? false))
            }
        }
        // Reading order: inline references in the order the text names them, then the rest as exported.
        let ordered = inline.compactMap { id in refs.first { $0.identifier == id } } + refs.filter { ref in !inline.contains(ref.identifier ?? "\u{0}") }
        var unique: [DayOneMediaRef] = []
        for ref in ordered where !unique.contains(ref) { unique.append(ref) }
        let readable = DayOneMarkdown.readable(text)
        guard !readable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !unique.isEmpty else {
            return .failure(.init(journal: journal, sourceID: uuid, reason: .empty))
        }
        var tags: [String] = []
        for tag in object["tags"] as? [String] ?? [] { let t = tag.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty && !tags.contains(t) { tags.append(t) } }
        let location = object["location"] as? [String: Any]
        let center = (location?["region"] as? [String: Any])?["center"] as? [String: Any]
        let place = [location?["placeName"], location?["localityName"], location?["administrativeArea"]].compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        var dateOnly = object["isAllDay"] as? Bool ?? false
        if !dateOnly, let zoneID, let zone = TimeZone(identifier: zoneID) {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            let parts = calendar.dateComponents([.hour, .minute, .second], from: created)
            dateOnly = parts.hour == 0 && parts.minute == 0 && parts.second == 0
        }
        return .success(.init(sourceID: uuid, journal: journal, createdAt: created, modifiedAt: date(object["modifiedDate"]), timeZoneID: zoneID, dateOnly: dateOnly,
                              text: text, tags: tags, starred: object["starred"] as? Bool ?? false, place: place,
                              latitude: number(location?["latitude"]) ?? number(center?["latitude"]), longitude: number(location?["longitude"]) ?? number(center?["longitude"]),
                              media: unique, hash: hash(object)))
    }

    public static func hash(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let plain = ISO8601DateFormatter(), fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return plain.date(from: text) ?? fractional.date(from: text)
    }
    static func number(_ value: Any?) -> Double? { (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? NSNumber)?.doubleValue }
    public static func mime(_ ext: String, kind: String) -> String {
        switch ext {
        case "jpeg", "jpg": "image/jpeg"; case "png": "image/png"; case "heic": "image/heic"; case "heif": "image/heif"; case "gif": "image/gif"; case "webp": "image/webp"
        case "m4a": "audio/mp4"; case "aac": "audio/aac"; case "mp3": "audio/mpeg"; case "wav": "audio/wav"; case "caf": "audio/x-caf"
        case "mov": "video/quicktime"; case "mp4": "video/mp4"; case "m4v": "video/x-m4v"
        case "pdf": "application/pdf"
        default: kind == "doc" ? "application/pdf" : "application/octet-stream"
        }
    }
}

/// Day key for an imported entry: its creation time in its *original* zone with the current `core.dayStart`
/// (N01, RD8). Without coordinates for a zone other than home, prayer times there are unknown, so the civil
/// date in that zone is used and `dayPolicy` says so. A date-only entry keeps its own date.
public enum DayOneDayKey {
    public struct Resolved: Equatable, Sendable {
        public let day: GregorianDay
        public let timeZoneID: String
        public let policy: String
    }
    public static func resolve(_ entry: DayOneEntryPlan, boundary: DayBoundary, home: ActivePlace, prayerDay: (ActivePlace, GregorianDay) -> PrayerDay?) -> Resolved {
        let zoneID = entry.timeZoneID ?? home.timeZoneID, zone = TimeZone(identifier: zoneID) ?? home.timeZone
        let civil = GregorianDay.containing(entry.createdAt, in: zone)
        if entry.dateOnly || boundary == .midnight { return .init(day: civil, timeZoneID: zoneID, policy: "midnight@1") }
        let place: ActivePlace?
        if let lat = entry.latitude, let lon = entry.longitude { place = try? ActivePlace(latitude: lat, longitude: lon, timeZoneID: zoneID) }
        else if zoneID == home.timeZoneID { place = home } else { place = nil }
        guard let place, let today = prayerDay(place, civil),
              let stored = try? MadarDay.resolve(instant: entry.createdAt, place: place, boundary: boundary, prayerDays: [today]) else {
            return .init(day: civil, timeZoneID: zoneID, policy: "midnight@1")
        }
        return .init(day: stored.date, timeZoneID: zoneID, policy: boundary.rawValue + "@1")
    }
}

/// Re-import rule (N01): matched by (source, sourceID). Same hash → skipped. Different hash → «عُدّلت في داي ون»:
/// update by default unless the entry was changed in Madar since import, then keep both.
public enum DayOneMerge {
    public enum Choice: String, Codable, CaseIterable, Sendable { case automatic, update, keepMine, keepBoth }
    public enum Action: String, Codable, Sendable { case add, same, update, keepMine, keepBoth, backfillTags }
    public struct Existing: Equatable, Sendable {
        public let hash: String?
        public let editedInMadar: Bool
        public let tags: [String]?
        public init(hash: String?, editedInMadar: Bool, tags: [String]? = nil) { self.hash = hash; self.editedInMadar = editedInMadar; self.tags = tags }
    }
    public static func action(hash: String, existing: Existing?, choice: Choice = .automatic, incomingTags: [String] = []) -> Action {
        guard let existing else { return .add }
        if existing.hash == hash {
            // V7 Entry rows archived the complete Day One JSON but had no dedicated tag field.
            // Let a user re-import the same export to restore tags without replacing local text edits.
            return existing.tags == nil && !incomingTags.isEmpty ? .backfillTags : .same
        }
        switch choice {
        case .automatic: return existing.editedInMadar ? .keepBoth : .update
        case .update: return .update
        case .keepMine: return .keepMine
        case .keepBoth: return .keepBoth
        }
    }
}

public enum DayOneMarkdown {
    private static let mediaToken = try! NSRegularExpression(pattern: #"!\[[^\]]*\]\(dayone-moment:[^)\s]*\)"#)
    private static let reference = try! NSRegularExpression(pattern: #"dayone-moment:(?://|/[A-Za-z]+/)([A-Za-z0-9-]+)"#)
    private static let heading = try! NSRegularExpression(pattern: #"(?m)^[ \t]{0,3}#{1,6}[ \t]+"#)
    /// Identifiers referenced inline, in reading order, without repeats.
    public static func inlineIdentifiers(_ text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        var result: [String] = []
        for match in reference.matches(in: text, range: range) {
            if let r = Range(match.range(at: 1), in: text), !result.contains(String(text[r])) { result.append(String(text[r])) }
        }
        return result
    }
    /// The Markdown with media references and heading markers removed; inline emphasis and escapes stay for the renderer.
    public static func readable(_ markdown: String) -> String {
        var text = mediaToken.stringByReplacingMatches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown), withTemplate: "")
        text = heading.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        while text.contains("\n\n\n") { text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Plain characters (no Markdown syntax) for search and exports.
    public static func plain(_ markdown: String) -> String {
        let readable = readable(markdown)
        guard let attributed = try? AttributedString(markdown: readable, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return readable }
        return String(attributed.characters)
    }
}
