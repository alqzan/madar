import Foundation
import SwiftData
import CryptoKit
import MadarCore
import MadarData
import MadarPrayer

/// What an import would do, computed before any row is written (N01 «المعاينة قبل الحفظ»).
public struct DayOnePreview: Equatable, Sendable {
    public var actions: [String: DayOneMerge.Action] = [:]
    public var add = 0, update = 0, keepBoth = 0, same = 0, keepMine = 0, tagBackfill = 0
    public var days: [GregorianDay] = []
    /// Distinct files for the entries that will be written, by Media.kind.
    public var mediaFound: [String: Int] = [:]
    public var mediaMissing: [String: Int] = [:]
    /// Files present in the export but above `ZIPReader.memberLimit`: reported, never truncated.
    public var mediaTooLarge: [String: Int] = [:]
    public var mediaBytes = 0
    /// Entries the owner deleted in Madar after an earlier import: they stay deleted (§11).
    public var deletedHere = 0
    /// RD8: each entry's first tag becomes (or joins) a diary project; every tag stays in the archived JSON.
    public var projects: [String] = []
    public var tags: [String] = []
    public var skipped: [DayOneSkip] = []
    public var writes: Int { add + update + keepBoth + tagBackfill }
    public var changed: Int { update + keepBoth + keepMine }
    public var duplicates: Int { same + skipped.filter { $0.reason == .duplicateInFile || $0.reason == .madarExport }.count }
}

/// Stored in ImportBatch.summaryJSON: the counts the result screen shows, and what one undo needs.
public struct DayOneBatchSummary: Codable, Equatable, Sendable {
    public struct Missing: Codable, Equatable, Sendable { public let kind: String; public let key: String; public let entry: String }
    public struct TagBackfill: Codable, Equatable, Sendable {
        public let entryID: UUID
        public let previousTags: [String]?
        public let appliedTags: [String]
        public let editedInMadar: Bool
        public init(entryID: UUID, previousTags: [String]?, appliedTags: [String], editedInMadar: Bool) {
            self.entryID = entryID; self.previousTags = previousTags; self.appliedTags = appliedTags; self.editedInMadar = editedInMadar
        }
    }
    public var added = 0, updated = 0, keptBoth = 0, unchanged = 0, keptMine = 0, days = 0, deletedHere = 0
    public var mediaFound: [String: Int] = [:]
    public var missing: [Missing] = []
    public var tooLarge: [Missing] = []
    public var skipped: [DayOneSkip] = []
    public var projects: [String] = []
    /// Optional so undo receipts written before the tag field can still be decoded.
    public var restoredTags: Int? = nil
    /// Optional so existing import receipts remain decodable. A backfill changes tags only, and stores the edit
    /// status that was in effect before its updatedAt/import batch metadata was advanced.
    public var tagBackfills: [TagBackfill]? = nil
    public var firstDay: String?
    public var lastDay: String?
    var created: [String: [UUID]] = [:]
    var before: [DataRecord] = []
    var pageOrigins: [String: String] = [:]
    public var undoneAt: Date?
}

public struct DayOneReceipt: Equatable, Sendable {
    public let batchID: UUID
    public let status: String
    public let summary: DayOneBatchSummary
}

@MainActor public enum DayOneImportHandler {
    struct Context {
        let boundary: DayBoundary
        let home: ActivePlace
        let options: PrayerCalculationOptions
        func key(_ entry: DayOneEntryPlan) -> DayOneDayKey.Resolved {
            DayOneDayKey.resolve(entry, boundary: boundary, home: home) { PrayerTimesEngine.calculate(day: $1, place: $0, options: options) }
        }
    }
    static func environment(_ context: ModelContext) throws -> Context {
        let settings = try SettingsStore(context: context), prayer = try PrayerRepository(context: context)
        return .init(boundary: DayBoundary(rawValue: try settings.value(for: "core.dayStart").string ?? "") ?? .fajr, home: prayer.home, options: prayer.options)
    }
    static func live<T: MadarRecordModel>(_ rows: [T], deleted: KeyPath<T, Date?>, merged: KeyPath<T, UUID?>) -> [T] { rows.filter { $0[keyPath: deleted] == nil && $0[keyPath: merged] == nil } }

    /// Rows that an undone Day One import tombstoned, with the moment of that undo. Only these may be revived by a
    /// re-import; a row the owner deleted in Madar stays deleted (§11 tombstones).
    static func undoneRows(_ context: ModelContext) throws -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        for batch in try context.fetch(FetchDescriptor<ImportBatch>()) where batch.kind == "dayOne" && batch.status == "cancelled" {
            guard let summary = try? JSONDecoder().decode(DayOneBatchSummary.self, from: batch.summaryJSON), let at = summary.undoneAt else { continue }
            for id in summary.created.values.joined() where (result[id] ?? .distantPast) < at { result[id] = at }
        }
        return result
    }
    /// The tombstone is the one that undo wrote (a later delete by the owner moves `deletedAt` past it).
    static func revivable(_ deletedAt: Date?, _ undoneAt: Date?) -> Bool {
        guard let deletedAt, let undoneAt else { return false }
        return abs(deletedAt.timeIntervalSince(undoneAt)) < 0.001
    }

    /// Primary (unbranched) Day One rows by sourceID, with whether the owner changed them in Madar after their last import.
    static func existingEntries(_ context: ModelContext) throws -> [String: (row: Entry, state: DayOneMerge.Existing)] {
        let entries = try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.source == "dayOne" && $0.deletedAt == nil && $0.mergedInto == nil }))
        let revised = Set(try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.source == "revision" && $0.deletedAt == nil })).compactMap(\.sourceID))
        let importedBatches = try context.fetch(FetchDescriptor<ImportBatch>())
        let batches = Dictionary(uniqueKeysWithValues: importedBatches.map { ($0.id, $0) })
        let summaries = Dictionary(uniqueKeysWithValues: importedBatches.compactMap { batch in
            (try? JSONDecoder().decode(DayOneBatchSummary.self, from: batch.summaryJSON)).map { (batch.id, $0) }
        })
        var result: [String: (Entry, DayOneMerge.Existing)] = [:]
        for row in entries where row.sourceBranch.isEmpty {
            guard let id = row.sourceID else { continue }
            let batchID = row.importBatchID
            let importedAt = batchID.flatMap { summaries[$0]?.undoneAt } ?? batchID.flatMap { batches[$0]?.finishedAt } ?? row.createdAt
            let backfillEditState = batchID.flatMap { summaries[$0]?.tagBackfills?.first(where: { $0.entryID == row.id })?.editedInMadar }
            let edited = revised.contains(row.id.uuidString) || backfillEditState == true || row.updatedAt > importedAt.addingTimeInterval(1)
            result[id] = (row, .init(hash: row.sourceHash, editedInMadar: edited, tags: row.tags))
        }
        return result
    }

    public static func preview(_ plan: DayOnePlan, choice: DayOneMerge.Choice = .automatic, context: ModelContext) throws -> DayOnePreview {
        let env = try environment(context), existing = try existingEntries(context)
        // A keep-both branch is keyed by the incoming hash, so the same export never adds it twice.
        let branches = Set(try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.source == "dayOne" && $0.deletedAt == nil && $0.mergedInto == nil }))
            .filter { !$0.sourceBranch.isEmpty }.compactMap { row in row.sourceID.map { $0 + ":" + row.sourceBranch } })
        let undone = try undoneRows(context)
        let tombstoned = Dictionary(try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.source == "dayOne" && $0.deletedAt != nil })).map { ($0.id, $0.deletedAt) },
                                    uniquingKeysWith: { first, _ in first })
        var preview = DayOnePreview(); preview.skipped = plan.skipped
        var days = Set<GregorianDay>(), media: [String: DayOneMediaRef] = [:], tags: [String] = [], firsts: [String] = []
        for entry in plan.entries {
            var action = DayOneMerge.action(hash: entry.hash, existing: existing[entry.sourceID]?.state, choice: choice, incomingTags: entry.tags)
            if action == .keepBoth, branches.contains(entry.sourceID + ":" + entry.hash) { action = .same }
            if action == .add || action == .keepBoth {
                let id = StableIdentity.uuid(for: "DayOneEntry:" + entry.sourceID + (action == .keepBoth ? ":" + entry.hash : ""))
                if let deletedAt = tombstoned[id], !revivable(deletedAt, undone[id]) {
                    preview.actions[entry.sourceID] = .same; preview.deletedHere += 1; continue // written nowhere, counted on its own
                }
            }
            preview.actions[entry.sourceID] = action
            switch action {
            case .add: preview.add += 1
            case .update: preview.update += 1
            case .keepBoth: preview.keepBoth += 1
            case .backfillTags: preview.tagBackfill += 1
            case .same: preview.same += 1
            case .keepMine: preview.keepMine += 1
            }
            guard [.add, .update, .keepBoth, .backfillTags].contains(action) else { continue }
            let day = [.update, .backfillTags].contains(action)
                ? ((try? GregorianDay(existing[entry.sourceID]?.row.dayKey ?? "")) ?? env.key(entry).day)
                : env.key(entry).day
            days.insert(day)
            if action != .backfillTags { for ref in entry.media { media[ref.key] = ref } }
            for tag in entry.tags where !tags.contains(tag) { tags.append(tag) }
            if action != .backfillTags, let first = entry.tags.first, !firsts.contains(first) { firsts.append(first) }
        }
        preview.days = days.sorted()
        for ref in media.values {
            if !ref.found { preview.mediaMissing[ref.kind, default: 0] += 1 }
            else if ref.size > ZIPReader.memberLimit { preview.mediaTooLarge[ref.kind, default: 0] += 1 }
            else { preview.mediaFound[ref.kind, default: 0] += 1; preview.mediaBytes += ref.size }
        }
        preview.tags = tags; preview.projects = firsts
        return preview
    }

    /// Writes one ImportBatch. Entries, media, pages and projects are tied to it so `undo` can reverse it in one step.
    /// Media bytes are inflated off the main actor; the context is saved every ~64 MB so a large export does not
    /// hold every file in memory. A re-run after a failure resumes by natural keys (same hash → skipped).
    public static func commit(_ plan: DayOnePlan, archive: ZIPReader, fileName: String, fileHash: String, choice: DayOneMerge.Choice = .automatic,
                              context: ModelContext, now: Date, writer: String, progress: (@MainActor (Int, Int) -> Void)? = nil) async throws -> DayOneReceipt {
        let env = try environment(context), existing = try existingEntries(context)
        let preview = try preview(plan, choice: choice, context: context)
        let batch = ImportBatch(); batch.kind = "dayOne"; batch.fileName = fileName; batch.fileHash = fileHash
        batch.startedAt = now; batch.status = "running"; batch.createdAt = now; batch.updatedAt = now; batch.writerID = writer
        context.insert(batch); try context.save()
        var summary = DayOneBatchSummary(); summary.skipped = plan.skipped; summary.unchanged = preview.same; summary.keptMine = preview.keepMine; summary.deletedHere = preview.deletedHere
        func created(_ model: String, _ id: UUID) { summary.created[model, default: []].append(id) }
        // Only rows an undone import tombstoned come back; a row the owner deleted stays deleted (§11).
        let undone = try undoneRows(context)
        do {
            // Media: one row per file (natural key = md5), reused across entries and re-imports.
            let writing = plan.entries.filter { [.add, .update, .keepBoth, .backfillTags].contains(preview.actions[$0.sourceID]) }
            let contentWriting = writing.filter { preview.actions[$0.sourceID] != .backfillTags }
            var mediaIDs: [String: UUID] = [:], owner: [String: String] = [:], pending = 0, done = 0
            for entry in contentWriting { for ref in entry.media where owner[ref.key] == nil { owner[ref.key] = entry.sourceID } }
            let refs: [DayOneMediaRef] = { var seen = Set<String>(); return contentWriting.flatMap(\.media).filter { seen.insert($0.key).inserted } }()
            let allMedia = try context.fetch(FetchDescriptor<Media>())
            let mediaByID = Dictionary(allMedia.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let liveMedia = Dictionary(allMedia.filter { $0.deletedAt == nil && $0.mergedInto == nil }.compactMap { row in row.sourceID.map { ($0, row) } }, uniquingKeysWith: { first, _ in first })
            for ref in refs {
                let key = ref.key, id = StableIdentity.uuid(for: "DayOneMedia:" + key)
                let tooLarge = ref.found && ref.size > ZIPReader.memberLimit
                let note = DayOneBatchSummary.Missing(kind: ref.kind, key: key, entry: owner[key] ?? "")
                if let current = liveMedia[key], current.state == "ok" || !ref.found || tooLarge {
                    mediaIDs[key] = current.id
                    if current.state == "ok" { summary.mediaFound[ref.kind, default: 0] += 1 } else if tooLarge { summary.tooLarge.append(note) } else { summary.missing.append(note) }
                    continue
                }
                if let old = mediaByID[id], old.deletedAt != nil, !revivable(old.deletedAt, undone[id]) { continue } // deleted by the owner: not linked again
                var bytes: Data?
                if !tooLarge, let path = ref.path, let member = archive.member(path) { bytes = try? await Task.detached(priority: .userInitiated) { try archive.read(member) }.value }
                let row: Media
                if let current = liveMedia[key] { summary.before.append(try current.record()); row = current } // a missing file now found: no bytes in the record
                else if let old = mediaByID[id] { row = old; row.deletedAt = nil; row.restoredAt = now; created("Media", id) }
                else { row = Media(); row.id = id; row.createdAt = now; row.updatedAt = now; context.insert(row); created("Media", id) }
                row.kind = ref.kind; row.contentType = ref.contentType; row.sourceID = key; row.durationS = ref.durationS; row.importBatchID = batch.id
                row.data = bytes; row.sizeBytes = bytes?.count ?? 0; row.sha256 = bytes.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? ""
                row.state = bytes == nil ? "missing" : "ok"; row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt); row.writerID = writer
                if bytes != nil { summary.mediaFound[ref.kind, default: 0] += 1 } else if tooLarge { summary.tooLarge.append(note) } else { summary.missing.append(note) }
                mediaIDs[key] = row.id
                pending += bytes?.count ?? 0; done += 1; progress?(done, refs.count)
                if pending > 64 * 1024 * 1024 { try context.save(); pending = 0 }
            }
            // The original journal JSON is archived as it was: tags, mood, weather, starred and unknown fields are never lost.
            for journal in plan.journals {
                guard let member = archive.member(journal.path) else { continue }
                let bytes = try await Task.detached(priority: .userInitiated) { try archive.read(member) }.value
                let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), key = "dayOne.journal:" + sha
                guard liveMedia[key] == nil else { continue }
                let id = StableIdentity.uuid(for: "DayOneMedia:" + key), row: Media
                if let old = mediaByID[id] { guard revivable(old.deletedAt, undone[id]) else { continue }; row = old; row.deletedAt = nil; row.restoredAt = now; created("Media", id) }
                else { row = Media(); row.id = id; row.createdAt = now; row.updatedAt = now; context.insert(row); created("Media", id) }
                row.kind = "doc"; row.contentType = "application/json"; row.data = bytes; row.sizeBytes = bytes.count; row.sha256 = sha; row.sourceID = key
                row.state = "ok"; row.importBatchID = batch.id; row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt); row.writerID = writer
            }
            // RD8 tags: the first tag of an entry links it to a project of that name (an existing one, else a closed chapter).
            var projectIDs: [String: UUID] = [:]
            let projects = try context.fetch(FetchDescriptor<Project>())
            let liveProjects = live(projects, deleted: \.deletedAt, merged: \.mergedInto)
            var latestByTag: [String: Date] = [:]
            for entry in contentWriting { if let tag = entry.tags.first { latestByTag[tag] = max(latestByTag[tag] ?? entry.createdAt, entry.createdAt) } }
            for tag in preview.projects {
                if let match = liveProjects.first(where: { normalized($0.name) == normalized(tag) }) { projectIDs[tag] = match.id; continue }
                let id = StableIdentity.uuid(for: "DayOneTag:" + normalized(tag)), row: Project
                if let old = projects.first(where: { $0.id == id }) {
                    if old.deletedAt == nil && old.mergedInto == nil { projectIDs[tag] = old.id; continue } // renamed by the owner
                    guard revivable(old.deletedAt, undone[id]) else { continue } // the owner deleted this project: entries stay unlinked
                    row = old; row.deletedAt = nil; row.restoredAt = now; created("Project", id)
                } else { row = Project(); row.id = id; row.createdAt = now; row.updatedAt = now; context.insert(row); created("Project", id) }
                row.name = tag; row.intention = ""; row.finishedAt = latestByTag[tag]
                row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt); row.writerID = writer
                projectIDs[tag] = row.id
            }
            summary.projects = preview.projects
            // Entries.
            let allEntries = try context.fetch(FetchDescriptor<Entry>())
            let entriesByID = Dictionary(allEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var days = Set<String>(), latest = now
            for entry in writing {
                let action = preview.actions[entry.sourceID]!
                let resolved = env.key(entry)
                func fill(_ row: Entry) {
                    row.text = entry.text; row.textFormat = "markdown"; row.attachmentMediaIDs = entry.media.compactMap { mediaIDs[$0.key] }
                    row.tags = entry.tags
                    row.projectID = entry.tags.first.flatMap { projectIDs[$0] } ?? row.projectID
                    row.place = entry.place; row.lat = entry.latitude; row.lon = entry.longitude
                    row.source = "dayOne"; row.sourceID = entry.sourceID; row.sourceJournal = entry.journal; row.sourceTimeZone = entry.timeZoneID
                    row.sourceModifiedAt = entry.modifiedAt; row.sourceHash = entry.hash; row.importBatchID = batch.id
                    row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt); row.writerID = writer
                    latest = max(latest, row.updatedAt)
                }
                switch action {
                case .update:
                    guard let row = existing[entry.sourceID]?.row else { continue }
                    summary.before.append(try row.record()); fill(row); summary.updated += 1; days.insert(row.dayKey)
                case .backfillTags:
                    guard let row = existing[entry.sourceID]?.row else { continue }
                    summary.tagBackfills = (summary.tagBackfills ?? []) + [
                        .init(entryID: row.id, previousTags: row.tags, appliedTags: entry.tags,
                              editedInMadar: existing[entry.sourceID]?.state.editedInMadar ?? false)
                    ]
                    row.tags = entry.tags; row.importBatchID = batch.id
                    row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt); row.writerID = writer
                    latest = max(latest, row.updatedAt); summary.restoredTags = (summary.restoredTags ?? 0) + 1
                case .add, .keepBoth:
                    let branch = action == .keepBoth ? entry.hash : ""
                    let id = StableIdentity.uuid(for: "DayOneEntry:" + entry.sourceID + (branch.isEmpty ? "" : ":" + branch))
                    let row: Entry
                    if let old = entriesByID[id] {
                        if old.deletedAt == nil && old.mergedInto == nil { summary.unchanged += 1; continue }
                        guard revivable(old.deletedAt, undone[id]) else { continue } // deleted by the owner (counted in the preview)
                        row = old; row.deletedAt = nil; row.restoredAt = now; created("Entry", id)
                    } else { row = Entry(); row.id = id; row.createdAt = now; row.updatedAt = now; context.insert(row); created("Entry", id) }
                    // The stored day is computed once at import and never recomputed.
                    row.dayKey = resolved.day.description; row.eventAt = entry.createdAt; row.tzID = resolved.timeZoneID; row.dayPolicy = resolved.policy
                    row.ink = "normal"; row.sourceBranch = branch; fill(row)
                    if action == .add { summary.added += 1 } else { summary.keptBoth += 1 }
                    days.insert(row.dayKey)
                default: continue
                }
            }
            // Day pages: origin = dayOne while the page has none of the owner's own content (N01): no native line,
            // intention, margin note, page photo or answer.
            let pages = try context.fetch(FetchDescriptor<DayPage>())
            var native = Set(live(allEntries, deleted: \.deletedAt, merged: \.mergedInto).filter { $0.source != "dayOne" }.map(\.dayKey))
            native.formUnion(live(try context.fetch(FetchDescriptor<Niyya>()), deleted: \.deletedAt, merged: \.mergedInto).map(\.dayKey))
            for margin in live(try context.fetch(FetchDescriptor<MarginNote>()), deleted: \.deletedAt, merged: \.mergedInto) { native.insert(margin.targetDayKey); native.insert(margin.writtenDayKey) }
            let pagesByDay = Dictionary(grouping: pages.filter { $0.mergedInto == nil }, by: \.dayKey)
            for key in days.sorted() {
                let keyed = pagesByDay[key] ?? []
                if keyed.contains(where: { $0.deletedAt != nil }) && !keyed.contains(where: { $0.deletedAt == nil }) { continue } // a deleted day stays deleted
                if let page = keyed.filter({ $0.deletedAt == nil }).max(by: { $0.updatedAt < $1.updatedAt }) {
                    if page.origin != "dayOne", !native.contains(key), page.questionAnswer == nil, page.photoMediaID == nil {
                        summary.pageOrigins[page.id.uuidString] = page.origin; page.origin = "dayOne"
                        page.updatedAt = StableIdentity.monotonic(now: now, previous: page.updatedAt); page.writerID = writer
                    }
                } else {
                    let page = DayPage(); page.dayKey = key; page.origin = native.contains(key) ? "native" : "dayOne"; page.createdAt = now; page.updatedAt = now; page.writerID = writer
                    context.insert(page); created("DayPage", page.id)
                }
            }
            let keys = days.sorted(); summary.days = keys.count; summary.firstDay = keys.first; summary.lastDay = keys.last
            batch.status = summary.missing.isEmpty && summary.tooLarge.isEmpty ? "done" : "partial"
            batch.finishedAt = latest; batch.summaryJSON = try JSONEncoder().encode(summary); batch.updatedAt = StableIdentity.monotonic(now: now, previous: batch.updatedAt)
            try context.save()
            // Dedupe pass after every import (natural keys).
            try RowMerger(context: context).run()
            try context.save()
            return .init(batchID: batch.id, status: batch.status, summary: summary)
        } catch {
            context.rollback()
            if let row = try? context.fetch(FetchDescriptor<ImportBatch>()).first(where: { $0.id == batch.id }) { row.status = "failed"; row.finishedAt = now; try? context.save() }
            throw error
        }
    }

    /// One undo for the whole batch: rows it created are tombstoned, rows it changed or revived get their previous
    /// record back, and pages it relabelled return to their origin. Pages it created stay (empty), relabelled native,
    /// so writing on those days is never blocked by a tombstoned page.
    public static func undo(batch id: UUID, context: ModelContext, now: Date, writer: String) throws {
        guard let batch = try context.fetch(FetchDescriptor<ImportBatch>()).first(where: { $0.id == id }), batch.kind == "dayOne" else { throw DataError.invalidValue("import batch") }
        var summary = try JSONDecoder().decode(DayOneBatchSummary.self, from: batch.summaryJSON)
        guard summary.undoneAt == nil else { return }
        func tombstone<T: MadarRecordModel>(_ type: T.Type, _ model: String, deleted: ReferenceWritableKeyPath<T, Date?>, updated: ReferenceWritableKeyPath<T, Date>) throws {
            let ids = Set(summary.created[model] ?? [])
            // A row the owner already deleted keeps its own tombstone, so a re-import never revives it.
            for row in try context.fetch(FetchDescriptor<T>()) where ids.contains(row.id) && row[keyPath: deleted] == nil {
                row[keyPath: deleted] = now; row[keyPath: updated] = StableIdentity.monotonic(now: now, previous: row[keyPath: updated])
            }
        }
        try tombstone(Entry.self, "Entry", deleted: \.deletedAt, updated: \.updatedAt)
        try tombstone(Media.self, "Media", deleted: \.deletedAt, updated: \.updatedAt)
        try tombstone(Project.self, "Project", deleted: \.deletedAt, updated: \.updatedAt)
        func restore<T: MadarRecordModel>(_ type: T.Type, _ model: String, updated: ReferenceWritableKeyPath<T, Date>) throws {
            let records = Dictionary(summary.before.filter { $0.model == model }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for row in try context.fetch(FetchDescriptor<T>()) { if let record = records[row.id] { try row.apply(record); row[keyPath: updated] = StableIdentity.monotonic(now: now, previous: row[keyPath: updated]) } }
        }
        try restore(Entry.self, "Entry", updated: \.updatedAt)
        try restore(Media.self, "Media", updated: \.updatedAt)
        try restore(Project.self, "Project", updated: \.updatedAt)
        if let tagBackfills = summary.tagBackfills, !tagBackfills.isEmpty {
            let entries = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Entry>()).map { ($0.id, $0) })
            for backfill in tagBackfills {
                // Restore only the field this action changed, and only if it still contains our imported value.
                // Later text edits and later tag edits both remain intact.
                guard let row = entries[backfill.entryID], row.tags == backfill.appliedTags else { continue }
                row.tags = backfill.previousTags
                row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt)
                row.writerID = writer
            }
        }
        let createdPages = Set(summary.created["DayPage"] ?? [])
        for page in try context.fetch(FetchDescriptor<DayPage>()) {
            if let origin = summary.pageOrigins[page.id.uuidString] { page.origin = origin } else if createdPages.contains(page.id) { page.origin = "native" } else { continue }
            page.updatedAt = StableIdentity.monotonic(now: now, previous: page.updatedAt); page.writerID = writer
        }
        summary.undoneAt = now
        batch.summaryJSON = try JSONEncoder().encode(summary); batch.status = "cancelled"; batch.updatedAt = StableIdentity.monotonic(now: now, previous: batch.updatedAt); batch.writerID = writer
        try context.save()
    }

    static func normalized(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}
