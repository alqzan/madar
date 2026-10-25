#if DEBUG
import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarCommands

@MainActor enum LegacyPersonalTrial {
    static func importBackup(_ backup: Data, to container: ModelContainer, zone: TimeZone,
                             now: Date = .now) throws -> [String: Int] {
        let observedDay = try DiaryLineRenderer.today(context: ModelContext(container), now: now)
        let plan = try LegacyPersonalImport.plan(backup: backup, observedDay: observedDay, zone: zone,
                                                 uuid: StableIdentity.uuid(for:))
        return try apply(plan, to: container, zone: zone, observedDay: observedDay, now: now)
    }
    static func apply(_ plan: LegacyPersonalImport.Plan, to container: ModelContainer, zone: TimeZone,
                      observedDay: GregorianDay, now: Date = .now) throws -> [String: Int] {
        let context = ModelContext(container); context.autosaveEnabled = false
        let writer = "madar.app.legacyPersonalTrial"
        var counts = plan.counts
        let letterIDs = Set(try context.fetch(FetchDescriptor<Letter>()).map(\.id))
        let dayIDs = Set(try context.fetch(FetchDescriptor<UpcomingDay>()).map(\.id))
        let linkIDs = Set(try context.fetch(FetchDescriptor<ImportLink>()).map(\.id))
        func stamp<T: MadarRecordModel>(_ row: T, _ meta: LegacyPersonalImport.Provenance, created: Date) throws {
            var record = try row.record()
            try record.set(created, for: "createdAt"); try record.set(meta.updatedAt, for: "updatedAt")
            try record.set(meta.deletedAt, for: "deletedAt"); try record.set(meta.deletionBarrierAt, for: "deletionBarrierAt")
            try record.set(meta.restoredAt, for: "restoredAt"); try record.set(writer, for: "writerID"); try row.apply(record)
        }
        for source in plan.letters where !letterIDs.contains(source.id) {
            let row = Letter(); row.id = source.id; row.text = source.text
            row.triggerKind = "date"; row.triggerValue = source.deliveryDay.description
            row.openAt = source.deliveryDay.date(in: zone)
            row.state = source.opened ? "opened" : "sealed"
            row.openedAt = source.openedDay.map { $0.date(in: zone).addingTimeInterval(43200) }
            try stamp(row, source.provenance, created: source.writtenDay.date(in: zone).addingTimeInterval(43200))
            context.insert(row); counts["letters.created", default: 0] += 1
        }
        for source in plan.days where !dayIDs.contains(source.id) {
            let row = UpcomingDay(); row.id = source.id; row.title = source.title; row.calendar = "greg"
            row.year = source.day.year; row.month = source.day.month; row.day = source.day.day; row.repeats = "none"
            // Source has no ring-count baseline. Only the new display begins now;
            // the original event date and archived source stay unchanged.
            row.countFromDayKey = observedDay.description
            try stamp(row, source.provenance, created: source.provenance.updatedAt)
            context.insert(row); counts["days.created", default: 0] += 1
        }
        for source in plan.archives {
            let id = StableIdentity.uuid(for: "myDream:ImportLink:\(source.model):\(source.sourceID)")
            guard !linkIDs.contains(id) else { continue }
            let row = ImportLink(); row.id = id; row.source = "myDream"; row.sourceModel = source.model
            row.sourceID = source.sourceID; row.unmappedJSON = source.json
            if let target = plan.letters.first(where: { $0.sourceID == source.sourceID }), source.model == "FutureLetter" {
                row.targetModel = "Letter"; row.targetID = target.id
            } else if let target = plan.days.first(where: { $0.sourceID == source.sourceID }), source.model == "CountdownEvent" {
                row.targetModel = "UpcomingDay"; row.targetID = target.id
            }
            row.importedAt = now; row.createdAt = now; row.updatedAt = now; row.writerID = writer
            context.insert(row); counts["links.created", default: 0] += 1
        }
        try RecordValidator.validate(RecordBridge.all(context)); try context.save()
        return counts
    }
}

extension AppSession {
    func runLegacyPersonalTrialIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        guard env["MADAR_UI_STORE_ID"] != nil, let path = env["MADAR_TRIAL_PERSONAL"], !path.isEmpty,
              managedStore?.root.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "UITestStores" else { return }
        var counts: [String: Int] = [:]
        do {
            let now = prayerNow(), backup = try Data(contentsOf: URL(fileURLWithPath: path))
            counts = try LegacyPersonalTrial.importBackup(backup, to: container, zone: activePlace.timeZone, now: now)
            func records() throws -> [DataRecord] {
                try RecordBridge.all(ModelContext(container)).sorted { ($0.model, $0.id.uuidString) < ($1.model, $1.id.uuidString) }
            }
            let before = try records()
            let replay = try LegacyPersonalTrial.importBackup(backup, to: container, zone: activePlace.timeZone, now: now)
            counts["replay.created"] = replay.filter { $0.key.hasSuffix(".created") }.values.reduce(0,+)
            counts["replay.unchanged"] = try records() == before ? 1 : 0
            counts["store.letters"] = try ModelContext(container).fetchCount(FetchDescriptor<Letter>())
            counts["store.days"] = try ModelContext(container).fetchCount(FetchDescriptor<UpcomingDay>())
            try reload(); try publishSnapshot()
        } catch { counts["failed"] = 1 }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stamp = env["MADAR_TRIAL_RUN"] ?? "run"
        try? encoder.encode(counts).write(to: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("personal-import-\(stamp).json"))
    }
}
#endif
