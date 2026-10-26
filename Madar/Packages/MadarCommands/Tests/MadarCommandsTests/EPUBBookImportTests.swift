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
    private func commandPayload(_ value: EPUBBookInspection, id: UUID, shelf: String = "want", turathID: Int? = nil) -> MadarCore.JSONValue {
        var payload: [String: MadarCore.JSONValue] = ["id": .string(id.uuidString), "fileID": .string(value.id.uuidString), "sha256": .string(value.sha256),
                 "title": .string(value.title), "author": .string(value.author), "language": .string(value.appLanguage ?? "en"), "shelf": .string(shelf)]
        if let turathID { payload["turathID"] = .number(Double(turathID)) }
        return .object(payload)
    }

    @Test func canceledPreviewStagingLeavesSourceAndNoStagedCopy() async throws {
        let folder = try root(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = fixture(), original = try Data(contentsOf: source), id = UUID()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await EPUBBookFiles.stageForPreview(source: source, root: folder, id: id)
        }
        do {
            _ = try await task.value
            Issue.record("Canceled preview staging must throw")
        } catch is CancellationError { }
        #expect(!FileManager.default.fileExists(atPath: EPUBBookFiles.stagedURL(id: id, root: folder).path))
        #expect(try Data(contentsOf: source) == original)
    }

    @Test func cancelingPreviewScanStopsBeforeCompletionAndAllowsRetry() async throws {
        let folder = try root(); defer { try? FileManager.default.removeItem(at: folder) }
        let staged = try EPUBBookFiles.stage(source: fixture(), root: folder)
        let file = EPUBBookFiles.stagedURL(id: staged.id, root: folder)
        let original = try Data(contentsOf: file)
        let started = AsyncStream<Void>.makeStream()
        let resume = DispatchSemaphore(value: 0)
        let task = Task {
            defer { started.continuation.finish() }
            return try await EPUBBookFiles.scanForPreview(file: file) { progress in
                if progress == 0 {
                    started.continuation.yield(())
                    // Pause only the parser thread until its caller cancels; bound the wait on test failure.
                    _ = resume.wait(timeout: .now() + 5)
                }
                #expect(progress < 1)
            }
        }
        for await _ in started.stream { break }
        task.cancel()
        resume.signal()
        do {
            _ = try await task.value
            Issue.record("Canceled scan must not return a partial report as complete")
        } catch is CancellationError { }
        #expect(try Data(contentsOf: file) == original)
        let retry = try await EPUBBookFiles.scanForPreview(file: file)
        #expect(retry.chapters == 1, "The fixture has one spine document containing ten headings")
        EPUBBookFiles.discard(id: staged.id, root: folder)
        #expect(!FileManager.default.fileExists(atPath: file.path))
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

    /// Owner's «أربعون» (25 Oct): re-zipped with «mimetype» after other files; Apple Books opens it, so Madar must too.
    @Test func acceptsMovedOrMissingMimetypeButNotAWrongOne() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        var moved = validEntries(); moved.append(moved.removeFirst())
        let movedSource = root.appendingPathComponent("moved.epub"); try archive(moved).write(to: movedSource)
        #expect(try EPUBBookFiles.stage(source: movedSource, root: root.appendingPathComponent("Staging")).title == "Test Book")
        let missingSource = root.appendingPathComponent("missing.epub"); try archive(Array(validEntries().dropFirst())).write(to: missingSource)
        #expect(try EPUBBookFiles.stage(source: missingSource, root: root.appendingPathComponent("Staging")).title == "Test Book")
        var wrong = validEntries(); wrong[0].bytes = Data("application/zip".utf8)
        let wrongSource = root.appendingPathComponent("wrong.epub"); try archive(wrong).write(to: wrongSource)
        #expect(throws: DataError.self) { try EPUBBookFiles.stage(source: wrongSource, root: root.appendingPathComponent("Staging")) }
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
        let id = UUID(), commandID = UUID(), now = Date(), payload = commandPayload(inspection, id: id, shelf: "reading", turathID: 12028)
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
        #expect(books[0].turathID == 12028)
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

    @Test func removedEPUBCanBeRestoredToTheSameBookAndRestoreUndoReturnsItToMissing() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appendingPathComponent("Store"))
        let adapter = DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 })
        let source = fixture(), inspection = try EPUBBookFiles.stage(source: source, root: adapter.bookStagingDirectory)
        let original = try Data(contentsOf: source), now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00+03:00")!
        let bookID = UUID(), mediaID = UUID(), context = ModelContext(container)
        let media = Media(); media.id = mediaID; media.kind = "doc"; media.contentType = "org.idpf.epub-container"; media.data = original
        media.sha256 = inspection.sha256; media.sizeBytes = original.count; context.insert(media)
        let book = Book(); book.id = bookID; book.title = "عنوان الكتاب محفوظ"; book.author = "مؤلفه"; book.kind = "file"; book.format = "epub"
        book.shelf = "reading"; book.mediaID = mediaID; book.fileHash = inspection.sha256; book.currentPage = 7
        book.locatorJSON = Data(#"{"href":"OEBPS/chapter.xhtml","type":"application/xhtml+xml"}"#.utf8); context.insert(book)
        let session = ReadingSession(); session.id = UUID(); session.bookID = bookID; session.start = now
        session.end = now.addingTimeInterval(300); session.activeSeconds = 300; session.fromPage = 1; session.toPage = 7; session.pagesCounted = 6; context.insert(session)
        let highlight = Highlight(); highlight.id = UUID(); highlight.bookID = bookID; highlight.locatorJSON = book.locatorJSON!; highlight.color = "yellow"; context.insert(highlight)
        try context.save()

        let bus = CommandBus(adapter: adapter), removePayload = MadarCore.JSONValue.object(["id": .string(bookID.uuidString)])
        let removed = try await bus.execute(.init(name: "book.removeFile", payload: removePayload, issuedAt: now), now: now)
        #expect(removed.status == .applied && removed.undoToken == nil)
        #expect(try #require(context.fetch(FetchDescriptor<Media>()).first { $0.id == mediaID }).data == nil)

        let restoreCommandID = UUID()
        let restorePayload = MadarCore.JSONValue.object(["id": .string(bookID.uuidString), "fileID": .string(inspection.id.uuidString), "sha256": .string(inspection.sha256)])
        #expect(BookCommand.parse("book.restoreFile", ["id": .string(bookID.uuidString), "fileID": .string(inspection.id.uuidString), "sha256": .string(inspection.sha256)]) == .restoreBookFile(id: bookID, fileID: inspection.id, sha256: inspection.sha256))
        let restored = try await bus.execute(.init(commandID: restoreCommandID, name: "book.restoreFile", payload: restorePayload, issuedAt: now.addingTimeInterval(1)), now: now.addingTimeInterval(1))
        #expect(restored.status == .applied && restored.undoToken != nil)
        let restoredBook = try #require(context.fetch(FetchDescriptor<Book>()).first { $0.id == bookID })
        let restoredMedia = try #require(context.fetch(FetchDescriptor<Media>()).first { $0.id == mediaID })
        #expect(restoredBook.title == "عنوان الكتاب محفوظ" && restoredBook.currentPage == 7 && restoredBook.locatorJSON == book.locatorJSON)
        #expect(restoredBook.deletedAt == nil && restoredMedia.state == "ok" && restoredMedia.data == original)
        #expect(try #require(context.fetch(FetchDescriptor<ReadingSession>()).first { $0.id == session.id }).deletedAt == nil)
        #expect(try #require(context.fetch(FetchDescriptor<Highlight>()).first { $0.id == highlight.id }).deletedAt == nil)

        let undone = try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken": .string(restoreCommandID.uuidString)]), issuedAt: now.addingTimeInterval(2)), now: now.addingTimeInterval(2))
        #expect(undone.status == .applied)
        #expect(try #require(context.fetch(FetchDescriptor<Media>()).first { $0.id == mediaID }).data == nil)
        #expect(try #require(context.fetch(FetchDescriptor<Media>()).first { $0.id == mediaID }).state == "missing")
        #expect(try #require(context.fetch(FetchDescriptor<Book>()).first { $0.id == bookID }).title == "عنوان الكتاب محفوظ")
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
    /// Owner, 24 Oct 2026: the full scan before a book reaches the shelf. The fixture holds one fault of each kind;
    /// the expected values are counted by hand from it.
    @Test func fullScanFindsEmptyChaptersBrokenIndexPagesAndVerses() throws {
        let container = Data(#"<container><rootfiles><rootfile full-path="OEBPS/package.opf"/></rootfiles></container>"#.utf8)
        let opf = Data(#"<package version="3.0" dir="rtl"><metadata><title>كتاب</title><language>ar</language></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/><item id="b" href="b.xhtml" media-type="application/xhtml+xml"/><item id="c" href="c.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="a"/><itemref idref="b"/><itemref idref="c"/></spine></package>"#.utf8)
        let nav = Data(#"<html xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol><li><a href="a.xhtml#start">الأول</a></li><li><a href="c.xhtml">الثالث</a></li><li><a href="a.xhtml#nowhere">مكسور</a></li><li><a href="missing.xhtml">مفقود</a></li></ol></nav><nav epub:type="page-list"><ol><li><a href="a.xhtml">١</a></li><li><a href="a.xhtml">٢</a></li><li><a href="c.xhtml">٤</a></li><li><a href="c.xhtml">٤</a></li><li><a href="c.xhtml">٢٠٠</a></li></ol></nav></body></html>"#.utf8)
        let a = Data(#"<html><body><h1 id="start">باب</h1><p>قال تعالى ﴿إن مع العسر يسرا﴾ وهذا</p><p>نص ثان</p><p> </p></body></html>"#.utf8)
        let b = Data(#"<html><body><p>  </p></body></html>"#.utf8)
        let c = Data(#"<html><body><p>﴿الحمد لله﴾</p></body></html>"#.utf8)
        let entries = [Entry(path: "mimetype", bytes: Data("application/epub+zip".utf8)), Entry(path: "META-INF/container.xml", bytes: container),
                       Entry(path: "OEBPS/package.opf", bytes: opf), Entry(path: "OEBPS/nav.xhtml", bytes: nav),
                       Entry(path: "OEBPS/a.xhtml", bytes: a), Entry(path: "OEBPS/b.xhtml", bytes: b), Entry(path: "OEBPS/c.xhtml", bytes: c)]
        let folder = try root(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("scan.epub"); try archive(entries).write(to: file)
        var steps: [Double] = []
        let scan = try EPUBBookFiles.scan(file: file) { steps.append($0) }
        #expect(scan.chapters == 3)
        #expect(scan.emptyChapters == [2])
        #expect(scan.unreadChapters == 0)
        #expect(scan.paragraphs == 3)
        #expect(scan.verses == 2)
        #expect(scan.tocEntries == 4)
        #expect(scan.brokenTOC == ["مكسور", "مفقود"])
        #expect(scan.pageLabels == 5)
        #expect(scan.pageRepeats == 1)
        #expect(scan.pageGaps == 1, "٢ then ٤ skips ٣; ٢٠٠ is a new run, not 195 missing pages")
        #expect(scan.isComplete == false)
        #expect(steps.last == 1)
    }

    @Test func fullScanCountsUnresolvedSpineEntriesAsUnreadInsteadOfDroppingThem() throws {
        let container = Data(#"<container><rootfiles><rootfile full-path="package.opf"/></rootfiles></container>"#.utf8)
        let opf = Data(#"<package><manifest><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="a"/><itemref idref="missing"/><itemref/></spine></package>"#.utf8)
        let entries = [Entry(path: "mimetype", bytes: Data("application/epub+zip".utf8)),
                       Entry(path: "META-INF/container.xml", bytes: container), Entry(path: "package.opf", bytes: opf),
                       Entry(path: "a.xhtml", bytes: Data("<html><body><p>نص مقروء</p></body></html>".utf8))]
        let folder = try root(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("missing-spine.epub"); try archive(entries).write(to: file)
        let scan = try EPUBBookFiles.scan(file: file)
        #expect(scan.chapters == 3)
        #expect(scan.unreadChapters == 2)
        #expect(scan.words == 2)
        #expect(!scan.isComplete)
    }
    @Test func fullScanChecksTargetsWithinOneChapterAndNormalizesPageDigits() throws {
        var entries = validEntries()
        entries[3].bytes = Data(#"<html xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol><li><a href="chapter.xhtml#later">Later</a></li><li><a href="chapter.xhtml#early">Early</a></li></ol></nav><nav epub:type="page-list"><ol><li><a href="chapter.xhtml#later">1</a></li><li><a href="chapter.xhtml#early">2</a></li><li><a href="chapter.xhtml#end">٢</a></li><li><a href="chapter.xhtml#missing">3</a></li></ol></nav></body></html>"#.utf8)
        entries[4].bytes = Data(#"<html><body><h1 id="early">First</h1><p id="later">Second</p><p id="end">Last</p></body></html>"#.utf8)
        let folder = try root(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("local-order.epub"); try archive(entries).write(to: file)
        let scan = try EPUBBookFiles.scan(file: file)
        #expect(scan.tocOutOfOrder == 1, "The TOC returns from the second block to the first in the same file")
        #expect(scan.brokenTOC.isEmpty)
        #expect(scan.pageOutOfOrder == 1, "Page 2's target precedes page 1, despite increasing labels")
        #expect(scan.pageRepeats == 1, "2 and ٢ are the same printed label")
        #expect(scan.pageGaps == 0)
        #expect(scan.unverifiedPageLinks == 1)
        #expect(!scan.isComplete)
    }

    @Test func orderedSameChapterTargetsRemainCompleteAndResetPagesForNewVolumes() throws {
        var entries = validEntries()
        entries[3].bytes = Data(#"<html xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol><li><a href="chapter.xhtml#early">Early</a></li><li><a href="chapter.xhtml#later">Later</a></li></ol></nav><nav epub:type="page-list"><ol><li><a href="chapter.xhtml#early">١/٩</a></li><li><a href="chapter.xhtml#later">٢/١</a></li></ol></nav></body></html>"#.utf8)
        entries[4].bytes = Data(#"<html><body><h1 id="early">First</h1><p id="later">Second</p></body></html>"#.utf8)
        let folder = try root(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("correct-order.epub"); try archive(entries).write(to: file)
        let scan = try EPUBBookFiles.scan(file: file)
        #expect(scan.tocOutOfOrder == 0)
        #expect(scan.pageOutOfOrder == 0)
        #expect(scan.pageGaps == 0)
        #expect(scan.pageRepeats == 0)
        #expect(scan.unverifiedPageLinks == 0)
        #expect(scan.isComplete)
        let descending = EPUBBookFiles.pageCheck(["٣", "٢", "1"])
        #expect(descending.outOfOrder == [1, 2])
    }

    @Test func legacyNCXPageTargetsUseTheSameDocumentOrder() throws {
        var entries = validEntries()
        entries[2].bytes = Data(#"<package><manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine toc="ncx"><itemref idref="chapter"/></spine></package>"#.utf8)
        entries[3] = Entry(path: "OEBPS/toc.ncx", bytes: Data(#"<ncx><navMap><navPoint><navLabel><text>Last</text></navLabel><content src="chapter.xhtml#later"/></navPoint><navPoint><navLabel><text>First</text></navLabel><content src="chapter.xhtml#early"/></navPoint></navMap><pageList><pageTarget><navLabel><text>1</text></navLabel><content src="chapter.xhtml#later"/></pageTarget><pageTarget><navLabel><text>2</text></navLabel><content src="chapter.xhtml#early"/></pageTarget></pageList></ncx>"#.utf8))
        entries[4].bytes = Data(#"<html><body><p id="early">First</p><p id="later">Last</p></body></html>"#.utf8)
        let folder = try root(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("ncx-order.epub"); try archive(entries).write(to: file)
        let scan = try EPUBBookFiles.scan(file: file)
        #expect(scan.tocEntries == 2)
        #expect(scan.tocOutOfOrder == 1)
        #expect(scan.pageLabels == 2)
        #expect(scan.pageOutOfOrder == 1)
        #expect(scan.pageGaps == 0)
        #expect(scan.unverifiedPageLinks == 0)
        #expect(!scan.isComplete)
    }

    @Test func fullScanPreservesMixedContentOrderAndFlagsSuspiciousEncoding() throws {
        var entries = validEntries()
        entries[4].bytes = Data(#"<html><body><p>قال: لقد <em>خلقنا الإنسان</em> في أحسن تقويم.</p><p>﴿إن <b>مع العسر</b> يسرا﴾</p><p>قل هو الله أحد</p><p>لقد خلقنا الإنسان</p><p>في أحسن تقويم</p><p>Ø§Ù„ÙƒØªØ§Ø¨</p><p>رمز � مفقود</p><script>لقد خلقنا الإنسان في أحسن تقويم</script></body></html>"#.utf8)
        let folder = try root(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("text-scan.epub"); let bytes = archive(entries); try bytes.write(to: file)
        let scan = try EPUBBookFiles.scan(file: file)
        #expect(scan.quotationScanAvailable)
        #expect(scan.unmarkedVerses == 1, "The complete ayah spans an inline tag; split paragraphs and short phrases do not match")
        #expect(scan.verses == 1)
        #expect(scan.suspectTextChapters == [1])
        #expect(!scan.isComplete)
        #expect(try Data(contentsOf: file) == bytes, "A finding never rewrites the source")
    }

}
