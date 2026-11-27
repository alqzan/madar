import Foundation
import CryptoKit

/// The old web app's backup keeps the diary in top-level `journalEntries`, media embedded as `data:` URLs.
/// This turns it into the Day One-shaped ZIP that `DayOneParser` reads, so the diary's own import (preview, merge,
/// undo) moves it. Mirrors `scripts/legacy-diary-to-dayone.py`; only embedded media becomes files.
/// Photo references that are not embedded stay references (they show as missing, never invented).
public enum LegacyDiaryArchive {
    public enum Failure: Error, Equatable, Sendable { case tooLarge }

    /// Number of entries in the backup's `journalEntries`; 0 when absent or unreadable.
    public static func entryCount(inBackup data: Data) -> Int {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return 0 }
        return (root["journalEntries"] as? [Any])?.count ?? 0
    }

    /// nil when the backup has no journal entries (or none with an id and a date).
    public static func zip(fromBackup data: Data) throws -> Data? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let source = root["journalEntries"] as? [Any], !source.isEmpty else { return nil }
        var files: [(path: String, bytes: Data)] = []
        var written = Set<String>()
        var entries: [[String: Any]] = []
        for case let e as [String: Any] in source {
            guard let uuid = nonEmpty(e["dayOneUUID"]) ?? nonEmpty(e["id"]), let day = e["date"] as? String,
                  let created = creation(e, day: day) else { continue }
            var text = e["content"] as? String ?? ""
            if let title = nonEmpty(e["title"]) { text = "# " + title + (text.isEmpty ? "" : "\n\n" + text) }
            var item: [String: Any] = ["uuid": uuid, "creationDate": created, "timeZone": nonEmpty(e["timeZone"]) ?? "Asia/Riyadh",
                                       "text": text, "starred": (e["starred"] as? Bool) ?? false, "madarLegacyDay": day]
            if let modified = nonEmpty(e["modifiedAt"]) { item["modifiedDate"] = modified }
            if let loc = e["location"] as? [String: Any], let lat = DayOneParser.number(loc["lat"]) {
                item["location"] = ["latitude": lat, "longitude": DayOneParser.number(loc["lng"]) ?? 0, "placeName": (loc["place"] as? String) ?? ""] as [String: Any]
            }
            var media: [String: [[String: Any]]] = [:]
            var seen = Set<String>()
            func add(_ value: Any?, _ forcedKind: String? = nil) {
                guard let s = value as? String, let m = decode(s) else { return }
                let kind = forcedKind ?? m.kind
                guard seen.insert(kind + m.md5).inserted else { return }
                let path = m.folder(kind) + "/" + m.md5 + "." + m.ext
                if written.insert(path).inserted { files.append((path, m.bytes)) }
                media[kind, default: []].append(["identifier": m.md5, "md5": m.md5, "type": m.ext, "orderInEntry": media[kind, default: []].count])
            }
            for v in e["photos"] as? [Any] ?? [] { add(v) }
            add(e["photo"])
            for v in e["audios"] as? [Any] ?? [] { add(v) }
            add(e["audio"])
            for case let a as [String: Any] in e["attachmentRefs"] as? [Any] ?? [] { add(a["localData"]) }
            for ref in e["photoRefs"] as? [String] ?? [] {
                media["photos", default: []].append(["identifier": ref, "md5": ref, "type": "jpeg", "orderInEntry": media["photos", default: []].count])
            }
            // Day One names the PDF list `pdfAttachments` (its folder stays `pdfs/`).
            for (key, list) in media { item[key == "pdfs" ? "pdfAttachments" : key] = list }
            entries.append(item)
        }
        guard !entries.isEmpty else { return nil }
        let journal = try JSONSerialization.data(withJSONObject: ["metadata": ["version": "1.0"], "entries": entries] as [String: Any], options: [.withoutEscapingSlashes])
        return try ZIPWriter.stored([("Journal.json", journal)] + files)
    }

    private static func nonEmpty(_ v: Any?) -> String? { (v as? String).flatMap { $0.isEmpty ? nil : $0 } }

    /// capturedAt as stored, else the old app's local date and time (+03:00) as UTC.
    private static func creation(_ e: [String: Any], day: String) -> String? {
        if let c = nonEmpty(e["capturedAt"]) { return c }
        let d = day.split(separator: "-").compactMap { Int($0) }
        guard d.count == 3 else { return nil }
        let t = (nonEmpty(e["time"]) ?? "12:00").split(separator: ":").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
        guard let date = calendar.date(from: DateComponents(year: d[0], month: d[1], day: d[2], hour: t.first ?? 12, minute: t.count > 1 ? t[1] : 0)) else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private struct Media { let kind: String, ext: String, bytes: Data, md5: String
        func folder(_ kind: String) -> String { kind == "photos" ? "photos" : kind == "audios" ? "audios" : "pdfs" } }

    private static func decode(_ s: String) -> Media? {
        guard s.hasPrefix("data:"), let comma = s.firstIndex(of: ",") else { return nil }
        let head = s[s.index(s.startIndex, offsetBy: 5)..<comma].split(separator: ";").map { $0.lowercased() }
        guard head.contains("base64"), let mime = head.first,
              let bytes = Data(base64Encoded: String(s[s.index(after: comma)...]), options: .ignoreUnknownCharacters), !bytes.isEmpty else { return nil }
        let table: [String: (String, String)] = [
            "image/jpeg": ("photos", "jpeg"), "image/jpg": ("photos", "jpeg"), "image/png": ("photos", "png"), "image/heic": ("photos", "heic"),
            "image/heif": ("photos", "heif"), "image/gif": ("photos", "gif"), "image/webp": ("photos", "webp"),
            "audio/mp4": ("audios", "m4a"), "audio/x-m4a": ("audios", "m4a"), "audio/aac": ("audios", "aac"), "audio/mpeg": ("audios", "mp3"),
            "audio/wav": ("audios", "wav"), "audio/x-wav": ("audios", "wav"), "audio/webm": ("audios", "webm"), "audio/ogg": ("audios", "ogg"),
            "application/pdf": ("pdfs", "pdf")]
        guard let (kind, ext) = table[mime] else { return nil }
        let md5 = Insecure.MD5.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return Media(kind: kind, ext: ext, bytes: bytes, md5: md5)
    }
}

/// Minimal STORED-method ZIP writer (UTF-8 names, CRC-32), no ZIP64.
enum ZIPWriter {
    private static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i); for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }; return c }
    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return ~c
    }
    static func stored(_ members: [(String, Data)]) throws -> Data {
        var out = Data(), central = Data()
        func u16(_ v: Int, _ d: inout Data) { d.append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
        func u32(_ v: Int, _ d: inout Data) { u16(v & 0xFFFF, &d); u16((v >> 16) & 0xFFFF, &d) }
        for (name, bytes) in members {
            let nameBytes = Data(name.utf8), crc = Int(crc32(bytes)), offset = out.count
            guard bytes.count < 0xFFFF_FFFF, offset < 0xFFFF_FFFF else { throw LegacyDiaryArchive.Failure.tooLarge }
            var local = Data()
            u32(0x04034b50, &local); u16(20, &local); u16(0x0800, &local); u16(0, &local); u16(0, &local); u16(0x21, &local)
            u32(crc, &local); u32(bytes.count, &local); u32(bytes.count, &local); u16(nameBytes.count, &local); u16(0, &local)
            out.append(local); out.append(nameBytes); out.append(bytes)
            u32(0x02014b50, &central); u16(20, &central); u16(20, &central); u16(0x0800, &central); u16(0, &central); u16(0, &central); u16(0x21, &central)
            u32(crc, &central); u32(bytes.count, &central); u32(bytes.count, &central); u16(nameBytes.count, &central)
            u16(0, &central); u16(0, &central); u16(0, &central); u16(0, &central); u32(0, &central); u32(offset, &central)
            central.append(nameBytes)
        }
        guard out.count + central.count < 0xFFFF_FFFF, members.count < 0xFFFF else { throw LegacyDiaryArchive.Failure.tooLarge }
        var end = Data()
        u32(0x06054b50, &end); u16(0, &end); u16(0, &end); u16(members.count, &end); u16(members.count, &end)
        u32(central.count, &end); u32(out.count, &end); u16(0, &end)
        return out + central + end
    }
}
