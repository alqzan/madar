#if DEBUG
import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarQuran
import MadarCommands

/// Owner Quran trial (item 19, 24 Oct 2026). Runs only in a DEBUG build, only in an isolated UI-test store, and only
/// when MADAR_TRIAL_QURAN names the old backup on this Mac. Never a registered command, URL or Shortcut. Rows are
/// inserted directly in one save (past sessions keep their legacy times), each with an ImportLink; ids derive from the
/// legacy ids, so a second run adds nothing. Writes a counts-only report next to the backup.
extension AppSession {
    func runLegacyQuranTrialIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        guard env["MADAR_UI_STORE_ID"] != nil, let path = env["MADAR_TRIAL_QURAN"], !path.isEmpty else { return }
        var counts: [String: Int] = [:]
        do {
            let catalog = try QuranResources.catalog(), now = Date(), batchID = StableIdentity.uuid(for: "myDream:ImportBatch:quran")
            counts = try importLegacyQuran(Data(contentsOf: URL(fileURLWithPath: path)), fileName: URL(fileURLWithPath: path).lastPathComponent, writer: "madar.app.trial", now: now)
            let check = ModelContext(container), snapshot = try QuranRepository(context: check, catalog: catalog).snapshot(at: now)
            counts["store.sessions"] = try check.fetch(FetchDescriptor<HifzSession>()).filter { $0.deletedAt == nil }.count
            counts["store.grades"] = try check.fetch(FetchDescriptor<PageGrade>()).filter { $0.deletedAt == nil }.count
            counts["store.spots"] = try check.fetch(FetchDescriptor<MistakeSpot>()).filter { $0.deletedAt == nil }.count
            counts["store.importLinks"] = try check.fetch(FetchDescriptor<ImportLink>()).filter { $0.deletedAt == nil && $0.importBatchID == batchID }.count
            counts["store.plans"] = try check.fetch(FetchDescriptor<HifzPlan>()).filter { $0.deletedAt == nil }.count
            counts["derived.coveredAyahs"] = snapshot.coverage.coveredAyahs.count
            counts["derived.completedPages"] = snapshot.coverage.completedPages.count
            counts["derived.maxCoveredAyah"] = snapshot.coverage.coveredAyahs.max() ?? 0
            counts["derived.duePages"] = snapshot.pages.filter(\.isDue).count
            counts["derived.openMistakes"] = snapshot.drillBoard.openCount
            counts["derived.reviewToday"] = snapshot.review.allPages.count
            counts["derived.testPages"] = snapshot.testPages.count
            try reload(); try publishSnapshot()
        } catch { counts["failed"] = 1; counts["failed." + String(String(describing: error).prefix(80))] = 1 }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stamp = env["MADAR_TRIAL_RUN"] ?? "run"
        try? encoder.encode(counts).write(to: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("quran-import-\(stamp).json"))
    }
}
#endif
