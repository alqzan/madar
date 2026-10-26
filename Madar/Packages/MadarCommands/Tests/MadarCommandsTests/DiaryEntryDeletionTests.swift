import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

@MainActor struct DiaryEntryDeletionTests {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func fixture() throws -> (ModelContainer, DurableCommandAdapter, CommandBus, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryEntryDeletion-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let adapter = DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 })
        return (container, adapter, CommandBus(adapter: adapter), root)
    }
    private func run(_ bus: CommandBus, _ name: String, _ payload: [String: MadarCore.JSONValue], at now: Date, id: UUID = UUID()) async throws -> CommandOutcome {
        try await bus.execute(.init(commandID: id, name: name, payload: .object(payload), issuedAt: now), now: now)
    }

    @Test func deletesRevisionFamilyKeepsMarginAndUndoRestoresRowsAndMedia() async throws {
        let (container, _, bus, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let written = date("2026-10-15T22:00:00+03:00"), rootID = UUID(), firstRevisionID = UUID(), headID = UUID()
        let mediaID = UUID(), media = Media(); media.id = mediaID; media.kind = "photo"; media.contentType = "image/jpeg"
        media.data = Data("private-photo-bytes".utf8); media.sizeBytes = media.data?.count ?? 0
        let seedContext = ModelContext(container); seedContext.insert(media); try seedContext.save()
        #expect(try await run(bus, "diary.appendLine", ["text": .string("أصل السطر"), "day": .string("today")], at: written, id: rootID).status == .applied)
        let seed = ModelContext(container), original = try #require(seed.fetch(FetchDescriptor<Entry>()).first { $0.id == rootID })
        original.attachmentMediaIDs = [mediaID]; try seed.save()
        let firstEditAt = date("2026-10-17T12:00:00+03:00")
        #expect(try await run(bus, "diary.editEntry", ["entryID": .string(rootID.uuidString), "revisionID": .string(firstRevisionID.uuidString), "text": .string("التعديل الأول")], at: firstEditAt).status == .applied)
        let secondEditAt = date("2026-10-18T12:00:00+03:00")
        #expect(try await run(bus, "diary.editEntry", ["entryID": .string(firstRevisionID.uuidString), "revisionID": .string(headID.uuidString), "text": .string("آخر تعديل")], at: secondEditAt).status == .applied)

        let context = ModelContext(container), margin = MarginNote(); margin.targetDayKey = "2026-10-15"; margin.targetEntryID = rootID
        margin.text = "هامش يبقى بعد حذف الأصل"; margin.writtenDayKey = "2026-10-18"; margin.writtenAt = secondEditAt
        context.insert(margin); try context.save()
        let deleteID = UUID(), deletedAt = secondEditAt.addingTimeInterval(60)
        let outcome = try await run(bus, "diary.deleteEntry", ["entryID": .string(headID.uuidString)], at: deletedAt, id: deleteID)
        #expect(outcome.status == .applied); #expect(outcome.undoToken == deleteID)
        var rows = try ModelContext(container).fetch(FetchDescriptor<Entry>())
        #expect(rows.count == 3); #expect(rows.allSatisfy { $0.deletedAt != nil })
        #expect(try ModelContext(container).fetch(FetchDescriptor<MarginNote>()).first?.targetEntryID == rootID)
        let receiptContext = ModelContext(container)
        let storedMedia = try #require(receiptContext.fetch(FetchDescriptor<Media>()).first { $0.id == mediaID })
        #expect(storedMedia.deletedAt == nil); #expect(storedMedia.data == Data("private-photo-bytes".utf8))
        let receipt = try #require(receiptContext.fetch(FetchDescriptor<CommandReceipt>()).first { $0.commandID == deleteID })
        let receiptText = String(decoding: try #require(receipt.undoJSON), as: UTF8.self)
        #expect(!receiptText.contains(Data("private-photo-bytes".utf8).base64EncodedString()))

        #expect(try await run(bus, "system.undo", ["undoToken": .string(deleteID.uuidString)], at: deletedAt.addingTimeInterval(2)).status == .applied)
        rows = try ModelContext(container).fetch(FetchDescriptor<Entry>())
        #expect(rows.count == 3); #expect(rows.allSatisfy { $0.deletedAt == nil })
        #expect(rows.first { $0.id == headID }?.text == "آخر تعديل")
        #expect(try ModelContext(container).fetch(FetchDescriptor<MarginNote>()).first?.targetEntryID == rootID)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Media>()).first { $0.id == mediaID }?.data == Data("private-photo-bytes".utf8))
    }

    @Test func expiredDeletionPurgesOnlyUnreferencedMediaWithoutKeepingTextReceipt() async throws {
        let (container, adapter, bus, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let now = date("2026-10-15T15:00:00+03:00"), entryID = UUID(), deleteID = UUID()
        let exclusiveID = UUID(), sharedID = UUID()
        let context = ModelContext(container)
        for id in [exclusiveID, sharedID] {
            let media = Media(); media.id = id; media.kind = "photo"; media.contentType = "image/jpeg"
            media.data = Data("media-\(id.uuidString)".utf8); media.sizeBytes = media.data?.count ?? 0; context.insert(media)
        }
        let entry = Entry(); entry.id = entryID; entry.dayKey = "2026-10-15"; entry.eventAt = now; entry.text = "سطر بمرفقين"
        entry.attachmentMediaIDs = [exclusiveID, sharedID]; entry.source = "native"; context.insert(entry)
        let other = Entry(); other.dayKey = "2026-10-15"; other.eventAt = now.addingTimeInterval(1); other.text = "مرفق مشترك"
        other.attachmentMediaIDs = [sharedID]; other.source = "native"; context.insert(other); try context.save()

        #expect(try await run(bus, "diary.deleteEntry", ["entryID": .string(entryID.uuidString)], at: now, id: deleteID).status == .applied)
        try adapter.purgeExpiredReceipts(pinnedIDs: [], now: now.addingTimeInterval(601))
        let fresh = ModelContext(container)
        let media = try fresh.fetch(FetchDescriptor<Media>())
        let exclusive = try #require(media.first { $0.id == exclusiveID }), shared = try #require(media.first { $0.id == sharedID })
        #expect(exclusive.deletedAt != nil); #expect(exclusive.data == nil)
        #expect(shared.deletedAt == nil); #expect(shared.data == Data("media-\(sharedID.uuidString)".utf8))
        #expect(try fresh.fetch(FetchDescriptor<Entry>()).first { $0.id == entryID }?.deletedAt != nil)
        #expect(try fresh.fetch(FetchDescriptor<CommandReceipt>()).first { $0.commandID == deleteID }?.undoJSON == nil)
    }
}
