import SwiftUI
import MadarDesign
import MadarData
import MadarCore
import SwiftData

extension BahwBlock: Identifiable { var id: String { rawValue } }

/// Owner, 3 Nov 2026 («ابيه بالتدريج»): Madar starts with the prayer room only. The other rooms are added one at a time from the lobby,
/// and each opens the first time with a short introduction and its few simple settings.
extension AppSession {
    static let roomTabs: [(block: BahwBlock, tab: String)] = [(.habits, "habits"), (.quran, "quran"), (.notes, "notes"), (.mal, "money"), (.mihbara, "mihbara")]
    static let tabInfo: [String: FoundationTab] = [
        "habits": .init(id: "habits", title: "العادات", symbol: "MadarHabits"), "quran": .init(id: "quran", title: "القرآن", symbol: "MadarQuran"),
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

    private func introKey(_ block: BahwBlock) -> String {
        #if DEBUG
        if let store = ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"], UUID(uuidString: store) != nil {
            return "Madar.UITest." + store + ".introSeen." + block.rawValue
        }
        #endif
        return "Madar.introSeen." + block.rawValue
    }
    func introNeeded(_ block: BahwBlock) -> Bool {
        guard BahwBlock.built.contains(block), block != .notes else { return false }
        #if DEBUG
        // UI tests that are not about the intro open rooms directly; MADAR_UI_INTRO=1 brings the sheet back.
        let environment = ProcessInfo.processInfo.environment
        if environment["MADAR_UI_STORE_ID"] != nil, environment["MADAR_UI_INTRO"] != "1" { return false }
        #endif
        return !UserDefaults.standard.bool(forKey: introKey(block))
    }
    func markIntroSeen(_ block: BahwBlock) { UserDefaults.standard.set(true, forKey: introKey(block)) }
    /// True once the room's intro was shown: from then on a hidden lobby tile is the user's own choice and a tab visit leaves it hidden (FB-39).
    func roomWasOpenedBefore(_ block: BahwBlock) -> Bool { UserDefaults.standard.bool(forKey: introKey(block)) }

    /// The lobby's door: the first visit shows the introduction, later visits open the room.
    func requestOpen(_ block: BahwBlock) {
        if block == .notes || madarTour.completed { markIntroSeen(block) }
        if introNeeded(block) { pendingIntro = block } else { openRoom(block) }
    }

    func prepareRoomTab(_ tab: String) {
        guard let block = Self.roomTabs.first(where: { $0.tab == tab })?.block else { return }
        if !roomEnabled(block) && !roomWasOpenedBefore(block) { enableRoom(block) }
        if block == .notes || madarTour.completed { markIntroSeen(block) }
        if introNeeded(block) { pendingIntro = block }
    }

    func openRoom(_ block: BahwBlock) {
        switch block {
        case .habits: selectedTab = "habits"
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
    /// The first actions are shared by the first-visit sheet and the guide.
    var intro: (sentence: String, steps: [String]) {
        switch self {
        case .salah:
            ("تُستخدم مواقيت مدينتك لحساب بداية اليوم والتذكيرات المرتبطة بالصلاة.", [])
        case .quran:
            ("اقرأ من المصحف، أو تابع الحفظ والمراجعة.", [
                "افتح «المصحف» وابدأ القراءة من الوجه الذي تختاره.",
                "اختر «ابدأ خطة الحفظ» ليقترح لك مدار وردًا ومراجعة.",
                "سجّل ما أنجزت من الورد وتابع تقدّمك."
            ])
        case .habits:
            ("عادة صغيرة تقدر تتابعها كل يوم.", [
                "اختر «أضف أول عادة»، واكتب اسمها وطريقة متابعتها.",
                "سجّل إنجازك من العادات أو من ودجتها في البهو.",
                "ارجع إلى سجل العادة وشاهد سلسلتها."
            ])
        case .notes:
            ("صفحة لكل يوم، للكتابة والصور والتسجيلات.", [
                "افتح صفحة اليوم واكتب سطرك الأول.",
                "سجّل صوتك أو أضف صورة إلى الصفحة.",
                "ارجع إلى أيامك السابقة من الأرشيف."
            ])
        case .mal:
            ("حساباتك ومصروفاتك وما عليك من التزامات.", [
                "اختر «أضف حسابك يدويًا» وعرّف أول حساب.",
                "استخدم زر الإضافة لتسجيل مصروف من الحساب.",
                "راجع حركاتك، وأضف راتبك إذا أردت تتبّع الصرف خلال دورته."
            ])
        case .mihbara:
            ("مكتبتك وصفحتك الأخيرة واقتباساتك.", [
                "اختر «أضف كتابك الأول» وأضف ملف PDF أو EPUB، أو سجّل كتابًا ورقيًا.",
                "افتح الكتاب من رفّك وارجع إلى الموضع الذي وقفت عنده.",
                "احفظ ما يعجبك من الكتاب في اقتباساتك."
            ])
        case .year:
            ("تصفّح أيام السنة بالهجري والميلادي.", ["افتح ودجة «السنة» من البهو."])
        case .upcoming:
            ("تابع الأيام التي تنتظرها.", ["أضف يومًا يهمّك وتابع كم بقي عليه."])
        }
    }
}

struct RoomIntroSheet: View {
    @Bindable var session: AppSession
    let block: BahwBlock
    @Environment(\.roomTheme) private var theme

    var body: some View {
        let content = block.intro
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MadarGlyph(block.symbol, size: 44).foregroundStyle(theme.accent).accessibilityHidden(true)
                Text(block.title).font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
                Text(content.sentence).font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(content.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text(MadarNumberFormatter(style: session.string("core.numerals") == "western" ? .western : .hindi).string(index + 1))
                                .font(MadarTypography.caption()).foregroundStyle(theme.accent)
                                .frame(width: 26, height: 26).background(theme.surface, in: .circle)
                                .accessibilityHidden(true)
                            Text(step).font(MadarTypography.body()).fixedSize(horizontal: false, vertical: true)
                        }.accessibilityElement(children: .combine)
                            .accessibilityIdentifier("intro-step-\(index + 1)")
                    }
                }
                Button("ابدأ") {
                    session.markIntroSeen(block); session.pendingIntro = nil
                    if AppSession.roomTabs.contains(where: { $0.block == block && $0.tab == session.selectedTab }) { return }
                    session.openRoom(block)
                }.buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("intro-start")
                Button { session.markIntroSeen(block); session.pendingIntro = nil } label: { Text("تخطَّ التعريف")
                    .font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("intro-later")
            }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(theme.background).foregroundStyle(theme.ink).font(MadarTypography.body())
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }
}

extension BahwBlock {
    var themeRoom: String {
        switch self { case .salah, .habits: "salah"; case .quran: "quran"; case .mal: "mal"; case .notes: "notes"; case .mihbara: "mihbara"; default: "bahw" }
    }
}
