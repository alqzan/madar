import SwiftUI
import MadarCommands
import MadarDesign

/// R18-Mushaf, with the owner's borderless 1405 palette and the verified 1439 page glyphs.
struct QuranMushafView: View {
    let service: AppQuranService
    let initialPage: Int
    /// FB-33: opened on an ayah (the wird's first), its tafsir is already up.
    var initialAyah: Int? = nil
    let close: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var number = 1
    @State private var page: QuranUIPage?
    @State private var error: String?
    @State private var tools = false
    /// The page fills the screen with no chrome, so the first reading says once how to bring the controls back.
    @State private var hint = !UserDefaults.standard.bool(forKey: "quran.mushaf.toolsHintSeen")
    /// FB-33: the ayah pressed for tafsir; nil when no sheet is up.
    @State private var selectedAyah: Int?
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    @State private var pan = CGSize.zero
    @GestureState private var dragging = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                theme.color("mushafPaper").ignoresSafeArea()
                if let page {
                    QuranCoachPage(page: page, coach: reading(page), stage: .grading, reveal: { _ in },
                                   readingTap: { if selectedAyah != nil { selectedAyah = nil } else { tools.toggle() } },
                                   medinaStyle: true, selectedAyah: selectedAyah, ayahPress: { selectedAyah = $0; tools = false })
                        .frame(width: geometry.size.width, height: min(geometry.size.height, geometry.size.width * 1.64))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    VStack(spacing: 16) { Text(error); Button("حاول مرة أخرى") { self.error = nil; Task { await load() } }; Button("رجوع", action: close) }.padding(24)
                } else { ProgressView() }
                // AU-18: while the page loads there is no page to tap, so the close stays visible.
                if tools || (page == nil && error == nil) { controls }
                if hint && !tools && page != nil {
                    VStack { Spacer(); Text("اضغط مطوّلًا على آية لتفسيرها، والمس الصفحة للأدوات").font(MadarTypography.caption()).padding(.horizontal, 16).padding(.vertical, 10).glassEffect(.regular, in: .capsule).padding(.bottom, 28) }
                        .allowsHitTesting(false).transition(.opacity).accessibilityHidden(true)
                }
            }
        }
        .foregroundStyle(theme.ink).background(theme.color("mushafPaper").ignoresSafeArea())
        .statusBarHidden(!tools).interactiveDismissDisabled()
        .onChange(of: tools) { _, shown in if shown { hint = false; UserDefaults.standard.set(true, forKey: "quran.mushaf.toolsHintSeen") } }
        .task(id: page != nil) { guard hint, page != nil else { return }; try? await Task.sleep(for: .seconds(5)); withAnimation { hint = false } }
        .task { number = min(604, max(1, initialPage)); if let initialAyah { selectedAyah = initialAyah } }
        .task(id: number) { await load() }
        .task { await QuranTafsirLibrary.shared.loadLocal() }
        .sheet(isPresented: Binding(get: { selectedAyah != nil }, set: { if !$0 { selectedAyah = nil } })) {
            if let selectedAyah {
                QuranAyahTafsirSheet(app: service.app, ayahID: selectedAyah, digits: service.numerals, select: open, close: { self.selectedAyah = nil })
                    .environment(\.roomTheme, theme)
            }
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
            }.padding(8).glassEffect(.regular, in: .capsule)
            Spacer()
            HStack(spacing: 4) {
                icon("chevron.right", label: "الوجه السابق", id: "quran-mushaf-previous") { move(-1) }.disabled(number == 1)
                icon("chevron.left", label: "الوجه التالي", id: "quran-mushaf-next") { move(1) }.disabled(number == 604)
                Spacer(minLength: 0)
                Button { selectedAyah = page?.semanticAyat.first?.id; tools = false } label: { Label("التفسير", systemImage: "text.book.closed") }
                    .font(MadarTypography.caption()).frame(minHeight: 44).buttonStyle(.madarPlain).disabled(page?.semanticAyat.isEmpty ?? true)
                    .accessibilityIdentifier("quran-mushaf-ayahs")
                Spacer(minLength: 0)
                icon(zoom == 1 ? "plus.magnifyingglass" : "minus.magnifyingglass", label: zoom == 1 ? "تكبير" : "الحجم الطبيعي", id: "quran-mushaf-zoom") { zoom = zoom == 1 ? 2 : 1; pan = .zero }
            }.padding(8).glassEffect(.regular, in: .capsule)
        }.padding(12)
    }
    private func icon(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44) }
            .buttonStyle(.madarPlain).accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private func move(_ delta: Int) { selectedAyah = nil; go(to: number + delta) }
    private func go(to target: Int) { let next = min(604, max(1, target)); if next != number { number = next; page = nil; error = nil; zoom = 1; pan = .zero } }
    /// The tafsir sheet walked to another ayah: light it, and turn the page when it starts on another one.
    private func open(_ ayahID: Int) {
        guard let ayah = try? QuranResources.catalog().ayah(id: ayahID) else { return }
        selectedAyah = ayahID
        if ayah.page != number && !(page?.semanticAyat.contains { $0.id == ayahID } ?? false) { go(to: ayah.page) }
    }
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
