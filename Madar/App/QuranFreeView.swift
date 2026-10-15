import SwiftUI
import MadarDesign
import MadarCommands

struct QuranFreeView: View {
    let service: AppQuranService
    let close: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var pages: [QuranUIIndexItem] = []
    @State private var from = 1
    @State private var through = 1
    @State private var pickingEnd = false
    @State private var preset = "range"
    @State private var session: QuranUISessionState?
    @State private var busy = false
    @State private var error: String?
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
                                ForEach(surahs, id: \.0) { id, title in Button(title) { selectSurah(id); preset = key } }
                            } else if key == "juz" {
                                ForEach(1...30, id: \.self) { n in Button("الجزء " + service.numerals.string(n)) { selectJuz(n); preset = key } }
                            } else { Button(title) { preset = key; if key == "last" { let saved = pages.filter(\.memorized).map(\.firstPage); through = saved.max() ?? 1; from = max(1,through - 4) } } }
                        } label: { Text(title).font(quranFont(12, bold: preset == key)).frame(maxWidth: .infinity, minHeight: 44).background(preset == key ? theme.color("hifzTint") : theme.surface, in: Capsule()) }
                    }
                }
                QuranPaperCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(pickingEnd ? "المس آخر وجه في النطاق" : "المس أول وجه، ثم آخر وجه").font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                        QuranPageMap(pages: pages, selected: range) { page in
                            if pickingEnd { through = page; pickingEnd = false } else { from = page; through = page; pickingEnd = true }
                        }
                        Text("في صدرك: مصمت، راجعته: نقطة، المستحق: خط مائل، الاختيار: إطار").font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                        Stepper("من الوجه " + service.numerals.string(from), value: $from, in: 1...604).accessibilityIdentifier("quran-free-from")
                        Stepper("إلى الوجه " + service.numerals.string(through), value: $through, in: 1...604).accessibilityIdentifier("quran-free-through")
                    }.font(quranFont(14))
                }
                if let error { Text(error).font(quranFont(13)).foregroundStyle(theme.color("dueText")) }
            }.padding(16)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.color("review"))
            .safeAreaInset(edge: .bottom) {
                QuranPaperCard {
                    VStack(spacing: 10) {
                        Text("من الوجه " + service.numerals.string(range.lowerBound) + " إلى " + service.numerals.string(range.upperBound)).font(quranFont(16, bold: true))
                        Text(saved == 0 ? "هذا النطاق للقراءة فقط؛ لا يُسجّل تقييمًا أو يزيد حفظك أو سلسلتك" : "يُسجّل من النطاق " + service.faceCount(saved) + " مكتملة في صدرك؛ الباقي قراءة فقط").font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                        Text("سرد متصل").font(quranFont(13)).frame(maxWidth: .infinity, minHeight: 38).overlay { Capsule().stroke(theme.color("review"), lineWidth: 1) }
                        Button(saved == 0 ? "ابدأ القراءة" : "ابدأ التسميع") {
                            busy = true; Task { defer { busy = false }; do { session = try await service.start(kind: .free, stepID: nil, range: QuranUIRange(fromPage: range.lowerBound,toPage: range.upperBound), rakaat: nil, spotID: nil) } catch { self.error = quranUserMessage(error) } }
                        }.font(quranFont(16,bold:true)).foregroundStyle(theme.onAccent).frame(maxWidth:.infinity,minHeight:50).background(theme.accent,in:Capsule()).disabled(busy).accessibilityIdentifier("quran-free-start")
                    }
                }.padding(16)
            }
            .task { do { pages = try await service.index(.page); if let last = pages.last(where: \.memorized) { through = last.firstPage; from = max(1,through - 4) } } catch { self.error = quranUserMessage(error) } }
            .fullScreenCover(item: $session) { initial in QuranHomeSessionFlow(service: service, state: Binding(get: { session ?? initial }, set: { session = $0 }), close: { session = nil }) }
    }
    private var surahs: [(Int,String)] { guard let catalog = try? QuranResources.catalog() else { return [] }; return Dictionary(grouping:catalog.ayahs,by:\.surahID).sorted { $0.key < $1.key }.map { ($0.key,$0.value[0].surahNameArabic) } }
    private func selectSurah(_ id: Int) { guard let ayahs = try? QuranResources.catalog().ayahs.filter({ $0.surahID == id }),let first=ayahs.first,let last=ayahs.last else { return };from=first.page;through=last.page }
    private func selectJuz(_ n: Int) { guard let ayahs = try? QuranResources.catalog().ayahs.filter({ $0.juz == n }),let first=ayahs.first,let last=ayahs.last else { return };from=first.page;through=last.page }
}
