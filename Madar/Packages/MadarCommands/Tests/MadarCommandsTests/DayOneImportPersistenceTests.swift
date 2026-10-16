import Foundation
import Testing
import SwiftData
import CryptoKit
import MadarCore
import MadarData
@testable import MadarCommands

/// M3-V09 store behaviour (N01 acceptance + RD8) on the synthetic export from `scripts/make-dayone-fixture.py`.
/// Expected days, counts and links come from the fixture inputs and the spec rules.
@MainActor struct DayOneImportPersistenceTests {
    private static let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "MadarCore/Tests/MadarCoreTests/Fixtures/dayone-synthetic.zip")
    private func store() throws -> (ModelContainer, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "DayOneImport-\(UUID())")
        return (try MadarContainerFactory.makeLocal(at: root.appending(path: "Data")), root)
    }
    private let now = ISO8601DateFormatter().date(from: "2026-10-16T12:00:00+03:00")!
    private func iso(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func archive(editing edit: ((inout [[String: Any]]) -> Void)? = nil) throws -> ZIPReader {
        let original = try ZIPReader(url: Self.fixtureURL)
        guard let edit else { return original }
        var files: [String: Data] = [:]
        for member in original.members { files[member.path] = try original.read(member) }
        var root = try #require(try JSONSerialization.jsonObject(with: files["Journal.json"]!) as? [String: Any])
        var entries = try #require(root["entries"] as? [[String: Any]]); edit(&entries); root["entries"] = entries
        files["Journal.json"] = try JSONSerialization.data(withJSONObject: root)
        // Madar's own stored ZIP writer: also proves stored (method 0) members read back.
        return try ZIPReader(data: DiaryExportArchive.encode(files))
    }
    private func run(_ zip: ZIPReader, _ context: ModelContext, at: Date? = nil, choice: DayOneMerge.Choice = .automatic) async throws -> DayOneReceipt {
        try await DayOneImportHandler.commit(try DayOneParser.plan(zip), archive: zip, fileName: "Journal.zip", fileHash: "test", choice: choice, context: context, now: at ?? now, writer: "test")
    }
    private func live<T: PersistentModel>(_ type: T.Type, _ context: ModelContext, _ isLive: (T) -> Bool) throws -> [T] { try context.fetch(FetchDescriptor<T>()).filter(isLive) }
    private func entries(_ c: ModelContext) throws -> [Entry] { try live(Entry.self, c) { $0.deletedAt == nil && $0.mergedInto == nil } }
    private func media(_ c: ModelContext) throws -> [Media] { try live(Media.self, c) { $0.deletedAt == nil && $0.mergedInto == nil } }
    private func projects(_ c: ModelContext) throws -> [Project] { try live(Project.self, c) { $0.deletedAt == nil && $0.mergedInto == nil } }
    private func pages(_ c: ModelContext) throws -> [DayPage] { try live(DayPage.self, c) { $0.deletedAt == nil && $0.mergedInto == nil } }

    @Test func previewWritesNothingAndCountsWhatWillHappen() throws {
        let (container, root) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let context = ModelContext(container), zip = try archive()
        let preview = try DayOneImportHandler.preview(try DayOneParser.plan(zip), context: context)
        #expect(preview.add == 5 && preview.writes == 5 && preview.same == 0)
        // fajr day start, home Riyadh: London 23:30 → 14 Jul; Riyadh 04:10 → 1 Mar; all-day → 11 Jan; Tokyo → 2 May; London 09:00 → 15 Jul.
        #expect(preview.days.map(\.description) == ["2025-01-11", "2025-03-01", "2025-05-02", "2025-07-14", "2025-07-15"])
        #expect(preview.mediaFound == ["photo": 1, "audio": 1, "doc": 1] && preview.mediaMissing == ["video": 1])
        #expect(preview.projects == ["سفر", "بيت"] && preview.tags == ["سفر", "عائلة", "بيت"])
        #expect(preview.skipped.map(\.reason) == [.empty, .noIdentity, .duplicateInFile] && preview.duplicates == 1)
        #expect(try context.fetch(FetchDescriptor<Entry>()).isEmpty && (try context.fetch(FetchDescriptor<ImportBatch>()).isEmpty))
    }

    @Test func importKeepsOriginalZoneTagsInlineMediaAndMarksMissing() async throws {
        let (container, root) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let context = ModelContext(container)
        let receipt = try await run(try archive(), context)
        #expect(receipt.status == "partial" && receipt.summary.added == 5 && receipt.summary.missing.map(\.kind) == ["video"])
        #expect(receipt.summary.firstDay == "2025-01-11" && receipt.summary.lastDay == "2025-07-15" && receipt.summary.days == 5)
        let rows = try entries(context), london = try #require(rows.first { $0.sourceID == "A1000000000000000000000000000001" })
        #expect(rows.count == 5 && rows.allSatisfy { $0.source == "dayOne" && $0.textFormat == "markdown" && $0.importBatchID == receipt.batchID })
        #expect(london.dayKey == "2025-07-14" && london.tzID == "Europe/London" && london.dayPolicy == "fajr@1" && london.eventAt == iso("2025-07-14T22:30:00Z"))
        #expect(london.text.hasPrefix("# مساء في لندن") && london.text.contains("dayone-moment://P1"))
        #expect(london.place == "Hyde Park" && london.lat == 51.5073 && london.sourceJournal == "Journal" && london.sourceTimeZone == "Europe/London")
        #expect(london.sourceModifiedAt == iso("2025-07-20T09:00:00Z") && london.sourceHash?.count == 64 && london.ink == "normal")
        let all = try media(context), byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        // Inline order resolved to real rows: the photo, then the rain recording.
        #expect(london.attachmentMediaIDs.compactMap { byID[$0]?.kind } == ["photo", "audio"])
        let photo = try #require(byID[london.attachmentMediaIDs[0]])
        #expect(photo.state == "ok" && photo.contentType == "image/jpeg" && photo.sourceID == "1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f" && photo.data?.prefix(2) == Data([0xFF, 0xD8]))
        #expect(photo.sha256 == SHA256.hash(data: photo.data!).map { String(format: "%02x", $0) }.joined() && photo.sizeBytes == photo.data!.count)
        // The second journal points at the same file: one Media row serves both entries.
        #expect(rows.first { $0.sourceID == "F6000000000000000000000000000006" }?.attachmentMediaIDs == [photo.id])
        let tokyo = try #require(rows.first { $0.sourceID == "D4000000000000000000000000000004" })
        #expect(tokyo.dayKey == "2025-05-02" && tokyo.tzID == "Asia/Tokyo" && tokyo.dayPolicy == "midnight@1")
        let night = try #require(rows.first { $0.sourceID == "B2000000000000000000000000000002" })
        #expect(night.dayKey == "2025-03-01" && night.attachmentMediaIDs.compactMap { byID[$0] }.map { "\($0.kind):\($0.state)" } == ["video:missing", "doc:ok"])
        #expect(night.attachmentMediaIDs.compactMap { byID[$0] }.first?.data == nil)
        // RD8: first tag → project chapter closed at its latest entry; every tag stays in the archived journal JSON.
        let chapters = try projects(context).sorted { $0.name < $1.name }
        #expect(chapters.map(\.name) == ["بيت", "سفر"] && chapters[1].finishedAt == iso("2025-07-15T08:00:00Z") && chapters.allSatisfy { $0.keyword == nil })
        #expect(london.projectID == chapters[1].id)
        let docs = all.filter { $0.kind == "doc" && $0.contentType == "application/json" }
        #expect(docs.count == 2 && docs.contains { String(data: $0.data!, encoding: .utf8)!.contains("\"عائلة\"") && String(data: $0.data!, encoding: .utf8)!.contains("futureField") })
        #expect(all.count == 6)
        #expect(try pages(context).map(\.origin) == Array(repeating: "dayOne", count: 5))
    }

    @Test func reimportingTheSameExportAddsNothing() async throws {
        let (container, root) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let context = ModelContext(container), zip = try archive()
        _ = try await run(zip, context)
        let again = try await run(zip, context, at: now.addingTimeInterval(60))
        #expect(again.summary.added == 0 && again.summary.unchanged == 5 && again.summary.updated == 0)
        #expect(try entries(context).count == 5 && (try media(context).count) == 6 && (try projects(context).count) == 2 && (try pages(context).count) == 5)
        #expect(try RowMerger(context: context).run() == 0)
    }

    @Test func changedInDayOneUpdatesUnlessEditedInMadarThenKeepsBoth() async throws {
        let (container, root) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let context = ModelContext(container)
        _ = try await run(try archive(), context)
        let v2 = try archive { $0[2]["text"] = "يوم كامل، بعد تعديل في داي ون." }
        #expect(try DayOneImportHandler.preview(try DayOneParser.plan(v2), context: context).update == 1)
        let updated = try await run(v2, context, at: now.addingTimeInterval(60))
        #expect(updated.summary.updated == 1 && updated.summary.added == 0)
        let row = try #require(try entries(context).first { $0.sourceID == "C3000000000000000000000000000003" })
        #expect(try row.text == "يوم كامل، بعد تعديل في داي ون." && row.dayKey == "2025-01-11" && (try entries(context).count) == 5)
        // The owner edits it in Madar; Day One changes it again → keep both, never overwrite.
        row.text = "نسختي"; row.updatedAt = now.addingTimeInterval(3600); try context.save()
        let v3 = try archive { $0[2]["text"] = "نسخة ثالثة من داي ون." }
        let both = try await run(v3, context, at: now.addingTimeInterval(7200))
        #expect(both.summary.keptBoth == 1)
        let copies = try entries(context).filter { $0.sourceID == "C3000000000000000000000000000003" }
        #expect(copies.count == 2 && Set(copies.map(\.text)) == ["نسختي", "نسخة ثالثة من داي ون."] && copies.contains { $0.sourceBranch.count == 64 })
        let repeatRun = try await run(v3, context, at: now.addingTimeInterval(7300))
        #expect(try repeatRun.summary.keptBoth == 0 && (try entries(context).count) == 6)
        #expect(try RowMerger(context: context).run() == 0)
    }

    @Test func undoThenNativeWritingThenReimportRestores() async throws {
        let (container, root) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let context = ModelContext(container), zip = try archive()
        let first = try await run(zip, context)
        try DayOneImportHandler.undo(batch: first.batchID, context: context, now: now.addingTimeInterval(10), writer: "test")
        #expect(try entries(context).isEmpty && (try projects(context).isEmpty) && (try media(context).isEmpty))
        #expect(try context.fetch(FetchDescriptor<ImportBatch>()).first?.status == "cancelled")
        // Pages are kept live (relabelled native) so writing on an imported day is never blocked by a tombstone.
        #expect(try pages(context).count == 5 && (try pages(context)).allSatisfy { $0.origin == "native" })
        _ = try DiaryMutationHandler.stage(text: "سطر كتبته بنفسي", day: "today", targetDay: nil, id: UUID(), context: context, now: now, writer: "test", storedDay: try GregorianDay("2025-07-14"))
        try context.save()
        let again = try await run(zip, context, at: now.addingTimeInterval(60))
        #expect(again.summary.added == 5)
        // Revived rows are recorded as created (undo tombstones them again); no row copy, so no media bytes, in the summary.
        #expect(again.summary.before.isEmpty && again.summary.created["Entry"]?.count == 5 && again.summary.created["Media"]?.count == 6)
        let rows = try entries(context)
        #expect(rows.filter { $0.source == "dayOne" }.count == 5 && rows.filter { $0.source == "dayOne" }.allSatisfy { $0.restoredAt != nil } && rows.count == 6)
        #expect(try media(context).count == 6 && (try projects(context).count) == 2)
        // A day with the owner's own line stays native; the others are Day One pages again.
        let origins = Dictionary(try pages(context).map { ($0.dayKey, $0.origin) }, uniquingKeysWith: { a, _ in a })
        #expect(origins["2025-07-14"] == "native" && origins["2025-03-01"] == "dayOne")
        _ = try RowMerger(context: context).run()
        #expect(try RowMerger(context: context).run() == 0)
    }

    @Test func entryOrProjectTheOwnerDeletedStaysDeletedOnReimport() async throws {
        // §11: a duplicate of a tombstoned key stays deleted unless explicitly restored; only undo's own tombstones revive.
        let (container, root) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let context = ModelContext(container), zip = try archive()
        let first = try await run(zip, context)
        let allDay = try #require(try entries(context).first { $0.sourceID == "C3000000000000000000000000000003" })
        allDay.deletedAt = now.addingTimeInterval(5); allDay.updatedAt = now.addingTimeInterval(5)
        let home = try #require(try projects(context).first { $0.name == "بيت" })
        home.deletedAt = now.addingTimeInterval(5); home.updatedAt = now.addingTimeInterval(5)
        try context.save()
        let preview = try DayOneImportHandler.preview(try DayOneParser.plan(zip), context: context)
        #expect(preview.deletedHere == 1 && preview.add == 0 && preview.same == 4 && preview.writes == 0)
        // Undo the first import, then import again: the four undone entries return, the deleted one does not.
        try DayOneImportHandler.undo(batch: first.batchID, context: context, now: now.addingTimeInterval(10), writer: "test")
        #expect(try context.fetch(FetchDescriptor<Entry>()).first { $0.id == allDay.id }?.deletedAt == now.addingTimeInterval(5))
        let again = try await run(zip, context, at: now.addingTimeInterval(60))
        #expect(again.summary.added == 4 && again.summary.deletedHere == 1)
        let rows = try entries(context)
        #expect(rows.count == 4 && !rows.contains { $0.sourceID == "C3000000000000000000000000000003" })
        // «بيت» was only on the deleted entry, so it is not in this import; «سفر» returns.
        #expect(try projects(context).map(\.name) == ["سفر"])
        // The revived rows undo again in one step.
        try DayOneImportHandler.undo(batch: again.batchID, context: context, now: now.addingTimeInterval(70), writer: "test")
        #expect(try entries(context).isEmpty && (try media(context).isEmpty) && (try projects(context).isEmpty))
    }

    @Test func aDayWithTheOwnersIntentionOrPhotoStaysNative() async throws {
        let (container, root) = try store(); defer { try? FileManager.default.removeItem(at: root) }
        let context = ModelContext(container)
        // 11 Jan: only an intention, no page row yet. 2 May: a native page with only a page photo. 1 Mar: a native page, empty.
        let niyya = Niyya(); niyya.dayKey = "2025-01-11"; niyya.text = "أن أكتب"; context.insert(niyya)
        let photoPage = DayPage(); photoPage.dayKey = "2025-05-02"; photoPage.origin = "native"; photoPage.photoMediaID = UUID(); context.insert(photoPage)
        let empty = DayPage(); empty.dayKey = "2025-03-01"; empty.origin = "native"; context.insert(empty)
        try context.save()
        let receipt = try await run(try archive(), context)
        let origins = Dictionary(try pages(context).map { ($0.dayKey, $0.origin) }, uniquingKeysWith: { a, _ in a })
        #expect(origins["2025-01-11"] == "native" && origins["2025-05-02"] == "native" && origins["2025-03-01"] == "dayOne" && origins["2025-07-14"] == "dayOne")
        try DayOneImportHandler.undo(batch: receipt.batchID, context: context, now: now.addingTimeInterval(10), writer: "test")
        #expect(try pages(context).first { $0.id == empty.id }?.origin == "native")
    }

    @Test func madarsOwnJSONExportIsRecognisedAndSkipped() throws {
        // V10 writes one entry per day with id = SHA-256("madar.diary.day.<day>") prefix and noon in the home zone.
        let id = SHA256.hash(data: Data("madar.diary.day.2026-10-14".utf8)).prefix(16).map { String(format: "%02X", $0) }.joined()
        let journal: [String: Any] = ["metadata": ["version": "1.0"], "entries": [["uuid": id, "creationDate": "2026-10-14T09:00:00Z", "timeZone": "Asia/Riyadh", "text": "# يوم\n\nسطر", "tags": []]]]
        let zip = try ZIPReader(data: DiaryExportArchive.encode(["Journal.json": try JSONSerialization.data(withJSONObject: journal)]))
        let plan = try DayOneParser.plan(zip)
        #expect(plan.entries.isEmpty && plan.skipped.map(\.reason) == [.madarExport])
    }
}
