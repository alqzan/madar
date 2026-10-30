import Foundation
import CryptoKit
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import MadarPrayer

struct MihbaraBook: Identifiable, Equatable {
    var id: UUID; var title: String; var author: String; var shelf: String; var pages: Int?; var page: Int?; var finished: Date?; var updated: Date
    var kind: String = "paper"; var format: String? = nil; var mediaID: UUID? = nil; var fileHash: String? = nil; var locatorJSON: Data? = nil
    var isbn13: String? = nil; var tocJSON: Data? = nil; var turathID: Int? = nil
    var language: String = "ar"
    var progress: Double? {
        if let paper = MihbaraReading.progress(page: page, pages: pages) { return paper }
        guard kind == "file", ["epub", "pdf", "pdfScanned"].contains(format ?? ""), let locatorJSON,
              case .object(let locator)? = try? JSONDecoder().decode(JSONValue.self, from: locatorJSON),
              case .object(let locations)? = locator["locations"],
              case .number(let value)? = locations["totalProgression"], value.isFinite else { return nil }
        return min(1, max(0, value))
    }
    var isReadableEPUB: Bool { kind == "file" && format == "epub" && mediaID != nil && fileHash?.count == 64 }
    var isReadablePDF: Bool { kind == "file" && ["pdf", "pdfScanned"].contains(format ?? "") && mediaID != nil && fileHash?.count == 64 }
}
struct MihbaraHighlight: Identifiable, Equatable {
    static let colors = ["yellow", "green", "rose"]
    var id: UUID; var locatorJSON: Data; var color: String; var pageLabel: String?
}
struct MihbaraHadith: Codable, Identifiable { var number: Int; var title: String; var text: String; var id: Int { number } }
struct MihbaraCollection: Codable {
    var collectionID: String; var editionID: String; var title: String; var source: String; var edition: String; var license: String; var licenseURL: String; var hadiths: [MihbaraHadith]
    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "nawawi40", withExtension: "json") else { throw DataError.invalidValue("نص الأربعين غير موجود") }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard value.collectionID == "nawawi40", value.hadiths.count == 42, Set(value.hadiths.map(\.number)) == Set(1...42), value.hadiths.allSatisfy({ !$0.text.isEmpty }) else { throw DataError.invalidValue("تعذر التحقق من مجموعة الحديث") }
        return value
    }
}
struct MihbaraHomeReading {
    var books: [MihbaraBook]; var collection: MihbaraCollection; var todayHadiths: [MihbaraHadith]; var readCount: Int; var completedToday: Int; var opensAfterFajr: Bool; var day: GregorianDay
    /// PDFs that became a flowing book: off the shelves (one book, not two), still opened through «الأصل».
    var originals: [MihbaraBook] = []
    /// Any book the room knows, the originals included (reader routes and «الأصل»).
    func book(_ id: UUID) -> MihbaraBook? { books.first { $0.id == id } ?? originals.first { $0.id == id } }
}
struct MihbaraMotivationCue: Identifiable {
    let id: String
    let title: String
    let message: String
    let source: String
    let actionTitle: String
    var bookID: UUID? = nil
    var hadithNumber: Int? = nil
}
@MainActor struct AppMihbaraService {
    unowned let app: AppSession
    var digits: MadarNumberFormatter { .init(style: app.string("core.numerals") == "western" ? .western : .hindi) }
    func load(at instant: Date? = nil) throws -> MihbaraHomeReading {
        guard !app.maintenanceInProgress else { throw BackupOperationError.busy }
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        let c = ModelContext(app.container), now = instant ?? app.prayerNow(), day = try DiaryLineRenderer.today(context: c, now: now)
        let storedBooks = try c.fetch(FetchDescriptor<Book>())
        var books: [MihbaraBook] = []
        for row in storedBooks where row.deletedAt == nil && row.mergedInto == nil {
            var page = row.currentPage
            if row.kind == "paper", let data = row.locatorJSON, let position = try? JSONDecoder().decode(PaperBookPosition.self, from: data) { page = position.page }
            books.append(MihbaraBook(id: row.id, title: row.title, author: row.author, shelf: row.shelf, pages: row.pages, page: page, finished: row.finishedAt, updated: row.updatedAt, kind: row.kind, format: row.format, mediaID: row.mediaID, fileHash: row.fileHash, locatorJSON: row.kind == "file" ? row.locatorJSON : nil, isbn13: row.isbn13, tocJSON: row.tocJSON, turathID: row.turathID, language: row.language))
        }
        books.sort { $0.updated == $1.updated ? $0.id.uuidString < $1.id.uuidString : $0.updated > $1.updated }
        // Owner, 25 Oct 2026 («الكتاب تكرر مرتين في مكتبتي»): a converted book stands for its PDF.
        var links = MihbaraConversions.links(app)
        let before = links
        let converted = Set(books.compactMap { MihbaraConversions.sourcePDFHash(of: $0, app: app, cache: &links) })
        if links != before { MihbaraConversions.save(links, app: app) }
        let originals = books.filter { $0.isReadablePDF && $0.fileHash.map(converted.contains) == true }
        books.removeAll { book in originals.contains { $0.id == book.id } }
        let collection = try MihbaraCollection.load()
        let rows = try c.fetch(FetchDescriptor<HadithProgress>()).filter { $0.collectionID == collection.collectionID && $0.deletedAt == nil && $0.mergedInto == nil }
        let read = Set(rows.filter { $0.readAt != nil }.map(\.number))
        let today = Set(try rows.filter { row in
            guard let readAt = row.readAt else { return false }
            return try DiaryLineRenderer.today(context: c, now: readAt) == day
        }.map(\.number))
        let numbers = MihbaraReading.nextHadith(numbers: collection.hadiths.map(\.number), read: read, readToday: today, count: Int(app.number("mihbara.wirdCount")))
        let prayer = try PrayerRepository(context: c), place = prayer.place(at: now)
        let civil = GregorianDay.containing(now, in: place.timeZone), options = prayer.calculationOptions(at: now)
        let fajr = PrayerTimesEngine.calculate(day: civil, place: place, options: options)?.fajr
        return .init(books: books, collection: collection, todayHadiths: collection.hadiths.filter { numbers.contains($0.number) }, readCount: read.count, completedToday: today.count, opensAfterFajr: fajr.map { now >= $0 } ?? false, day: day, originals: originals)
    }

    func hasLocalFile(for book: MihbaraBook) -> Bool {
        guard book.kind == "file", let mediaID = book.mediaID, let fileHash = book.fileHash else { return false }
        let context = ModelContext(app.container)
        let descriptor = FetchDescriptor<Media>(predicate: #Predicate { $0.id == mediaID })
        guard let media = try? context.fetch(descriptor).first else { return false }
        return media.deletedAt == nil && media.mergedInto == nil && media.kind == "doc"
            && media.state == "ok" && media.sha256 == fileHash
    }

    /// A missing local file can be restored only to its original, live book and only
    /// with the exact bytes recorded by its checksum and size.
    func bookRestorableFromFile(sha256: String, sizeBytes: Int, formats: Set<String>) throws -> MihbaraBook? {
        let context = ModelContext(app.container)
        let books = try context.fetch(FetchDescriptor<Book>())
        let matches = books.filter { $0.fileHash == sha256 && $0.mergedInto == nil }
        guard !matches.isEmpty else { return nil }
        guard matches.count == 1, let row = matches.first, row.deletedAt == nil,
              row.kind == "file", formats.contains(row.format ?? ""), let mediaID = row.mediaID else {
            throw DataError.invalidValue("هذا الكتاب عندك بالفعل، أو أُزيل سابقًا؛ لن يُضاف مكررًا.")
        }
        let descriptor = FetchDescriptor<Media>(predicate: #Predicate { $0.id == mediaID })
        guard let media = try context.fetch(descriptor).first,
              media.deletedAt == nil, media.mergedInto == nil, media.kind == "doc",
              media.state == "missing",
              media.sha256 == sha256, media.sizeBytes == sizeBytes else {
            throw DataError.invalidValue("الكتاب عندك وملفه موجود، أو لم يطابق الملف النسخة المحفوظة.")
        }
        let page = row.currentPage
        return MihbaraBook(id: row.id, title: row.title, author: row.author, shelf: row.shelf, pages: row.pages,
                           page: page, finished: row.finishedAt, updated: row.updatedAt, kind: row.kind, format: row.format,
                           mediaID: row.mediaID, fileHash: row.fileHash, locatorJSON: row.locatorJSON,
                           isbn13: row.isbn13, tocJSON: row.tocJSON, turathID: row.turathID, language: row.language)
    }

    /// RMI3: a book line comes only from the user's own page-linked note. When none exists,
    /// the home offers a short reading step and real progress instead of inventing a quotation.
    func motivationCues(for reading: MihbaraHomeReading, book: MihbaraBook?) throws -> [MihbaraMotivationCue] {
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        var cues: [MihbaraMotivationCue] = []
        if let book {
            let context = ModelContext(app.container)
            let notes = try context.fetch(FetchDescriptor<NotebookNote>())
                .filter { $0.targetID == book.id && $0.link == "page" && $0.deletedAt == nil && $0.mergedInto == nil && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .sorted { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
            if let note = notes.first {
                let text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let clipped = text.count <= 220 ? text : String(text.prefix(219)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
                let position = note.page.map { "صفحة " + digits.string($0) } ?? "من دفتر كتابك"
            let attribution = MadarInlineText.joined([book.title, book.author])
                cues.append(.init(
                    id: "note-\(note.id.uuidString)", title: "من هامشك", message: clipped,
                source: MadarInlineText.joined([attribution, position]), actionTitle: "افتح الكتاب", bookID: book.id
                ))
            }

            if let total = book.pages, total > 0, let current = book.page, current >= 0, current < total {
                let remaining = total - current
                cues.append(.init(
                    id: "progress-\(book.id.uuidString)", title: "أنت أقرب مما تظن",
                    message: MihbaraCopy.pagesLeft(remaining, digits) + " لتكمل «" + book.title + "»",
                    source: "موضعك: صفحة " + digits.string(current) + " من " + digits.string(total),
                    actionTitle: "واصل القراءة", bookID: book.id
                ))
            }

            let remainingPages = book.pages.flatMap { total in book.page.map { max(0, total - $0) } }
            let stepPages = remainingPages.map { min(5, max(1, $0)) } ?? 5
            let minutes = max(1, Int((Double(stepPages) * 1.4).rounded()))
            cues.append(.init(
                id: "step-\(book.id.uuidString)", title: "خطوة صغيرة تكفي",
                message: arabicCount(stepPages, ["صفحة واحدة", "صفحتان", "صفحات", "صفحة"], digits) + " فقط",
                source: "وقت تقريبي: " + PrayerCopy.minutes(minutes, digits: digits) + "، من موضعك المحفوظ",
                actionTitle: book.isReadableEPUB || book.isReadablePDF ? "ابدأ القراءة" : "افتح موضعك", bookID: book.id
            ))
        }

        if let hadith = reading.todayHadiths.first {
            cues.append(.init(
                id: "hadith-\(hadith.number)", title: "ورد السنّة",
                message: hadith.text,
                source: reading.collection.title + " · الحديث " + digits.string(hadith.number) + "\n" + reading.collection.edition,
                actionTitle: "افتح الحديث", hadithNumber: hadith.number
            ))
        }
        return cues
    }

    /// M6-V08: the book's live paragraph highlights, oldest first so a later one draws on top.
    func highlights(for bookID: UUID) throws -> [MihbaraHighlight] {
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        return try ModelContext(app.container).fetch(FetchDescriptor<Highlight>())
            .filter { $0.bookID == bookID && $0.deletedAt == nil && $0.mergedInto == nil && MihbaraHighlight.colors.contains($0.color) }
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
            .map { MihbaraHighlight(id: $0.id, locatorJSON: $0.locatorJSON, color: $0.color, pageLabel: $0.pageLabel) }
    }

    func epubData(for book: MihbaraBook) throws -> Data {
        try Self.verifiedBookData(container: app.container, for: book, allowedFormats: ["epub"])
    }

    func pdfData(for book: MihbaraBook) throws -> Data {
        try Self.verifiedBookData(container: app.container, for: book, allowedFormats: ["pdf", "pdfScanned"])
    }

    /// The same checked read off the main actor, for a search that walks every book: reading and hashing a large file must not freeze the screen.
    func readableBookData(for book: MihbaraBook) async -> Data? {
        let container = app.container, isEPUB = book.isReadableEPUB
        return await Task.detached(priority: .userInitiated) {
            try? Self.verifiedBookData(container: container, for: book, allowedFormats: isEPUB ? ["epub"] : ["pdf", "pdfScanned"])
        }.value
    }

    nonisolated private static func verifiedBookData(container: ModelContainer, for book: MihbaraBook, allowedFormats: Set<String>) throws -> Data {
        guard book.kind == "file", allowedFormats.contains(book.format ?? ""),
              let mediaID = book.mediaID, let expectedHash = book.fileHash, expectedHash.count == 64 else {
            throw DataError.invalidValue("هذا الكتاب لا يملك ملفًا صالحًا للقراءة")
        }
        let context = ModelContext(container)
        let books = try context.fetch(FetchDescriptor<Book>())
        guard let currentBook = books.first(where: { $0.id == book.id && $0.deletedAt == nil && $0.mergedInto == nil }),
              currentBook.kind == "file", allowedFormats.contains(currentBook.format ?? ""),
              currentBook.mediaID == mediaID, currentBook.fileHash == expectedHash else { throw DataError.invalidValue("تغيّر ملف الكتاب؛ افتح مكتبته مجددًا") }
        let mediaRows = try context.fetch(FetchDescriptor<Media>())
        if let media = mediaRows.first(where: { $0.id == mediaID && $0.deletedAt == nil && $0.mergedInto == nil }), media.state == "missing" {
            // RD4: a backup restored on another device may leave a large book file out.
            throw DataError.invalidValue(currentBook.turathID != nil ? "ملف هذا الكتاب لم يدخل النسخة الاحتياطية. نزّله من تراث مجددًا." : "ملف هذا الكتاب لم يدخل النسخة الاحتياطية. استورد الملف الأصلي مجددًا.")
        }
        guard let media = mediaRows.first(where: { $0.id == mediaID && $0.deletedAt == nil && $0.mergedInto == nil }),
              media.kind == "doc", media.state == "ok", let data = media.data,
              data.count == media.sizeBytes, data.count <= 500 * 1024 * 1024,
              media.sha256 == expectedHash,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expectedHash else { throw DataError.invalidValue("تعذر التحقق من ملف الكتاب المحلي") }
        return data
    }
}

/// Owner, 30 Oct 2026: the book on the stand is the book «أكمل القراءة» means everywhere (the card, the Siri phrase, the widget, the lobby).
/// The choice is a per-device convenience kept in defaults, so it survives a relaunch; it is a pick among books on «أقرؤها» only.
enum MihbaraStand {
    static let key = "mihbara.standBookID"
    static func savedID(_ defaults: UserDefaults = .standard) -> UUID? { defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) }
    static func save(_ id: UUID?, _ defaults: UserDefaults = .standard) { defaults.set(id?.uuidString, forKey: key) }
    /// The saved book while it is still being read, else the first book on «أقرؤها».
    static func pick(from books: [MihbaraBook], preferred: UUID? = nil, _ defaults: UserDefaults = .standard) -> MihbaraBook? {
        let reading = books.filter { $0.shelf == "reading" }
        return reading.first { $0.id == preferred } ?? reading.first { $0.id == savedID(defaults) } ?? reading.first
    }
}
