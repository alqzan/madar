import SwiftUI
import MadarCommands
import MadarDesign

/// R18-Mushaf, with the owner's borderless 1405 palette and the verified 1439 page glyphs.
struct QuranMushafView: View {
    private struct PageRequest: Equatable {
        let page: Int
        var attempt = 0
    }
    private struct PageLoad: Equatable {
        let request: PageRequest
        let wantsSpread: Bool
    }

    let service: AppQuranService
    let close: () -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var request: PageRequest
    @State private var page: QuranUIPage?
    @State private var failedFace: Int?
    #if DEBUG
    @State private var injectedReadFailure = false
    #endif
    @State private var tools = false
    /// The page fills the screen with no chrome, so the first reading says once how to bring the controls back.
    @State private var hint = !UserDefaults.standard.bool(forKey: "quran.mushaf.toolsHintSeen")
    /// FB-33: the ayah pressed for tafsir; nil when no sheet is up.
    @State private var selectedAyah: Int?
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    @State private var pan = CGSize.zero
    @GestureState private var dragging = CGSize.zero
    /// iPad landscape shows two facing pages; `facing` is the other page of the open spread.
    @State private var landscapeWide = false
    @State private var facing: QuranUIPage?
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The naming alert captures the visible face, which may still be on screen during a page turn.
    @State private var bookmarks: [QuranBookmark] = []
    @State private var bookmarkPage: Int?
    @State private var bookmarkName = ""
    @State private var bookmarkError: String?

    /// FB-33: an ayah link opens its tafsir with the reader.
    init(service: AppQuranService, initialPage: Int, initialAyah: Int? = nil, close: @escaping () -> Void) {
        self.service = service
        self.close = close
        _request = State(initialValue: PageRequest(page: min(604, max(1, initialPage))))
        _selectedAyah = State(initialValue: initialAyah)
    }

    private var pendingLoad: PageLoad { .init(request: request, wantsSpread: landscapeWide && isPadWide(sizeClass)) }
    private var twoUp: Bool { pendingLoad.wantsSpread && facing != nil }
    private func sheet(_ page: QuranUIPage) -> some View {
        QuranCoachPage(page: page, coach: reading(page), stage: .grading, reveal: { _ in },
                       readingTap: { if selectedAyah != nil { selectedAyah = nil } else { tools.toggle() } },
                       medinaStyle: true, selectedAyah: selectedAyah, ayahPress: { selectedAyah = $0; tools = false })
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                theme.color("mushafPaper").ignoresSafeArea()
                if let page {
                    Group {
                        if twoUp, let facing {
                            // iPad landscape: the open book, odd page on the right and its facing even page on the left.
                            let right = page.page % 2 == 1 ? page : facing, left = page.page % 2 == 1 ? facing : page
                            let width = min(geometry.size.width / 2, geometry.size.height / 1.64)
                            HStack(spacing: 0) {
                                sheet(right).frame(width: width, height: min(geometry.size.height, width * 1.64))
                                Rectangle().fill(LinearGradient(colors: [theme.ink.opacity(0), theme.ink.opacity(0.12), theme.ink.opacity(0)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: 14).accessibilityHidden(true)
                                sheet(left).frame(width: width, height: min(geometry.size.height, width * 1.64))
                            }
                        } else {
                            sheet(page).frame(width: geometry.size.width, height: min(geometry.size.height, geometry.size.width * 1.64))
                        }
                    }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaleEffect(scale).offset(offset(in: geometry.size))
                        .gesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }.onEnded { value in zoom = min(3, max(1, zoom * value.magnification)); if zoom == 1 { pan = .zero } })
                        .simultaneousGesture(DragGesture(minimumDistance: 20).updating($dragging) { value, state, _ in if scale > 1 { state = value.translation } }.onEnded { value in
                            if zoom > 1 { pan = bounded(CGSize(width: pan.width + value.translation.width, height: pan.height + value.translation.height), in: geometry.size) }
                            else if abs(value.translation.width) > 60, abs(value.translation.width) > abs(value.translation.height) { turn(forward: value.translation.width > 0) }
                        })
                        .onTapGesture(count: 2) { zoom = zoom == 1 ? 2 : 1; pan = .zero }
                        .clipped()
                        .accessibilityIdentifier("quran-mushaf-page")
                        .accessibilityAction(named: "إظهار الأدوات") { tools = true }
                        .accessibilityScrollAction { edge in if edge == .leading { turn(forward: true) } else if edge == .trailing { turn(forward: false) } }
                } else if failedFace == nil { ProgressView() }
                // AU-18: while the page loads there is no page to tap, so the close stays visible.
                if tools || (page == nil && failedFace == nil) { controls }
                if let failedFace {
                    VStack {
                        if page != nil { Spacer() }
                        loadFailure(failedFace)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, page == nil ? 0 : tools ? 76 : 12)
                }
                if hint && !tools && failedFace == nil && page != nil {
                    VStack { Spacer(); Text("اضغط مطوّلًا على آية لتفسيرها، والمس الصفحة للأدوات").font(MadarTypography.caption()).padding(.horizontal, 16).padding(.vertical, 10).glassEffect(.regular, in: .capsule).padding(.bottom, 28) }
                        .allowsHitTesting(false).transition(.opacity).accessibilityHidden(true)
                }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height && $0.size.width >= 900 } action: { landscapeWide = $0 }
        .foregroundStyle(theme.ink).background(theme.color("mushafPaper").ignoresSafeArea())
        .statusBarHidden(!tools).interactiveDismissDisabled()
        .onChange(of: tools) { _, shown in if shown { hint = false; UserDefaults.standard.set(true, forKey: "quran.mushaf.toolsHintSeen") } }
        .task(id: page != nil) { guard hint, page != nil else { return }; try? await Task.sleep(for: .seconds(5)); withAnimation { hint = false } }
        .task(id: pendingLoad) { [pendingLoad] in await load(pendingLoad) }
        .task { await QuranTafsirLibrary.shared.loadLocal() }
        .task { await loadBookmarks() }
        .alert("لم تكتمل عملية العلامة", item: $bookmarkError) { _ in
            Button("تمّ", role: .cancel) {}
        } message: { Text($0) }
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
    private func loadFailure(_ failedFace: Int) -> some View {
        QuranPaperCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("تعذّر فتح الوجه \(service.numerals.string(failedFace))")
                    .font(quranFont(15)).accessibilityIdentifier("quran-mushaf-read-error")
                Button(action: retryLoad) {
                    Text("حاول مرة أخرى").font(quranFont(14, bold: true)).frame(minHeight: 44)
                        .contentShape(Rectangle())
                }.buttonStyle(.madarPlain).accessibilityIdentifier("quran-mushaf-retry")
                if page == nil {
                    Button(action: close) {
                        Text("رجوع").font(quranFont(14)).frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("quran-mushaf-error-close")
                }
            }
        }
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
                icon("chevron.right", label: twoUp ? "الصفحتان السابقتان" : "الوجه السابق", id: "quran-mushaf-previous") { turn(forward: false) }
                    .disabled(turnTarget(forward: false) == nil)
                icon("chevron.left", label: twoUp ? "الصفحتان التاليتان" : "الوجه التالي", id: "quran-mushaf-next") { turn(forward: true) }
                    .disabled(turnTarget(forward: true) == nil)
                Spacer(minLength: 0)
                Button { selectedAyah = page?.semanticAyat.first?.id; tools = false } label: { Label("التفسير", systemImage: "text.book.closed") }
                    .font(MadarTypography.caption()).frame(minHeight: 44).buttonStyle(.madarPlain).disabled(page?.semanticAyat.isEmpty ?? true)
                    .accessibilityIdentifier("quran-mushaf-ayahs")
                Spacer(minLength: 0)
                bookmarkMenu
                icon(zoom == 1 ? "plus.magnifyingglass" : "minus.magnifyingglass", label: zoom == 1 ? "تكبير" : "الحجم الطبيعي", id: "quran-mushaf-zoom") { zoom = zoom == 1 ? 2 : 1; pan = .zero }
            }.padding(8).glassEffect(.regular, in: .capsule)
        }.padding(12)
    }
    private var marked: [QuranBookmark] { bookmarks.filter { $0.page == page?.page || (twoUp && $0.page == facing?.page) } }
    private var bookmarkMenu: some View {
        Menu {
            if twoUp, let page, let facing {
                ForEach([page.page, facing.page].sorted(), id: \.self) { target in
                    bookmarkAction(on: target, title: "علامة على الوجه " + service.numerals.string(target))
                }
            } else if let page {
                bookmarkAction(on: page.page, title: "علامة على هذا الوجه")
            }
            if !bookmarks.isEmpty {
                Section("العلامات") {
                    ForEach(bookmarks) { mark in
                        Button { selectedAyah = nil; go(to: mark.page) } label: { Text(mark.name + "، الوجه " + service.numerals.string(mark.page)) }
                    }
                }
            }
            if !marked.isEmpty {
                Section("حذف") {
                    ForEach(marked) { mark in
                        Button(role: .destructive) { Task { await deleteBookmark(mark) } } label: { Label("حذف «" + mark.name + "»", systemImage: "trash") }
                    }
                }
            }
        } label: {
            Image(systemName: marked.isEmpty ? "bookmark" : "bookmark.fill")
                .font(.system(size: 17, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: marked.isEmpty)
                .symbolEffectsRemoved(reduceMotion)
                .frame(width: 44, height: 44)
        }
            .buttonStyle(.madarPlain).accessibilityLabel("العلامات")
            .disabled(page == nil && bookmarks.isEmpty)
            .accessibilityValue(marked.isEmpty ? "" : "هذا الموضع معلَّم")
            .accessibilityIdentifier("quran-mushaf-bookmarks")
            .alert("اسم العلامة", item: $bookmarkPage) { target in
                TextField("مثل: موضع المراجعة", text: $bookmarkName).accessibilityIdentifier("quran-mushaf-bookmark-name")
                Button("احفظ") {
                    let name = String(bookmarkName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                    Task { await saveBookmark(name, on: target) }
                }.disabled(bookmarkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("إلغاء", role: .cancel) {}
            } message: { target in
                Text("تظهر العلامة في القائمة وتعيدك إلى الوجه \(service.numerals.string(target)).")
            }
    }
    private func bookmarkAction(on target: Int, title: String) -> some View {
        Button {
            bookmarkName = "علامة " + service.numerals.string(target)
            bookmarkPage = target
        } label: {
            Label(title, systemImage: "bookmark")
        }
    }

    private func saveBookmark(_ name: String, on target: Int) async {
        guard !name.isEmpty else { return }
        do {
            try await service.command("quran.saveBookmark", ["id": .string(UUID().uuidString), "page": .number(Double(target)), "name": .string(name)])
            await loadBookmarks()
        } catch { bookmarkError = quranUserMessage(error) }
    }
    private func deleteBookmark(_ mark: QuranBookmark) async {
        do {
            try await service.command("quran.deleteBookmark", ["id": .string(mark.id.uuidString)])
            await loadBookmarks()
        } catch { bookmarkError = quranUserMessage(error) }
    }
    private func loadBookmarks() async { if let rows = try? await service.bookmarks() { bookmarks = rows } }
    private func icon(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44) }
            .buttonStyle(.madarPlain).accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private func turnTarget(forward: Bool) -> Int? {
        guard let page else { return nil }
        let stride = twoUp ? 2 : 1
        let target = page.page + (forward ? stride : -stride)
        // Clamping a two-page turn at either end would show the same spread again.
        return (1...604).contains(target) ? target : nil
    }
    private func turn(forward: Bool) {
        guard let target = turnTarget(forward: forward) else { return }
        selectedAyah = nil
        go(to: target)
    }
    private func go(to target: Int) {
        let next = min(604, max(1, target))
        guard next != request.page else {
            if failedFace != nil { retryLoad() }
            return
        }
        failedFace = nil
        request = PageRequest(page: next)
    }

    private func retryLoad() {
        failedFace = nil
        request.attempt += 1
    }

    /// The tafsir sheet walked to another ayah: light it, and turn the page when it starts on another one.
    private func open(_ ayahID: Int) {
        guard let ayah = try? QuranResources.catalog().ayah(id: ayahID) else { return }
        selectedAyah = ayahID
        if ayah.page != request.page && !(page?.semanticAyat.contains { $0.id == ayahID } ?? false) { go(to: ayah.page) }
    }

    private func load(_ target: PageLoad) async {
        guard pendingLoad == target, !Task.isCancelled else { return }
        let number = target.request.page
        let other = number % 2 == 1 ? number + 1 : number - 1
        var readingFace = number
        var primary: QuranUIPage?
        do {
            let loaded = try await readFace(number)
            guard pendingLoad == target, !Task.isCancelled else { return }
            primary = loaded
            readingFace = other
            let companion = target.wantsSpread ? try await readFace(other) : cachedFace(other)
            guard pendingLoad == target, !Task.isCancelled else { return }
            // A turn replaces a visible spread only once both of its faces are ready.
            if page?.page != number { zoom = 1; pan = .zero }
            page = loaded
            facing = companion
            failedFace = nil
        } catch {
            guard pendingLoad == target, !Task.isCancelled else { return }
            if page == nil { page = primary }
            failedFace = readingFace
            return
        }
        // Warm the two neighbours (font registration and glyph table) so turning the page does not wait.
        for neighbour in [number + 1, number - 1] where (1...604).contains(neighbour) && neighbour != facing?.page {
            guard pendingLoad == target, !Task.isCancelled else { return }
            _ = try? await service.page(neighbour)
        }
    }

    private func cachedFace(_ number: Int) -> QuranUIPage? {
        if page?.page == number { return page }
        return facing?.page == number ? facing : nil
    }

    private func readFace(_ number: Int) async throws -> QuranUIPage {
        if let cached = cachedFace(number) { return cached }
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if !injectedReadFailure,
           UUID(uuidString: environment["MADAR_UI_STORE_ID"] ?? "") != nil,
           environment["MADAR_UI_QURAN_MUSHAF_FAIL_PAGE_ONCE"] == String(number) {
            injectedReadFailure = true
            throw CocoaError(.fileReadUnknown)
        }
        #endif
        return try await service.page(number)
    }
}
