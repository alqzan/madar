import SwiftUI
import MadarDesign
import MadarCommands
import MadarData

struct QuranFreeView: View {
    let service: AppQuranService
    let close: () -> Void
    var initialRange: QuranUIRange? = nil
    @Environment(\.roomTheme) private var theme
    @State private var pages: [QuranUIIndexItem] = []
    @State private var from = 1
    @State private var through = 1
    @State private var pickingEnd = false
    @State private var preset = "range"
    @State private var session: QuranUISessionState?
    @State private var busy = false
    @State private var error: String?
    @State private var userSelectedRange = false
    @State private var selectLastAfterIndex = false
    @State private var injectedIndexDelay = false
    @State private var injectedStartFailure = false
    @State private var indexAttempt = 0
    private var range: ClosedRange<Int> { min(from,through)...max(from,through) }
    private var saved: Int { pages.filter { range.contains($0.firstPage) && $0.memorized }.count }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                QuranScreenHeader(title: "مراجعة حرة", close: close)
                Text("تختار ما تسمّعه خارج الجدول").font(quranFont(13)).foregroundStyle(theme.secondaryInk)
                Text("انقر من أين إلى أين، ويُحتسب في جدولك ما في صدرك وحده").font(quranFont(13))
                HStack(spacing: 4) {
                    ForEach([("last","آخر أوجه"),("surah","سورة"),("juz","الجزء"),("range","اختر نطاقًا")], id: \.0) { key, title in
                        Menu {
                            if key == "surah" {
                                ForEach(surahs, id: \.0) { id, title in Button(title) { selectSurah(id); preset = key }.accessibilityIdentifier("quran-free-surah-\(id)") }
                            } else if key == "juz" {
                                ForEach(1...30, id: \.self) { n in Button("الجزء " + service.numerals.string(n)) { selectJuz(n); preset = key }.accessibilityIdentifier("quran-free-juz-\(n)") }
                            } else { Button(title) {
                                preset = key
                                if key == "last" {
                                    userSelectedRange = true
                                    if pages.isEmpty { selectLastAfterIndex = true }
                                    else { selectLastAfterIndex = false; selectLastPages(pages) }
                                } else { selectLastAfterIndex = false }
                            }.accessibilityIdentifier("quran-free-preset-action-" + key) }
                        } label: { Text(title).font(quranFont(12, bold: preset == key)).frame(maxWidth: .infinity, minHeight: 44).background(preset == key ? theme.color("hifzTint") : theme.surface, in: Capsule()) }
                    .accessibilityIdentifier("quran-free-preset-" + key)
                    }
                }
                QuranPaperCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(pickingEnd ? "المس آخر وجه في النطاق" : "المس أول وجه، ثم آخر وجه").font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                        QuranPageMap(pages: pages, selected: range) { page in
                            userSelectedRange = true
                            selectLastAfterIndex = false
                            if pickingEnd { through = page; pickingEnd = false; if through < from { swap(&from, &through) } } else { from = page; through = page; pickingEnd = true }
                        }.disabled(busy)
                        Text("في صدرك: مصمت، راجعته: نقطة، المستحق: خط مائل، الاختيار: إطار").font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                        Stepper("من الوجه " + service.numerals.string(from), value: Binding(get: { from }, set: { from = $0; through = max(through, $0); userSelectedRange = true; selectLastAfterIndex = false }), in: 1...604)
                            .disabled(busy).accessibilityIdentifier("quran-free-from")
                        Stepper("إلى الوجه " + service.numerals.string(through), value: Binding(get: { through }, set: { through = $0; from = min(from, $0); userSelectedRange = true; selectLastAfterIndex = false }), in: 1...604)
                            .disabled(busy).accessibilityIdentifier("quran-free-through")
                    }.font(quranFont(14))
                }
                if let error { Text(error).font(quranFont(13)).foregroundStyle(theme.color("dueText")).accessibilityIdentifier("quran-free-error") }
                // AU-95: a failed index read left «ابدأ» disabled for good; one tap reads it again.
                if error != nil, pages.isEmpty {
                    Button("أعِد المحاولة") { error = nil; indexAttempt += 1 }
                        .font(quranFont(14, bold: true)).frame(minHeight: 44).contentShape(Rectangle())
                        .accessibilityIdentifier("quran-free-retry")
                }
            }.padding(16)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.color("review"))
            .safeAreaInset(edge: .bottom) {
                QuranPaperCard {
                    VStack(spacing: 10) {
                        Text("من الوجه " + service.numerals.string(range.lowerBound) + " إلى " + service.numerals.string(range.upperBound))
                            .font(quranFont(16, bold: true)).accessibilityIdentifier("quran-free-range-summary")
                        Text(saved == 0 ? "هذا النطاق للقراءة فقط؛ لا يُسجّل تقييمًا أو يزيد حفظك أو سلسلتك" : "يُسجّل من النطاق ما اكتمل في صدرك (" + service.faceCount(saved) + ")؛ الباقي قراءة فقط").font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                        Text("سرد متصل").font(quranFont(13)).frame(maxWidth: .infinity, minHeight: 38).glassEffect(.regular.interactive(), in: .capsule)
                        Button(saved == 0 ? "ابدأ القراءة" : "ابدأ التسميع") {
                            beginReading(range)
                        }.font(quranFont(16,bold:true)).foregroundStyle(theme.onAccent).frame(maxWidth:.infinity,minHeight:50).background(theme.accent,in:Capsule()).disabled(busy || pages.isEmpty).accessibilityIdentifier("quran-free-start")
                    }
                }.padding(16)
            }
            .task(id: indexAttempt) {
                do {
                    #if DEBUG
                    let environment = ProcessInfo.processInfo.environment
                    if !injectedIndexDelay, UUID(uuidString: environment["MADAR_UI_STORE_ID"] ?? "") != nil,
                       environment["MADAR_UI_QURAN_INDEX_DELAY_ONCE"] == "1" {
                        injectedIndexDelay = true
                        try await Task.sleep(for: .seconds(12))
                    }
                    #endif
                    let indexed = try await service.index(.page)
                    try Task.checkCancellation()
                    pages = indexed
                    if selectLastAfterIndex {
                        selectLastPages(indexed)
                        selectLastAfterIndex = false
                    } else if !userSelectedRange {
                        if let initialRange { from = initialRange.fromPage; through = initialRange.toPage }
                        else if let last = pages.last(where: \.memorized) { through = last.firstPage; from = max(1,through - 4) }
                    }
                } catch is CancellationError { }
                catch { self.error = quranUserMessage(error) }
            }
            .fullScreenCover(item: $session) { initial in QuranHomeSessionFlow(service: service, state: Binding(get: { session ?? initial }, set: { session = $0 }), close: { session = nil }) }
    }
    private static let surahList: [(Int,String)] = { guard let catalog = try? QuranResources.catalog() else { return [] }; return Dictionary(grouping:catalog.ayahs,by:\.surahID).sorted { $0.key < $1.key }.map { ($0.key,$0.value[0].surahNameArabic) } }()
    private var surahs: [(Int,String)] { Self.surahList }
    private func selectLastPages(_ indexed: [QuranUIIndexItem]) {
        // AU-34: with nothing memorised the preset says why it cannot pick, instead of silently choosing page 1.
        guard let last = indexed.filter(\.memorized).map(\.firstPage).max() else { error = "لا شيء في صدرك بعد؛ اختر سورة أو نطاقًا للقراءة"; return }
        error = nil; through = last; from = max(1, last - 4)
    }
    private func selectSurah(_ id: Int) { guard let ayahs = try? QuranResources.catalog().ayahs.filter({ $0.surahID == id }),let first=ayahs.first,let last=ayahs.last else { return };from=first.page;through=last.page;userSelectedRange = true;selectLastAfterIndex = false }
    private func selectJuz(_ n: Int) { guard let ayahs = try? QuranResources.catalog().ayahs.filter({ $0.juz == n }),let first=ayahs.first,let last=ayahs.last else { return };from=first.page;through=last.page;userSelectedRange = true;selectLastAfterIndex = false }
    private func beginReading(_ selectedRange: ClosedRange<Int>) {
        guard !busy else { return }
        error = nil; busy = true
        let request = QuranUIRange(fromPage: selectedRange.lowerBound, toPage: selectedRange.upperBound)
        Task { @MainActor in
            defer { busy = false }
            do {
                #if DEBUG
                let environment = ProcessInfo.processInfo.environment
                if !injectedStartFailure, UUID(uuidString: environment["MADAR_UI_STORE_ID"] ?? "") != nil,
                   environment["MADAR_UI_QURAN_FREE_START_FAILURE_ONCE"] == "1" {
                    injectedStartFailure = true
                    throw DataError.invalidValue("تعذّر بدء القراءة في الاختبار. حاول مرة أخرى")
                }
                #endif
                session = try await service.start(kind: .free, stepID: nil, range: request, rakaat: nil, spotID: nil)
            } catch { self.error = quranUserMessage(error) }
        }
    }
}
