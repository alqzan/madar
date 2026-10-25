#if DEBUG
import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarCommands

/// Development-only adapter. The production app has no legacy-file entry point.
/// Stable source identities protect native edits/tombstones on replay.
@MainActor enum LegacyHabitTrial {
    static func importBackup(_ backup: Data, to container: ModelContainer, zone: TimeZone,
                             now: Date = .now) throws -> [String: Int] {
        let observedDay = try DiaryLineRenderer.today(context: ModelContext(container), now: now)
        let plan = try LegacyHabitImport.plan(backup: backup, observedDay: observedDay, zone: zone,
                                              uuid: StableIdentity.uuid(for:))
        return try apply(plan, to: container, zone: zone, now: now)
    }
    static func apply(_ plan: LegacyHabitImport.Plan, to container: ModelContainer, zone: TimeZone,
                      now: Date = .now) throws -> [String: Int] {
        let context = ModelContext(container); context.autosaveEnabled = false
        let writer = "madar.app.legacyHabitTrial"
        var counts = plan.counts
        let habitIDs = Set(try context.fetch(FetchDescriptor<Habit>()).map(\.id))
        let policyIDs = Set(try context.fetch(FetchDescriptor<HabitPolicy>()).map(\.id))
        let eventIDs = Set(try context.fetch(FetchDescriptor<HabitEvent>()).map(\.id))
        let pauseIDs = Set(try context.fetch(FetchDescriptor<HabitPause>()).map(\.id))
        let linkIDs = Set(try context.fetch(FetchDescriptor<ImportLink>()).map(\.id))
        for source in plan.habits {
            if !habitIDs.contains(source.id) {
                let row = Habit(); row.id = source.id; row.name = source.name; row.icon = source.icon; row.color = source.color
                row.kind = "custom"; row.linkedSource = nil; row.reminder = "dot"; row.order = source.order
                row.startDate = source.start.date(in: zone); row.createdAt = min(row.startDate, source.updatedAt)
                row.updatedAt = source.updatedAt; row.deletedAt = source.deletedAt
                row.deletionBarrierAt = source.deletionBarrierAt; row.restoredAt = source.restoredAt
                row.writerID = writer; context.insert(row); counts["habits.created", default: 0] += 1
            }
            let id = StableIdentity.uuid(for: "myDream:HabitPolicy:" + source.sourceID)
            if !policyIDs.contains(id) {
                let row = HabitPolicy(); row.id = id; row.habitID = source.id; row.effectiveFrom = source.start.description
                row.frequency = "daily"; row.measure = "once"; row.target = 1
                row.createdAt = source.start.date(in: zone); row.updatedAt = source.updatedAt; row.writerID = writer
                context.insert(row); counts["policies.created", default: 0] += 1
            }
        }
        for source in plan.events where !eventIDs.contains(source.id) {
            let row = HabitEvent(); row.id = source.id; row.habitID = source.habitID
            row.dayKey = source.day.description; row.periodKey = source.day.description; row.delta = 1
            // The old file stores a day, no clock. Noon is only an anchor for that
            // stored legacy day; it is never used to recalculate the day key.
            row.eventAt = source.day.date(in: zone).addingTimeInterval(12 * 3600)
            row.tzID = zone.identifier; row.dayPolicy = "legacy@0"
            row.createdAt = row.eventAt; row.updatedAt = max(row.eventAt, source.deletedAt ?? .distantPast)
            row.deletedAt = source.deletedAt; row.deletionBarrierAt = source.deletedAt; row.writerID = writer
            context.insert(row); counts["events.created", default: 0] += 1
        }
        for source in plan.pauses where !pauseIDs.contains(source.id) {
            let row = HabitPause(); row.id = source.id; row.habitID = source.habitID
            row.fromDayKey = source.observedFrom.description; row.reason = "freeze"
            row.createdAt = now; row.updatedAt = now; row.writerID = writer; context.insert(row)
            counts["pauses.created", default: 0] += 1
        }
        for source in plan.archives {
            let id = StableIdentity.uuid(for: "myDream:ImportLink:Habits:" + source.sourceID)
            guard !linkIDs.contains(id) else { continue }
            let row = ImportLink(); row.id = id; row.source = "myDream"; row.sourceModel = "Habits"
            row.sourceID = source.sourceID; row.unmappedJSON = source.json
            if source.sourceID.hasPrefix("habit:"), let target = plan.habits.first(where: { "habit:" + $0.sourceID == source.sourceID }) {
                row.targetModel = "Habit"; row.targetID = target.id
            }
            row.createdAt = now; row.updatedAt = now; row.importedAt = now; row.writerID = writer; context.insert(row)
            counts["links.created", default: 0] += 1
        }
        try RecordValidator.validate(RecordBridge.all(context))
        try context.save()
        return counts
    }
}

extension AppSession {
    func runLegacyHabitTrialIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        guard env["MADAR_UI_STORE_ID"] != nil, let path = env["MADAR_TRIAL_HABITS"], !path.isEmpty,
              managedStore?.root.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "UITestStores" else { return }
        var counts: [String: Int] = [:]
        do {
            let now = prayerNow(), backup = try Data(contentsOf: URL(fileURLWithPath: path))
            counts = try LegacyHabitTrial.importBackup(backup, to: container, zone: activePlace.timeZone, now: now)
            func records() throws -> [DataRecord] {
                try RecordBridge.all(ModelContext(container)).sorted { ($0.model, $0.id.uuidString) < ($1.model, $1.id.uuidString) }
            }
            let before = try records()
            let replay = try LegacyHabitTrial.importBackup(backup, to: container, zone: activePlace.timeZone, now: now)
            counts["replay.created"] = replay.filter { $0.key.hasSuffix(".created") }.values.reduce(0, +)
            counts["replay.unchanged"] = try records() == before ? 1 : 0
            let context = ModelContext(container)
            counts["store.habits"] = try context.fetchCount(FetchDescriptor<Habit>())
            counts["store.events"] = try context.fetchCount(FetchDescriptor<HabitEvent>())
            counts["store.pauses"] = try context.fetchCount(FetchDescriptor<HabitPause>())
            try reload(); try publishSnapshot()
        } catch { counts["failed"] = 1 }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stamp = env["MADAR_TRIAL_RUN"] ?? "run"
        try? encoder.encode(counts).write(to: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("habits-import-\(stamp).json"))
    }
}
#endif
