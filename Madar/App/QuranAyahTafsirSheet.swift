import SwiftUI
import MadarCore
import MadarCommands
import MadarDesign
import MadarQuran

/// FB-33 (owner, 5 Nov: «ابي طريقه اذكى مثل تطبيقات القرآن»): press an ayah in the mushaf, it lights up, and
/// its tafsir rises in a sheet over the page. The page stays readable above the half sheet; next and previous
/// walk the ayahs and turn the page when an ayah begins on the next one.
struct QuranAyahTafsirSheet: View {
    let app: AppSession
    let ayahID: Int
    let digits: MadarNumberFormatter
    /// Moves the selection (and the page under the sheet) to another ayah.
    let select: (Int) -> Void
    let close: () -> Void

    @Environment(\.roomTheme) private var theme
    @State private var library = QuranTafsirLibrary.shared
    @State private var bookID = 42
    @State private var showingLibrary = false
    private let strong = Font.custom("thmanyahsans-Bold", size: 13, relativeTo: .subheadline)

    private var ayah: QuranAyahResourceRecord? { try? QuranResources.catalog().ayah(id: ayahID) }
    private var book: QuranTafsirLibraryBook? { library.books.first { $0.id == bookID } }
    private var passages: [QuranTafsirPassage] { library.index(for: bookID)?.passages(forAyahID: ayahID) ?? [] }
    private var excerpts: [QuranWirdReferenceExcerpt] {
        QuranWirdReferenceExcerpt.verified.filter { $0.ayahID == ayahID && $0.kind != .tafsir }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                tafsir
                ForEach(excerpts) { excerpt in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(excerpt.kind.title).font(strong).foregroundStyle(theme.color("hifzText"))
                        Text(excerpt.text).font(.custom("Amiri-Regular", size: 19, relativeTo: .body)).lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(excerpt.book + "، " + excerpt.citation).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    }
                    .accessibilityIdentifier("quran-tafsir-excerpt-\(excerpt.id)")
                }
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) { stepper }
        .foregroundStyle(theme.ink)
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.fraction(0.46), .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.46)))
        .presentationDragIndicator(.visible)
        .task {
            bookID = QuranTafsirPreferences.lastBookIDs(in: app).first ?? QuranTafsirPreferences.defaultBookID(in: app)
            await library.loadLocal()
            if library.index(for: bookID) == nil, let first = library.books.first { bookID = first.id }
        }
        .fullScreenCover(isPresented: $showingLibrary) { QuranTafsirLibraryView(app: app) }
        .sensoryFeedback(.selection, trigger: ayahID)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            // Owner, 5 Nov: the ayah is lit on the page above, so the sheet names it and explains it, never repeats it.
            HStack(spacing: 10) {
                Text(ayah.map { digits.string($0.ayahNumber) } ?? "")
                    .font(.custom("Amiri-Bold", size: 17)).foregroundStyle(theme.color("onCover"))
                    .frame(minWidth: 34, minHeight: 34)
                    .background(theme.color("cover"), in: .circle)
                    .overlay { Circle().stroke(theme.color("gold"), lineWidth: 1.5) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(ayah.map { "سورة " + $0.surahNameArabic } ?? "").font(.custom("Amiri-Bold", size: 21))
                        .foregroundStyle(theme.color("reviewText"))
                    Text(ayah.map { "الآية " + digits.string($0.ayahNumber) } ?? "")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
            }
            .accessibilityElement(children: .combine).accessibilityIdentifier("quran-tafsir-ayah-title")
            Spacer(minLength: 8)
            bookMenu
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).frame(width: 40, height: 40)
            }
            .buttonStyle(.plain).glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("إغلاق التفسير").accessibilityIdentifier("quran-tafsir-close")
        }
    }

    private var bookMenu: some View {
        Menu {
            ForEach(library.books) { option in
                Button {
                    bookID = option.id
                    QuranTafsirPreferences.saveLastBookIDs([option.id] + QuranTafsirPreferences.lastBookIDs(in: app), in: app)
                } label: {
                    if option.id == bookID { Label(option.metadata.title, systemImage: "checkmark") } else { Text(option.metadata.title) }
                }
            }
            Divider()
            Button { showingLibrary = true } label: { Label("تفاسير أخرى", systemImage: "books.vertical") }
        } label: {
            HStack(spacing: 5) {
                Text(shortTitle(book?.metadata.title ?? "التفسير")).font(strong).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 12).frame(height: 36).foregroundStyle(theme.color("onGold"))
            .glassEffect(.regular.tint(theme.color("gold").opacity(0.7)).interactive(), in: .capsule)
        }
        .accessibilityLabel("كتاب التفسير، " + (book?.metadata.title ?? ""))
        .accessibilityIdentifier("quran-tafsir-book")
    }

    @ViewBuilder private var tafsir: some View {
        if library.isLoadingLocal && passages.isEmpty {
            ProgressView().frame(maxWidth: .infinity, minHeight: 90)
        } else if passages.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("لا يذكر " + shortTitle(book?.metadata.title ?? "هذا الكتاب") + " هذه الآية وحدها.")
                    .font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                Button("اختر تفسيرًا آخر") { showingLibrary = true }.font(strong)
                    .foregroundStyle(theme.color("hifzText")).frame(minHeight: 40)
            }
        } else {
            ForEach(passages) { passage in
                VStack(alignment: .leading, spacing: 10) {
                    if passage.firstAyahID != passage.lastAyahID { Text(rangeLabel(passage)).font(strong).foregroundStyle(theme.color("reviewText")) }
                    Text(Self.explanation(passage.text))
                        .font(.custom("Amiri-Regular", size: 20, relativeTo: .body)).lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .accessibilityIdentifier("quran-tafsir-text-\(bookID)-\(passage.firstAyahID)")
                    if let page = passage.pages.first {
                        Text(((book?.metadata.author).map { $0 + "، " } ?? "") + citation(page))
                            .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    }
                }
            }
        }
    }

    /// Previous and next ayah, in glass, always under the thumb.
    private var stepper: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                step("chevron.right", label: "الآية السابقة", id: "quran-tafsir-previous", to: ayahID - 1)
                Spacer(minLength: 0)
                step("chevron.left", label: "الآية التالية", id: "quran-tafsir-next", to: ayahID + 1)
            }
            .accessibilityElement(children: .contain)
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
        .background {
            LinearGradient(colors: [theme.color("mushafPaper").opacity(0), theme.color("mushafPaper").opacity(0.92)], startPoint: .top, endPoint: .center)
                .ignoresSafeArea().allowsHitTesting(false)
        }
    }

    private func step(_ symbol: String, label: String, id: String, to target: Int) -> some View {
        Button { select(target) } label: {
            // The arrow sits on the outer side: right for the previous ayah, left for the next.
            HStack(spacing: 6) {
                if target < ayahID { Image(systemName: symbol); Text(label) } else { Text(label); Image(systemName: symbol) }
            }
            .font(strong).padding(.horizontal, 16).frame(height: 44)
            .foregroundStyle(target > ayahID ? theme.color("onCover") : theme.color("reviewText"))
        }
        // The next ayah is the way on: the Quran's green with gold; the previous stays quiet glass.
        .buttonStyle(.plain)
        .glassEffect(target > ayahID ? .regular.tint(theme.color("cover").opacity(0.9)).interactive() : .regular.interactive(), in: .capsule)
        .disabled(!(1...6_236).contains(target)).accessibilityIdentifier(id)
    }

    /// Saadi (and most tafsir books) open a passage by quoting its ayahs: «- ٧ ﴿إِنَّ الَّذِينَ…﴾ * ﴿خَتَمَ…﴾».
    /// The page above already shows them lit, so the sheet starts at the explanation itself.
    static func explanation(_ text: String) -> String {
        let open: Character = "\u{FD3F}", close: Character = "\u{FD3E}"
        let filler: Set<Character> = ["-", "–", "*", ".", ":", "،", " ", "\n", "\t", close]
        var rest = Substring(text)
        /// Skips «- ٧» and separators only when they lead into another quoted ayah, so numbers in the explanation stay.
        func skipToQuote() -> Bool {
            var probe = rest
            while let c = probe.first, filler.contains(c) || c.isNumber { probe = probe.dropFirst() }
            guard probe.first == open else { return false }
            rest = probe; return true
        }
        var stripped = false
        while skipToQuote(), let end = rest.firstIndex(of: close) {
            rest = rest[rest.index(after: end)...]; stripped = true
        }
        let body = rest.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ".*")))
        return stripped && body.count > 20 ? body : text
    }

    private func rangeLabel(_ passage: QuranTafsirPassage) -> String {
        let catalog = try? QuranResources.catalog()
        let first = catalog?.ayah(id: passage.firstAyahID)?.ayahNumber ?? 0
        let last = catalog?.ayah(id: passage.lastAyahID)?.ayahNumber ?? 0
        return "تفسير الآيات " + digits.string(first) + "–" + digits.string(last) + " معًا"
    }

    private func citation(_ page: QuranTafsirPageReference) -> String {
        let number = Int(page.printedPage).map { digits.string($0) } ?? page.printedPage
        guard let volume = Int(page.volume) else { return "الصفحة " + number }
        return "الجزء " + digits.string(volume) + "، الصفحة " + number
    }

    /// «تفسير السعدي = تيسير الكريم…» reads as «تفسير السعدي» in the small button.
    private func shortTitle(_ title: String) -> String {
        let cut = title.split(whereSeparator: { "=-(،".contains($0) }).first.map(String.init) ?? title
        return cut.trimmingCharacters(in: .whitespaces)
    }
}
