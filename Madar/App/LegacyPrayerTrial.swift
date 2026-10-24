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
            let home = ActivePlace.riyadh
            let plan = try LegacyPrayerImport.plan(backup: Data(contentsOf: URL(fileURLWithPath: path)), home: home, uuid: StableIdentity.uuid(for:))
            counts = plan.counts
            let context = ModelContext(container), now = Date(), writer = "madar.app.trial"
            let logIDs = Set(try context.fetch(FetchDescriptor<PrayerLog>()).map(\.id)), qadaIDs = Set(try context.fetch(FetchDescriptor<QadaItem>()).map(\.id))
            let linkIDs = Set(try context.fetch(FetchDescriptor<ImportLink>()).map(\.id))
            for log in plan.logs where !logIDs.contains(log.id) {
                let row = PrayerLog(); row.id = log.id; row.dayKey = log.dayKey; row.prayer = log.prayer.rawValue; row.status = log.status.rawValue
                row.heart = log.heart?.rawValue; row.eventAt = log.eventAt; row.loggedAt = log.loggedAt; row.fridayKind = log.fridayKind?.rawValue
                row.tzID = home.timeZoneID; row.dayPolicy = "legacy@0"; row.source = "import"
                row.createdAt = log.loggedAt ?? log.eventAt; row.updatedAt = row.createdAt; row.writerID = writer; context.insert(row)
                counts["logs.created", default: 0] += 1
            }
            for item in plan.qada where !qadaIDs.contains(item.id) {
                let row = QadaItem(); row.id = item.id; row.prayer = item.prayer.rawValue; row.originalDayKey = item.dayKey; row.madeUpAt = item.madeUpAt
                row.createdAt = item.madeUpAt ?? now; row.updatedAt = row.createdAt; row.writerID = writer; context.insert(row)
                counts["qada.created", default: 0] += 1
            }
            for archive in plan.archives {
                let id = StableIdentity.uuid(for: "myDream:ImportLink:PrayerDay:\(archive.dayKey)")
                guard !linkIDs.contains(id) else { continue }
                let link = ImportLink(); link.id = id; link.source = "myDream"; link.sourceModel = "PrayerLog"; link.sourceID = archive.dayKey
                link.targetModel = "PrayerLog"; link.unmappedJSON = archive.json
                link.createdAt = now; link.updatedAt = now; link.importedAt = now; link.writerID = writer; context.insert(link)
            }
            if let start = plan.trackingStart {
                try SettingsStore(context: context, schema: schema).prepare(.object(["dayKey": .string(start.description), "edits": .number(0)]), for: "salah.trackingStart")
            }
            try context.save()
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
