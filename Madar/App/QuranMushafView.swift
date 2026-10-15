import SwiftUI
import MadarDesign

/// R18-Mushaf, with the owner's borderless 1405 palette and the verified 1439 page glyphs.
struct QuranMushafView: View {
    let service: AppQuranService
    let initialPage: Int
    let close: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var number = 1
    @State private var page: QuranUIPage?
    @State private var error: String?
    @State private var tools = false
    @State private var verses = false
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    @State private var pan = CGSize.zero
    @GestureState private var dragging = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                theme.color("mushafPaper").ignoresSafeArea()
                if let page {
                    QuranCoachPage(page: page, coach: reading(page), stage: .grading, reveal: { _ in }, readingTap: { tools.toggle() })
                        .scaleEffect(scale).offset(offset(in: geometry.size))
                        .gesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }.onEnded { value in zoom = min(3, max(1, zoom * value.magnification)); if zoom == 1 { pan = .zero } })
                        .simultaneousGesture(DragGesture(minimumDistance: 20).updating($dragging) { value, state, _ in if scale > 1 { state = value.translation } }.onEnded { value in
                            if zoom > 1 { pan = bounded(CGSize(width: pan.width + value.translation.width, height: pan.height + value.translation.height), in: geometry.size) }
                            else if abs(value.translation.width) > 60, abs(value.translation.width) > abs(value.translation.height) { move(value.translation.width > 0 ? 1 : -1) }
                        })
                        .onTapGesture(count: 2) { zoom = zoom == 1 ? 2 : 1; pan = .zero }
                        .clipped()
                        .accessibilityIdentifier("quran-mushaf-page")
                        .accessibilityAction(named: "إظهار الأدوات") { tools = true }
                        .accessibilityScrollAction { edge in if edge == .leading { move(1) } else if edge == .trailing { move(-1) } }
                } else if let error {
                    VStack(spacing: 16) { Text(error); Button("حاول مرة أخرى") { Task { await load() } }; Button("رجوع", action: close) }.padding(24)
                } else { ProgressView() }
                if tools { controls }
            }
        }
        .foregroundStyle(theme.ink).background(theme.color("mushafPaper").ignoresSafeArea())
        .statusBarHidden(!tools).interactiveDismissDisabled()
        .task { number = min(604, max(1, initialPage)); await load() }
        .task(id: number) { await load() }
        .sheet(isPresented: $verses) {
            if let page { QuranAyahReaderSheet(page: page, close: { verses = false }).environment(\.roomTheme, theme).environment(\.layoutDirection, .rightToLeft) }
        }
    }
    private var scale: CGFloat { min(3, max(1, zoom * magnification)) }
    private func bounded(_ value: CGSize, in size: CGSize) -> CGSize {
        let x = size.width * (scale - 1) / 2, y = size.height * (scale - 1) / 2
        return CGSize(width: min(x, max(-x, value.width)), height: min(y, max(-y, value.height)))
    }
    private func offset(in size: CGSize) -> CGSize { bounded(CGSize(width: pan.width + dragging.width, height: pan.height + dragging.height), in: size) }
    private func reading(_ page: QuranUIPage) -> QuranUICoach {
        let ids = Set(page.semanticAyat.map(\.id))
        return QuranUICoach(activeAyahID: 0, activeAyahNumber: "", plannedAyahs: ids, revealedAyahs: ids, repetition: 0, target: 0, bridge: false, method: "continuous", stageTitle: "", pageProgress: "", caption: "", pages: [page.page], pastDay: false)
    }
    private var controls: some View {
        VStack {
            HStack {
                icon("xmark", label: "إغلاق المصحف", id: "quran-mushaf-close", action: close)
                Spacer()
                Text(page?.title ?? "المصحف").font(MadarTypography.section()).accessibilityIdentifier("quran-mushaf-number")
                Spacer()
                icon("chevron.down", label: "إخفاء الأدوات", id: "quran-mushaf-hide") { tools = false }
            }.padding(8).background(theme.surface, in: Capsule())
            Spacer()
            HStack(spacing: 4) {
                icon("chevron.right", label: "الوجه السابق", id: "quran-mushaf-previous") { move(-1) }.disabled(number == 1)
                icon("chevron.left", label: "الوجه التالي", id: "quran-mushaf-next") { move(1) }.disabled(number == 604)
                Spacer(minLength: 0)
                Button("آية آية") { verses = true }.font(MadarTypography.caption()).frame(minHeight: 44).accessibilityIdentifier("quran-mushaf-ayahs")
                Spacer(minLength: 0)
                icon(zoom == 1 ? "plus.magnifyingglass" : "minus.magnifyingglass", label: zoom == 1 ? "تكبير" : "الحجم الطبيعي", id: "quran-mushaf-zoom") { zoom = zoom == 1 ? 2 : 1; pan = .zero }
            }.padding(8).background(theme.surface, in: Capsule())
        }.padding(12)
    }
    private func icon(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44) }
            .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private func move(_ delta: Int) { let next = min(604, max(1, number + delta)); if next != number { number = next; page = nil; zoom = 1; pan = .zero } }
    private func load() async {
        let requested = number
        do { let loaded = try await service.page(requested); guard number == requested else { return }; page = loaded; error = nil }
        catch { guard number == requested else { return }; self.error = quranUserMessage(error) }
    }
}

private struct QuranAyahReaderSheet: View {
    let page: QuranUIPage
    let close: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var position = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { Text("آية آية").font(MadarTypography.cardTitle()); Spacer(); Button("تمّ", action: close).frame(minHeight: 44) }
                if page.semanticAyat.indices.contains(position) {
                    let ayah = page.semanticAyat[position]
                    Text(ayah.title).font(MadarTypography.section())
                    Text(ayah.text).font(.custom("Amiri-Regular", size: 28, relativeTo: .title2)).lineSpacing(10).accessibilityIdentifier("quran-mushaf-semantic-ayah")
                    HStack {
                        Button("السابقة") { position -= 1 }.disabled(position == 0)
                        Spacer()
                        Button("التالية") { position += 1 }.disabled(position == page.semanticAyat.count - 1)
                    }.frame(minHeight: 44)
                }
            }.padding(24)
        }.foregroundStyle(theme.ink).background(theme.surface).presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}
