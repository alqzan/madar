import Foundation
import Testing
import CoreGraphics
import CoreText
import PDFKit
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

@MainActor struct PDFBookImportTests {
    private func pdf(pages: Int = 2, text: Bool = false) -> Data {
        let bytes = NSMutableData()
        let consumer = CGDataConsumer(data: bytes)!
        var box = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            if text {
                context.textPosition = CGPoint(x: 20, y: 300)
                let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 18, nil)]
                CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "Reading opens a door to knowledge.", attributes: attributes)), context)
            } else { context.setFillColor(CGColor(gray: 0.4, alpha: 1)); context.fill(CGRect(x: 20, y: 20, width: 200, height: 300)) }
            context.endPDFPage()
        }
        context.closePDF()
        return bytes as Data
    }
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PDFBookTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func previewDetectsTextAndTextlessPagesWithoutCreatingAnyRows() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appendingPathComponent("Store"))
        let source = root.appendingPathComponent("كتاب.pdf"); try pdf().write(to: source)
        let scanned = try PDFBookFiles.stage(source: source, root: root.appendingPathComponent("Staging"))
        #expect(scanned.scanned && scanned.pages == 2 && scanned.textPages == 0)
        #expect(scanned.outline.isEmpty && !scanned.hasPageLabels && scanned.detectedLanguage == nil)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Book>()) == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Media>()) == 0)
        try pdf(text: true).write(to: source)
        let text = try PDFBookFiles.stage(source: source, root: root.appendingPathComponent("Staging"))
        #expect(!text.scanned && text.textPages == 2)
        PDFBookFiles.discard(id: scanned.id, root: root.appendingPathComponent("Staging"))
        #expect(!FileManager.default.fileExists(atPath: PDFBookFiles.stagedURL(id: scanned.id, root: root.appendingPathComponent("Staging")).path))
    }

    @Test func signatureTypeAndByteLimitRejectBeforeCopyAndCorruptionLeavesNoStagedFile() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let staging = root.appendingPathComponent("Staging"), source = root.appendingPathComponent("كتاب.pdf")
        try Data("not a PDF".utf8).write(to: source)
        #expect(throws: (any Error).self) { try PDFBookFiles.stage(source: source, root: staging) }
        #expect(!FileManager.default.fileExists(atPath: staging.path))
        let renamed = root.appendingPathComponent("كتاب.txt"); try pdf().write(to: renamed)
        #expect(throws: (any Error).self) { try PDFBookFiles.stage(source: renamed, root: staging) }
        try Data("%PDF-1.7\n".utf8).write(to: source)
        let handle = try FileHandle(forWritingTo: source); try handle.truncate(atOffset: UInt64(PDFBookFiles.maximumBytes + 1)); try handle.close()
        #expect(throws: (any Error).self) { try PDFBookFiles.stage(source: source, root: staging) }
        #expect(!FileManager.default.fileExists(atPath: staging.path))
        try Data("%PDF-1.7\ncorrupt".utf8).write(to: source)
        #expect(throws: (any Error).self) { try PDFBookFiles.stage(source: source, root: staging) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
    }

    @Test func moreThanOneThousandPagesIsRejectedAndCopyIsRemoved() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("كبير.pdf"), staging = root.appendingPathComponent("Staging")
        try pdf(pages: 1001).write(to: source)
        #expect(throws: (any Error).self) { try PDFBookFiles.stage(source: source, root: staging) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
    }

    @Test func confirmationCommitsOriginalOnceWithSmallReceiptAndUndoTombstonesBothRows() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appendingPathComponent("Store"))
        let adapter = DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 })
        let source = root.appendingPathComponent("كتاب.pdf"), original = pdf()
        try original.write(to: source)
        let inspection = try PDFBookFiles.stage(source: source, root: adapter.bookStagingDirectory)
        let id = UUID(), commandID = UUID(), now = Date()
        let payload: MadarCore.JSONValue = .object(["id": .string(id.uuidString), "fileID": .string(inspection.id.uuidString), "sha256": .string(inspection.sha256), "title": .string("كتاب مصوّر"), "author": .string(""), "language": .string("ar")])
        #expect(try payload.canonicalData().count < 1024)
        let bus = CommandBus(adapter: adapter), envelope = CommandEnvelope(commandID: commandID, name: "book.importPDF", payload: payload, issuedAt: now)
        let denied = try await bus.execute(.init(name: "book.importPDF", payload: payload, source: .shortcut, issuedAt: now), now: now)
        #expect(denied.status == .needsApp)
        let first = try await bus.execute(envelope, now: now)
        #expect(first.status == .applied && first.undoToken != nil)
        PDFBookFiles.discard(id: inspection.id, root: adapter.bookStagingDirectory)
        #expect(try await bus.execute(envelope, now: now) == first) // Replay needs no staged original.
        let context = ModelContext(container)
        let books = try context.fetch(FetchDescriptor<Book>()), media = try context.fetch(FetchDescriptor<Media>())
        #expect(books.count == 1 && media.count == 1)
        #expect(books[0].format == "pdfScanned" && books[0].kind == "file" && books[0].shelf == "want")
        #expect(books[0].pages == 2 && books[0].fileHash == inspection.sha256 && books[0].importBatchID == nil)
        #expect(media[0].data == original && media[0].sha256 == inspection.sha256)
        let receipt = try #require(context.fetch(FetchDescriptor<MadarData.CommandReceipt>()).first)
        #expect((receipt.undoJSON?.count ?? 0) < 8_192)
        let duplicatePreview = try PDFBookFiles.stage(source: source, root: adapter.bookStagingDirectory)
        let duplicate: MadarCore.JSONValue = .object(["id": .string(UUID().uuidString), "fileID": .string(duplicatePreview.id.uuidString), "sha256": .string(inspection.sha256), "title": .string("مكرر"), "author": .string(""), "language": .string("ar")])
        let refused = try await bus.execute(.init(name: "book.importPDF", payload: duplicate, issuedAt: now), now: now)
        #expect(refused.status == .rejected)
        #expect(try context.fetchCount(FetchDescriptor<Book>()) == 1)
        let undo = try await bus.execute(.init(name: "system.undo", payload: .object(["undoToken": .string(commandID.uuidString)]), issuedAt: now), now: now)
        #expect(undo.status == .applied)
        #expect(try context.fetch(FetchDescriptor<Book>()).first?.deletedAt != nil)
        #expect(try context.fetch(FetchDescriptor<Media>()).first?.deletedAt != nil)
        #expect(try context.fetch(FetchDescriptor<Media>()).first?.data == nil)
        #expect(try context.fetchCount(FetchDescriptor<ImportBatch>()) == 0)
    }

    @Test func protectedPDFAndAChangedStagedOriginalAreRejectedWithoutBookOrMedia() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("محمي.pdf"), staging = root.appendingPathComponent("BookStaging")
        let document = try #require(PDFDocument(data: pdf()))
        #expect(document.write(to: source, withOptions: [.ownerPasswordOption: "owner", .userPasswordOption: "secret"]))
        #expect(throws: (any Error).self) { try PDFBookFiles.stage(source: source, root: staging) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
        try pdf().write(to: source)
        let inspection = try PDFBookFiles.stage(source: source, root: staging)
        try pdf(text: true).write(to: PDFBookFiles.stagedURL(id: inspection.id, root: staging))
        let container = try MadarContainerFactory.makeLocal(at: root.appendingPathComponent("Store"))
        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        let payload: MadarCore.JSONValue = .object(["id": .string(UUID().uuidString), "fileID": .string(inspection.id.uuidString), "sha256": .string(inspection.sha256), "title": .string("تغيّر"), "author": .string(""), "language": .string("ar")])
        let result = try await bus.execute(.init(name: "book.importPDF", payload: payload), now: Date())
        #expect(result.status == .rejected)
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<Book>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Media>()) == 0)
    }
}
