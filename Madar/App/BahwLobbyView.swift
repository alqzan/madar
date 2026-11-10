import SwiftUI
import UniformTypeIdentifiers
import MadarCore
import MadarDesign
import MadarPrayer

/// M4-V01 · `bahw/02-W1-Bahw.jpg`: the flexible lobby (RL1 labelled blocks first).
/// A room enters the lobby after its milestone builds its block; RL9 still excludes deferred options.
enum BahwBlock: String, CaseIterable {
    case habits, salah, quran, mal, year, upcoming, notes, mihbara
    static let built: Set<BahwBlock> = [.habits, .salah, .quran, .mal, .year, .upcoming, .notes, .mihbara]
    var title: String {
        switch self { case .habits: "عاداتك"; case .salah: "الصلاة"; case .quran: "القرآن"; case .mal: "المال"; case .year: "السنة"; case .upcoming: "الأيام القادمة"; case .notes: "المذكرات"; case .mihbara: "المحبرة" }
    }
    var symbol: String {
        switch self { case .habits: "MadarHabits"; case .salah: "MadarPrayer"; case .quran: "MadarQuran"; case .year: "MadarYear"; case .upcoming: "MadarUpcoming"; case .notes: "MadarDiary"; case .mihbara: "books.vertical"; case .mal: "banknote" }
    }
    var tab: String? { switch self { case .salah: "prayer"; case .quran: "quran"; case .notes: "notes"; default: nil } }
}

struct BahwLayoutValue: Equatable {
    var blocks: [String]
    var hidden: [String]
    var pinned: [String]
    var sizes: [String: String]
    init(_ value: JSONValue?) {
        func strings(_ key: String) -> [String] { if case .object(let o) = value, case .array(let a) = o[key] { a.compactMap { if case .string(let s) = $0 { s } else { nil } } } else { [] } }
        blocks = strings("blocks"); hidden = strings("hidden"); pinned = strings("pinned")
        var sizes: [String: String] = [:]
        if case .object(let o) = value, case .object(let s) = o["sizes"] { for (k, v) in s { if case .string(let raw) = v { sizes[k] = raw } } }
        self.sizes = sizes
    }
    var json: JSONValue {
        .object(["blocks": .array(blocks.map { .string($0) }), "hidden": .array(hidden.map { .string($0) }), "pinned": .array(pinned.map { .string($0) }),
                 "sizes": .object(sizes.mapValues { .string($0) })])
    }
    func size(_ block: BahwBlock) -> BahwBlockSize { sizes[block.rawValue].flatMap(BahwBlockSize.init(rawValue:)) ?? .small }
    var visible: [BahwBlock] { blocks.compactMap(BahwBlock.init(rawValue:)).filter { BahwBlock.built.contains($0) && !hidden.contains($0.rawValue) } }
    /// Hidden rooms, plus any built room the saved list does not mention yet (a room added in a later version can always be turned on).
    var hiddenBuilt: [BahwBlock] {
        let listed = blocks.compactMap(BahwBlock.init(rawValue:)).filter { BahwBlock.built.contains($0) && hidden.contains($0.rawValue) }
        let unlisted = BahwBlock.built.filter { !blocks.contains($0.rawValue) }.sorted { $0.rawValue < $1.rawValue }
        return listed + unlisted
    }
}

struct BahwGridLayout: Layout {
    let placements: [BahwPlacement]
    var columns: Int = 4
    let gap: CGFloat = 10
    func cell(_ width: CGFloat) -> CGFloat { (width - CGFloat(columns - 1) * gap) / CGFloat(columns) }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 365, rows = CGFloat(BahwGrid.rows(placements))
        return .init(width: width, height: rows * cell(width) + max(0, rows - 1) * gap)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let unit = cell(bounds.width)
        for (subview, place) in zip(subviews, placements) {
            let w = CGFloat(place.size.columns) * unit + CGFloat(place.size.columns - 1) * gap, h = CGFloat(place.size.rows) * unit + CGFloat(place.size.rows - 1) * gap
            // Column 0 is the leading edge; SwiftUI mirrors custom layouts in right-to-left, so it lands on the right.
            subview.place(at: .init(x: bounds.minX + CGFloat(place.column) * (unit + gap), y: bounds.minY + CGFloat(place.row) * (unit + gap)), proposal: .init(width: w, height: h))
        }
    }
}

private struct BahwMinuteTimelineSchedule: TimelineSchedule, Equatable, Sendable {
    let isActive: Bool

    func entries(from startDate: Date, mode: Mode) -> AnySequence<Date> {
        guard isActive else { return AnySequence(EmptyCollection<Date>()) }
        let minuteStart = Date(timeIntervalSince1970: floor(startDate.timeIntervalSince1970 / 60) * 60)
        let schedule = PeriodicTimelineSchedule(from: minuteStart, by: 60)
        return AnySequence(schedule.entries(from: startDate, mode: mode))
    }
}

struct BahwLobbyView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isFrontRoom) private var isFrontRoom
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Bindable var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arranging = false
    @State private var drawerOpen = false
    @State private var wiggle = false
    @State private var attention: BahwAttention?
    @State private var moneyRevealed = false
    @State private var moneyRevealID = 0
    @Environment(\.scenePhase) private var scenePhase
    private var theme: RoomTheme { RoomTheme(room: "bahw", dark: colorScheme == .dark) }
    private var service: AppBahwService { .init(session: session) }
    private var layout: BahwLayoutValue { BahwLayoutValue(session.values["bahw.layout"]) }
    var body: some View {
        TimelineView(BahwMinuteTimelineSchedule(isActive: isFrontRoom)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header.padding(.top, 8).padding(.bottom, 4)
                    if !arranging, let day = session.bahwReturnPlanDay {
                        BahwReturnPlanCard(day: day, digits: service.digits, theme: theme,
                                           openQuran: { session.selectedTab = "quran" },
                                           openHabits: { session.habitsOpen = true })
                    }
                    // B3-1: what to do now leads the lobby (it used to sit under the grid, past the fold).
                    if !arranging { BahwSuggestionsView(session: session) }
                    let visible = layout.visible
                    let columns = isPadWide(sizeClass) ? 8 : 4
                    let placements = BahwGrid.pack(visible.map { ($0.rawValue, layout.size($0)) }, columns: columns)
                    BahwGridLayout(placements: placements, columns: columns) {
                        ForEach(visible, id: \.self) { block in tile(block, size: layout.size(block)) }
                    }
                    // AU-32: hiding every widget leaves a way back, not a blank lobby.
                    if visible.isEmpty && !arranging {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("أخفيت كل الودجات").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                            Button { arranging = true; drawerOpen = true } label: { Text("أظهر الودجات المخفية").font(MadarTypography.body().bold()).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle()) }.accessibilityIdentifier("bahw-show-hidden")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !arranging {
                        SavedLobbyWidgets(session: session)
                    }
                    if arranging {
                        Button { drawerOpen = true } label: {
                            Label(layout.hiddenBuilt.isEmpty ? "لا ودجات مخفية" : "المخفية: " + WidgetCopy.agree(layout.hiddenBuilt.count, service.digits, one: "ودجة واحدة", two: "ودجتان", few: "ودجات", many: "ودجة"), systemImage: "plus")
                                .font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 46).glassEffect(.regular.interactive(), in: .capsule)
                        }.buttonStyle(.madarPlain).disabled(layout.hiddenBuilt.isEmpty).accessibilityIdentifier("bahw-drawer")
                    }
                }.padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 24).frame(maxWidth: isPadWide(sizeClass) ? 1100 : 620).frame(maxWidth: .infinity)
            }
            // Owner 7 Nov 2026: pull down to bring in what arrived outside the app and read every tile again now.
            .refreshable { await session.refreshFromPull() }
            // The hidden navigation bar must not let scrolling ink enter the status-bar safe area.
            .madarTopClipped()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if arranging {
                HStack {
                    Text("رتّب البهو").font(MadarTypography.section())
                    Spacer()
                    Button { withAnimation(.snappy) { arranging = false } } label: { Text("تمّ")
                        .font(MadarTypography.section()).frame(minHeight: 44).padding(.horizontal, 20)
                        .background(theme.accentFill, in: .capsule).contentShape(.capsule).foregroundStyle(theme.onAccent) }
                        .accessibilityIdentifier("bahw-arrange")
                }.padding(.horizontal, 14).padding(.vertical, 6).background(theme.background)
            }
        }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
        .environment(\.roomTheme, theme)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $session.habitsOpen) { HabitsRoomView(session: session) }
        .navigationDestination(isPresented: $session.yearOpen) { BahwYearView(session: session) }
        .sheet(isPresented: $drawerOpen) { drawer.presentationDetents([.medium]).madarSheetErrorAlert(session) }
        .onChange(of: arranging) { _, on in wiggle = on && !reduceMotion }
        .task(id: moneyRevealID) {
            guard moneyRevealed else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { moneyRevealed = false }
        }
        .onChange(of: session.selectedTab) { moneyRevealed = false }
        .sheet(item: $attention) { value in
            BahwAttentionSheet(session: session, attention: value).madarSheetErrorAlert(session)
        }
        // On opening, after the splash has settled: what waits (unlogged prayers, unsorted messages) appears once, never as a notification.
        .task { try? await Task.sleep(for: .seconds(1.4)); presentAttention(force: false) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { try? await Task.sleep(for: .seconds(0.9)); presentAttention(force: false) } }
        }
        .onChange(of: session.attentionRequest) { _, _ in presentAttention(force: true) }
        // FB-39: an app opened into another room (a widget, a notification) never showed what waits once the lobby came to the front.
        .onChange(of: session.selectedTab) { _, tab in
            if tab == "foundation" { Task { try? await Task.sleep(for: .seconds(0.5)); presentAttention(force: false) } }
        }
    }

    private func presentAttention(force: Bool) {
        // Never over the first-run welcome (it opened on top of it and hid the welcome until dismissed).
        guard session.onboardingComplete, session.pendingIntro == nil, !arranging, !drawerOpen, attention == nil, session.selectedTab == "foundation" else { return }
        let value = service.attention(includeReconcile: true, ignoringThrottle: force)
        #if DEBUG
        // UI tests drive the lobby behind a fixed clock and a fresh store; the sheet is opened there only on request (`MADAR_UI_ATTENTION=1`).
        let environment = ProcessInfo.processInfo.environment
        if !force, environment["MADAR_UI_STORE_ID"] != nil && environment["MADAR_UI_ATTENTION"] != "1" { return }
        #endif
        guard !value.isEmpty, force || BahwAttentionMemory.isNew(value) else { return }
        attention = value
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                MadarDateLabel(session.dateLabels(service.today, weekday: true)).foregroundStyle(theme.secondaryInk).accessibilityElement(children: .combine).accessibilityIdentifier("bahw-date")
                Text(greeting).font(MadarTypography.title()).accessibilityAddTraits(.isHeader).accessibilityIdentifier("bahw-greeting")
            }.frame(maxWidth: .infinity, alignment: .leading)

            Button { withAnimation(.snappy) { arranging = true } } label: {
                Text("رتّب")
                    .font(.custom("thmanyahsans-Bold", size: 14, relativeTo: .caption))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.madarPlain)
            .accessibilityIdentifier("bahw-arrange-start")

            Button { session.selectedTab = "customize" } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.madarPlain)
            .accessibilityLabel("خصّص مدار")
            .accessibilityIdentifier("bahw-customize")
        }
    }
    private var greeting: String {
        service.greeting
    }
    /// Both dates, the first calendar first; joined with «، », never "·" beside a digit (RU1).
    private var dateLine: String { session.dateLabels(service.today).combined }

    @ViewBuilder private func tile(_ block: BahwBlock, size: BahwBlockSize) -> some View {
        if arranging {
            tileContent(block, size: size)
                .draggable(block.rawValue) { BahwBlockView(service: service, block: block, size: .icon).frame(width: 84, height: 84) }
        } else { tileContent(block, size: size) }
    }
    private func tileContent(_ block: BahwBlock, size: BahwBlockSize) -> some View {
        Group {
            // Larger habits cards contain real quick-log buttons, so their header opens the room.
            // The icon has no quick actions and remains a single room-entry button.
            if block == .habits && size == .icon { Button { open(block) } label: { BahwBlockView(service: service, block: block, size: size, interactive: !arranging, moneyRevealed: block == .mal && moneyRevealed).contentShape(.rect(cornerRadius:22)) } }
            else if block == .habits { BahwBlockView(service: service, block: block, size: size, interactive: !arranging, moneyRevealed: block == .mal && moneyRevealed).contentShape(.rect(cornerRadius:22)) }
            else { Button { open(block) } label: { BahwBlockView(service: service, block: block, size: size, interactive: !arranging, moneyRevealed: block == .mal && moneyRevealed).contentShape(.rect(cornerRadius:22)) } }
        }.buttonStyle(.madarPlain)
            .rotationEffect(.degrees(wiggle ? 0.7 : 0)).animation(wiggle ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true) : .default, value: wiggle)
            .overlay(alignment: .topLeading) {
                if arranging {
                    Button { update { $0.hidden.append(block.rawValue) } } label: { Image(systemName: "minus").font(.body.bold()).frame(width: 30, height: 30).background(theme.surface, in: .circle).glassEffect(.regular.interactive(), in: .circle) }
                        .buttonStyle(.madarPlain).frame(width: 44, height: 44).offset(x: -10, y: -10).accessibilityLabel("أخفِ " + block.title).accessibilityIdentifier("bahw-hide-" + block.rawValue)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if arranging {
                    Menu {
                        ForEach(BahwBlockSize.allCases, id: \.self) { option in
                            Button { update { $0.sizes[block.rawValue] = option.rawValue } } label: { Label(sizeTitle(option), systemImage: option == size ? "checkmark" : "square") }
                        }
                    } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.footnote.bold()).frame(width: 30, height: 30).foregroundStyle(theme.onAccent).background(theme.accentFill, in: .circle) }
                        .frame(width: 44, height: 44).accessibilityLabel("حجم " + block.title).accessibilityIdentifier("bahw-size-" + block.rawValue)
                }
            }
            .contentShape(.rect(cornerRadius: 22))
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.52).onEnded { _ in withAnimation(.snappy) { arranging = true } })
            .dropDestination(for: String.self) { items, _ in
                guard arranging, let moved = items.first, moved != block.rawValue else { return false }
                update { value in
                    guard let from = value.blocks.firstIndex(of: moved) else { return }
                    value.blocks.remove(at: from)
                    value.blocks.insert(moved, at: value.blocks.firstIndex(of: block.rawValue) ?? value.blocks.endIndex)
                }
                return true
            }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "افتح") { open(block) }
            .accessibilityIdentifier("bahw-block-" + block.rawValue)
    }
    private func open(_ block: BahwBlock) {
        guard !arranging else { return }
        // The first touch on hidden money shows it for four seconds; a touch while it shows opens the room.
        if block == .mal, session.bool("core.hideMoneyUntilTouch"), !moneyRevealed {
            withAnimation(.easeOut(duration: 0.2)) { moneyRevealed = true }
            moneyRevealID &+= 1
            return
        }
        session.requestOpen(block)
    }
    private func sizeTitle(_ size: BahwBlockSize) -> String {
        switch size { case .icon: "أيقونة"; case .small: "صغيرة"; case .wide: "عريضة"; case .large: "كبيرة" }
    }
    /// Every layout change goes through settings, so it has undo and a reset like any setting.
    private func update(_ change: (inout BahwLayoutValue) -> Void) {
        var value = layout; change(&value)
        guard value != layout else { return }
        session.set(value.json, key: "bahw.layout")
    }
    private var drawer: some View {
        NavigationStack {
            List(layout.hiddenBuilt, id: \.self) { block in
                Button { update { $0.hidden.removeAll { $0 == block.rawValue } }; drawerOpen = layout.hiddenBuilt.count > 1 } label: { Label { Text(block.title) } icon: { MadarGlyph(block.symbol) } }
                    .accessibilityIdentifier("bahw-show-" + block.rawValue)
            }
            .scrollContentBackground(.hidden).background(theme.background)
            .navigationTitle("الودجات المخفية").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تمّ") { drawerOpen = false } } }
        }.environment(\.roomTheme, theme).tint(theme.accent)
    }
}

private struct BahwReturnPlanCard: View {
    let day: Int
    let digits: MadarNumberFormatter
    let theme: RoomTheme
    let openQuran: () -> Void
    let openHabits: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("أهلًا بك من جديد")
                    .font(MadarTypography.section())
                    .foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                Text("اليوم \(digits.string(day)) من \(digits.string(3))")
                    .font(MadarTypography.caption())
                    .foregroundStyle(theme.secondaryInk)
                    .accessibilityIdentifier("bahw-return-day")
            }
            Text("نصف وردك، وعادة واحدة تكفي اليوم.")
                .font(MadarTypography.body())
                .foregroundStyle(theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("bahw-return-plan-copy")
            HStack(spacing: 10) {
                action("افتح القرآن", glyph: "MadarQuran", identifier: "bahw-return-quran", primary: true, action: openQuran)
                action("افتح العادات", glyph: "MadarHabits", identifier: "bahw-return-habits", primary: false, action: openHabits)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: .rect(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.line, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bahw-return-plan")
    }

    private func action(_ title: String, glyph: String, identifier: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                MadarGlyph(glyph, size: 16)
                Text(title).font(MadarTypography.caption()).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(primary ? theme.onAccent : theme.accent)
            .background(primary ? theme.accentFill : .clear, in: .capsule)
            .overlay { Capsule().stroke(primary ? Color.clear : theme.line, lineWidth: 1) }
        }
        .buttonStyle(.madarPlain)
        .accessibilityIdentifier(identifier)
    }
}


private struct BahwSuggestionsView: View {
    @Bindable var session: AppSession
    @State private var suggestions: [BahwSuggestion] = []
    @Environment(\.roomTheme) private var theme
    private var refreshKey: String {
        "\(session.prayerRevision)-\(session.habitReadingsVersion)-\(session.string("bahw.smartPresence"))-\(Int(session.prayerNow().timeIntervalSince1970 / 60))-\(session.protectedDataAuthorized)"
    }
    /// «الآن» for the one step that leads; the following rows are «بعدها».
    private var heading: String { suggestions.count > 1 ? "الآن، ثم بعدها" : "الآن" }
    var body: some View {
        VStack(spacing: 0) {
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(heading).font(MadarTypography.section())
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        let lead = index == 0
                        Button { open(suggestion.destination) } label: {
                            HStack(spacing: 12) {
                                MadarGlyph(suggestion.symbol, size: lead ? 28 : 22).foregroundStyle(lead ? theme.onAccent : theme.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(suggestion.title).font(lead ? MadarTypography.section() : MadarTypography.body())
                                    Text(suggestion.detail).font(MadarTypography.fine()).foregroundStyle(lead ? theme.onAccent.opacity(0.85) : theme.secondaryInk)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.left").font(.caption).foregroundStyle(lead ? theme.onAccent.opacity(0.85) : theme.secondaryInk)
                            }.frame(maxWidth: .infinity, minHeight: lead ? 72 : 52, alignment: .leading).padding(12)
                                .foregroundStyle(lead ? theme.onAccent : theme.ink)
                                .background(lead ? theme.accentFill : theme.surface, in: .rect(cornerRadius: lead ? 22 : 18))
                        }.buttonStyle(.madarPlain).accessibilityIdentifier("bahw-suggestion-" + suggestion.id)
                    }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("bahw-suggestions")
            }
        }.task(id: refreshKey) { suggestions = AppBahwService(session: session).suggestions() }
    }
    private func open(_ destination: BahwSuggestion.Destination) {
        switch destination {
        case .prayer:
            session.selectedTab = "prayer"
        case .habit(let id): session.habitRouteID = id; session.habitsOpen = true
        case .quran(let route):
            // Batch 3: the step opens the session itself (madar://quran/session/hifz|review|drill) when the Quran room has one ready.
            if let route, route.contains("/session/"), let url = URL(string: route) { session.open(url) } else { session.selectedTab = "quran" }
        case .diary:
            if let url = URL(string: "madar://notes/write") { session.open(url) }
        case .money:
            if AppBahwService(session: session).attention().moneyCount > 0 { session.attentionRequest += 1 } else { session.open(URL(string: "madar://mal/messages")!) }
        // The suggestion names a book, so it opens that book (a stale id falls back to the room's own alert).
        case .mihbara(let book): if let book { session.openSpotlightBook(book) } else { session.selectedTab = "mihbara" }
        }
    }
}
