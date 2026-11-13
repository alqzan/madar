import Foundation

/// Recovery when the store cannot be opened (T03). Everything here works without a session: it only reads the
/// backup folder and the pre-migration copies, and it never deletes the store that failed to open.
public enum StartupRecovery {
    public struct Candidate: Equatable, Sendable, Identifiable {
        public enum Source: String, Sendable { case manual, automatic, preMigration }
        public let url: URL, date: Date, bytes: Int64, source: Source
        public var id: String { url.path }
    }

    /// Automatic and manual backups from the catalogue, then folders kept before a migration. Newest first.
    public static func candidates(groupDirectory: URL) -> [Candidate] {
        let fm = FileManager.default
        var result: [Candidate] = []
        let backups = groupDirectory.appendingPathComponent("Backups", isDirectory: true)
        let catalogURL = backups.appendingPathComponent("BackupCatalog.json")
        if let data = try? Data(contentsOf: catalogURL), let receipts = try? JSONDecoder().decode([BackupReceipt].self, from: data) {
            for receipt in receipts {
                // The container path can change between launches, so the file is found again by its name.
                let url = backups.appendingPathComponent(receipt.fileURL.lastPathComponent)
                guard fm.fileExists(atPath: url.path) else { continue }
                result.append(.init(url: url, date: receipt.createdAt, bytes: size(of: url), source: receipt.kind == .manual ? .manual : .automatic))
            }
        }
        for folder in (try? MadarContainerFactory.preMigrationBackups(in: groupDirectory)) ?? [] {
            let date = (try? fm.attributesOfItem(atPath: folder.path)[.modificationDate] as? Date) ?? .distantPast
            result.append(.init(url: folder, date: date, bytes: size(of: folder), source: .preMigration))
        }
        return result.sorted { $0.date > $1.date }
    }

    /// Moves the unreadable store next to itself (never deletes it) so a clean store can open and a backup be restored.
    @discardableResult public static func setAsideStore(groupDirectory: URL, now: Date = Date()) throws -> URL {
        let fm = FileManager.default
        let root = groupDirectory.appendingPathComponent("ManagedData", isDirectory: true)
        guard fm.fileExists(atPath: root.path) else { throw DataError.invalidValue("no store to set aside") }
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "")
        let target = groupDirectory.appendingPathComponent("ManagedData.unreadable-\(stamp)", isDirectory: true)
        guard !fm.fileExists(atPath: target.path) else { throw DataError.invalidValue("recovery folder exists") }
        try fm.moveItem(at: root, to: target)
        return target
    }

    /// Puts the set-aside store back, used when the clean store also fails to open.
    public static func putBack(_ setAside: URL, groupDirectory: URL) throws {
        let fm = FileManager.default
        let root = groupDirectory.appendingPathComponent("ManagedData", isDirectory: true)
        if fm.fileExists(atPath: root.path) { try fm.removeItem(at: root) } // only the empty replacement that just failed
        try fm.moveItem(at: setAside, to: root)
    }

    private static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue { return ((try? fm.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0 }
        let files = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])?.compactMap { (try? ($0 as? URL)?.resourceValues(forKeys: [.fileSizeKey]))??.fileSize } ?? []
        return files.reduce(0) { $0 + Int64($1) }
    }
}
