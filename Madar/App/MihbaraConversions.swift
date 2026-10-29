import Foundation
import Observation
import UIKit
import MadarCore
import MadarData
import MadarCommands

/// Owner, 25 Oct 2026: «اول ما احمل بي دي اف يقولي ترا بحوله لك ولي انا الخيار ولا يخليني اقعد بنفس المكان
/// اقدر اتنقل بالتطبيق». A PDF converts while the person moves around the app; the result joins the library
/// on the PDF's shelf as the same book, and the PDF stays its original («الأصل»), not a second copy.
private struct PDFConversionCheckpointManifest: Codable {
    /// Bump when page extraction or its saved representation changes.
    var version: Int
    var sourceHash: String
    var language: String
    var totalPages: Int
    var completedPages: Int
}

private struct PDFConversionCheckpointPage: Codable {
    var index: Int
    var text: String
    var optical: Bool
    var unreliable: Bool
    var label: String?
    var image: Data?
    var blank: Bool

    init(index: Int, page: PDFBookEPUB.Page) {
        self.index = index; text = page.text; optical = page.optical; unreliable = page.unreliable
        label = page.label; image = page.image; blank = page.blank
    }

    var page: PDFBookEPUB.Page {
        PDFBookEPUB.Page(text: text, optical: optical, unreliable: unreliable, label: label, image: image, blank: blank)
    }
}

private struct PDFConversionLoadedCheckpoint {
    var manifest: PDFConversionCheckpointManifest
    var pages: [PDFBookEPUB.Page]
}

@MainActor @Observable final class MihbaraConversions {
    static let shared = MihbaraConversions()

    struct Job: Equatable, Identifiable {
        enum State: Equatable {
            case running, assembling, staging, staged, canceling, committing, saving, finished(UUID?), failed(String)

            var isActive: Bool {
                switch self {
                case .running, .assembling, .staging, .staged, .canceling, .committing, .saving: true
                case .finished, .failed: false
                }
            }

            var isCancellable: Bool {
                switch self {
                case .running, .assembling, .staging, .staged, .committing: true
                case .canceling, .saving, .finished, .failed: false
                }
            }
        }
        let id: UUID
        let title: String
        var done = 0, total = 0
        var state = State.running
        var summary: PDFBookEPUB.Summary?
        var started = Date()
        /// Pages already read when this run began (a resumed checkpoint), so the pace counts only this run.
        var startDone = 0

        /// Seconds left at the pace so far, once a few pages have been read.
        var secondsLeft: Int? {
            guard state == .running, done - startDone >= 5, total > done else { return nil }
            return Int((Date().timeIntervalSince(started) / Double(done - startDone) * Double(total - done)).rounded(.up))
        }
    }

    private(set) var jobs: [Job] = []
    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// Leaving the app mid-conversion asks iOS for the time it allows, instead of stopping at once.
    private var background: [UUID: UIBackgroundTaskIdentifier] = [:]
    /// Called after a converted book joins the library, so an open room reloads.
    var onFinished: (() -> Void)?

    func job(for bookID: UUID) -> Job? { jobs.first { $0.id == bookID } }

    func start(_ book: MihbaraBook, app: AppSession) {
        guard job(for: book.id)?.state.isActive != true else { return }
        jobs.removeAll { $0.id == book.id }
        jobs.append(Job(id: book.id, title: book.title))
        background[book.id] = UIApplication.shared.beginBackgroundTask(withName: "pdf-conversion") { [weak self] in
            MainActor.assumeIsolated { self?.endBackground(book.id) }
        }
        Self.setPending(book.id, true, app: app)
        tasks[book.id] = Task { [weak self] in await self?.run(book, app: app) }
    }

    func cancel(_ bookID: UUID, app: AppSession) {
        guard job(for: bookID)?.state.isCancellable == true else { return }
        update(bookID) { $0.state = .canceling }
        tasks[bookID]?.cancel()
        Self.setPending(bookID, false, app: app)
        Self.removeCheckpoint(bookID, app: app)
    }

    /// A conversion stopped by closing the app resumes after its last completed page.
    func resume(_ books: [MihbaraBook], app: AppSession) {
        let pending = Self.pending(app)
        guard !pending.isEmpty else { return }
        let byID = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in pending {
            if job(for: id)?.state.isActive == true { continue }
            guard let book = byID[id], book.isReadablePDF else {
                Self.setPending(id, false, app: app)
                Self.removeCheckpoint(id, app: app)
                continue
            }
            if job(for: id) == nil { start(book, app: app) }
        }
    }

    func dismiss(_ bookID: UUID) { if job(for: bookID)?.state.isActive != true { jobs.removeAll { $0.id == bookID } } }

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
            try Task.checkCancellation()
            guard authorized(app) else { throw DataError.authenticationFailed }
            let service = AppMihbaraService(app: app), stagingID = UUID()
            update(book.id) { $0.state = .staging }
            let inspection = try await service.stageEPUB(file, id: stagingID)
            defer { EPUBBookFiles.discard(id: stagingID, root: app.bookStagingDirectory) }

            update(book.id) { $0.state = .staged }
#if DEBUG
            // Deterministically exercise the cancel window after staging and before the durable import.
            if UUID(uuidString: ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"] ?? "") != nil,
               let milliseconds = Int(ProcessInfo.processInfo.environment["MADAR_UI_PDF_CONVERSION_STAGED_HOLD_MS"] ?? ""),
               milliseconds > 0, milliseconds <= 30_000 {
                try? await Task.sleep(for: .milliseconds(milliseconds))
            }
#endif
            // Yield once so a pending «إيقاف» tap can cancel and discard this staged copy before saving it.
            await Task.yield()
            try Task.checkCancellation()
            guard authorized(app) else { throw DataError.authenticationFailed }

            update(book.id) { $0.state = .committing }
            await Task.yield()
            try Task.checkCancellation()
            guard authorized(app) else { throw DataError.authenticationFailed }
            update(book.id) { $0.state = .saving }
            let newID: UUID?
            do {
                let id = UUID()
                try await service.confirmEPUB(inspection, bookID: id, commandID: UUID(), title: book.title, author: book.author,
                                              language: book.language, shelf: book.shelf)
                if let hash = book.fileHash { Self.link(epub: inspection.sha256, toPDF: hash, app: app) }
                newID = id
            } catch DataError.invalidValue(let message) where message.contains("عندك بالفعل") {
                newID = nil   // Converted before: the same bytes are already in the library.
            }
            Self.setPending(book.id, false, app: app)
            Self.removeCheckpoint(book.id, app: app)
            update(book.id) { $0.state = .finished(newID); $0.summary = summary }
            onFinished?()
        } catch is CancellationError {
            jobs.removeAll { $0.id == book.id }
            Self.setPending(book.id, false, app: app)
            Self.removeCheckpoint(book.id, app: app)
        } catch DataError.authenticationFailed {
            // Locked mid-way: keep it pending with its checkpoint; the shelf resumes it after the next unlock.
            jobs.removeAll { $0.id == book.id }
            tasks[book.id] = nil; endBackground(book.id)
            return
        } catch {
            update(book.id) { $0.state = .failed("تعذّر تحويل «\(book.title)». يبقى PDF كما هو وتقرؤه بصفحاته.") }
        }
        Self.setPending(book.id, false, app: app)
        tasks[book.id] = nil; endBackground(book.id)
    }

    /// Reads every page (embedded text first, on-device OCR otherwise) and writes the EPUB to a private folder.
    private func convert(_ book: MihbaraBook, app: AppSession) async throws -> (URL, PDFBookEPUB.Summary) {
        guard authorized(app) else { throw DataError.authenticationFailed }
        let bytes = try AppMihbaraService(app: app).pdfData(for: book)
        let reader = PDFBookTextReader(data: bytes, language: book.language)
        let total = try await reader.pageCount()
        update(book.id) { $0.total = total }
        guard let sourceHash = book.fileHash else { throw DataError.invalidValue("هذا الكتاب لا يملك ملفًا صالحًا للقراءة") }
        var checkpoint = try Self.loadCheckpoint(bookID: book.id, sourceHash: sourceHash, language: book.language, total: total, app: app)
        var pages = checkpoint.pages
        var pictures = pages.filter { $0.image != nil }.count
        let checkpointDirectory = Self.checkpointFolder(book.id, app: app)
        update(book.id) { [count = pages.count] in $0.done = count; $0.startDone = count; $0.started = Date() }
#if DEBUG
        if !pages.isEmpty,
           UUID(uuidString: ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"] ?? "") != nil,
           let milliseconds = Int(ProcessInfo.processInfo.environment["MADAR_UI_PDF_CONVERSION_RESUME_HOLD_MS"] ?? ""),
           milliseconds > 0, milliseconds <= 30_000 {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            try Task.checkCancellation()
        }
#endif
        /// A page without words keeps its picture (cover, basmala, ornament) instead of a «not extracted» note.
        func picture(_ index: Int) async throws -> (jpeg: Data?, blank: Bool) {
            guard pictures < PDFBookEPUB.maximumPictures else { return (jpeg: nil, blank: false) }
            let result: (jpeg: Data?, blank: Bool) = (try? await reader.pagePicture(at: index)) ?? (jpeg: nil, blank: false)
            if result.jpeg != nil { pictures += 1 }
            return result
        }
        for index in pages.count..<total {
            let label = try await reader.pageLabel(at: index)
            let completedPage: PDFBookEPUB.Page
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
                    completedPage = cover && shot.jpeg != nil ? .init(text: "", optical: true, unreliable: false, label: label, image: shot.jpeg)
                                                               : .init(page, label: label, image: shot.jpeg, blank: shot.blank)
                } else { completedPage = .init(page, label: label) }
            }
            catch is CancellationError { throw CancellationError() }
            // A page OCR cannot read becomes its picture, or an honest gap with its number, not a failed book.
            catch {
                let shot = try await picture(index)
                completedPage = .init(text: "", optical: false, unreliable: true, label: label, image: shot.jpeg, blank: shot.blank)
            }
            try Task.checkCancellation()
            guard authorized(app) else { throw DataError.authenticationFailed }
            try Self.savePage(completedPage, index: index, manifest: &checkpoint.manifest, directory: checkpointDirectory)
            pages.append(completedPage)
            update(book.id) { $0.done = index + 1 }
#if DEBUG
            if UUID(uuidString: ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"] ?? "") != nil,
               Int(ProcessInfo.processInfo.environment["MADAR_UI_PDF_CONVERSION_HOLD_AFTER_PAGE"] ?? "") == index + 1,
               let milliseconds = Int(ProcessInfo.processInfo.environment["MADAR_UI_PDF_CONVERSION_PAGE_HOLD_MS"] ?? ""),
               milliseconds > 0, milliseconds <= 30_000 {
                try? await Task.sleep(for: .milliseconds(milliseconds))
                try Task.checkCancellation()
            }
#endif
        }
        let outline = try await reader.outline()
        update(book.id) { $0.state = .assembling }
        let title = book.title, author = book.author, language = book.language, hash = sourceHash
        let pagesToBuild = pages
        let summary = PDFBookEPUB.summary(pagesToBuild)
        let epub = try await Task.detached(priority: .userInitiated) {
#if DEBUG
            if UUID(uuidString: ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"] ?? "") != nil,
               let milliseconds = Int(ProcessInfo.processInfo.environment["MADAR_UI_PDF_CONVERSION_BUILD_HOLD_MS"] ?? ""),
               milliseconds > 0, milliseconds <= 30_000 {
                try? await Task.sleep(for: .milliseconds(milliseconds))
            }
#endif
            return try PDFBookEPUB.build(title: title, author: author, language: language, sourceHash: hash, pages: pagesToBuild, outline: outline)
        }.value
        try Task.checkCancellation()
        let file = checkpointDirectory.appendingPathComponent("converted.epub")
        do {
            try epub.write(to: file, options: [.atomic, .completeFileProtection])
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        return (file, summary)
    }

    // MARK: - Converted book ↔ original PDF

    private static func folder(_ app: AppSession) -> URL {
        app.bookStagingDirectory.deletingLastPathComponent().appendingPathComponent("PDFConversions")
    }
    private static func checkpointRoot(_ app: AppSession) -> URL {
        folder(app).appendingPathComponent("checkpoints", isDirectory: true)
    }
    private static func checkpointFolder(_ bookID: UUID, app: AppSession) -> URL {
        checkpointRoot(app).appendingPathComponent(bookID.uuidString.lowercased(), isDirectory: true)
    }
    private static func manifestURL(_ directory: URL) -> URL { directory.appendingPathComponent("manifest.json") }
    private static func pageURL(_ index: Int, directory: URL) -> URL {
        directory.appendingPathComponent(String(format: "page-%06d.json", index))
    }
    private static let checkpointVersion = 1

    private static func preparePrivateDirectory(_ directory: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.complete])
        try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var writableDirectory = directory
        try writableDirectory.setResourceValues(values)
    }

    private static func removeCheckpoint(_ bookID: UUID, app: AppSession) {
        let root = checkpointRoot(app), directory = checkpointFolder(bookID, app: app)
        guard directory.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func writeManifest(_ manifest: PDFConversionCheckpointManifest, directory: URL) throws {
        try JSONEncoder().encode(manifest).write(to: manifestURL(directory), options: [.atomic, .completeFileProtection])
    }

    private static func loadCheckpoint(bookID: UUID, sourceHash: String, language: String, total: Int,
                                       app: AppSession) throws -> PDFConversionLoadedCheckpoint {
        let directory = checkpointFolder(bookID, app: app)
        try preparePrivateDirectory(checkpointRoot(app))
        if FileManager.default.fileExists(atPath: directory.path) {
            try preparePrivateDirectory(directory)
            // A process can die after EPUB assembly but before the shelf transaction. Rebuild it from
            // the page checkpoints rather than leaving a second unmanaged copy beside them.
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("converted.epub"))
            if let data = try? Data(contentsOf: manifestURL(directory)),
               var manifest = try? JSONDecoder().decode(PDFConversionCheckpointManifest.self, from: data),
               manifest.version == checkpointVersion, manifest.sourceHash == sourceHash,
               manifest.language == language, manifest.totalPages == total,
               (0...total).contains(manifest.completedPages) {
                var pages: [PDFBookEPUB.Page] = []
                for index in 0..<manifest.completedPages {
                    guard let data = try? Data(contentsOf: pageURL(index, directory: directory)),
                          let record = try? JSONDecoder().decode(PDFConversionCheckpointPage.self, from: data),
                          record.index == index else { break }
                    pages.append(record.page)
                }
                if manifest.completedPages != pages.count {
                    manifest.completedPages = pages.count
                    try writeManifest(manifest, directory: directory)
                }
                for name in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] where name.hasPrefix("page-") {
                    guard let index = Int(name.dropFirst(5).split(separator: ".").first ?? ""), index < pages.count else {
                        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)); continue
                    }
                }
                return PDFConversionLoadedCheckpoint(manifest: manifest, pages: pages)
            }
        }
        removeCheckpoint(bookID, app: app)
        try preparePrivateDirectory(directory)
        let manifest = PDFConversionCheckpointManifest(version: checkpointVersion, sourceHash: sourceHash,
                                                       language: language, totalPages: total, completedPages: 0)
        try writeManifest(manifest, directory: directory)
        return PDFConversionLoadedCheckpoint(manifest: manifest, pages: [])
    }

    private static func savePage(_ page: PDFBookEPUB.Page, index: Int,
                                 manifest: inout PDFConversionCheckpointManifest, directory: URL) throws {
        guard manifest.completedPages == index else { throw CocoaError(.fileWriteUnknown) }
        let record = PDFConversionCheckpointPage(index: index, page: page)
        try JSONEncoder().encode(record).write(to: pageURL(index, directory: directory), options: [.atomic, .completeFileProtection])
        manifest.completedPages = index + 1
        try writeManifest(manifest, directory: directory)
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
