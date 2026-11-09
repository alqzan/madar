import SwiftUI
import MadarCore
import MadarCommands
import MadarDesign
import MadarQuran

struct QuranWirdReferenceRequest: Identifiable {
    let id = UUID()
    let range: QuranAyahRange
}

enum QuranWirdReferenceKind: String, Codable, Sendable, Equatable {
    case tafsir, asbab, context

    var title: String {
        switch self {
        case .tafsir: "التفسير"
        case .asbab: "سبب النزول"
        case .context: "السياق"
        }
    }
}

private enum QuranWirdReferenceFilter: String, CaseIterable, Identifiable {
    case all, tafsir, asbab, context
    var id: String { rawValue }
    var kind: QuranWirdReferenceKind? { self == .all ? nil : QuranWirdReferenceKind(rawValue: rawValue) }
    var title: String {
        switch self {
        case .all: "الكل"
        case .tafsir: "التفسير"
        case .asbab: "سبب النزول"
        case .context: "السياق"
        }
    }
}

struct QuranWirdReferenceExcerpt: Codable, Identifiable, Sendable {
    let id: String
    let ayahID: Int
    let kind: QuranWirdReferenceKind
    let text: String
    let book: String
    let author: String
    let citation: String
    let sourceURL: URL
    let sourceNote: String?

    static let verified: [Self] = {
        guard let data = try? QuranWirdReferenceResource.bundledData() else { return [] }
        return (try? JSONDecoder().decode([Self].self, from: data)) ?? []
    }()
}

enum QuranWirdReferenceSearch {
    static let wordLimit = 12

    static func url(for ayah: QuranAyahResourceRecord) -> URL? {
        // Search the catalog's normalized orthography, not Mushaf display text
        // that may carry a printed ayah-end glyph such as U+FD00.
        let phrase = ayah.searchText.split(whereSeparator: \.isWhitespace)
            .prefix(wordLimit)
            .joined(separator: " ")
        guard !phrase.isEmpty else { return nil }
        var components = URLComponents(string: "https://shamela.ws/search")
        components?.queryItems = [URLQueryItem(name: "q", value: "\"\(phrase)\"")]
        return components?.url
    }
}

struct QuranWirdReferenceView: View {
    let request: QuranWirdReferenceRequest
    let digits: MadarNumberFormatter
    let app: AppSession
    let close: () -> Void

    @Environment(\.roomTheme) private var theme
    @State private var ayahs: [QuranAyahResourceRecord] = []
    @State private var library = QuranTafsirLibrary.shared
    @State private var selectedBookIDs: [Int] = []
    @State private var filter: QuranWirdReferenceFilter = .all
    @State private var showingAyahs = false
    @State private var showingTafsirLibrary = false
    @State private var loading = true
    @State private var failed = false
    @State private var retryCount = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("مرجع وردك").font(serif(27)).accessibilityIdentifier("quran-reference-title")
                        Text(rangeTitle).font(bodyFont(14, bold: true)).foregroundStyle(theme.color("hifzText"))
                            .accessibilityIdentifier("quran-reference-range")
                        Text("اقرأ التفاسير التي اخترتها لكل آيات هذا الورد، مع بقاء أسباب النزول والسياق في موضعيهما.")
                            .font(bodyFont(12)).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("quran-reference-intro")
                    }
                    filterPicker
                    tafsirPicker
                    if loading || library.isLoadingLocal {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    } else if failed {
                        failureState
                    } else {
                        let matchingAyahs = ayahs.filter { hasSourceData(for: $0) }
                        if matchingAyahs.isEmpty {
                            emptyState
                        } else {
                            ForEach(matchingAyahs, id: \.id) { ayah in referenceCard(ayah) }
                            if matchingAyahs.count < ayahs.count {
                                partialCoverageState(coveredCount: matchingAyahs.count)
                            }
                        }
                        ayahList
                    }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 32)
                .frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(theme.ink)
        .background(theme.background.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task(id: retryCount) {
            loadAyahs()
            await library.loadLocal()
            restoreBookSelection()
        }
        .onChange(of: app.values[QuranTafsirPreferences.lastBooksKey]) { _, _ in
            restoreBookSelection()
        }
        .fullScreenCover(isPresented: $showingTafsirLibrary) {
            QuranTafsirLibraryView(app: app)
        }
    }

    private var header: some View {
        HStack {
            Button(action: close) {
                Label("رجوع", systemImage: "chevron.right")
                    .font(bodyFont(13, bold: true)).frame(minWidth: 72, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.madarPlain).accessibilityIdentifier("quran-reference-close")
            Spacer()
            Text("الورد اليومي").font(bodyFont(13, bold: true)).foregroundStyle(theme.secondaryInk)
            Spacer()
            Color.clear.frame(width: 72, height: 44).accessibilityHidden(true)
        }
        .padding(.horizontal, 18).padding(.top, 4)
    }

    private var filterPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(QuranWirdReferenceFilter.allCases) { option in
                    let selected = filter == option
                    Button { filter = option } label: {
                        Text(option.title).font(bodyFont(12, bold: selected))
                            .padding(.horizontal, 14).frame(minHeight: 42)
                            .foregroundStyle(selected ? theme.color("hifzText") : theme.secondaryInk)
                            .background(selected ? theme.color("hifzTint") : theme.surface, in: Capsule())
                            .overlay { Capsule().stroke(selected ? theme.color("hifz") : theme.line, lineWidth: 1) }
                    }
                    .buttonStyle(.madarPlain)
                    .accessibilityIdentifier("quran-reference-filter-\(option.rawValue)")
                    .accessibilityValue(selected ? "محدد" : "غير محدد")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var tafsirPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Menu {
                Section("التفاسير المحفوظة") {
                    ForEach(library.books) { book in
                        Button {
                            toggleBook(book.id)
                        } label: {
                            Label(book.metadata.title, systemImage: selectedBookIDs.contains(book.id) ? "checkmark.circle.fill" : "circle")
                        }
                        .accessibilityIdentifier("quran-reference-tafsir-choice-\(book.id)")
                    }
                }
                Button { showingTafsirLibrary = true } label: {
                    Label("مكتبة التفاسير", systemImage: "books.vertical")
                }
                .accessibilityIdentifier("quran-reference-open-tafsir-library")
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "books.vertical")
                    Text(selectedBookTitles.isEmpty ? "اختر تفسيرًا للورد" : selectedBookTitles.joined(separator: "، "))
                        .font(bodyFont(13, bold: true)).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 14).frame(minHeight: 48)
                .foregroundStyle(theme.color("hifzText"))
                .background(theme.color("hifzTint"), in: .rect(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.color("hifz").opacity(0.6), lineWidth: 1) }
            }
            .buttonStyle(.madarPlain)
            .accessibilityIdentifier("quran-reference-tafsir-picker")

            if !selectedBooks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(selectedBooks) { book in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(book.metadata.title).font(bodyFont(12, bold: true))
                                Text(book.metadata.author).font(bodyFont(11)).foregroundStyle(theme.secondaryInk)
                            }
                            Spacer(minLength: 4)
                            if let url = URL(string: book.metadata.shamelaURL) {
                                Link("الكتاب في الشاملة", destination: url)
                                    .font(bodyFont(11, bold: true)).frame(minHeight: 40)
                                    .accessibilityIdentifier("quran-reference-tafsir-book-\(book.id)")
                            }
                        }
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: .rect(cornerRadius: 16))
                .accessibilityIdentifier("quran-reference-tafsir-sources")
            }
        }
    }

    private var failureState: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("تعذّر فتح خريطة آيات الورد.").font(bodyFont(14, bold: true))
                Button { retryCount += 1 } label: { Text("حاول مرة أخرى")
                    .font(bodyFont(13, bold: true)).frame(minHeight: 44).contentShape(Rectangle()) }
                    .accessibilityIdentifier("quran-reference-retry")
            }
        }
    }

    private var emptyState: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Label("لا يوجد تفسير محفوظ لهذه الآيات", systemImage: "books.vertical")
                    .font(bodyFont(14, bold: true)).fixedSize(horizontal: false, vertical: true)
                Text("نزّل تفسيرًا من المكتبة أو اختر سبب النزول والسياق لعرض موادهما الموثّقة.")
                    .font(bodyFont(12)).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
        }.accessibilityIdentifier("quran-reference-empty")
    }

    private func partialCoverageState(coveredCount: Int) -> some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "تظهر مقتطفات موثّقة لـ \(digits.string(coveredCount)) \(ayahs.count == 1 ? "من آية واحدة" : ayahs.count == 2 ? "من آيتين" : "من " + digits.string(ayahs.count) + ((3...10).contains(ayahs.count % 100) ? " آيات" : " آية")) بحسب الاختيار الحالي.",
                    systemImage: "books.vertical"
                )
                .font(bodyFont(13, bold: true)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("quran-reference-partial-coverage-count")
                Text("قد تكون للآيات الأخرى مراجع في المصادر؛ لم ندرج لها مقتطفًا موثّقًا هنا.")
                    .font(bodyFont(12)).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var ayahList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { showingAyahs.toggle() } label: {
                HStack(spacing: 10) {
                    Text(showingAyahs ? "أخفِ آيات الورد" : "آيات الورد")
                        .font(bodyFont(14, bold: true))
                    Text(digits.string(ayahs.count)).font(bodyFont(12)).foregroundStyle(theme.secondaryInk)
                    Spacer()
                    Image(systemName: showingAyahs ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .semibold))
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.madarPlain).accessibilityIdentifier("quran-reference-ayahs-toggle")
            if showingAyahs {
                card {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(ayahs, id: \.id) { ayah in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(ayah.surahNameArabic + "، الآية " + digits.string(ayah.ayahNumber))
                                    .font(bodyFont(12, bold: true)).foregroundStyle(theme.color("hifzText"))
                                Text(ayah.uthmaniText).font(.custom("Amiri-Regular", size: 21, relativeTo: .title3))
                                    .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("quran-reference-ayah-text-\(ayah.id)")
                                if let searchURL = QuranWirdReferenceSearch.url(for: ayah) {
                                    Link(destination: searchURL) {
                                        Label("ابحث عن مطلع الآية في الشاملة", systemImage: "magnifyingglass")
                                            .font(bodyFont(12, bold: true)).frame(minHeight: 44, alignment: .leading)
                                    }
                                    .buttonStyle(.madarPlain).foregroundStyle(theme.color("hifzText"))
                                    .accessibilityIdentifier("quran-reference-search-\(ayah.id)")
                                }
                            }
                            if ayah.id != ayahs.last?.id { Divider().overlay(theme.line) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func referenceCard(_ ayah: QuranAyahResourceRecord) -> some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text(ayah.surahNameArabic + " · الآية " + digits.string(ayah.ayahNumber))
                    .font(bodyFont(13, bold: true)).foregroundStyle(theme.color("hifzText"))
                ForEach(readings(for: ayah)) { reading in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(reading.rangeLabel)
                            .font(bodyFont(12, bold: true)).foregroundStyle(theme.secondaryInk)
                        Text(reading.passage.text)
                            .font(.custom("Amiri-Regular", size: 19, relativeTo: .title3))
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("quran-reference-tafsir-text-\(reading.bookID)-\(reading.passage.firstAyahID)")
                        ForEach(reading.passage.pages) { page in
                            if let url = pageURL(bookID: reading.bookID, pageID: page.id) {
                                Link(citation(for: page), destination: url)
                                    .font(bodyFont(11, bold: true)).frame(minHeight: 40)
                                    .accessibilityIdentifier("quran-reference-tafsir-page-\(reading.bookID)-\(reading.passage.firstAyahID)-\(page.id)")
                            } else {
                                Text(citation(for: page)).font(bodyFont(11)).foregroundStyle(theme.secondaryInk)
                            }
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.color("hifzTint").opacity(0.55), in: .rect(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line.opacity(0.7), lineWidth: 1) }
                }
                ForEach(entries(for: ayah)) { excerpt in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(excerpt.kind.title).font(bodyFont(12, bold: true)).foregroundStyle(theme.secondaryInk)
                        Text("«" + excerpt.text + "»")
                            .font(.custom("Amiri-Regular", size: 19, relativeTo: .title3))
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("quran-reference-excerpt-\(excerpt.id)")
                        if let sourceNote = excerpt.sourceNote {
                            Text(sourceNote).font(bodyFont(11)).foregroundStyle(theme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("quran-reference-note-\(excerpt.id)")
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(excerpt.book).font(bodyFont(12, bold: true))
                            Text(excerpt.author + "، " + excerpt.citation)
                                .font(bodyFont(11)).foregroundStyle(theme.secondaryInk)
                                .accessibilityIdentifier("quran-reference-citation-\(excerpt.id)")
                        }
                        Link(destination: excerpt.sourceURL) {
                            Label("الصفحة كاملة في الشاملة", systemImage: "arrow.up.right.square")
                                .font(bodyFont(12, bold: true)).frame(minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.madarPlain).foregroundStyle(theme.color("hifzText"))
                        .accessibilityIdentifier("quran-reference-source-\(excerpt.id)")
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.color("hifzTint").opacity(0.55), in: .rect(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line.opacity(0.7), lineWidth: 1) }
                }
            }
        }
    }

    private func entries(for ayah: QuranAyahResourceRecord) -> [QuranWirdReferenceExcerpt] {
        QuranWirdReferenceExcerpt.verified.filter { excerpt in
            excerpt.ayahID == ayah.id && excerpt.kind != .tafsir && (filter.kind == nil || excerpt.kind == filter.kind)
        }
    }

    private struct BookReading: Identifiable {
        let bookID: Int
        let passage: QuranTafsirPassage
        let rangeLabel: String
        var id: String { "\(bookID)-\(passage.id)" }
    }

    private var selectedBooks: [QuranTafsirLibraryBook] {
        selectedBookIDs.compactMap { id in library.books.first { $0.id == id } }
    }

    private var selectedBookTitles: [String] { selectedBooks.map { $0.metadata.title } }

    private func hasSourceData(for ayah: QuranAyahResourceRecord) -> Bool {
        (!selectedBookIDs.isEmpty && filter.kind != .asbab && filter.kind != .context && !readings(for: ayah).isEmpty)
            || !entries(for: ayah).isEmpty
    }

    private func readings(for ayah: QuranAyahResourceRecord) -> [BookReading] {
        guard filter.kind != .asbab && filter.kind != .context else { return [] }
        return selectedBookIDs.flatMap { bookID -> [BookReading] in
            guard let index = library.index(for: bookID) else { return [] }
            return index.passages(forAyahID: ayah.id).compactMap { passage in
                guard max(passage.firstAyahID, request.range.first) == ayah.id else { return nil }
                let first = catalogAyah(passage.firstAyahID)
                let last = catalogAyah(passage.lastAyahID)
                let label: String
                if let first, let last, first.id != last.id {
                    label = "الآيات " + digits.string(first.ayahNumber) + "–" + digits.string(last.ayahNumber)
                } else {
                    label = "الآية " + digits.string(first?.ayahNumber ?? ayah.ayahNumber)
                }
                return BookReading(bookID: bookID, passage: passage, rangeLabel: label)
            }
        }
    }

    private func catalogAyah(_ id: Int) -> QuranAyahResourceRecord? {
        try? QuranResources.catalog().ayah(id: id)
    }

    private func toggleBook(_ id: Int) {
        if selectedBookIDs.contains(id) {
            guard selectedBookIDs.count > 1 else { return }
            selectedBookIDs.removeAll { $0 == id }
        } else if selectedBookIDs.count < 8 {
            selectedBookIDs.append(id)
        }
        QuranTafsirPreferences.saveLastBookIDs(selectedBookIDs, in: app)
    }

    private func restoreBookSelection() {
        let available = Set(library.books.map(\.id))
        let stored = QuranTafsirPreferences.lastBookIDs(in: app).filter(available.contains)
        let selected = stored.isEmpty ? [QuranTafsirPreferences.defaultBookID(in: app)] : stored
        selectedBookIDs = selected.contains(where: available.contains) ? selected : [42]
    }

    private func pageURL(bookID: Int, pageID: Int) -> URL? {
        guard let base = library.index(for: bookID)?.metadata.shamelaURL else { return nil }
        return URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/\(pageID)")
    }

    private func citation(for page: QuranTafsirPageReference) -> String {
        let pageNumber = displayNumber(page.printedPage)
        let volume = displayNumber(page.volume)
        if volume.isEmpty { return "الصفحة " + pageNumber }
        return "الجزء " + volume + "، الصفحة " + pageNumber
    }

    private func displayNumber(_ value: String) -> String {
        if let number = Int(value) { return digits.string(number) }
        return value
    }

    private var rangeTitle: String {
        guard let first = ayahs.first, let last = ayahs.last else { return "" }
        if first.id == last.id {
            return first.surahNameArabic + " · الآية " + digits.string(first.ayahNumber)
        }
        if first.surahID == last.surahID {
            return first.surahNameArabic + " · الآيات " + digits.string(first.ayahNumber) + "–" + digits.string(last.ayahNumber)
        }
        return first.surahNameArabic + " " + digits.string(first.ayahNumber) + " – " + last.surahNameArabic + " " + digits.string(last.ayahNumber)
    }

    private func loadAyahs() {
        loading = true
        failed = false
        defer { loading = false }
        guard request.range.first <= request.range.last,
              (1...6236).contains(request.range.first), (1...6236).contains(request.range.last) else {
            failed = true
            return
        }
        do {
            let catalog = try QuranResources.catalog()
            let values = (request.range.first...request.range.last).compactMap { catalog.ayah(id: $0) }
            guard values.count == request.range.last - request.range.first + 1 else {
                failed = true
                return
            }
            ayahs = values
        } catch {
            failed = true
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.line.opacity(0.65), lineWidth: 1) }
            .shadow(color: theme.ink.opacity(0.04), radius: 14, x: 0, y: 7)
    }

    private func serif(_ size: CGFloat) -> Font { .custom("Amiri-Bold", size: size, relativeTo: .title2) }
    private func bodyFont(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "thmanyahsans-Bold" : "thmanyahsans-Regular", size: size, relativeTo: .body)
    }
}
