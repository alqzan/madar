import Foundation
import PDFKit
import SwiftUI
#if os(iOS)
import ReadiumShared
#endif
import MadarCore
import MadarDesign

/// Owner, 30 Oct 2026: «البحث في نصوص مكتبتك كلها». The library search matched titles and authors only; this looks
/// inside the text of every readable book on the device. EPUBs use Readium's own search service (diacritics and case
/// ignored); PDFs use their embedded text through PDFKit. Nothing is indexed or stored: each search reads the local
/// files, a few results per book, and a tap opens the reader at the match.
struct MihbaraTextHit: Identifiable, Sendable {
    let id = UUID()
    let bookID: UUID
    let title: String
    let before: String, match: String, after: String
    var locatorJSON: String? = nil
    var pdfPage: Int? = nil
}

struct MihbaraTextSearchResult {
    var hits: [MihbaraTextHit] = []
    var incompleteBooks: [MihbaraBook] = []
    var completedBooks = 0
}

@MainActor enum MihbaraLibrarySearch {
    nonisolated static let perBook = 3, total = 60

    /// A file can belong in a text search even when a restore has left its local copy unavailable.
    static func supportsSearch(_ book: MihbaraBook) -> Bool {
        book.kind == "file" && ["epub", "pdf", "pdfScanned"].contains(book.format ?? "")
    }

    static func search(_ query: String, in books: [MihbaraBook], service: AppMihbaraService, progress: (Int) -> Void) async throws -> MihbaraTextSearchResult {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = MihbaraTextSearchResult()
        guard needle.count >= 2 else { return result }
        for (index, book) in books.filter(supportsSearch).enumerated() {
            try Task.checkCancellation()
            guard result.hits.count < total else { break }
            progress(index + 1)
            let matches: Matches<MihbaraTextHit>
            if book.format == "epub" {
                matches = await epub(needle, book, service)
            } else if let data = await service.readableBookData(for: book) {
                try Task.checkCancellation()
                matches = await pdf(needle, book, data)
            } else {
                matches = .init(complete: false)
            }
            try Task.checkCancellation()
            result.hits += matches.hits.prefix(total - result.hits.count)
            if matches.complete { result.completedBooks += 1 }
            else { result.incompleteBooks.append(book) }
        }
        return result
    }

    private struct Matches<Hit: Sendable>: Sendable {
        var hits: [Hit] = []
        var complete = true
    }

    #if os(iOS)
    private static func epub(_ needle: String, _ book: MihbaraBook, _ service: AppMihbaraService) async -> Matches<MihbaraTextHit> {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("MadarSearch-" + UUID().uuidString).appendingPathExtension("epub")
        defer { try? FileManager.default.removeItem(at: file) }
        // Release the file bytes before opening the publication for search.
        guard await writeBook(book, service, to: file), !Task.isCancelled,
              let publication = try? await MihbaraEPUBLoader.open(at: file) else { return .init(complete: false) }
        defer { publication.close() }
        guard case .success(let iterator) = await publication.search(query: needle, options: SearchOptions(caseSensitive: false, diacriticSensitive: false)) else {
            return .init(complete: false)
        }
        var hits: [MihbaraTextHit] = []
        while hits.count < perBook, !Task.isCancelled {
            switch await iterator.next() {
            case .failure:
                return .init(hits: hits, complete: false)
            case .success(let page):
                guard let page, !page.locators.isEmpty else { return .init(hits: hits) }
                for locator in page.locators.prefix(perBook - hits.count) {
                    hits.append(.init(bookID: book.id, title: book.title, before: tail(locator.text.before), match: locator.text.highlight ?? needle,
                                      after: head(locator.text.after), locatorJSON: try? locator.jsonString()))
                }
            }
        }
        return .init(hits: hits)
    }

    private static func writeBook(_ book: MihbaraBook, _ service: AppMihbaraService, to file: URL) async -> Bool {
        guard let data = await service.readableBookData(for: book) else { return false }
        return await writeBookData(data, to: file)
    }

    @concurrent private static func writeBookData(_ data: Data, to file: URL) async -> Bool {
        guard !Task.isCancelled else { return false }
        return (try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
    }
    #else
    /// The Mac has no Readium: the book is unpacked by the Mac reader's own EPUB loader and each chapter's text searched with
    /// the same rules (case and diacritics ignored). A hit opens the reader at that chapter and its place in it.
    private static func epub(_ needle: String, _ book: MihbaraBook, _ service: AppMihbaraService) async -> Matches<MihbaraTextHit> {
        guard let data = await service.readableBookData(for: book) else { return .init(complete: false) }
        let found = await macMatches(needle, in: data, limit: perBook)
        return .init(hits: found.hits.map { .init(bookID: book.id, title: book.title, before: tail($0.before), match: $0.match,
                                                 after: head($0.after), locatorJSON: $0.locator) }, complete: found.complete)
    }

    private struct MacMatch: Sendable { let before: String, match: String, after: String, locator: String? }

    @concurrent private static func macMatches(_ needle: String, in data: Data, limit: Int) async -> Matches<MacMatch> {
        guard !Task.isCancelled, let publication = try? MacEPUB(data: data) else { return .init(complete: false) }
        defer { publication.discard() }
        var result = Matches<MacMatch>()
        for chapter in publication.spine.indices {
            guard result.hits.count < limit, !Task.isCancelled else { break }
            guard let html = try? String(contentsOf: publication.url(chapter: chapter), encoding: .utf8) else {
                result.complete = false
                continue
            }
            let text = MacEPUB.plainText(html)
            let length = Double(max(text.count, 1))
            var searchRange: Range<String.Index> = text.startIndex..<text.endIndex
            while result.hits.count < limit, !Task.isCancelled,
                  let hit = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
                let offset = Double(text.distance(from: text.startIndex, to: hit.lowerBound))
                let beforeStart = text.index(hit.lowerBound, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex
                let afterEnd = text.index(hit.upperBound, offsetBy: 60, limitedBy: text.endIndex) ?? text.endIndex
                result.hits.append(.init(before: String(text[beforeStart..<hit.lowerBound]), match: String(text[hit]),
                                         after: String(text[hit.upperBound..<afterEnd]),
                                         locator: publication.locatorJSON(chapter: chapter, progression: offset / length)))
                searchRange = hit.upperBound..<text.endIndex
            }
        }
        return result
    }

    #endif

    @concurrent private static func pdf(_ needle: String, _ book: MihbaraBook, _ data: Data) async -> Matches<MihbaraTextHit> {
        guard !Task.isCancelled, let document = PDFDocument(data: data), !document.isLocked, document.pageCount > 0 else {
            return .init(complete: false)
        }
        var hits: [MihbaraTextHit] = []
        for selection in document.findString(needle, withOptions: [.caseInsensitive, .diacriticInsensitive]) {
            if hits.count >= perBook || Task.isCancelled { break }
            guard let page = selection.pages.first, let text = page.string as NSString?,
                  case let range = selection.range(at: 0, on: page), range.location != NSNotFound, NSMaxRange(range) <= text.length else { continue }
            let start = max(0, range.location - 60), end = min(text.length, NSMaxRange(range) + 60)
            hits.append(.init(bookID: book.id, title: book.title,
                              before: tail(text.substring(with: NSRange(location: start, length: range.location - start))),
                              match: text.substring(with: range),
                              after: head(text.substring(with: NSRange(location: NSMaxRange(range), length: end - NSMaxRange(range)))),
                              pdfPage: document.index(for: page)))
        }
        return .init(hits: hits)
    }

    nonisolated private static func clean(_ text: String?) -> String { (text ?? "").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
    // The side touching the match keeps its space, so «الكتاب نافذة هادئة» never reads as one word.
    nonisolated private static func tail(_ text: String?) -> String { let t = clean(text); return t.count > 50 ? "…" + String(String(t.suffix(50)).drop { $0 == " " }) : t }
    nonisolated private static func head(_ text: String?) -> String { let t = clean(text); return t.count > 50 ? String(String(t.prefix(50)).reversed().drop { $0 == " " }.reversed()) + "…" : t }
}

/// Inside «مكتبتي»: an offer to look inside the books for the typed words, then the matches grouped by book.
struct MihbaraTextSearchSection: View {
    let query: String
    let books: [MihbaraBook]
    let service: AppMihbaraService
    let open: (MihbaraTextHit) -> Void
    @Environment(\.roomTheme) private var theme
    @State private var result: MihbaraTextSearchResult?
    @State private var searchedFor = ""
    @State private var running: Task<Void, Never>?
    @State private var progress = 0
    @State private var runID: UUID?

    private var searchable: [MihbaraBook] { books.filter(MihbaraLibrarySearch.supportsSearch) }
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        if trimmed.count >= 2 && !searchable.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if running != nil {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("أبحث في " + service.digits.string(progress) + " من " + service.digits.string(searchable.count)).font(MadarTypography.caption())
                        Spacer()
                        Button { stop() } label: { Text("أوقف").frame(minHeight: 44).contentShape(Rectangle()) }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-text-search-stop")
                    }
                } else if result == nil || searchedFor != trimmed {
                    Button { start() } label: {
                        Label("ابحث عن «" + trimmed + "» داخل نصوص كتبك", systemImage: "text.magnifyingglass").font(MadarTypography.body())
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.horizontal, 16)
                            .background(theme.surface, in: .rect(cornerRadius: 14))
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-text-search")
                }
                if let result, searchedFor == trimmed {
                    if running == nil, searchable.contains(where: { $0.format == "pdf" || $0.format == "pdfScanned" }),
                       result.completedBooks > 0 || !result.hits.isEmpty {
                        Text("يشمل بحث PDF النص المضمّن فقط. للصفحات المصوّرة، افتح الكتاب واختر البحث.")
                            .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            .accessibilityIdentifier("mihbara-text-search-pdf-scope")
                    }
                    if running == nil, !result.incompleteBooks.isEmpty {
                        incompleteNotice(result.incompleteBooks)
                    }
                    if running == nil, result.hits.isEmpty, result.completedBooks > 0 {
                        let scope = result.incompleteBooks.isEmpty ? "النصوص القابلة للبحث" : "الكتب التي اكتمل البحث فيها"
                        Text("لم أجد «" + trimmed + "» في " + scope + ".").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            .accessibilityIdentifier("mihbara-text-search-none")
                    }
                    ForEach(result.hits) { hit in
                        Button { open(hit) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(hit.pdfPage.map { hit.title + "، صفحة " + service.digits.string($0 + 1) } ?? hit.title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                                Text("\(Text(hit.before))\(Text(hit.match).bold().foregroundStyle(theme.accent))\(Text(hit.after))")
                                    .font(.custom("Amiri-Regular", size: 16, relativeTo: .body)).lineLimit(3).multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14).background(theme.surface, in: .rect(cornerRadius: 14))
                        }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-text-hit")
                    }
                }
            }
            .onDisappear { stop() }
            .onChange(of: trimmed) { _, _ in stop(); result = nil }
        }
    }

    private func incompleteNotice(_ books: [MihbaraBook]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let book = books.first, books.count == 1 {
                Text("تعذّر إكمال البحث في «\(book.title)».")
                    .accessibilityIdentifier("mihbara-text-search-incomplete")
            } else {
                DisclosureGroup("كتب تعذّر إكمال البحث فيها") {
                    ForEach(books) { book in
                        Text(book.title).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .accessibilityIdentifier("mihbara-text-search-incomplete")
            }
            Button("أعد البحث", action: start)
                .frame(minHeight: 44)
                .buttonStyle(.madarPlain)
                .foregroundStyle(theme.accent)
                .accessibilityIdentifier("mihbara-text-search-retry")
        }
        .font(MadarTypography.caption())
        .foregroundStyle(theme.secondaryInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .background(theme.surface, in: .rect(cornerRadius: 14))
    }

    private func stop() {
        runID = nil
        running?.cancel()
        running = nil
    }

    private func start() {
        let needle = trimmed, id = UUID(), books = searchable
        progress = 0; runID = id
        running = Task {
            // A stopped search that is still unwinding never clears the flag of a newer one.
            defer { if runID == id { running = nil; runID = nil } }
            guard let found = try? await MihbaraLibrarySearch.search(needle, in: books, service: service, progress: {
                if runID == id { progress = $0 }
            }), runID == id, !Task.isCancelled else { return }
            result = found
            searchedFor = needle
        }
    }
}
