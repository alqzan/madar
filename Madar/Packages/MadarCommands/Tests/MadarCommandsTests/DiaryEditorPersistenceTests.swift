import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

@MainActor struct DiaryEditorPersistenceTests {
    private func fixture() throws -> (ModelContainer, CommandBus, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryEditor-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        return (container, CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 })), root)
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    @Test func longDraftCommitsOnceOnItsChosenDayAfterBoundaryChangeAndUndoes() async throws {
        let (container, bus, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), now = date("2026-10-15T22:00:00+03:00"), later = date("2026-10-16T12:00:00+03:00"), text = String(repeating: "ذكرى ", count: 1000)
        let payload: [String:MadarCore.JSONValue] = ["id": .string(id.uuidString), "text": .string(text), "day": .string("today"), "writingDayKey": .string("2026-10-15")]
        _ = try await bus.execute(.init(name: "diary.saveDraft", payload: .object(payload), issuedAt: now), now: now)
        _ = try await bus.execute(.init(name: "settings.set", payload: .object(["settings": .object(["core.dayStart": .string("midnight")])]), issuedAt: later), now: later)
        _ = try await bus.execute(.init(name: "diary.saveDraft", payload: .object(payload), issuedAt: later), now: later)
        let command = CommandEnvelope(commandID: id, name: "diary.commitDraft", payload: .object(["id": .string(id.uuidString)]), issuedAt: later)
        let result = try await bus.execute(command, now: later); #expect(result.status == .applied)
        _ = try await bus.execute(command, now: later.addingTimeInterval(1))
        let context = ModelContext(container), rows = try context.fetch(FetchDescriptor<Entry>())
        #expect(rows.count == 1); #expect(rows[0].dayKey == "2026-10-15"); #expect(rows[0].text == text); #expect(rows[0].ink == "late")
        let draft = try #require(context.fetch(FetchDescriptor<SessionDraft>()).first)
        #expect(draft.dayKey == "2026-10-15"); #expect(draft.deletedAt != nil)
        _ = try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken": .string(id.uuidString)]), issuedAt: later), now: later.addingTimeInterval(2))
        #expect(try ModelContext(container).fetch(FetchDescriptor<Entry>()).first?.deletedAt != nil)
    }
    @Test func audioBytesSurviveTranscriptEditsAndTranscriptUndo() async throws {
        let (container, bus, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let now = date("2026-10-15T12:00:00+03:00"), id = UUID()
        let directory = root.appending(path: "DiaryStaging"); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bytes = Data("abc".utf8); try bytes.write(to: directory.appending(path: id.uuidString + ".m4a"))
        let result = try await bus.execute(.init(commandID: id, name: "diary.appendMedia", payload: .object(["fileID": .string(id.uuidString), "kind": .string("audio"), "contentType": .string("audio/mp4"), "caption": .string(""), "day": .string("today"), "writingDayKey": .string("2026-10-15")]), issuedAt: now), now: now)
        #expect(result.status == .applied)
        _ = try await bus.execute(.init(name: "diary.setTranscript", payload: .object(["entryID": .string(id.uuidString), "text": .string("النص الأول")]), issuedAt: now), now: now.addingTimeInterval(1))
        let second = try await bus.execute(.init(name: "diary.setTranscript", payload: .object(["entryID": .string(id.uuidString), "text": .string("النص المصحّح")]), issuedAt: now), now: now.addingTimeInterval(2))
        let context = ModelContext(container), audio = try #require(context.fetch(FetchDescriptor<Media>()).first)
        #expect(audio.data == bytes); #expect(audio.sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let token = try #require(second.undoToken)
        _ = try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken": .string(token.uuidString)]), issuedAt: now), now: now.addingTimeInterval(3))
        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<Entry>()).first?.text == "النص الأول")
        #expect(try fresh.fetch(FetchDescriptor<Media>()).first?.data == bytes)
    }
    @Test func missingMediaRollsBackAndExtensionCannotWriteDrafts() async throws {
        let (container, bus, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let now = date("2026-10-15T12:00:00+03:00"), id = UUID()
        let payload: [String:MadarCore.JSONValue] = ["fileID": .string(id.uuidString), "kind": .string("photo"), "contentType": .string("image/jpeg"), "caption": .string(""), "day": .string("today"), "writingDayKey": .string("2026-10-15")]
        do { _ = try await bus.execute(.init(name: "diary.appendMedia", payload: .object(payload), issuedAt: now), now: now); Issue.record("A missing source must not create an entry") } catch {}
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 0); #expect(try context.fetchCount(FetchDescriptor<Media>()) == 0)
        let denied = try await bus.execute(.init(name: "diary.saveDraft", payload: .object([:]), source: .widget, issuedAt: now), now: now)
        #expect(denied.status == .needsApp)
    }
    /// Owner, 24 Oct 2026: a library-linked photo keeps the small copy as its data and the asset as its natural key.
    @Test func linkedPhotoStoresTheAssetAsSourceID() async throws {
        let (container, bus, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let now = date("2026-10-24T12:00:00+03:00"), id = UUID()
        let directory = root.appending(path: "DiaryStaging"); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bytes = Data("abc".utf8); try bytes.write(to: directory.appending(path: id.uuidString + ".blob"))
        let result = try await bus.execute(.init(commandID: id, name: "diary.appendMedia", payload: .object(["fileID": .string(id.uuidString), "kind": .string("photo"), "contentType": .string("image/jpeg"), "caption": .string(""), "day": .string("today"), "writingDayKey": .string("2026-10-24"), "assetID": .string("ABC-123/L0/001")]), issuedAt: now), now: now)
        #expect(result.status == .applied)
        let photo = try #require(ModelContext(container).fetch(FetchDescriptor<Media>()).first)
        #expect(photo.sourceID == "photos:ABC-123/L0/001"); #expect(photo.data == bytes); #expect(photo.kind == "photo")
    }
}
