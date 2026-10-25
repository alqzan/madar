#if DEBUG
import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarPrayer

/// Owner prayer trial (item 19, 24 Oct 2026). Runs only in a DEBUG build, only in an isolated UI-test store, and only
/// when MADAR_TRIAL_PRAYER names the old backup on this Mac. Rows are inserted directly in one save (past prayers keep
/// their own day), each legacy day with an ImportLink; ids derive from day and prayer, so a second run adds nothing.
/// Tracking starts at the first legacy day, so the imported history counts. Writes a counts-only report.
extension AppSession {
    func runLegacyPrayerTrialIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        guard env["MADAR_UI_STORE_ID"] != nil, let path = env["MADAR_TRIAL_PRAYER"], !path.isEmpty else { return }
        var counts: [String: Int] = [:]
        do {
            counts = try importLegacyPrayer(Data(contentsOf: URL(fileURLWithPath: path)), writer: "madar.app.trial", now: Date())
            let check = ModelContext(container)
            counts["store.logs"] = try check.fetch(FetchDescriptor<PrayerLog>()).filter { $0.deletedAt == nil }.count
            counts["store.qadaOpen"] = try check.fetch(FetchDescriptor<QadaItem>()).filter { $0.deletedAt == nil && $0.madeUpAt == nil }.count
            counts["store.qadaMadeUp"] = try check.fetch(FetchDescriptor<QadaItem>()).filter { $0.deletedAt == nil && $0.madeUpAt != nil }.count
            try reload(); try publishSnapshot()
        } catch { counts["failed"] = 1; counts["failed." + String(String(describing: error).prefix(80))] = 1 }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stamp = env["MADAR_TRIAL_RUN"] ?? "run"
        try? encoder.encode(counts).write(to: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("prayer-import-\(stamp).json"))
    }
}
#endif
