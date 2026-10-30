import Foundation
import PDFKit
import SwiftUI
import ReadiumShared
import MadarCore
import MadarDesign

/// Owner, 30 Oct 2026: «البحث في نصوص مكتبتك كلها». The library search matched titles and authors only; this looks
/// inside the text of every readable book on the device. EPUBs use Readium's own search service (diacritics and case
/// ignored); PDFs use their embedded text through PDFKit. Nothing is indexed or stored: each search reads the local
/// files, a few results per book, and a tap opens the reader at the match.
struct MihbaraTextHit: Identifiable {
    let id = UUID()
    let bookID: UUID
    let title: String
    let before: String, match: String, after: String
    var locatorJSON: String? = nil
    var pdfPage: Int? = nil
}

@MainActor enum MihbaraLibrarySearch {
    nonisolated static let perBook = 3, total = 60

    static func search(_ query: String, in books: [MihbaraBook], service: AppMihbaraService, progress: (Int) -> Void) async -> [MihbaraTextHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { return [] }
        var hits: [MihbaraTextHit] = []
        for (index, book) in books.enumerated() where book.isReadableEPUB || book.isReadablePDF {
            if Task.isCancelled || hits.count >= total { break }
            progress(index + 1)
            if book.isReadableEPUB { hits += await epub(needle, book, service) }
            else if let data = try? service.pdfData(for: book) { hits += await pdf(needle, book, data) }
        }
        return Array(hits.prefix(total))
    }

    private static func epub(_ needle: String, _ book: MihbaraBook, _ service: AppMihbaraService) async -> [MihbaraTextHit] {
        guard let data = try? service.epubData(for: book) else { return [] }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("MadarSearch-" + UUID().uuidString).appendingPathExtension("epub")
        defer { try? FileManager.default.removeItem(at: file) }
        guard (try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil,
              let publication = try? await MihbaraEPUBLoader.open(at: file) else { return [] }
        defer { publication.close() }
        guard case .success(let iterator) = await publication.search(query: needle, options: SearchOptions(caseSensitive: false, diacriticSensitive: false)) else { return [] }
        defer { iterator.close() }
        var hits: [MihbaraTextHit] = []
        while hits.count < perBook, !Task.isCancelled, case .success(let page?) = await iterator.next() {
            for locator in page.locators where hits.count < perBook {
                hits.append(.init(bookID: book.id, title: book.title, before: tail(locator.text.before), match: locator.text.highlight ?? needle,
                                  after: head(locator.text.after), locatorJSON: try? locator.jsonString()))
            }
            if page.locators.isEmpty { break }
        }
        return hits
    }

    private static func pdf(_ needle: String, _ book: MihbaraBook, _ data: Data) async -> [MihbaraTextHit] {
        let found: [(page: Int, before: String, match: String, after: String)] = await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(data: data) else { return [] }
            var result: [(Int, String, String, String)] = []
            for selection in document.findString(needle, withOptions: [.caseInsensitive, .diacriticInsensitive]) {
                if result.count >= perBook || Task.isCancelled { break }
                guard let page = selection.pages.first, let text = page.string as NSString?,
                      case let range = selection.range(at: 0, on: page), range.location != NSNotFound, NSMaxRange(range) <= text.length else { continue }
                let start = max(0, range.location - 60), end = min(text.length, NSMaxRange(range) + 60)
                result.append((document.index(for: page), text.substring(with: NSRange(location: start, length: range.location - start)),
                               text.substring(with: range), text.substring(with: NSRange(location: NSMaxRange(range), length: end - NSMaxRange(range)))))
            }
            return result
        }.value
        return found.map { .init(bookID: book.id, title: book.title, before: tail($0.before), match: $0.match, after: head($0.after), pdfPage: $0.page) }  // 0-based, as the reader's `startPage` is
    }

    private static func clean(_ text: String?) -> String { (text ?? "").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
    // The side touching the match keeps its space, so «الكتاب نافذة هادئة» never reads as one word.
    private static func tail(_ text: String?) -> String { let t = clean(text); return t.count > 50 ? "…" + String(String(t.suffix(50)).drop { $0 == " " }) : t }
    private static func head(_ text: String?) -> String { let t = clean(text); return t.count > 50 ? String(String(t.prefix(50)).reversed().drop { $0 == " " }.reversed()) + "…" : t }
}

/// Inside «مكتبتي»: an offer to look inside the books for the typed words, then the matches grouped by book.
struct MihbaraTextSearchSection: View {
    let query: String
    let books: [MihbaraBook]
    let service: AppMihbaraService
    let open: (MihbaraTextHit) -> Void
    @Environment(\.roomTheme) private var theme
    @State private var hits: [MihbaraTextHit]?
    @State private var searchedFor = ""
    @State private var running: Task<Void, Never>?
    @State private var progress = 0
    @State private var runID: UUID?

    private var readable: [MihbaraBook] { books.filter { $0.isReadableEPUB || $0.isReadablePDF } }
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        if trimmed.count >= 2 && !readable.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if running != nil {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("أبحث في " + service.digits.string(progress) + " من " + service.digits.string(readable.count)).font(MadarTypography.caption())
                        Spacer()
                        Button("أوقف") { running?.cancel(); running = nil; runID = nil }.frame(minHeight: 44).buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-text-search-stop")
                    }
                } else if hits == nil || searchedFor != trimmed {
                    Button { start() } label: {
                        Label("ابحث عن «" + trimmed + "» داخل نصوص كتبك", systemImage: "text.magnifyingglass").font(MadarTypography.body())
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.horizontal, 16)
                            .background(theme.surface, in: .rect(cornerRadius: 14))
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-text-search")
                }
                if let hits, searchedFor == trimmed, running == nil {
                    if hits.isEmpty {
                        Text("لم أجد «" + trimmed + "» في نصوص كتبك.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            .accessibilityIdentifier("mihbara-text-search-none")
                    }
                    ForEach(hits) { hit in
                        Button { open(hit) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(hit.pdfPage.map { hit.title + "، صفحة " + service.digits.string($0 + 1) } ?? hit.title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                                (Text(hit.before) + Text(hit.match).bold().foregroundColor(theme.accent) + Text(hit.after))
                                    .font(.custom("Amiri-Regular", size: 16, relativeTo: .body)).lineLimit(3).multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14).background(theme.surface, in: .rect(cornerRadius: 14))
                        }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-text-hit")
                    }
                }
            }
            .onDisappear { running?.cancel() }
            // A new word stops the old search, so the offer to search for it appears at once.
            .onChange(of: trimmed) { _, _ in if running != nil { running?.cancel(); running = nil; runID = nil } }
        }
    }

    private func start() {
        let needle = trimmed, id = UUID()
        progress = 0; runID = id
        running = Task {
            let found = await MihbaraLibrarySearch.search(needle, in: readable, service: service) { if runID == id { progress = $0 } }
            // A stopped search that is still unwinding never clears the flag of a newer one.
            guard runID == id else { return }
            if !Task.isCancelled { hits = found; searchedFor = needle }
            running = nil; runID = nil
        }
    }
}
