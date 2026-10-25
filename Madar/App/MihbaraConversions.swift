import Foundation
import Observation
import UIKit
import MadarCore
import MadarData
import MadarCommands

/// Owner, 25 Oct 2026: «اول ما احمل بي دي اف يقولي ترا بحوله لك ولي انا الخيار ولا يخليني اقعد بنفس المكان
/// اقدر اتنقل بالتطبيق». A PDF converts while the person moves around the app; the result joins the library
/// on the PDF's shelf as the same book, and the PDF stays its original («الأصل»), not a second copy.
@MainActor @Observable final class MihbaraConversions {
    static let shared = MihbaraConversions()

    struct Job: Equatable, Identifiable {
        enum State: Equatable { case running, finished(UUID?), failed(String) }
        let id: UUID
        let title: String
        var done = 0, total = 0
        var state = State.running
        var summary: PDFBookEPUB.Summary?
    }

    private(set) var jobs: [Job] = []
    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// Leaving the app mid-conversion asks iOS for the time it allows, instead of stopping at once.
    private var background: [UUID: UIBackgroundTaskIdentifier] = [:]
    /// Called after a converted book joins the library, so an open room reloads.
    var onFinished: (() -> Void)?

    func job(for bookID: UUID) -> Job? { jobs.first { $0.id == bookID } }

    func start(_ book: MihbaraBook, app: AppSession) {
        guard job(for: book.id)?.state != .running else { return }
        jobs.removeAll { $0.id == book.id }
        jobs.append(Job(id: book.id, title: book.title))
        background[book.id] = UIApplication.shared.beginBackgroundTask(withName: "pdf-conversion") { [weak self] in
            MainActor.assumeIsolated { self?.endBackground(book.id) }
        }
        Self.setPending(book.id, true, app: app)
        tasks[book.id] = Task { [weak self] in await self?.run(book, app: app) }
    }

    func cancel(_ bookID: UUID, app: AppSession) {
        tasks[bookID]?.cancel(); tasks[bookID] = nil; endBackground(bookID)
        jobs.removeAll { $0.id == bookID }
        Self.setPending(bookID, false, app: app)
    }

    /// A conversion iOS stopped by closing the app starts again from the first page the next time the room
    /// opens, while its PDF is still on a shelf (pages are read again; nothing half-written is kept).
    func resume(_ books: [MihbaraBook], app: AppSession) {
        let pending = Self.pending(app)
        guard !pending.isEmpty else { return }
        for book in books where pending.contains(book.id) && book.isReadablePDF && job(for: book.id) == nil { start(book, app: app) }
        let known = Set(books.map(\.id))
        for id in pending where !known.contains(id) { Self.setPending(id, false, app: app) }
    }

    func dismiss(_ bookID: UUID) { if job(for: bookID)?.state != .running { jobs.removeAll { $0.id == bookID } } }

    private func endBackground(_ id: UUID) {
        guard let task = background.removeValue(forKey: id), task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    private func authorized(_ app: AppSession) -> Bool { app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized }

    private func run(_ book: MihbaraBook, app: AppSession) async {
        do {
            let (file, summary) = try await convert(book, app: app)
            defer { try? FileManager.default.removeItem(at: file) }
            guard authorized(app) else { throw DataError.authenticationFailed }
            let service = AppMihbaraService(app: app), stagingID = UUID()
            let newID: UUID?
            do {
                let inspection = try await service.stageEPUB(file, id: stagingID)
                let id = UUID()
                try await service.confirmEPUB(inspection, bookID: id, commandID: UUID(), title: book.title, author: book.author,
                                              language: book.language, shelf: book.shelf)
                if let hash = book.fileHash { Self.link(epub: inspection.sha256, toPDF: hash, app: app) }
                newID = id
            } catch DataError.invalidValue(let message) where message.contains("عندك بالفعل") {
                newID = nil   // Converted before: the same bytes are already in the library.
            }
            update(book.id) { $0.state = .finished(newID); $0.summary = summary }
            onFinished?()
        } catch is CancellationError {
        } catch {
            update(book.id) { $0.state = .failed("تعذّر تحويل «\(book.title)». يبقى PDF كما هو وتقرؤه بصفحاته.") }
        }
        if job(for: book.id)?.state != .running { Self.setPending(book.id, false, app: app) }
        tasks[book.id] = nil; endBackground(book.id)
    }

    /// Reads every page (embedded text first, on-device OCR otherwise) and writes the EPUB to a private folder.
    private func convert(_ book: MihbaraBook, app: AppSession) async throws -> (URL, PDFBookEPUB.Summary) {
        guard authorized(app) else { throw DataError.authenticationFailed }
        let bytes = try AppMihbaraService(app: app).pdfData(for: book)
        let reader = PDFBookTextReader(data: bytes, language: book.language)
        let total = try await reader.pageCount()
        update(book.id) { $0.total = total }
        var pages: [PDFBookEPUB.Page] = []
        var pictures = 0
        /// A page without words keeps its picture (cover, basmala, ornament) instead of a «not extracted» note.
        func picture(_ index: Int) async throws -> (jpeg: Data?, blank: Bool) {
            guard pictures < PDFBookEPUB.maximumPictures else { return (jpeg: nil, blank: false) }
            let result: (jpeg: Data?, blank: Bool) = (try? await reader.pagePicture(at: index)) ?? (jpeg: nil, blank: false)
            if result.jpeg != nil { pictures += 1 }
            return result
        }
        for index in 0..<total {
            let label = try await reader.pageLabel(at: index)
            do {
                var page = try await reader.page(at: index)
                // Garbled embedded Arabic: read the page image instead of showing broken words.
                if page.hasUnreliableArabicMapping, let optical = try? await reader.page(at: index, optical: true),
                   !optical.text.isEmpty { page = optical }
                let wordless = page.hasUnreliableArabicMapping || PDFBookEPUB.paragraphs(page.text).isEmpty
                // A scanned book's first page is its cover: keep it as a picture, not its OCR'd title and stamps.
                let cover = index == 0 && page.source == .optical
                if wordless || cover {
                    let shot = try await picture(index)
                    pages.append(cover && shot.jpeg != nil ? .init(text: "", optical: true, unreliable: false, label: label, image: shot.jpeg)
                                 : .init(page, label: label, image: shot.jpeg, blank: shot.blank))
                } else { pages.append(.init(page, label: label)) }
            }
            catch is CancellationError { throw CancellationError() }
            // A page OCR cannot read becomes its picture, or an honest gap with its number, not a failed book.
            catch {
                let shot = try await picture(index)
                pages.append(.init(text: "", optical: false, unreliable: true, label: label, image: shot.jpeg, blank: shot.blank))
            }
            try Task.checkCancellation()
            guard authorized(app) else { throw DataError.authenticationFailed }
            update(book.id) { $0.done = index + 1 }
        }
        let outline = try await reader.outline()
        let title = book.title, author = book.author, language = book.language, hash = book.fileHash ?? book.id.uuidString
        let epub = try await Task.detached(priority: .userInitiated) {
            try PDFBookEPUB.build(title: title, author: author, language: language, sourceHash: hash, pages: pages, outline: outline)
        }.value
        let folder = Self.folder(app)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(UUID().uuidString + ".epub")
        try epub.write(to: file, options: [.atomic, .completeFileProtection])
        return (file, PDFBookEPUB.summary(pages))
    }

    // MARK: - Converted book ↔ original PDF

    private static func folder(_ app: AppSession) -> URL {
        app.bookStagingDirectory.deletingLastPathComponent().appendingPathComponent("PDFConversions")
    }
    private static func linksURL(_ app: AppSession) -> URL { folder(app).appendingPathComponent("links.json") }

    /// EPUB file hash → source PDF hash (or "" for an EPUB that did not come from a PDF). A cache only:
    /// every entry is re-derivable from the EPUB's own identifier `urn:madar:pdf:<hash>`.
    private static func pendingURL(_ app: AppSession) -> URL { folder(app).appendingPathComponent("pending.json") }

    static func pending(_ app: AppSession) -> Set<UUID> {
        (try? JSONDecoder().decode(Set<UUID>.self, from: Data(contentsOf: pendingURL(app)))) ?? []
    }

    private static func setPending(_ id: UUID, _ on: Bool, app: AppSession) {
        var all = pending(app)
        guard all.contains(id) != on else { return }
        if on { all.insert(id) } else { all.remove(id) }
        try? FileManager.default.createDirectory(at: folder(app), withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: pendingURL(app), options: [.atomic, .completeFileProtection])
    }

    static func links(_ app: AppSession) -> [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: linksURL(app)))) ?? [:]
    }

    static func link(epub: String, toPDF pdf: String, app: AppSession) {
        var all = links(app); all[epub] = pdf; save(all, app: app)
    }

    static func save(_ links: [String: String], app: AppSession) {
        try? FileManager.default.createDirectory(at: folder(app), withIntermediateDirectories: true)
        try? JSONEncoder().encode(links).write(to: linksURL(app), options: [.atomic, .completeFileProtection])
    }

    /// The source PDF hash of a converted EPUB. Converted books are stored uncompressed, so the identifier
    /// is plain bytes in the file; the answer is cached per EPUB.
    static func sourcePDFHash(of book: MihbaraBook, app: AppSession, cache: inout [String: String]) -> String? {
        guard book.isReadableEPUB, let hash = book.fileHash else { return nil }
        if let known = cache[hash] { return known.isEmpty ? nil : known }
        var found = ""
        if let data = try? AppMihbaraService(app: app).epubData(for: book),
           let range = data.range(of: Data("urn:madar:pdf:".utf8)), data.count >= range.upperBound + 64,
           let text = String(data: data[range.upperBound..<range.upperBound + 64], encoding: .ascii),
           text.allSatisfy(\.isHexDigit) { found = text }
        cache[hash] = found
        return found.isEmpty ? nil : found
    }
}
