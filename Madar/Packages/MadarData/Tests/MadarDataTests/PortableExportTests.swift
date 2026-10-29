import Foundation
import SwiftData
import Testing
@testable import MadarData

@Suite(.serialized) @MainActor struct PortableExportTests {
    private func scratch() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("MadarPlainTests-\(UUID())")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true); return base
    }
    private func seeded() throws -> [DataRecord] {
        let container = try MadarContainerFactory.makeInMemory(); try fixture(container.mainContext)
        return try RecordBridge.all(container.mainContext)
    }
    private func manifest(_ files: [String: Data]) throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: files["manifest.json"]!)
    }
    @Test func emptyExportListsEveryModelWithZeroAndRoundTrips() throws {
        let bytes = try PortableExportCodec.export(records: [], now: Date(timeIntervalSince1970: 2_000_000_000))
        #expect(Array(bytes.prefix(4)) == [0x50, 0x4b, 0x03, 0x04])
        let files = try PortableZIP.decode(bytes); let value = try manifest(files)
        #expect(value["magic"] == .string("MADAR-PLAIN")); #expect(value["formatVersion"] == .number(1))
        #expect(value["createdAt"] == .string("2033-05-18T03:33:20Z"))
        #expect(Set(value["counts"]!.object!.keys) == Set(MadarSchema.syncedNames))
        #expect(value["counts"]!.object!.values.allSatisfy { $0 == .number(0) })
        #expect(files.count == 57); #expect(files["data/MoneyTransaction.jsonl"] == Data())
        #expect(files["data/Transaction.jsonl"] == nil)
        #expect(try PortableExportCodec.validate(bytes).records.isEmpty)
    }
    @Test func everySyncedModelPhotoAudioAliasAndTombstoneRoundTripsIntoEmptyStore() throws {
        let expected = try seeded(); let bytes = try PortableExportCodec.export(records: expected)
        let files = try PortableZIP.decode(bytes); let validated = try PortableExportCodec.validate(bytes)
        #expect(validated.manifest.counts.count == 56)
        #expect(validated.manifest.counts["Media"] == 2)
        #expect(try RecordFingerprint.hash(validated.records) == RecordFingerprint.hash(expected))
        let target = try MadarContainerFactory.makeInMemory()
        #expect(try BackupRestore.merge(validated, into: target.mainContext) == expected.count)
        #expect(try RecordFingerprint.hash(RecordBridge.all(target.mainContext)) == RecordFingerprint.hash(expected))
        #expect(try BackupRestore.merge(validated, into: target.mainContext) == 0)
        let photoPath = "media/\(StableIdentity.uuid(for: "fixture:Media").uuidString)"
        #expect(files[photoPath] == Data([1, 2, 3, 4]))
        #expect(validated.manifest.files.first { $0.path == photoPath }?.sha256 == "9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a")
        let mediaFields = try JSONDecoder().decode([String: JSONValue].self, from: Data(files["data/Media.jsonl"]!.split(separator: 0x0a).first!))
        #expect(mediaFields["data"] == .null)
        #expect(expected.contains { $0.deletedAt != nil }); #expect(expected.contains { $0.fields["mergedInto"] != .null })
    }
    @Test func goodreadsBookAndItsPrivateNoteKeepTheirLinkAcrossPortableRestore() throws {
        let source = try MadarContainerFactory.makeInMemory(), sourceContext = source.mainContext
        let bookID = UUID(), noteID = UUID()
        let book = Book(); book.id = bookID; book.title = "رحلة Goodreads"; book.author = "أحمد"; book.kind = "paper"
        book.shelf = "finished"; book.sourceGoodreadsID = "9001"
        let note = NotebookNote(); note.id = noteID; note.text = "ملاحظة خاصة"; note.isPrivate = true; note.link = "general"; note.targetID = bookID
        sourceContext.insert(book); sourceContext.insert(note); try sourceContext.save()

        let expected = try RecordBridge.all(sourceContext)
        let validated = try PortableExportCodec.validate(PortableExportCodec.export(records: expected))
        let restored = try MadarContainerFactory.makeInMemory(), restoredContext = restored.mainContext
        #expect(try BackupRestore.merge(validated, into: restoredContext) == expected.count)
        let restoredBook = try #require(restoredContext.fetch(FetchDescriptor<Book>()).first { $0.id == bookID })
        let restoredNote = try #require(restoredContext.fetch(FetchDescriptor<NotebookNote>()).first { $0.id == noteID })
        #expect(restoredBook.sourceGoodreadsID == "9001" && restoredBook.title == "رحلة Goodreads")
        #expect(restoredNote.isPrivate && restoredNote.text == "ملاحظة خاصة")
        #expect(restoredNote.link == "general" && restoredNote.targetID == restoredBook.id)
    }
    @Test func unsupportedVersionsCountsMissingFilesAndInvalidTypedRowsAreRejected() throws {
        let original = try PortableZIP.decode(PortableExportCodec.export(records: seeded()))
        for kind in 0..<8 {
            var files = original; var value = try manifest(files)
            switch kind {
            case 0: value["formatVersion"] = .number(2)
            case 1: value["storeSchemaVersion"] = .number(Double(MadarSchema.version + 1))
            case 2: var counts = value["counts"]!.object!; counts["PrayerLog"] = .number(99); value["counts"] = .object(counts)
            case 3: var counts = value["counts"]!.object!; counts.removeValue(forKey: "Entry"); value["counts"] = .object(counts)
            case 4: files.removeValue(forKey: "data/PrayerLog.jsonl")
            case 5: files.removeValue(forKey: files.keys.first { $0.hasPrefix("media/") }!)
            case 6:
                var fields = try JSONDecoder().decode([String: JSONValue].self, from: Data(files["data/PrayerLog.jsonl"]!.split(separator: 0x0a).first!))
                fields["status"] = .string("invalid-status")
                files["data/PrayerLog.jsonl"] = try JSONValue.object(fields).canonicalData() + Data([0x0a])
                var entries = value["files"]!.array!
                let index = entries.firstIndex { $0.object?["path"] == .string("data/PrayerLog.jsonl") }!
                var entry = entries[index].object!; entry["bytes"] = .number(Double(files["data/PrayerLog.jsonl"]!.count)); entry["sha256"] = .string(BackupCodec.hash(files["data/PrayerLog.jsonl"]!))
                entries[index] = .object(entry); value["files"] = .array(entries)
            default: files["device/CommandReceipt.jsonl"] = Data()
            }
            files["manifest.json"] = try JSONValue.object(value).canonicalData()
            #expect(throws: (any Error).self) { try PortableExportCodec.validate(PortableZIP.encode(files)) }
        }
    }
    @Test func truncatedTamperedTrailingAndTraversalZIPAreRejected() throws {
        let bytes = try PortableExportCodec.export(records: seeded())
        #expect(throws: (any Error).self) { try PortableExportCodec.validate(Data(bytes.dropLast())) }
        #expect(throws: (any Error).self) { try PortableExportCodec.validate(bytes + Data([0])) }
        var flipped = bytes; flipped[40] ^= 1
        #expect(throws: (any Error).self) { try PortableExportCodec.validate(flipped) }
        // Both local and central path names are changed without involving filesystem extraction.
        let small = try PortableZIP.encode(["manifest.json": Data()])
        var traversal = small
        let pattern = Data("manifest.json".utf8)
        while let range = traversal.range(of: pattern) { traversal.replaceSubrange(range, with: Data("../ifest.json".utf8)) }
        #expect(throws: DataError.invalidBackup) { try PortableZIP.decode(traversal) }
        #expect(throws: DataError.invalidBackup) { try PortableZIP.encode(["../outside": Data()]) }
    }
    @Test func mediaHashTamperIsRejectedEvenWithUpdatedZIPCRC() throws {
        var files = try PortableZIP.decode(PortableExportCodec.export(records: seeded()))
        let path = files.keys.first { $0.hasPrefix("media/") }!; files[path]![0] ^= 1
        #expect(throws: (any Error).self) { try PortableExportCodec.validate(PortableZIP.encode(files)) }
    }
    @Test func coordinatorExportQuiescesWritersExcludesDeviceRowsAndDoesNotConfigureBackups() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let store = try ManagedDataStore(root: base.appendingPathComponent("Managed"), commandLockURL: base.appendingPathComponent("CommandBus.lock"))
        let context = store.container.mainContext; try fixture(context)
        for key in ["core.faceIDLock", "sys.writerID"] {
            let row = DeviceSetting(); row.key = key; row.valueJSON = Data("\"private-device-value\"".utf8); context.insert(row)
        }
        context.insert(CommandReceipt()); context.insert(NotificationLedger()); try context.save()
        let allBefore = try RecordFingerprint.hash(RecordBridge.all(context, syncedOnly: false)); let generation = store.binding.generationID
        var events: [String] = []
        let coordinator = BackupCoordinator(store: store, backupDirectory: base.appendingPathComponent("Backups"), keyStore: MemoryBackupKeyStore(), lifecycle: .init(quiesce: { events.append("quiesce") }, resume: { events.append("resume") }))
        let file = try await coordinator.exportPlain()
        #expect(events == ["quiesce", "resume"]); #expect(!store.isBusy)
        #expect(file.path.contains("/Backups/PlainExports/")); #expect(file.pathExtension == "zip")
        #expect(store.binding.generationID == generation)
        #expect(try RecordFingerprint.hash(RecordBridge.all(context, syncedOnly: false)) == allBefore)
        #expect(try !coordinator.hasConfiguredKey()); #expect(try coordinator.catalog().isEmpty)
        #expect(try coordinator.status().lastSuccessAt == nil)
        let bytes = try Data(contentsOf: file); let files = try PortableZIP.decode(bytes)
        #expect(files.keys.allSatisfy { $0 == "manifest.json" || $0.hasPrefix("data/") || $0.hasPrefix("media/") })
        #expect(files["data/DeviceSetting.jsonl"] == nil); #expect(files["data/CommandReceipt.jsonl"] == nil)
        #expect(files["data/NotificationLedger.jsonl"] == nil)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("private-device-value"))
        _ = try PortableExportCodec.validate(bytes)
        // A second export removes the first unencrypted copy instead of piling them up.
        let second = try await coordinator.exportPlain()
        #expect(!FileManager.default.fileExists(atPath: file.path)); #expect(FileManager.default.fileExists(atPath: second.path))
    }
    @Test func cancelledExportCleansPartialDirectoryAndPreservesPreviousShareFile() async throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let store = try ManagedDataStore(root: base.appendingPathComponent("Managed"), commandLockURL: base.appendingPathComponent("CommandBus.lock")); try fixture(store.container.mainContext)
        let coordinator = BackupCoordinator(store: store, backupDirectory: base.appendingPathComponent("Backups"), keyStore: MemoryBackupKeyStore())
        let good = try await coordinator.exportPlain(); let before = try Data(contentsOf: good); let cancellation = BackupCancellation()
        await #expect(throws: BackupOperationError.cancelled) {
            try await coordinator.exportPlain(progress: { if $0.phase == .writing { cancellation.cancel() } }, cancellation: cancellation)
        }
        #expect(try Data(contentsOf: good) == before); #expect(!store.isBusy)
        #expect(try FileManager.default.contentsOfDirectory(atPath: good.deletingLastPathComponent().deletingLastPathComponent().path).count == 1)
        try StoreLease.checkMaintenance(lockURL: store.commandLockURL)
    }
    #if os(macOS)
    @Test func systemUnzipCanReadPortableArchive() throws {
        let base = try scratch(); defer { try? FileManager.default.removeItem(at: base) }
        let zip = base.appendingPathComponent("portable.zip"); try PortableExportCodec.export(records: seeded()).write(to: zip)
        let process = Process(); let output = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-t", zip.path]; process.standardOutput = output; process.standardError = output
        try process.run(); let report = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self); process.waitUntilExit()
        #expect(process.terminationStatus == 0); #expect(report.contains("No errors detected"))
    }
    #endif
}
