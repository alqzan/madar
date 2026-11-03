import SwiftUI
import MadarDesign
import MadarData
import SwiftData

extension BahwBlock: Identifiable { var id: String { rawValue } }

/// Owner, 3 Nov 2026 («ابيه بالتدريج»): Madar starts with the prayer room only. The other rooms are added one at a time from the lobby,
/// and each opens the first time with a short introduction and its few simple settings.
extension AppSession {
    static let roomTabs: [(block: BahwBlock, tab: String)] = [(.salah, "prayer"), (.quran, "quran"), (.notes, "notes"), (.mal, "money"), (.mihbara, "mihbara")]
    static let tabInfo: [String: FoundationTab] = [
        "prayer": .init(id: "prayer", title: "الصلاة", symbol: "MadarPrayer"), "quran": .init(id: "quran", title: "القرآن", symbol: "MadarQuran"),
        "notes": .init(id: "notes", title: "المذكرات", symbol: "MadarDiary"), "money": .init(id: "money", title: "المال", symbol: "wallet.bifold"),
        "mihbara": .init(id: "mihbara", title: "المحبرة", symbol: "books.vertical")]

    var lobbyLayout: BahwLayoutValue { BahwLayoutValue(values["bahw.layout"]) }
    func roomEnabled(_ block: BahwBlock) -> Bool { lobbyLayout.visible.contains(block) }

    func enableRoom(_ block: BahwBlock) {
        var layout = lobbyLayout
        guard layout.hidden.contains(block.rawValue) || !layout.blocks.contains(block.rawValue) else { return }
        layout.hidden.removeAll { $0 == block.rawValue }
        if !layout.blocks.contains(block.rawValue) { layout.blocks.append(block.rawValue) }
        Task { do { try await applySettingsAndWait(["bahw.layout": layout.json]) } catch { errorMessage = "لم يُضف القسم. \(madarUserMessage(error))" } }
    }

    private func introKey(_ block: BahwBlock) -> String { "Madar.introSeen." + block.rawValue }
    func introNeeded(_ block: BahwBlock) -> Bool {
        #if DEBUG
        // UI tests that are not about the intro open rooms directly; MADAR_UI_INTRO=1 brings the sheet back.
        let environment = ProcessInfo.processInfo.environment
        if environment["MADAR_UI_STORE_ID"] != nil, environment["MADAR_UI_INTRO"] != "1" { return false }
        #endif
        return !UserDefaults.standard.bool(forKey: introKey(block))
    }
    func markIntroSeen(_ block: BahwBlock) { UserDefaults.standard.set(true, forKey: introKey(block)) }

    /// The lobby's door: the first visit shows the introduction, later visits open the room.
    func requestOpen(_ block: BahwBlock) {
        if introNeeded(block) { pendingIntro = block } else { openRoom(block) }
    }

    func openRoom(_ block: BahwBlock) {
        switch block {
        case .habits: habitsOpen = true
        case .mal: open(URL(string: "madar://mal")!)
        case .mihbara: selectedTab = "mihbara"
        case .notes where (AppBahwService(session: self).diary()?.count ?? 0) == 0: open(URL(string: "madar://notes/write")!)
        case .year, .upcoming: yearOpen = true
        default: if let tab = block.tab { selectedTab = tab }
        }
    }

    /// A room that already holds the person's records.
    private func roomHasData(_ block: BahwBlock, in context: ModelContext) -> Bool {
        func any<T: PersistentModel>(_: T.Type) -> Bool { var d = FetchDescriptor<T>(); d.fetchLimit = 1; return ((try? context.fetch(d))?.isEmpty == false) }
        switch block {
        case .habits: return any(Habit.self)
        case .quran: return any(HifzPlan.self) || any(HifzSession.self) || any(PageGrade.self)
        case .notes: return any(Entry.self) || any(DayPage.self)
        case .mal: return any(Account.self) || any(MoneyTransaction.self) || any(Obligation.self)
        case .mihbara: return any(Book.self)
        default: return false
        }
    }

    /// Owner, 3 Nov: the app starts with the prayer room and adds the others one at a time. A room that already holds the
    /// person's records is never put away by an update; only empty rooms are, once (v2: build 3 had skipped this for everyone).
    func applyProgressiveRoomsOnce() async {
        let key = "Madar.progressiveRooms.v2"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"] != nil { UserDefaults.standard.set(true, forKey: key); return }
        #endif
        let context = ModelContext(container)
        var layout = lobbyLayout
        for block in BahwBlock.allCases where block != .salah && BahwBlock.built.contains(block) {
            if roomHasData(block, in: context) { markIntroSeen(block); layout.hidden.removeAll { $0 == block.rawValue }; continue }
            if !layout.blocks.contains(block.rawValue) { layout.blocks.append(block.rawValue) }
            if !layout.hidden.contains(block.rawValue) { layout.hidden.append(block.rawValue) }
        }
        layout.pinned.removeAll { layout.hidden.contains($0) } // a room cannot be both pinned and put away
        do { try await applySettingsAndWait(["bahw.layout": layout.json]); UserDefaults.standard.set(true, forKey: key); UserDefaults.standard.removeObject(forKey: "Madar.progressiveRooms.pending") } catch { }
    }
}

extension BahwBlock {
    /// One sentence a person can understand, the three things done there, and the few settings worth choosing on day one.
    var intro: (sentence: String, steps: [String], toggles: [(key: String, title: String)]) {
        switch self {
        case .salah: ("سجّل صلواتك في وقتها وشاهد الصلاة القادمة.", ["اضغط على الصلاة لتسجّلها", "اطّلع على المواقيت", "تابع التزامك"], [("salah.askReminder", "اسألني عن الصلاة بعد الأذان")])
        case .quran: ("ورد يومي من القرآن بمقدار يناسبك.", ["اختر ورد اليوم", "سجّل ما قرأت", "تابع تقدّمك"], [("quran.lateReminder", "ذكّرني بالورد المتأخر")])
        case .habits: ("عادات صغيرة تتابعها كل يوم.", ["أضف عادة", "علّمها حين تنجزها", "شاهد سلسلتك"], [])
        case .notes: ("صفحة تكتب فيها يومك بصوتك أو بقلمك.", ["اكتب أو سجّل صوتك", "أضف صورة من يومك", "ارجع لذكرياتك"], [("notes.morningNiyya", "نيّة الصباح")])
        case .mal: ("سجّل مصروفك واعرف ما بقي لك.", ["سجّل مصروفًا", "اضبط راتبك", "شاهد ما بقي"], [("mal.alert80", "نبّهني عند ٨٠٪ من الحد")])
        case .mihbara: ("مكتبتك وقراءاتك في مكان واحد.", ["أضف كتابًا", "اقرأ وعلّم ما يعجبك", "ارجع لاقتباساتك"], [])
        case .year: ("سنتك أمامك أيامًا أيامًا.", ["شاهد أيام السنة", "أضف حدثًا", "تابع ما مضى"], [])
        case .upcoming: ("الأيام القادمة التي تنتظرها.", ["أضف موعدًا", "شاهد العدّ التنازلي"], [])
        }
    }
}

struct RoomIntroSheet: View {
    @Bindable var session: AppSession
    let block: BahwBlock
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let content = block.intro
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MadarGlyph(block.symbol, size: 44).foregroundStyle(theme.accent).accessibilityHidden(true)
                Text(block.title).font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
                Text(content.sentence).font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                if !content.toggles.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(content.toggles, id: \.key) { item in
                            Toggle(item.title, isOn: Binding(get: { session.bool(item.key) }, set: { session.set(.bool($0), key: item.key) }))
                                .frame(minHeight: 48).accessibilityIdentifier("intro-\(item.key)")
                        }
                    }
                }
                if let reminder = block.reminderLine, session.canRequestNotificationPermission {
                    Text(reminder).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    Button { session.requestPrayerNotificationPermission() } label: {
                        Label("اسمح بالتذكيرات", systemImage: "bell").font(MadarTypography.body().bold()).foregroundStyle(theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 48).contentShape(Capsule())
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("intro-notifications")
                }
                Button("ابدأ") {
                    session.markIntroSeen(block); session.pendingIntro = nil
                    if let tab = block.tab, session.selectedTab == tab { return }
                    session.openRoom(block)
                }.buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("intro-start")
                Button("ليس الآن") { session.markIntroSeen(block); session.pendingIntro = nil }
                    .font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()).accessibilityIdentifier("intro-later")
            }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(theme.background).foregroundStyle(theme.ink).font(MadarTypography.body())
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }
}

/// The lobby card that adds the next room.
struct AddRoomCard: View {
    @Bindable var session: AppSession
    let blocks: [BahwBlock]
    let theme: RoomTheme
    /// The rooms the owner uses every day come first.
    private var ordered: [BahwBlock] {
        let order: [BahwBlock] = [.quran, .habits, .notes, .mal, .mihbara, .year, .upcoming]
        return blocks.sorted { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("أضف قسمًا").font(MadarTypography.section()).accessibilityAddTraits(.isHeader)
            ForEach(Array(ordered.prefix(2)), id: \.self) { block in
                Button { session.enableRoom(block); session.requestOpen(block) } label: {
                    HStack(spacing: 12) {
                        MadarGlyph(block.symbol, size: 26).foregroundStyle(theme.accent)
                        Text(block.title).font(MadarTypography.body().bold())
                        Spacer(minLength: 8)
                        Image(systemName: "plus.circle").font(.title3).foregroundStyle(theme.accent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.madarPlain).accessibilityIdentifier("bahw-add-" + block.rawValue)
                if block != ordered.prefix(2).last { Divider().overlay(theme.line) }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: .rect(cornerRadius: 22)).overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.line) }
    }
}

extension BahwBlock {
    var themeRoom: String {
        switch self { case .salah: "salah"; case .quran: "quran"; case .mal: "mal"; case .notes: "notes"; case .mihbara: "mihbara"; default: "bahw" }
    }
}

extension BahwBlock {
    /// What a reminder from this room says it will do, shown beside the one permission button.
    var reminderLine: String? {
        switch self {
        case .salah: "يسألك مدار عن صلاتك بعد الأذان بنحو نصف ساعة، ولا يصلك شيء وقت الصلاة نفسها."
        case .quran: "يذكّرك بوردك بلطف في الوقت الذي تختاره، ولا يزعجك إن قرأته."
        case .habits: "يذكّرك بعادتك في وقتها بكلمة خفيفة تشجّعك."
        case .notes: "يسألك عن نيّة يومك، ويذكّرك بذكرى من مثل هذا اليوم."
        default: nil
        }
    }
}
