import Foundation

/// B1-17: unpacked books, import caches and export folders were left in the temporary directory when a screen was closed
/// abnormally. At launch, items this app creates there (known names only) that are over an hour old are removed.
enum TemporaryFilesCleanup {
    static let knownPrefixes = ["MadarReader", "DayOneImport", "DiaryExport", "MadarImport-", "MadarSearch-", "DiaryPreview-", "Journal.zip"]
    static let knownSuffixes = [".epub", ".m4a"]

    @discardableResult
    static func run(in directory: URL = FileManager.default.temporaryDirectory, now: Date = Date(), olderThan age: TimeInterval = 3600) -> Int {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return 0 }
        var removed = 0
        for item in items {
            let name = item.lastPathComponent
            let ours = knownPrefixes.contains { name.hasPrefix($0) }
                || (knownSuffixes.contains { name.hasSuffix($0) } && UUID(uuidString: item.deletingPathExtension().lastPathComponent) != nil)
            guard ours, let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  now.timeIntervalSince(modified) > age else { continue }
            if (try? fileManager.removeItem(at: item)) != nil { removed += 1 }
        }
        return removed
    }
}
