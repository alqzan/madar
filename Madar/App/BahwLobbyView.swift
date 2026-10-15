import SwiftUI
import UniformTypeIdentifiers
import MadarCore
import MadarDesign

/// M4-V01 · `bahw/02-W1-Bahw.jpg`: the flexible lobby (RL1 labelled blocks first). Only built rooms enter;
/// habits, money and Mihbara keep their slots in `bahw.layout` but have no entry point until they are built.
enum BahwBlock: String, CaseIterable {
    case habits, salah, quran, mal, year, upcoming, notes, mihbara
    static let built: Set<BahwBlock> = [.salah, .quran, .year, .upcoming, .notes]
    var title: String {
        switch self { case .habits: "عاداتك"; case .salah: "الصلاة"; case .quran: "القرآن"; case .mal: "المال"; case .year: "السنة"; case .upcoming: "الأيام القادمة"; case .notes: "المذكرات"; case .mihbara: "المحبرة" }
    }
    var symbol: String {
        switch self { case .salah: "building.columns"; case .quran: "book"; case .year: "clock"; case .upcoming: "calendar"; case .notes: "pencil"; default: "circle" }
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
    @Bindable var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arranging = false
    @State private var drawerOpen = false
    @State private var wiggle = false
    private var theme: RoomTheme { RoomTheme(room: "bahw", dark: session.string("core.theme") == "dark") }
    private var service: AppBahwService { .init(session: session) }
    private var layout: BahwLayoutValue { BahwLayoutValue(session.values["bahw.layout"]) }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            // The header stays fixed while the blocks scroll under it (02-W1-Bahw-s1).
            VStack(spacing: 0) {
            header.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 12).frame(maxWidth: 620)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let visible = layout.visible
                    let placements = BahwGrid.pack(visible.map { ($0.rawValue, layout.size($0)) })
                    BahwGridLayout(placements: placements) {
                        ForEach(visible, id: \.self) { block in tile(block, size: layout.size(block)) }
                    }
                    if arranging {
                        Button { drawerOpen = true } label: {
                            Label(layout.hiddenBuilt.isEmpty ? "لا كتل مخفية" : "المخفية: " + service.digits.string(layout.hiddenBuilt.count), systemImage: "plus")
                                .font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 46).overlay { Capsule().stroke(theme.line) }
                        }.buttonStyle(.plain).disabled(layout.hiddenBuilt.isEmpty).accessibilityIdentifier("bahw-drawer")
                    }
                }.padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            }
        }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
        .environment(\.roomTheme, theme)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $session.yearOpen) { BahwYearView(session: session) }
        .sheet(isPresented: $drawerOpen) { drawer.presentationDetents([.medium]) }
        .onChange(of: arranging) { _, on in wiggle = on && !reduceMotion }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateLine).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("bahw-date")
                Text(greeting).font(MadarTypography.title()).accessibilityAddTraits(.isHeader).accessibilityIdentifier("bahw-greeting")
            }
            Spacer(minLength: 8)
            Button { withAnimation(.snappy) { arranging.toggle() } } label: {
                Text(arranging ? "تمّ" : "رتّب").font(MadarTypography.section()).padding(.horizontal, 16).frame(minHeight: 46)
                    .background(arranging ? theme.accentFill : .clear, in: .capsule).foregroundStyle(arranging ? theme.onAccent : theme.ink).overlay { Capsule().stroke(theme.line) }
            }.buttonStyle(.plain).accessibilityIdentifier("bahw-arrange")
            Button { session.selectedTab = "customize" } label: { Image(systemName: "slider.horizontal.3").frame(width: 46, height: 46).overlay { Circle().stroke(theme.line) } }
                .buttonStyle(.plain).accessibilityLabel("خصّص مدار").accessibilityIdentifier("settings-button")
        }
    }
    private var greeting: String {
        let place = session.activePlace, day = GregorianDay.containing(service.now, in: place.timeZone)
        guard let times = PrayerTimesEngine.calculate(day: day, place: place) else { return "أهلًا بك" }
        return service.now >= times.fajr && service.now < times.dhuhr ? "صباح الخير" : "مساء الخير"
    }
    /// Both dates, the first calendar first; joined with «، », never "·" beside a digit (RU1).
    private var dateLine: String {
        let day = service.today, hijriFirst = session.string("core.firstCalendar") != "gregorian"
        let weekday = { () -> String in let f = DateFormatter(); f.locale = Locale(identifier: "ar"); f.timeZone = .gmt; f.dateFormat = "EEEE"; return f.string(from: day.date(in: .gmt).addingTimeInterval(12 * 3600)) }()
        let hijri = service.shortDate(day, hijri: true) + " " + service.digits.string(service.calendarDays.hijri(day).year)
        let gregorian = service.shortDate(day, hijri: false)
        return weekday + " " + (hijriFirst ? hijri + "، " + gregorian : gregorian + " " + service.digits.string(day.year) + "، " + service.shortDate(day, hijri: true))
    }

    @ViewBuilder private func tile(_ block: BahwBlock, size: BahwBlockSize) -> some View {
        if arranging {
            tileContent(block, size: size)
                .draggable(block.rawValue) { BahwBlockView(service: service, block: block, size: .icon).frame(width: 84, height: 84) }
        } else { tileContent(block, size: size) }
    }
    private func tileContent(_ block: BahwBlock, size: BahwBlockSize) -> some View {
        Button { open(block) } label: {
            BahwBlockView(service: service, block: block, size: size).contentShape(.rect(cornerRadius: 22))
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
        if let tab = block.tab { session.selectedTab = tab }
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
                Button { update { $0.hidden.removeAll { $0 == block.rawValue } }; drawerOpen = layout.hiddenBuilt.count > 1 } label: { Label(block.title, systemImage: block.symbol) }
                    .accessibilityIdentifier("bahw-show-" + block.rawValue)
            }
            .scrollContentBackground(.hidden).background(theme.background)
            .navigationTitle("الكتل المخفية").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تم") { drawerOpen = false } } }
        }.environment(\.roomTheme, theme).tint(theme.accent)
    }
}

private struct BahwOpened: Identifiable { let block: BahwBlock; var id: String { block.rawValue } }

/// A tap opens a sheet with the room's summary and a button into the room (§7.1 «التفاعل»).
struct BahwBlockSheet: View {
    @Bindable var session: AppSession
    let block: BahwBlock
    let open: () -> Void
    @Environment(\.dismiss) private var dismiss
    private var theme: RoomTheme { RoomTheme(room: "bahw", dark: session.string("core.theme") == "dark") }
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
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تم") { dismiss() }.accessibilityIdentifier("bahw-sheet-done") } }
        }.environment(\.roomTheme, theme).tint(theme.accent).presentationDetents([.medium, .large])
    }
}
