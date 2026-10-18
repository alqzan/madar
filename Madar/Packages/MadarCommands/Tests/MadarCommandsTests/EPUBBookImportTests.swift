import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

@MainActor struct EPUBBookImportTests {
    private struct Entry {
        var path: String
        var bytes: Data = Data()
        var flags: UInt16 = 0
        var declaredSize: Int?
        var declaredCompressedSize: Int?
        var creator: UInt16 = 0x0314
        var externalAttributes: UInt32 = 0
    }

    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EPUBBookTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func fixture() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../Tests/Fixtures/Mihbara/english-import-poc.epub").standardizedFileURL
    }

    private func validEntries() -> [Entry] {
        let container = Data(#"<container><rootfiles><rootfile full-path="OEBPS/package.opf"/></rootfiles></container>"#.utf8)
        let opf = Data(#"<package version="3.0" dir="ltr"><metadata><title>Test Book</title><creator>Test Author</creator><language>en</language></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>"#.utf8)
        let nav = Data(#"<html xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol><li><a href="chapter.xhtml">Opening</a></li></ol></nav></body></html>"#.utf8)
        let chapter = Data(#"<html><body><p>Original test text.</p></body></html>"#.utf8)
        return [Entry(path: "mimetype", bytes: Data("application/epub+zip".utf8)),
                Entry(path: "META-INF/container.xml", bytes: container), Entry(path: "OEBPS/package.opf", bytes: opf),
                Entry(path: "OEBPS/nav.xhtml", bytes: nav), Entry(path: "OEBPS/chapter.xhtml", bytes: chapter)]
    }

    private func archive(_ entries: [Entry]) -> Data {
        var local = Data(), central = Data()
        for entry in entries {
            let name = Data(entry.path.utf8), offset = local.count, crc = CRC32.checksum(entry.bytes)
            let compressed = entry.declaredCompressedSize ?? entry.bytes.count
            let uncompressed = entry.declaredSize ?? entry.bytes.count
            put32(0x04034B50, into: &local); put16(20, into: &local); put16(entry.flags, into: &local); put16(0, into: &local)
            put16(0, into: &local); put16(0, into: &local); put32(crc, into: &local)
            put32(UInt32(compressed), into: &local); put32(UInt32(uncompressed), into: &local)
            put16(UInt16(name.count), into: &local); put16(0, into: &local); local.append(name); local.append(entry.bytes)

            put32(0x02014B50, into: &central); put16(entry.creator, into: &central); put16(20, into: &central)
            put16(entry.flags, into: &central); put16(0, into: &central); put16(0, into: &central); put16(0, into: &central)
            put32(crc, into: &central); put32(UInt32(compressed), into: &central); put32(UInt32(uncompressed), into: &central)
            put16(UInt16(name.count), into: &central); put16(0, into: &central); put16(0, into: &central)
            put16(0, into: &central); put16(0, into: &central); put32(entry.externalAttributes, into: &central)
            put32(UInt32(offset), into: &central); central.append(name)
        }
        var result = local
        let centralOffset = result.count
        result.append(central)
        put32(0x06054B50, into: &result); put16(0, into: &result); put16(0, into: &result)
        put16(UInt16(entries.count), into: &result); put16(UInt16(entries.count), into: &result)
        put32(UInt32(central.count), into: &result); put32(UInt32(centralOffset), into: &result); put16(0, into: &result)
        return result
    }

    private func put16(_ value: UInt16, into data: inout Data) {
        data.append(UInt8(value & 0xFF)); data.append(UInt8(value >> 8))
    }
    private func put32(_ value: UInt32, into data: inout Data) {
        for shift in stride(from: 0, through: 24, by: 8) { data.append(UInt8((value >> shift) & 0xFF)) }
    }
    private func commandPayload(_ value: EPUBBookInspection, id: UUID, shelf: String = "want") -> MadarCore.JSONValue {
        .object(["id": .string(id.uuidString), "fileID": .string(value.id.uuidString), "sha256": .string(value.sha256),
                 "title": .string(value.title), "author": .string(value.author), "language": .string(value.appLanguage ?? "en"), "shelf": .string(shelf)])
    }

    @Test func readsRealMetadataAndNavigationWithoutCreatingRecords() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let inspection = try EPUBBookFiles.stage(source: fixture(), root: root.appendingPathComponent("Staging"))
        #expect(inspection.version == "3")
        #expect(inspection.title == "A Book About Reading")
        #expect(inspection.author == "Madar Fixture Author")
        #expect(inspection.appLanguage == "en" && inspection.direction == "ltr")
        #expect(inspection.outline.count == 10 && inspection.outline.first?.title == "Opening the Book")
        #expect(inspection.hasPageList && inspection.hasCover && inspection.hasFootnotes == true)
        #expect(inspection.coverData != nil)
        EPUBBookFiles.discard(id: inspection.id, root: root.appendingPathComponent("Staging"))
    }

    @Test func readsEPUB2NCXNavigation() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        var entries = validEntries()
        entries[2].bytes = Data(#"<package version="2.0"><metadata><title>كتاب قديم</title><creator>مؤلف</creator><language>ar</language></metadata><manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine toc="ncx" page-progression-direction="rtl"><itemref idref="chapter"/></spine></package>"#.utf8)
        entries[3] = Entry(path: "OEBPS/toc.ncx", bytes: Data(#"<ncx><navMap><navPoint><navLabel><text>باب أول</text></navLabel><content src="chapter.xhtml"/><navPoint><navLabel><text>فصل داخلي</text></navLabel><content src="chapter.xhtml#two"/></navPoint></navPoint></navMap><pageList><pageTarget/></pageList></ncx>"#.utf8))
        let source = root.appendingPathComponent("epub2.epub"); try archive(entries).write(to: source)
        let inspection = try EPUBBookFiles.stage(source: source, root: root.appendingPathComponent("Staging"))
        #expect(inspection.version == "2" && inspection.appLanguage == "ar" && inspection.direction == "rtl")
        #expect(inspection.outline.map(\.title) == ["باب أول", "فصل داخلي"] && inspection.outline[1].depth == 1)
        #expect(inspection.hasPageList)
    }

    @Test func confirmationStoresOriginalAppOnlyAndUndoClearsMedia() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appendingPathComponent("Store"))
        let adapter = DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 })
        let original = try Data(contentsOf: fixture())
        let source = root.appendingPathComponent("selected.epub"); try original.write(to: source)
        let inspection = try EPUBBookFiles.stage(source: source, root: adapter.bookStagingDirectory)
        let id = UUID(), commandID = UUID(), now = Date(), payload = commandPayload(inspection, id: id, shelf: "reading")
        #expect(try payload.canonicalData().count < 1024)
        let bus = CommandBus(adapter: adapter), envelope = CommandEnvelope(commandID: commandID, name: "book.importEPUB", payload: payload, issuedAt: now)
        let denied = try await bus.execute(.init(name: "book.importEPUB", payload: payload, source: .shortcut, issuedAt: now), now: now)
        #expect(denied.status == .needsApp)
        let result = try await bus.execute(envelope, now: now)
        #expect(result.status == .applied && result.undoToken != nil)
        EPUBBookFiles.discard(id: inspection.id, root: adapter.bookStagingDirectory)
        #expect(try await bus.execute(envelope, now: now) == result)
        let context = ModelContext(container)
        let books = try context.fetch(FetchDescriptor<Book>()), media = try context.fetch(FetchDescriptor<Media>())
        #expect(books.count == 1 && books[0].kind == "file" && books[0].format == "epub" && books[0].shelf == "reading")
        #expect(books[0].pages == nil && books[0].fileHash == inspection.sha256)
        #expect(try JSONDecoder().decode([EPUBBookOutlineItem].self, from: #require(books[0].tocJSON)).count == 10)
        #expect(media.count == 1 && media[0].contentType == "org.idpf.epub-container" && media[0].data == original)
        let duplicate = try EPUBBookFiles.stage(source: source, root: adapter.bookStagingDirectory)
        let duplicateResult = try await bus.execute(.init(name: "book.importEPUB", payload: commandPayload(duplicate, id: UUID()), issuedAt: now), now: now)
        #expect(duplicateResult.status == .rejected)
        #expect(try context.fetchCount(FetchDescriptor<Book>()) == 1)
        let undo = try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken": .string(commandID.uuidString)]), issuedAt: now), now: now)
        #expect(undo.status == .applied)
        #expect(try context.fetch(FetchDescriptor<Book>()).first?.deletedAt != nil)
        #expect(try context.fetch(FetchDescriptor<Media>()).first?.deletedAt != nil)
        #expect(try context.fetch(FetchDescriptor<Media>()).first?.data == nil)
    }

    @Test func rejectsUnsafePathsEncryptedEntriesSymlinksAndZIPLimitsBeforeCopy() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let staging = root.appendingPathComponent("Staging"), source = root.appendingPathComponent("invalid.epub")
        func rejected(_ entries: [Entry]) throws {
            try archive(entries).write(to: source)
            #expect(throws: (any Error).self) { try EPUBBookFiles.stage(source: source, root: staging) }
            #expect(!FileManager.default.fileExists(atPath: staging.path))
        }
        var unsafe = validEntries(); unsafe.append(Entry(path: "../outside", bytes: Data("x".utf8)))
        try rejected(unsafe)
        var encrypted = validEntries(); encrypted.append(Entry(path: "OEBPS/secret.xhtml", flags: 1))
        try rejected(encrypted)
        var symlink = validEntries(); symlink.append(Entry(path: "OEBPS/link", creator: 0x0314, externalAttributes: 0xA1FF0000))
        try rejected(symlink)
        var ratio = validEntries(); ratio.append(Entry(path: "OEBPS/bomb", bytes: Data([0]), declaredSize: 101, declaredCompressedSize: 1))
        try rejected(ratio)
        var expanded = validEntries(); expanded.append(Entry(path: "OEBPS/huge", bytes: Data([0]), declaredSize: 1_073_741_825, declaredCompressedSize: 1))
        try rejected(expanded)
        var tooMany = validEntries()
        tooMany.append(contentsOf: (0..<10_000).map { Entry(path: String(format: "OEBPS/%05d", $0)) })
        try rejected(tooMany)
    }

    @Test func changedStagedBytesFailBeforeCreatingBookOrMedia() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appendingPathComponent("Store"))
        let adapter = DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 })
        let source = root.appendingPathComponent("selected.epub"); try Data(contentsOf: fixture()).write(to: source)
        let inspection = try EPUBBookFiles.stage(source: source, root: adapter.bookStagingDirectory)
        try Data("changed".utf8).write(to: EPUBBookFiles.stagedURL(id: inspection.id, root: adapter.bookStagingDirectory))
        let result = try await CommandBus(adapter: adapter).execute(.init(name: "book.importEPUB", payload: commandPayload(inspection, id: UUID())), now: Date())
        #expect(result.status == .rejected)
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<Book>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Media>()) == 0)
    }
}
