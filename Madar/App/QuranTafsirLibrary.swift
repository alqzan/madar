import Foundation
import Observation
import SwiftUI
import MadarCore
import MadarCommands
import MadarDesign
import MadarQuran

struct QuranTafsirLibraryBook: Identifiable, Equatable {
    let metadata: QuranTafsirBookMetadata
    let pageCount: Int
    let sizeBytes: Int?
    let isBundled: Bool

    var id: Int { metadata.bookID }
}

@MainActor @Observable
final class QuranTafsirLibrary {
    static let shared = QuranTafsirLibrary()

    private(set) var indexes: [Int: QuranTafsirIndex] = [:]
    private(set) var books: [QuranTafsirLibraryBook] = []
    private(set) var catalogue: [TurathCatalogueBook] = []
    private(set) var isLoadingLocal = false
    private(set) var isLoadingCatalogue = false
    private(set) var downloadingBookID: Int?
    private(set) var localErrorMessage: String?
    private(set) var catalogueErrorMessage: String?
    private(set) var operationErrorMessage: String?
    private(set) var operationFailureDescription: String?
    var errorMessages: [String] { [localErrorMessage, catalogueErrorMessage, operationErrorMessage].compactMap { $0 } }

    private let directory: URL
    private var didLoadLocal = false
    private var didLoadCatalogue = false
    private var localLoadTask: Task<Void, Never>?

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = support.appendingPathComponent("QuranTafsir", isDirectory: true)
        }
    }

    func index(for bookID: Int) -> QuranTafsirIndex? { indexes[bookID] }

    func loadLocal() async {
        guard !didLoadLocal else { return }
        if let localLoadTask {
            await localLoadTask.value
            return
        }
        let task = Task { @MainActor in await performLocalLoad() }
        localLoadTask = task
        await task.value
    }

    private func performLocalLoad() async {
        isLoadingLocal = true
        defer {
            isLoadingLocal = false
            localLoadTask = nil
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let catalog = try QuranResources.catalog()
            let saadi = try await Task.detached(priority: .userInitiated) {
                try QuranTafsirIndex.bundledSaadi(catalog: catalog)
            }.value

            var nextIndexes = [saadi.metadata.bookID: saadi]
            var nextBooks = [QuranTafsirLibraryBook(metadata: saadi.metadata, pageCount: 2_175, sizeBytes: nil, isBundled: true)]
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            for file in files where file.pathExtension == "tafsir" {
                guard let data = try? Data(contentsOf: file),
                      let index = try? JSONDecoder().decode(QuranTafsirIndex.self, from: data),
                      index.metadata.bookID != saadi.metadata.bookID else { continue }
                nextIndexes[index.metadata.bookID] = index
                nextBooks.append(.init(
                    metadata: index.metadata,
                    pageCount: Set(index.passages.flatMap { $0.pages.map(\.id) }).count,
                    sizeBytes: data.count,
                    isBundled: false
                ))
            }
#if DEBUG
            if ProcessInfo.processInfo.environment["MADAR_UI_TAFSIR_FIXTURE"] == "secondBook" {
                let metadata = QuranTafsirBookMetadata(
                    bookID: 1_503,
                    title: "تفسير ابن كثير - ط ابن الجوزي",
                    author: "إسماعيل بن عمر ابن كثير",
                    turathURL: "https://app.turath.io/book/1503",
                    shamelaURL: "https://shamela.ws/book/1503"
                )
                let passages = [
                    QuranTafsirPassage(
                        id: "1503-194-194-1", surahID: 2, firstAyahID: 194, lastAyahID: 194,
                        pages: [.init(id: 1, volume: "2", printedPage: "67")],
                        text: "شرح الآية ١٨٧ من سورة البقرة في تفسير ابن كثير."
                    ),
                    QuranTafsirPassage(
                        id: "1503-195-195-2", surahID: 2, firstAyahID: 195, lastAyahID: 195,
                        pages: [.init(id: 2, volume: "2", printedPage: "67")],
                        text: "شرح الآية ١٨٨ من سورة البقرة في تفسير ابن كثير."
                    ),
                ]
                let index = QuranTafsirIndex(metadata: metadata, passages: passages)
                nextIndexes[metadata.bookID] = index
                nextBooks.append(.init(metadata: metadata, pageCount: 2, sizeBytes: 1_024, isBundled: false))
            }
#endif
            indexes = nextIndexes
            books = nextBooks.sorted { $0.metadata.bookID < $1.metadata.bookID }
            didLoadLocal = true
            localErrorMessage = nil
        } catch {
            localErrorMessage = "تعذّر فتح مكتبة التفاسير على هذا الجهاز. حاول مرة أخرى."
        }
    }

    func loadCatalogue() async {
        guard !didLoadCatalogue, !isLoadingCatalogue else { return }
        isLoadingCatalogue = true
        defer { isLoadingCatalogue = false }
        do {
            catalogue = try await MihbaraTurathSource.catalogue().filter { $0.categoryID == 3 }
            didLoadCatalogue = true
            catalogueErrorMessage = nil
        } catch {
            catalogueErrorMessage = "تعذّر الوصول إلى فهرس تراث. تحقق من الاتصال ثم حاول مرة أخرى."
        }
    }

    func download(_ book: TurathCatalogueBook) async {
        guard downloadingBookID == nil, book.id > 0 else { return }
        downloadingBookID = book.id
        operationErrorMessage = nil
        operationFailureDescription = nil
        defer { downloadingBookID = nil }
        do {
            let data = try await MihbaraTurathSource.fetch(book)
            let metadata = QuranTafsirBookMetadata(
                bookID: book.id,
                title: book.title,
                author: book.author,
                turathURL: book.link.absoluteString,
                shamelaURL: book.shamelaLink.absoluteString
            )
            let quran = try QuranResources.catalog()
            let index = try await Task.detached(priority: .userInitiated) {
                try QuranTafsirIndex.decodeTurathJSON(data, metadata: metadata, catalog: quran)
            }.value
            guard !index.passages.isEmpty else { throw QuranTafsirIndexError.noVerseSections }
            let indexedData = try await Task.detached(priority: .utility) {
                try JSONEncoder().encode(index)
            }.value
            let destination = fileURL(for: book.id)
            try indexedData.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            indexes[book.id] = index
            books.removeAll { $0.id == book.id }
            books.append(.init(
                metadata: index.metadata,
                pageCount: Set(index.passages.flatMap { $0.pages.map(\.id) }).count,
                sizeBytes: indexedData.count,
                isBundled: false
            ))
            books.sort { $0.metadata.bookID < $1.metadata.bookID }
            operationErrorMessage = nil
        } catch TurathError.tooLarge {
            operationErrorMessage = "حجم هذا الكتاب أكبر من الحد المتاح للتنزيل."
        } catch is CancellationError {
            operationErrorMessage = "أُوقف التنزيل قبل حفظ الكتاب."
        } catch {
            operationFailureDescription = String(reflecting: error)
            operationErrorMessage = "تعذّر تنزيل هذا التفسير أو فهرسته. لم يُحفظ ملف ناقص؛ حاول مرة أخرى."
        }
    }

    func remove(bookID: Int) {
        guard bookID != 42 else { return }
        do {
            try FileManager.default.removeItem(at: fileURL(for: bookID))
            indexes.removeValue(forKey: bookID)
            books.removeAll { $0.id == bookID }
            operationErrorMessage = nil
        } catch {
            operationErrorMessage = "تعذّر حذف هذا الكتاب من الجهاز."
        }
    }

    private func fileURL(for bookID: Int) -> URL {
        directory.appendingPathComponent("\(bookID).tafsir", isDirectory: false)
    }
}

@MainActor enum QuranTafsirPreferences {
    static let defaultBookKey = "quran.defaultTafsirBook"
    static let lastBooksKey = "quran.lastWirdTafsirBooks"

    static func defaultBookID(in app: AppSession) -> Int {
        Int(app.values[defaultBookKey]?.number ?? 42)
    }

    static func lastBookIDs(in app: AppSession) -> [Int] {
        let ids = app.values[lastBooksKey]?.array?.compactMap { $0.string.flatMap(Int.init) } ?? []
        return ids.isEmpty ? [defaultBookID(in: app)] : ids
    }

    static func saveLastBookIDs(_ ids: [Int], in app: AppSession) {
        var seen = Set<Int>()
        let unique = ids.filter { $0 > 0 && seen.insert($0).inserted }.prefix(8)
        let selection = unique.isEmpty ? [defaultBookID(in: app)] : Array(unique)
        app.set(.array(selection.map { .string(String($0)) }), key: lastBooksKey)
    }
}

struct QuranTafsirLibraryView: View {
    let app: AppSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var library = QuranTafsirLibrary.shared
    @State private var query = ""
    @State private var deleteBookID: Int?

    private var theme: RoomTheme { RoomTheme(room: "quran", dark: colorScheme == .dark) }
    private var digits: MadarNumberFormatter {
        MadarNumberFormatter(style: app.string("core.numerals") == "western" ? .western : .hindi)
    }
    private var selectedDefault: Int { QuranTafsirPreferences.defaultBookID(in: app) }

    private var suggestedBooks: [TurathCatalogueBook] {
        let suggestedIDs: [Int] = [1_503, 7_798, 9_776, 1_407]
        let byID = Dictionary(uniqueKeysWithValues: library.catalogue.map { ($0.id, $0) })
        return suggestedIDs.compactMap { byID[$0] }
    }

    private var searchResults: [TurathCatalogueBook] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return suggestedBooks }
        return TurathCatalogue.search(library.catalogue, query: query, limit: 30)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Text("تجد التفسير في زر «تفسير الورد» داخل وردك. تفسير السعدي موجود دائمًا بلا تنزيل، وإن أحببت تفسيرًا آخر فأضفه من الأسفل.")
                    .font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                currentTafsir
                if library.books.contains(where: { $0.id != selectedDefault }) { localBooks }
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) { searchField; remoteBooks }.padding(.top, 10)
                } label: {
                    Text("أضف تفسيرًا آخر").font(MadarTypography.section())
                }
                .tint(theme.accent).accessibilityIdentifier("quran-tafsir-add-more")
                ForEach(library.errorMessages, id: \.self) { message in
                    Text(message).font(MadarTypography.caption()).foregroundStyle(theme.color("hifzText"))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("quran-tafsir-library-message")
                }
                Button("أعِد تفسير السعدي") {
                    app.reset([QuranTafsirPreferences.defaultBookKey, QuranTafsirPreferences.lastBooksKey])
                }
                .font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("quran-tafsir-reset")
            }
            .padding(18).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(theme.background.ignoresSafeArea())
        .foregroundStyle(theme.ink)
        .environment(\.layoutDirection, .rightToLeft)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            await library.loadLocal()
            await library.loadCatalogue()
        }
        .confirmationDialog(
            "احذف هذا التفسير من الجهاز؟",
            isPresented: Binding(get: { deleteBookID != nil }, set: { if !$0 { deleteBookID = nil } }),
            titleVisibility: .visible
        ) {
            Button("احذف التفسير", role: .destructive) { deleteSelectedBook() }
            Button("أبقِه", role: .cancel) { deleteBookID = nil }
        } message: {
            Text("يمكن تنزيله مرة أخرى من تراث عند الحاجة.")
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Label("القرآن", systemImage: "chevron.backward")
                    .font(MadarTypography.caption()).frame(minHeight: 44)
            }
            .buttonStyle(.madarPlain).accessibilityIdentifier("quran-tafsir-library-back")
            Spacer()
            Text("التفسير").font(MadarTypography.section())
        }
    }

    /// The one tafsir shown when an ayah is touched, said plainly.
    private var currentTafsir: some View {
        libraryCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("تفسيرك الآن").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                if let book = library.books.first(where: { $0.id == selectedDefault }) ?? library.books.first {
                    Text(book.metadata.title).font(MadarTypography.section()).fixedSize(horizontal: false, vertical: true)
                    Text(book.metadata.author).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                } else { Text("تفسير السعدي").font(MadarTypography.section()) }
            }
        }
        .accessibilityIdentifier("quran-tafsir-current")
    }

    private var localBooks: some View {
        libraryCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("تفاسير نزّلتها").font(MadarTypography.section())
                if library.isLoadingLocal && library.books.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 64)
                } else if library.books.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("لا يوجد تفسير محفوظ بعد.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        Button("أعد فتح المكتبة") { Task { await library.loadLocal() } }
                            .font(MadarTypography.caption()).accessibilityIdentifier("quran-tafsir-local-retry")
                    }
                } else {
                    ForEach(library.books.filter { $0.id != selectedDefault }) { book in
                        localBookRow(book)
                        Divider().overlay(theme.line)
                    }
                }
            }
        }
        .accessibilityIdentifier("quran-tafsir-local-books")
    }

    private func localBookRow(_ book: QuranTafsirLibraryBook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.metadata.title).font(MadarTypography.section()).fixedSize(horizontal: false, vertical: true)
                    Text(book.metadata.author).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
                Spacer(minLength: 8)
                if selectedDefault == book.id {
                    Text("تفسيرك").font(MadarTypography.fine()).foregroundStyle(theme.color("hifzText"))
                        .accessibilityIdentifier("quran-tafsir-default-\(book.id)")
                }
            }
            HStack(spacing: 12) {
                Text(book.isBundled ? "مضمّن · كامل القرآن" : "\(digits.string(book.pageCount)) صفحة مفهرسة، \(sizeLabel(book.sizeBytes ?? 0))")
                    .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                Spacer(minLength: 0)
                if selectedDefault != book.id {
                    Button("اجعله تفسيري") {
                        app.set(.number(Double(book.id)), key: QuranTafsirPreferences.defaultBookKey)
                        QuranTafsirPreferences.saveLastBookIDs([book.id], in: app)
                    }
                    .font(MadarTypography.caption()).frame(minHeight: 44)
                    .accessibilityIdentifier("quran-tafsir-make-default-\(book.id)")
                }
                if !book.isBundled {
                    Button("احذف") { deleteBookID = book.id }
                        .font(MadarTypography.caption()).frame(minHeight: 44)
                        .foregroundStyle(theme.color("hifzText"))
                        .accessibilityIdentifier("quran-tafsir-delete-\(book.id)")
                }
            }
        }
        .padding(.vertical, 5)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryInk)
            TextField("ابحث باسم التفسير أو مؤلفه", text: $query)
                .font(MadarTypography.body()).submitLabel(.search)
                .accessibilityIdentifier("quran-tafsir-search")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                    .buttonStyle(.madarPlain).accessibilityLabel("امسح البحث")
            }
        }
        .padding(.horizontal, 16).background(theme.surface, in: Capsule())
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var remoteBooks: some View {
        libraryCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("تفاسير للتنزيل").font(MadarTypography.section())
                        Text(query.isEmpty ? "مقترحة لك، أو ابحث باسم التفسير" : "نتائج البحث")
                            .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    }
                    Spacer()
                    if library.isLoadingCatalogue { ProgressView() }
                    else if library.catalogue.isEmpty {
                        Button("حاول مرة أخرى") { Task { await library.loadCatalogue() } }
                            .font(MadarTypography.caption()).accessibilityIdentifier("quran-tafsir-catalogue-retry")
                    }
                }
                ForEach(searchResults) { book in remoteBookRow(book) }
                if !query.isEmpty && searchResults.isEmpty && !library.isLoadingCatalogue {
                    Text(library.catalogue.isEmpty ? "تعذّر تحميل الكتب الآن." : "لا يوجد تفسير بهذا الاسم.")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
            }
        }
        .accessibilityIdentifier("quran-tafsir-remote-books")
    }

    private func remoteBookRow(_ book: TurathCatalogueBook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(book.title).font(MadarTypography.body()).fixedSize(horizontal: false, vertical: true)
            Text(book.author).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            HStack {
                Text("نحو \(digits.string((book.sizeBytes + 524_288) / 1_048_576)) م.ب، \(digits.string(book.pageCount)) صفحة")
                    .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                Spacer()
                if library.books.contains(where: { $0.id == book.id }) {
                    Label("محفوظ", systemImage: "checkmark.circle.fill")
                        .font(MadarTypography.caption()).foregroundStyle(theme.color("hifzText"))
                        .accessibilityIdentifier("quran-tafsir-downloaded-\(book.id)")
                } else {
                    Button {
                        Task { await library.download(book) }
                    } label: {
                        if library.downloadingBookID == book.id { ProgressView().frame(minWidth: 68, minHeight: 40) }
                        else { Text("نزّل").frame(minWidth: 68, minHeight: 40) }
                    }
                    .buttonStyle(.borderedProminent).tint(theme.color("hifz"))
                    .disabled(library.downloadingBookID != nil)
                    .accessibilityIdentifier("quran-tafsir-download-\(book.id)")
                }
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .contain)
    }

    private func deleteSelectedBook() {
        guard let id = deleteBookID else { return }
        deleteBookID = nil
        if selectedDefault == id {
            app.set(.number(42), key: QuranTafsirPreferences.defaultBookKey)
        }
        var last = QuranTafsirPreferences.lastBookIDs(in: app).filter { $0 != id }
        if last.isEmpty { last = [selectedDefault == id ? 42 : selectedDefault] }
        QuranTafsirPreferences.saveLastBookIDs(last, in: app)
        library.remove(bookID: id)
    }

    private func sizeLabel(_ bytes: Int) -> String {
        "\(digits.string(max(1, bytes / 1_024))) ك.ب"
    }

    private func libraryCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.line.opacity(0.65), lineWidth: 1) }
            .shadow(color: theme.ink.opacity(0.04), radius: 14, x: 0, y: 7)
    }
}
