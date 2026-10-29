import SwiftUI
import UniformTypeIdentifiers
import MadarCore
import MadarDesign

/// M4-V01 · `bahw/02-W1-Bahw.jpg`: the flexible lobby (RL1 labelled blocks first).
/// A room enters the lobby after its milestone builds its block; RL9 still excludes deferred options.
enum BahwBlock: String, CaseIterable {
    case habits, salah, quran, mal, year, upcoming, notes, mihbara
    static let built: Set<BahwBlock> = [.habits, .salah, .quran, .mal, .year, .upcoming, .notes, .mihbara]
    var title: String {
        switch self { case .habits: "عاداتك"; case .salah: "الصلاة"; case .quran: "القرآن"; case .mal: "المال"; case .year: "السنة"; case .upcoming: "الأيام القادمة"; case .notes: "المذكرات"; case .mihbara: "المحبرة" }
    }
    var symbol: String {
        switch self { case .habits: "MadarHabits"; case .salah: "MadarPrayer"; case .quran: "MadarQuran"; case .year: "MadarYear"; case .upcoming: "MadarUpcoming"; case .notes: "MadarDiary"; case .mihbara: "books.vertical"; default: "circle" }
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
    var hiddenBuilt: [BahwBlock] { blocks.compactMap(BahwBlock.init(rawValue:)).filter { BahwBlock.built.contains($0) && hidden.contains($0.rawValue) } }
}

struct BahwGridLayout: Layout {
    let placements: [BahwPlacement]
    let gap: CGFloat = 10
    func cell(_ width: CGFloat) -> CGFloat { (width - 3 * gap) / 4 }
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

struct BahwLobbyView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arranging = false
    @State private var drawerOpen = false
    @State private var wiggle = false
    private var theme: RoomTheme { RoomTheme(room: "bahw", dark: colorScheme == .dark) }
    private var service: AppBahwService { .init(session: session) }
    private var layout: BahwLayoutValue { BahwLayoutValue(session.values["bahw.layout"]) }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header.padding(.top, 8).padding(.bottom, 4)
                    if !arranging, let day = session.bahwReturnPlanDay {
                        BahwReturnPlanCard(day: day, digits: service.digits, theme: theme,
                                           openQuran: { session.selectedTab = "quran" },
                                           openHabits: { session.habitsOpen = true })
                    }
                    let visible = layout.visible
                    let placements = BahwGrid.pack(visible.map { ($0.rawValue, layout.size($0)) })
                    BahwGridLayout(placements: placements) {
                        ForEach(visible, id: \.self) { block in tile(block, size: layout.size(block)) }
                    }
                    // AU-32: hiding every widget leaves a way back, not a blank lobby.
                    if visible.isEmpty && !arranging {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("أخفيت كل الودجات").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                            Button("أظهر الودجات المخفية") { arranging = true; drawerOpen = true }.font(MadarTypography.body().bold()).frame(minHeight: 44).accessibilityIdentifier("bahw-show-hidden")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !arranging {
                        SavedLobbyWidgets(session: session)
                        BahwSuggestionsView(session: session)
                    }
                    if arranging {
                        Button { drawerOpen = true } label: {
                            Label(layout.hiddenBuilt.isEmpty ? "لا ودجات مخفية" : "المخفية: " + WidgetCopy.agree(layout.hiddenBuilt.count, service.digits, one: "ودجة واحدة", two: "ودجتان", few: "ودجات", many: "ودجة"), systemImage: "plus")
                                .font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 46).overlay { Capsule().stroke(theme.line) }
                        }.buttonStyle(.plain).disabled(layout.hiddenBuilt.isEmpty).accessibilityIdentifier("bahw-drawer")
                    }
                }.padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            // The hidden navigation bar must not let scrolling ink enter the status-bar safe area.
            .clipped()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if arranging {
                HStack {
                    Text("رتّب البهو").font(MadarTypography.section())
                    Spacer()
                    Button("تمّ") { withAnimation(.snappy) { arranging = false } }
                        .font(MadarTypography.section()).frame(minHeight: 44).padding(.horizontal, 20)
                        .background(theme.accentFill, in: .capsule).foregroundStyle(theme.onAccent)
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
                    .overlay { Circle().stroke(theme.line) }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bahw-arrange-start")

            Button { session.selectedTab = "customize" } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 44, height: 44)
                    .overlay { Circle().stroke(theme.line) }
            }
            .buttonStyle(.plain)
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
            if block == .habits { BahwBlockView(service: service, block: block, size: size, interactive: !arranging).contentShape(.rect(cornerRadius:22)).onTapGesture { open(block) } }
            else { Button { open(block) } label: { BahwBlockView(service: service, block: block, size: size, interactive: !arranging).contentShape(.rect(cornerRadius:22)) } }
        }.buttonStyle(.plain)
            .rotationEffect(.degrees(wiggle ? 0.7 : 0)).animation(wiggle ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true) : .default, value: wiggle)
            .overlay(alignment: .topLeading) {
                if arranging {
                    Button { update { $0.hidden.append(block.rawValue) } } label: { Image(systemName: "minus").font(.body.bold()).frame(width: 30, height: 30).background(theme.surface, in: .circle).overlay { Circle().stroke(theme.line) } }
                        .buttonStyle(.plain).frame(width: 44, height: 44).offset(x: -10, y: -10).accessibilityLabel("أخفِ " + block.title).accessibilityIdentifier("bahw-hide-" + block.rawValue)
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
        if block == .habits { session.habitsOpen = true }
        else if block == .mal { session.open(URL(string: "madar://mal")!) }
        else if block == .mihbara { session.selectedTab = "mihbara" }
        else if block == .notes, (service.diary()?.count ?? 0) == 0 { session.open(URL(string: "madar://notes/write")!) }
        else if let tab = block.tab { session.selectedTab = tab }
        else if block == .year || block == .upcoming { session.yearOpen = true }
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
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

private struct BahwOpened: Identifiable { let block: BahwBlock; var id: String { block.rawValue } }

/// A tap opens a sheet with the room's summary and a button into the room (§7.1 «التفاعل»).
struct BahwBlockSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var session: AppSession
    let block: BahwBlock
    let open: () -> Void
    @Environment(\.dismiss) private var dismiss
    private var theme: RoomTheme { RoomTheme(room: "bahw", dark: colorScheme == .dark) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    BahwBlockView(service: .init(session: session), block: block, size: .large).frame(height: 365)
                    if block.tab != nil || block == .year || block == .upcoming {
                        Button { open() } label: { Text(block.tab == nil ? "افتح السنة وما يهمّك" : "افتح " + block.title).font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(theme.onAccent).background(theme.accentFill, in: .capsule) }
                            .buttonStyle(.plain).accessibilityIdentifier("bahw-open-" + (block.tab ?? "year"))
                    }
                }.padding(18)
            }.background(theme.background).foregroundStyle(theme.ink)
                .navigationTitle(block.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تمّ") { dismiss() }.accessibilityIdentifier("bahw-sheet-done") } }
        }.environment(\.roomTheme, theme).tint(theme.accent).presentationDetents([.medium, .large])
    }
}


private struct BahwSuggestionsView: View {
    @Bindable var session: AppSession
    @State private var suggestions: [BahwSuggestion] = []
    @Environment(\.roomTheme) private var theme
    private var refreshKey: String {
        "\(session.prayerRevision)-\(session.string("bahw.smartPresence"))-\(Int(session.prayerNow().timeIntervalSince1970 / 60))-\(session.protectedDataAuthorized)"
    }
    var body: some View {
        VStack(spacing: 0) {
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("خطوتك التالية").font(MadarTypography.section())
                    ForEach(suggestions) { suggestion in
                        Button { open(suggestion.destination) } label: {
                            HStack(spacing: 12) {
                                MadarGlyph(suggestion.symbol, size: 22).foregroundStyle(theme.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(suggestion.title).font(MadarTypography.body())
                                    Text(suggestion.detail).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.left").font(.caption).foregroundStyle(theme.secondaryInk)
                            }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).padding(12)
                                .background(theme.surface, in: .rect(cornerRadius: 18))
                        }.buttonStyle(.plain).accessibilityIdentifier("bahw-suggestion-" + suggestion.id)
                    }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("bahw-suggestions")
            }
        }.task(id: refreshKey) { suggestions = AppBahwService(session: session).suggestions() }
    }
    private func open(_ destination: BahwSuggestion.Destination) {
        switch destination {
        case .prayer: session.selectedTab = "prayer"
        case .habit(let id): session.habitRouteID = id; session.habitsOpen = true
        case .quran: session.selectedTab = "quran"
        case .diary:
            if let url = URL(string: "madar://notes/write") { session.open(url) }
        case .money: session.selectedTab = "money"
        case .mihbara: session.selectedTab = "mihbara"
        }
    }
}
