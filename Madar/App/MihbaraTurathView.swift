import SwiftUI
import MadarCore
import MadarCommands
import MadarDesign

/// M6-T01: search the Turath catalogue (the Shamela corpus), download a book, and hand a local EPUB
/// to the existing import review. Search and download need the internet; the book then reads offline.
@MainActor enum MihbaraTurathSource {
    static let maximumBytes = 150 * 1024 * 1024
    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("turath-catalogue-v3.json")
    }

    static func catalogue() async throws -> [TurathCatalogueBook] {
        #if DEBUG
        if let encoded = ProcessInfo.processInfo.environment["MADAR_UI_TURATH_CATALOGUE_BASE64"], let data = Data(base64Encoded: encoded) {
            return try TurathCatalogue.decode(data)
        }
        #endif
        let cache = cacheURL
        let age = (try? cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { Date().timeIntervalSince($0) }
        if let age, age < 7 * 86_400, let data = try? Data(contentsOf: cache), let books = try? TurathCatalogue.decode(data) { return books }
        do {
            let (data, response) = try await URLSession.shared.data(from: TurathCatalogue.catalogueURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TurathError.unreadable }
            let books = try await Task.detached { try TurathCatalogue.decode(data) }.value
            try? data.write(to: cache, options: .atomic)
            return books
        } catch {
            if let data = try? Data(contentsOf: cache), let books = try? TurathCatalogue.decode(data) { return books }
            throw error
        }
    }

    /// Downloads the book and writes a deterministic EPUB beside the import staging area.
    static func download(_ book: TurathCatalogueBook, into folder: URL) async throws -> URL {
        guard book.sizeBytes <= maximumBytes else { throw TurathError.tooLarge }
        let data: Data
        #if DEBUG
        if let encoded = ProcessInfo.processInfo.environment["MADAR_UI_TURATH_BOOK_BASE64"], let fixture = Data(base64Encoded: encoded) { data = fixture }
        else { data = try await fetch(book) }
        #else
        data = try await fetch(book)
        #endif
        let epub = try await Task.detached(priority: .userInitiated) {
            try TurathEPUB.build(TurathBookDocument.decode(data, catalogue: book))
        }.value
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = book.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").prefix(80)
        let file = folder.appendingPathComponent("\(name).epub")
        try epub.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return file
    }

    private static func fetch(_ book: TurathCatalogueBook) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: TurathCatalogue.bookURL(book.id))
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= maximumBytes else { throw TurathError.unreadable }
        return data
    }
}

struct MihbaraTurathView: View {
    let app: AppSession
    /// Prefilled search, e.g. the title of a PDF the owner wants as a flowing book.
    var initialQuery = ""
    let onImported: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var books: [TurathCatalogueBook] = []
    @State private var loading = true
    @State private var catalogueAttempt = 0
    @State private var query = ""
    @State private var results: [TurathCatalogueBook] = []
    @State private var downloading: Int?
    @State private var error: String?
    @State private var downloaded: URL?
    @State private var downloadedTurathID: Int?
    @State private var reviewing = false
    @FocusState private var searching: Bool
    private var digits: MadarNumberFormatter { AppMihbaraService(app: app).digits }
    private let suggestions = ["صيد الخاطر", "رياض الصالحين", "الأذكار", "مختصر منهاج القاصدين", "الرحيق المختوم", "الفوائد"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    VStack(spacing: 2) {
                        Text("من تراث").font(.custom("thmanyahserifdisplay-Bold", size: 21, relativeTo: .title2))
                        Text("المكتبة الشاملة").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    }
                    HStack {
                        Button { dismiss() } label: { Label("رجوع", systemImage: "chevron.right").font(MadarTypography.caption()).frame(minHeight: 44) }
                            .accessibilityIdentifier("mihbara-turath-back")
                        Spacer()
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryInk)
                    TextField("عنوان الكتاب أو اسم المؤلف", text: $query, prompt: Text("عنوان الكتاب أو اسم المؤلف").foregroundStyle(theme.secondaryInk))
                        .textFieldStyle(.plain).font(MadarTypography.body()).submitLabel(.search).focused($searching)
                        .autocorrectionDisabled().accessibilityIdentifier("mihbara-turath-search")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondaryInk) }
                            .buttonStyle(.plain).frame(minWidth: 44, minHeight: 44).accessibilityLabel("امسح البحث")
                    }
                }
                .padding(.horizontal, 14).frame(minHeight: 52)
                .background(theme.surface, in: .rect(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(searching ? theme.ink.opacity(0.5) : theme.line, lineWidth: 1) }

                if let error {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).font(MadarTypography.caption()).foregroundStyle(theme.ink)
                            .accessibilityIdentifier("mihbara-turath-error")
                        if books.isEmpty && !loading {
                            Button { catalogueAttempt += 1 } label: {
                                Label("حاول مرة أخرى", systemImage: "arrow.clockwise")
                                    .font(MadarTypography.body()).frame(minHeight: 44)
                            }
                            .buttonStyle(.plain).accessibilityIdentifier("mihbara-turath-retry")
                        }
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface, in: .rect(cornerRadius: 14))
                }

                if loading {
                    HStack(spacing: 10) { ProgressView().tint(theme.ink); Text("يجلب فهرس الكتب…").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else if !books.isEmpty || error == nil {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        starter
                    } else if results.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "text.magnifyingglass").font(.title2).foregroundStyle(theme.secondaryInk)
                            Text("لا كتاب بهذا الاسم في الفهرس").font(MadarTypography.cardTitle())
                            Text("جرّب كلمة واحدة من العنوان، أو اسم المؤلف المشهور.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        }.frame(maxWidth: .infinity, minHeight: 160).accessibilityIdentifier("mihbara-turath-empty")
                    } else {
                        Text(results.count >= 50 ? "أقرب \(digits.string(50)) نتيجة" : arabicCount(results.count, ["نتيجة واحدة", "نتيجتان", "نتائج", "نتيجة"], digits))
                            .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, book in
                                row(book)
                                if index < results.count - 1 { Divider().padding(.leading, 16) }
                            }
                        }
                        .background(theme.surface, in: .rect(cornerRadius: 18))
                        .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line.opacity(0.7), lineWidth: 1) }
                    }
                }
            }
            .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 28)
            .frame(maxWidth: 650).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(theme.ink).background(theme.background.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft).toolbarVisibility(.hidden, for: .navigationBar).statusBarHidden(true)
        .task(id: catalogueAttempt) { await load() }
        .onChange(of: query) { _, value in results = TurathCatalogue.search(books, query: value) }
        .navigationDestination(isPresented: $reviewing) {
            if let downloaded {
                MihbaraEPUBImportView(app: app, source: downloaded, turathID: downloadedTurathID) {
                    try? FileManager.default.removeItem(at: downloaded)
                    reviewing = false; onImported()
                }
            }
        }
    }

    private var starter: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ابدأ بكتاب").font(MadarTypography.section())
            FlowChips(items: suggestions) { query = $0 }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "books.vertical").font(.title3).foregroundStyle(theme.color("sunnah")).frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(books.isEmpty ? "المكتبة الشاملة" : "في الفهرس \(MihbaraCopy.books(books.count, digits))").font(MadarTypography.section())
                    Text("البحث والتنزيل عبر الإنترنت من تراث، ثم يُقرأ الكتاب على جهازك بلا إنترنت بترقيم المطبوع وفهرسه.")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14).background(theme.surface, in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.line.opacity(0.7), lineWidth: 1) }
        }
    }

    private func row(_ book: TurathCatalogueBook) -> some View {
        Button { download(book) } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(book.title).font(MadarTypography.cardTitle()).multilineTextAlignment(.leading).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    if !book.author.isEmpty {
                        Text(book.authorDeath.map { "\(book.author)، ت \(deathYears($0))" } ?? book.author)
                            .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    }
                    Text([book.category, book.pageCount > 0 ? MihbaraCopy.pages(book.pageCount, digits) : "", size(book.sizeBytes)].filter { !$0.isEmpty }.joined(separator: "، "))
                        .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }
                Spacer(minLength: 0)
                Group {
                    if downloading == book.id { ProgressView().tint(theme.ink) }
                    else { Image(systemName: "arrow.down.circle").font(.title2).foregroundStyle(theme.color("sunnah")) }
                }.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16).padding(.vertical, 12).contentShape(.rect)
        }
        .buttonStyle(.plain).disabled(downloading != nil)
        .accessibilityLabel("\(book.title)، \(book.author)").accessibilityHint("ينزّل الكتاب ويعرض معاينته قبل إضافته")
        .accessibilityIdentifier("mihbara-turath-book-\(book.id)")
    }

    /// The death year in both calendars: «٦٧٦هـ، ١٢٧٧م». The Gregorian year is the civil-calendar conversion of the middle of the Hijri year.
    private func deathYears(_ hijriYear: Int) -> String {
        let hijri = digits.string(hijriYear) + "هـ"
        var civil = Calendar(identifier: .islamicCivil)
        civil.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard hijriYear > 0, let date = civil.date(from: DateComponents(year: hijriYear, month: 7, day: 1)) else { return hijri }
        let gregorianYear = Calendar(identifier: .gregorian).component(.year, from: date)
        return hijri + "، " + digits.string(gregorianYear) + "م"
    }
    private func size(_ bytes: Int) -> String {
        guard bytes > 0 else { return "" }
        let mb = Double(bytes) / 1_048_576
        if mb < 1 { return "أقل من \(digits.string(1)) م.ب" }
        return "\(digits.string(Int(mb.rounded()))) م.ب"
    }

    private func load() async {
        if query.isEmpty, !initialQuery.isEmpty { query = initialQuery }
        guard books.isEmpty else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            #if DEBUG
            if UUID(uuidString: ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"] ?? "") != nil,
               ProcessInfo.processInfo.environment["MADAR_UI_TURATH_CATALOGUE_FAILURE_ONCE"] == "1", catalogueAttempt == 0 {
                throw TurathError.unreadable
            }
            #endif
            let loaded = try await MihbaraTurathSource.catalogue()
            try Task.checkCancellation()
            books = loaded
            results = TurathCatalogue.search(books, query: query)
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "تعذّر الوصول إلى فهرس تراث. تأكد من الاتصال بالإنترنت وحاول مرة أخرى."
            results = []
        }
    }

    private func download(_ book: TurathCatalogueBook) {
        guard downloading == nil else { return }
        downloading = book.id; error = nil; searching = false
        Task { @MainActor in
            do {
                let folder = app.bookStagingDirectory.deletingLastPathComponent().appendingPathComponent("TurathDownloads")
                downloaded = try await MihbaraTurathSource.download(book, into: folder)
                downloadedTurathID = book.id
                downloading = nil; reviewing = true
            } catch TurathError.tooLarge {
                downloading = nil; error = "هذا الكتاب أكبر من ١٥٠ م.ب؛ لا يُنزّل إلى الجهاز."
            } catch {
                downloading = nil; self.error = "تعذّر تنزيل «\(book.title)». تحقق من الاتصال وحاول مرة أخرى."
            }
        }
    }
}

/// Suggestion chips that wrap onto lines, right to left.
private struct FlowChips: View {
    let items: [String]
    let action: (String) -> Void
    @Environment(\.roomTheme) private var theme
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { action(item) } label: {
                    Text(item).font(MadarTypography.caption()).padding(.horizontal, 14).frame(minHeight: 40)
                        .background(theme.surface, in: .capsule).overlay { Capsule().stroke(theme.line, lineWidth: 1) }
                }.buttonStyle(.plain).accessibilityIdentifier("mihbara-turath-suggestion-\(item)")
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing; line = max(line, size.height)
        }
        return CGSize(width: width, height: y + line)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width { x = 0; y += line + spacing; line = 0 }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: .init(size))
            x += size.width + spacing; line = max(line, size.height)
        }
    }
}
