import Foundation
import Testing
@testable import MadarData

@MainActor struct BackupFolderDeliveryTests {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarFolderTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func receipt(_ bytes: Data, root: URL, index: Int, kind: BackupKind = .automatic) throws -> BackupReceipt {
        let id = UUID(), file = root.appendingPathComponent("Madar-" + id.uuidString + ".madarbackup")
        try bytes.write(to: file)
        return .init(id: id, fileURL: file, createdAt: Date(timeIntervalSince1970: Double(index)), kind: kind,
                     generationID: UUID(), sha256: BackupCodec.hash(bytes), counts: [:])
    }
    @Test func encryptedBytesRoundTripAndOnlyOldOwnedAutomaticFilesArePruned() async throws {
        let base = try root(); defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("Source"), folder = base.appendingPathComponent("Chosen")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bytes = try BackupCodec.export(records: [], passphrase: "synthetic long password")
        let receipts = try (1...5).map { try receipt(bytes, root: source, index: $0) }
        let manual = try receipt(bytes, root: source, index: 0, kind: .manual)
        let config = try BackupFolderDelivery.select(folder)
        let first = try await BackupFolderDelivery.deliver([manual] + Array(receipts.prefix(4)), from: source, to: config)
        let destination = folder.appendingPathComponent("Madar-" + config.ownerID.uuidString)
        let untouched = destination.appendingPathComponent("owner-file.txt"); try Data("keep".utf8).write(to: untouched)
        let second = try await BackupFolderDelivery.deliver([manual] + Array(receipts.suffix(4)), from: source, to: first.configuration)
        #expect(second.configuration.owned.count == 5)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent(receipts[0].fileURL.lastPathComponent).path))
        #expect(try Data(contentsOf: untouched) == Data("keep".utf8))
        let delivered = try Data(contentsOf: destination.appendingPathComponent(receipts[4].fileURL.lastPathComponent))
        #expect(delivered == bytes)
        #expect(try BackupCodec.validate(delivered, passphrase: "synthetic long password").records.isEmpty)
        #expect(second.uploadedToICloud == nil, "A local copy must never be reported as a confirmed cloud upload")
        let replay = try await BackupFolderDelivery.deliver([manual] + Array(receipts.suffix(4)), from: source, to: second.configuration, now: Date(timeIntervalSince1970: 200))
        #expect(replay.configuration.owned.count == 5)
        #expect(replay.configuration.lastCopiedAt == second.configuration.lastCopiedAt, "Verifying unchanged files must not invent a new copy time")
        let emptyCatalog = try await BackupFolderDelivery.deliver([], from: source, to: replay.configuration)
        #expect(emptyCatalog.configuration.owned.count == 5, "An empty/lost local catalog cannot erase remote recovery copies")
    }

    @Test func changedOwnedFilesArePreservedAndSourceTamperingWritesNoBackup() async throws {
        let base = try root(); defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("Source"), folder = base.appendingPathComponent("Chosen")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bytes = try BackupCodec.export(records: [], passphrase: "synthetic long password")
        let receipts = try (1...5).map { try receipt(bytes, root: source, index: $0) }
        let config = try BackupFolderDelivery.select(folder)
        let first = try await BackupFolderDelivery.deliver(Array(receipts.prefix(4)), from: source, to: config)
        let destination = folder.appendingPathComponent("Madar-" + config.ownerID.uuidString)
        let changed = destination.appendingPathComponent(receipts[0].fileURL.lastPathComponent)
        try Data("owner changed this file".utf8).write(to: changed)
        let result = try await BackupFolderDelivery.deliver(Array(receipts.suffix(4)), from: source, to: first.configuration)
        #expect(result.preservedChangedFiles == 1)
        #expect(try Data(contentsOf: changed) == Data("owner changed this file".utf8))
        try Data("damaged".utf8).write(to: receipts[4].fileURL)
        await #expect(throws: BackupFolderError.invalidSource) {
            try await BackupFolderDelivery.deliver([receipts[4]], from: source, to: result.configuration)
        }
        #expect(try Data(contentsOf: destination.appendingPathComponent(receipts[4].fileURL.lastPathComponent)) == bytes)
    }

    @Test func symlinkTargetsAndPlainExportsAreRejected() async throws {
        let base = try root(); defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("Source"), folder = base.appendingPathComponent("Chosen")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bytes = try BackupCodec.export(records: [], passphrase: "synthetic long password")
        let saved = try receipt(bytes, root: source, index: 1)
        let config = try BackupFolderDelivery.select(folder)
        let destination = folder.appendingPathComponent("Madar-" + config.ownerID.uuidString)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let other = base.appendingPathComponent("Other"); try Data("other bytes".utf8).write(to: other)
        try FileManager.default.createSymbolicLink(at: destination.appendingPathComponent(saved.fileURL.lastPathComponent), withDestinationURL: other)
        await #expect(throws: (any Error).self) { try await BackupFolderDelivery.deliver([saved], from: source, to: config) }
        #expect(try Data(contentsOf: other) == Data("other bytes".utf8))
        let plain = try receipt(Data("plain private text".utf8), root: source, index: 2)
        await #expect(throws: BackupFolderError.invalidSource) { try await BackupFolderDelivery.deliver([plain], from: source, to: config) }
    }
    private final class ChangedOnRelinquish: NSFileCoordinator {
        override func coordinate(writingItemAt url: URL, options: NSFileCoordinator.WritingOptions = [], error outError: AutoreleasingUnsafeMutablePointer<NSError?>?, byAccessor writer: (URL) -> Void) {
            // A provider commits a newer file before it grants this coordinated accessor.
            try! Data("new provider bytes".utf8).write(to: url)
            writer(url)
        }
    }
    @Test func pruningRechecksProviderBytesInsideCoordinatedDeletion() throws {
        let base = try root(); defer { try? FileManager.default.removeItem(at: base) }
        let file = base.appendingPathComponent("old.madarbackup")
        let old = Data("old receipt".utf8); try old.write(to: file)
        let expected = BackupCodec.hash(old)
        #expect(try BackupFolderDelivery.removeUnchanged(at: file, expectedHash: expected, coordinator: ChangedOnRelinquish()) == false)
        #expect(try Data(contentsOf: file) == Data("new provider bytes".utf8))
    }

}
