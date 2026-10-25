import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarCommands

/// Also used by the old-Madar move (item 24) with its own writer id.
/// Stable source identities protect native edits/tombstones on replay.
@MainActor enum LegacyHabitTrial {
    static func importBackup(_ backup: Data, to container: ModelContainer, zone: TimeZone,
                             now: Date = .now, writer: String = "madar.app.legacyHabitTrial") throws -> [String: Int] {
        let observedDay = try DiaryLineRenderer.today(context: ModelContext(container), now: now)
        let plan = try LegacyHabitImport.plan(backup: backup, observedDay: observedDay, zone: zone,
                                              uuid: StableIdentity.uuid(for:))
        return try apply(plan, to: container, zone: zone, now: now, writer: writer)
    }
    static func apply(_ plan: LegacyHabitImport.Plan, to container: ModelContainer, zone: TimeZone,
                      now: Date = .now, writer: String = "madar.app.legacyHabitTrial") throws -> [String: Int] {
        let context = ModelContext(container); context.autosaveEnabled = false
        var counts = plan.counts
        let habits = try context.fetch(FetchDescriptor<Habit>()), habitIDs = Set(habits.map(\.id))
        // A habit the owner already keeps under the same name takes the old history; it is never duplicated.
        func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let planIDs = Set(plan.habits.map(\.id))
        // Only a plain daily habit takes old daily times; a linked or weekly/monthly/yearly one keeps its own rules.
        let dailyPolicies = Set(try context.fetch(FetchDescriptor<HabitPolicy>()).filter { $0.deletedAt == nil }
            .sorted { $0.effectiveFrom < $1.effectiveFrom }.reduce(into: [UUID: String]()) { $0[$1.habitID ?? UUID()] = $1.frequency }
            .filter { $0.value == "daily" }.keys)
        let nativeByName = Dictionary(habits.filter { $0.deletedAt == nil && !planIDs.contains($0.id) && $0.kind == "custom" && dailyPolicies.contains($0.id) }.map { (key($0.name), $0.id) }, uniquingKeysWith: { a, _ in a })
        let mapped = Dictionary(plan.habits.filter { !habitIDs.contains($0.id) && $0.deletedAt == nil }.compactMap { h in nativeByName[key(h.name)].map { (h.id, $0) } }, uniquingKeysWith: { a, _ in a })
        let policyIDs = Set(try context.fetch(FetchDescriptor<HabitPolicy>()).map(\.id))
        let events = try context.fetch(FetchDescriptor<HabitEvent>()), eventIDs = Set(events.map(\.id))
        let nativeDays = Set(events.filter { $0.deletedAt == nil }.map { ($0.habitID?.uuidString ?? "") + "|" + $0.dayKey })
        let pauseIDs = Set(try context.fetch(FetchDescriptor<HabitPause>()).map(\.id))
        let linkIDs = Set(try context.fetch(FetchDescriptor<ImportLink>()).map(\.id))
        for source in plan.habits {
            if mapped[source.id] != nil { counts["habits.keptNative", default: 0] += 1; continue }
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
            let habitID = mapped[source.habitID] ?? source.habitID
            guard mapped[source.habitID] == nil || !nativeDays.contains(habitID.uuidString + "|" + source.day.description) else {
                counts["events.keptNative", default: 0] += 1; continue
            }
            let row = HabitEvent(); row.id = source.id; row.habitID = habitID
            row.dayKey = source.day.description; row.periodKey = source.day.description; row.delta = 1
            // The old file stores a day, no clock. Noon is only an anchor for that
            // stored legacy day; it is never used to recalculate the day key.
            row.eventAt = source.day.date(in: zone).addingTimeInterval(12 * 3600)
            row.tzID = zone.identifier; row.dayPolicy = "legacy@0"
            row.createdAt = row.eventAt; row.updatedAt = max(row.eventAt, source.deletedAt ?? .distantPast)
            row.deletedAt = source.deletedAt; row.deletionBarrierAt = source.deletedAt; row.writerID = writer
            context.insert(row); counts["events.created", default: 0] += 1
        }
        for source in plan.pauses where !pauseIDs.contains(source.id) && mapped[source.habitID] == nil {
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

#if DEBUG
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
