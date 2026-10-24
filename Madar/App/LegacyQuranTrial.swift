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
            let catalog = try QuranResources.catalog(), zone = TimeZone(identifier: "Asia/Riyadh")!
            let plan = try LegacyQuranImport.plan(backup: Data(contentsOf: URL(fileURLWithPath: path)), timeZone: zone, catalog: catalog, uuid: StableIdentity.uuid(for:))
            counts = plan.counts
            let context = ModelContext(container), now = Date(), writer = "madar.app.trial"
            let links = Set(try context.fetch(FetchDescriptor<ImportLink>()).map(\.id))
            let batchID = StableIdentity.uuid(for: "myDream:ImportBatch:quran")
            func link(_ model: String, _ sourceID: String, target: String, _ targetID: UUID?, _ json: Data?) {
                let id = StableIdentity.uuid(for: "myDream:ImportLink:\(model):\(sourceID)")
                guard !links.contains(id) else { counts["replay.existing", default: 0] += 1; return }
                let row = ImportLink(); row.id = id; row.source = "myDream"; row.sourceModel = model; row.sourceID = sourceID
                row.targetModel = target; row.targetID = targetID; row.importBatchID = batchID; row.unmappedJSON = json
                row.createdAt = now; row.updatedAt = now; row.importedAt = now; row.writerID = writer; context.insert(row)
                counts["links.created", default: 0] += 1
            }
            if !(try context.fetch(FetchDescriptor<ImportBatch>()).contains { $0.id == batchID }) {
                let batch = ImportBatch(); batch.id = batchID; batch.kind = "migration"; batch.fileName = URL(fileURLWithPath: path).lastPathComponent
                batch.startedAt = now; batch.finishedAt = now; batch.status = "done"
                batch.summaryJSON = (try? JSONEncoder().encode(plan.counts)) ?? Data()
                batch.createdAt = now; batch.updatedAt = now; batch.writerID = writer; context.insert(batch)
            }
            let planIDs = Set(try context.fetch(FetchDescriptor<HifzPlan>()).map(\.id))
            if let p = plan.plan, !planIDs.contains(p.id) {
                let row = HifzPlan(); row.id = p.id; row.version = 1; row.startAyah = p.startAyah; row.unit = p.unit; row.amount = p.amount
                row.rhythm = p.rhythm; row.frontierAyah = p.frontierAyah; row.activeFrom = p.activeFrom
                row.createdAt = p.activeFrom; row.updatedAt = p.updatedAt; row.writerID = writer; context.insert(row)
                link("HifzPlan.v1", p.sourceID, target: "HifzPlan", p.id, nil)
            }
            let sessionIDs = Set(try context.fetch(FetchDescriptor<HifzSession>()).map(\.id))
            for s in plan.sessions where !sessionIDs.contains(s.id) {
                let row = HifzSession(); row.id = s.id; row.planID = plan.plan?.id; row.dayKey = s.dayKey; row.endedAt = s.endedAt
                row.tzID = zone.identifier; row.dayPolicy = "legacy@0"; row.kind = s.kind; row.fromAyah = s.fromAyah; row.toAyah = s.toAyah
                row.pages = s.pages; row.source = "import"; row.createdAt = s.endedAt; row.updatedAt = s.updatedAt; row.writerID = writer
                context.insert(row); link(s.sourceModel, s.sourceID, target: "HifzSession", s.id, s.raw)
            }
            let gradeIDs = Set(try context.fetch(FetchDescriptor<PageGrade>()).map(\.id))
            let ended = Dictionary(uniqueKeysWithValues: plan.sessions.map { ($0.id, $0.endedAt) })
            for g in plan.grades where !gradeIDs.contains(g.id) {
                let row = PageGrade(); row.id = g.id; row.sessionID = g.sessionID; row.page = g.page; row.grade = g.grade; row.role = "regular"
                row.createdAt = ended[g.sessionID] ?? now; row.updatedAt = row.createdAt; row.writerID = writer; context.insert(row)
            }
            let spotIDs = Set(try context.fetch(FetchDescriptor<MistakeSpot>()).map(\.id))
            for m in plan.spots where !spotIDs.contains(m.id) {
                let row = MistakeSpot(); row.id = m.id; row.ayahId = m.ayahId; row.wordIndex = m.wordIndex; row.legacyHits = m.legacyHits
                row.legacyLastDrillAt = m.legacyLastDrillAt; row.legacyStreak = m.legacyStreak
                row.createdAt = m.updatedAt; row.updatedAt = m.updatedAt; row.writerID = writer
                context.insert(row); link("HifzMistake", m.sourceID, target: "MistakeSpot", m.id, m.raw)
            }
            for a in plan.archives { link(a.sourceModel, a.sourceID, target: "", nil, a.json) }
            // The snapshot is the acceptance oracle: it throws on a completed face without hifz provenance.
            let repository = try QuranRepository(context: context, catalog: catalog)
            try QuranMutationHandler.rebuildCache(repository, at: now, writer: writer)
            try context.save()
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
