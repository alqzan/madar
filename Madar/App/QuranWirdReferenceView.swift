import SwiftUI
import MadarCore
import MadarCommands
import MadarDesign
import MadarQuran

struct QuranWirdReferenceRequest: Identifiable {
    let id = UUID()
    let range: QuranAyahRange
}

enum QuranWirdReferenceKind: String, Sendable, Equatable {
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

struct QuranWirdReferenceExcerpt: Identifiable, Sendable {
    let id: String
    let ayahID: Int
    let kind: QuranWirdReferenceKind
    let text: String
    let book: String
    let author: String
    let citation: String
    let sourceURL: URL
    let sourceNote: String?

    static let verified: [Self] = [
        .init(
            id: "tabari-1-2",
            ayahID: 2,
            kind: .tafsir,
            text: "الشكرُ للَّهِ خالصًا دونَ سائرِ ما يُعْبَدُ مِن دونِه",
            book: "تفسير الطبري جامع البيان - ت التركي",
            author: "ابن جرير الطبري",
            citation: "١/ ١٣٥",
            sourceURL: URL(string: "https://shamela.ws/book/7798/315")!,
            sourceNote: nil
        ),
        .init(
            id: "qurtubi-1-3-in-ibn-kathir",
            ayahID: 3,
            kind: .tafsir,
            text: "ليكون من باب قرن الترغيب بعد الترهيب",
            book: "تفسير ابن كثير - ط ابن الجوزي",
            author: "القرطبي (نقلًا عن ابن كثير)",
            citation: "١/ ٢٠٢",
            sourceURL: URL(string: "https://shamela.ws/book/1503/257")!,
            sourceNote: "ينقل ابن كثير هذا التعليل عن القرطبي."
        ),
        .init(
            id: "ibn-kathir-1-4",
            ayahID: 4,
            kind: .tafsir,
            text: "وكلاهما صحيح متواتر في السبع",
            book: "تفسير ابن كثير - ط ابن الجوزي",
            author: "ابن كثير",
            citation: "١/ ٢٠٢",
            sourceURL: URL(string: "https://shamela.ws/book/1503/257")!,
            sourceNote: "عن قراءتي «مَلِكِ» و«مَالِكِ» في آية يوم الدين."
        ),
        .init(
            id: "ibn-kathir-1-5",
            ayahID: 5,
            kind: .tafsir,
            text: "وفي الشرع عبارة عما يجمع كمال المحبة والخضوع والخوف",
            book: "تفسير ابن كثير - ط ابن الجوزي",
            author: "ابن كثير",
            citation: "١/ ٢٠٥",
            sourceURL: URL(string: "https://shamela.ws/book/1503/260")!,
            sourceNote: nil
        ),
        .init(
            id: "saadi-2-182",
            ayahID: 189,
            kind: .tafsir,
            text: "ينبغي لمن حضر الموصي وقت الوصية بها، أن ينصحه بما هو الأحسن والأعدل",
            book: "تفسير السعدي = تيسير الكريم الرحمن",
            author: "عبد الرحمن السعدي",
            citation: "ص ٨٥",
            sourceURL: URL(string: "https://shamela.ws/book/42/122")!,
            sourceNote: nil
        ),
        .init(
            id: "saadi-2-183",
            ayahID: 190,
            kind: .tafsir,
            text: "فإن الصيام من أكبر أسباب التقوى",
            book: "تفسير السعدي = تيسير الكريم الرحمن",
            author: "عبد الرحمن السعدي",
            citation: "ص ٨٦",
            sourceURL: URL(string: "https://shamela.ws/book/42/123")!,
            sourceNote: nil
        ),
        .init(
            id: "ibn-kathir-2-184",
            ayahID: 191,
            kind: .tafsir,
            text: "لئلا يشق على النفوس",
            book: "تفسير ابن كثير - ط ابن الجوزي",
            author: "ابن كثير",
            citation: "٢/ ٥٣",
            sourceURL: URL(string: "https://shamela.ws/book/1503/758")!,
            sourceNote: nil
        ),
        .init(
            id: "ibn-kathir-2-185",
            ayahID: 192,
            kind: .tafsir,
            text: "يمدح تعالى شهر الصيام من بين سائر الشهور بأن اختاره من بينهن لإنزال القرآن العظيم",
            book: "تفسير ابن كثير - ط ابن الجوزي",
            author: "ابن كثير",
            citation: "٢/ ٥٧",
            sourceURL: URL(string: "https://shamela.ws/book/1503/762")!,
            sourceNote: nil
        ),
        .init(
            id: "ibn-ashur-2-186",
            ayahID: 193,
            kind: .tafsir,
            text: "وَجُعِلَ هَذَا الْخَيْرُ مُرَتَّبًا عَلَى تَقْدِيرِ سُؤَالِهِمْ",
            book: "تفسير ابن عاشور التحرير والتنوير",
            author: "ابن عاشور",
            citation: "٢/ ١٧٨",
            sourceURL: URL(string: "https://shamela.ws/book/9776/945")!,
            sourceNote: nil
        ),
        .init(
            id: "ibn-kathir-2-187",
            ayahID: 194,
            kind: .tafsir,
            text: "هذه رخصة من الله تعالى للمسلمين، ورفع لما كان عليه الأمر في ابتداء الإسلام…",
            book: "تفسير ابن كثير - ط ابن الجوزي",
            author: "ابن كثير",
            citation: "٢/ ٦٧",
            sourceURL: URL(string: "https://shamela.ws/book/1503/772")!,
            sourceNote: nil
        ),
        .init(
            id: "bukhari-2-187",
            ayahID: 194,
            kind: .asbab,
            text: "فَلَمَّا انْتَصَفَ النَّهَارُ غُشِيَ عَلَيْهِ، فَذُكِرَ ذَلِكَ لِلنَّبِيِّ ﷺ فَنَزَلَتْ هَذِهِ الْآيَةُ…",
            book: "صحيح البخاري - ت البغا",
            author: "البخاري",
            citation: "٢/ ٦٧٦",
            sourceURL: URL(string: "https://shamela.ws/book/735/3072")!,
            sourceNote: nil
        ),
        .init(
            id: "maathur-2-188",
            ayahID: 195,
            kind: .asbab,
            text: "وأراد امرؤُ القيس أن يحلف؛ ففيه نزلت: ﴿ولا تأكلوا أموالكم بينكم بالباطل﴾",
            book: "موسوعة التفسير المأثور",
            author: "مجموعة من المؤلفين",
            citation: "٣/ ٤٢٣",
            sourceURL: URL(string: "https://shamela.ws/book/639/1698")!,
            sourceNote: "أورده المصدر عن سعيد بن جبير، من طريق عطاء بن دينار؛ ولا يحكم هذا الموضع على إسناده."
        ),
        .init(
            id: "ibn-kathir-2-188",
            ayahID: 195,
            kind: .tafsir,
            text: "أي: تعلمون بطلان ما تدعونه وتروجونه في كلامكم…",
            book: "تفسير ابن كثير - ط ابن الجوزي",
            author: "ابن كثير",
            citation: "٢/ ٧٩",
            sourceURL: URL(string: "https://shamela.ws/book/1503/784")!,
            sourceNote: nil
        ),
        .init(
            id: "ibn-kathir-2-255",
            ayahID: 262,
            kind: .tafsir,
            text: "هذه آية الكرسي، ولها شأن عظيم",
            book: "تفسير ابن كثير - ط ابن الجوزي",
            author: "ابن كثير",
            citation: "٢/ ٢٣٩",
            sourceURL: URL(string: "https://shamela.ws/book/1503/944")!,
            sourceNote: nil
        ),
        .init(
            id: "saadi-2-286",
            ayahID: 293,
            kind: .tafsir,
            text: "بل هي غذاء للأرواح ودواء للأبدان",
            book: "تفسير السعدي = تيسير الكريم الرحمن",
            author: "عبد الرحمن السعدي",
            citation: "ص ١٢٠",
            sourceURL: URL(string: "https://shamela.ws/book/42/195")!,
            sourceNote: nil
        ),
        .init(
            id: "saadi-3-190",
            ayahID: 483,
            kind: .tafsir,
            text: "وخص الله بالآيات أولي الألباب، وهم أهل العقول؛ لأنهم هم المنتفعون بها، الناظرون إليها بعقولهم لا بأبصارهم.",
            book: "تفسير السعدي = تيسير الكريم الرحمن",
            author: "عبد الرحمن السعدي",
            citation: "ص ١٦١",
            sourceURL: URL(string: "https://shamela.ws/book/42/284")!,
            sourceNote: nil
        ),
        .init(
            id: "maathur-3-190-context",
            ayahID: 483,
            kind: .context,
            text: "ولِمَ لا أفعل وقد أنزل علي هذه الليلة",
            book: "موسوعة التفسير المأثور",
            author: "مجموعة من المؤلفين",
            citation: "٥/ ٧٦٢",
            sourceURL: URL(string: "https://shamela.ws/book/639/3482")!,
            sourceNote: "تورد الموسوعة الخبر عن عائشة في قيام النبي ﷺ وتلاوته الآيات؛ وتنقل حاشيتها عن الألباني: «إسناد جيد». يصف الخبر تلاوة الآيات ولا يذكر حادثةً سبقت نزولها."
        ),
        .init(
            id: "saadi-2-189",
            ayahID: 196,
            kind: .context,
            text: "فلو كان الحساب بالسنة الشمسية، لم يعرفه إلا النادر من الناس",
            book: "تفسير السعدي = تيسير الكريم الرحمن",
            author: "عبد الرحمن السعدي",
            citation: "ص ٨٨",
            sourceURL: URL(string: "https://shamela.ws/book/42/127")!,
            sourceNote: "في بيان فائدة جعل الأهلة مواقيت للعبادات والمعاملات."
        )
    ]
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
    let close: () -> Void

    @Environment(\.roomTheme) private var theme
    @State private var ayahs: [QuranAyahResourceRecord] = []
    @State private var filter: QuranWirdReferenceFilter = .all
    @State private var showingAyahs = false
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
                        Text("مقتطفات موثّقة للتفسير والسياق، وسبب النزول حين يصرّح به المصدر.")
                            .font(bodyFont(12)).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("quran-reference-intro")
                    }
                    filterPicker
                    if loading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    } else if failed {
                        failureState
                    } else {
                        let matchingAyahs = ayahs.filter { !entries(for: $0).isEmpty }
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
        .task(id: retryCount) { loadAyahs() }
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

    private var failureState: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("تعذّر فتح خريطة آيات الورد.").font(bodyFont(14, bold: true))
                Button("حاول مرة أخرى") { retryCount += 1 }
                    .font(bodyFont(13, bold: true)).frame(minHeight: 44)
                    .accessibilityIdentifier("quran-reference-retry")
            }
        }
    }

    private var emptyState: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Label("لا مقتطف موثّق لهذا الاختيار في فهرس الورد الحالي", systemImage: "books.vertical")
                    .font(bodyFont(14, bold: true)).fixedSize(horizontal: false, vertical: true)
                Text("عدم ظهور مقتطف هنا لا يعني خلوّ الآيات من التفسير أو سبب النزول.")
                    .font(bodyFont(12)).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
        }.accessibilityIdentifier("quran-reference-empty")
    }

    private func partialCoverageState(coveredCount: Int) -> some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "تظهر مقتطفات موثّقة لـ \(digits.string(coveredCount)) من \(digits.string(ayahs.count)) آيات بحسب الاختيار الحالي.",
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
                                Text(ayah.surahNameArabic + " · " + digits.string(ayah.ayahNumber))
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
                ForEach(entries(for: ayah)) { excerpt in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(excerpt.kind.title).font(bodyFont(12, bold: true)).foregroundStyle(theme.secondaryInk)
                        Text("«" + excerpt.text + "»")
                            .font(.custom("Amiri-Regular", size: 19, relativeTo: .title3))
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("quran-reference-excerpt-\(excerpt.kind.rawValue)-\(ayah.id)")
                        if let sourceNote = excerpt.sourceNote {
                            Text(sourceNote).font(bodyFont(11)).foregroundStyle(theme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("quran-reference-note-\(excerpt.id)")
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(excerpt.book).font(bodyFont(12, bold: true))
                            Text(excerpt.author + " · " + excerpt.citation)
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
            excerpt.ayahID == ayah.id && (filter.kind == nil || excerpt.kind == filter.kind)
        }
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
