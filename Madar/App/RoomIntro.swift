import SwiftUI
import MadarDesign
import MadarData

extension BahwBlock: Identifiable { var id: String { rawValue } }

/// Owner, 3 Nov 2026 («ابيه بالتدريج»): Madar starts with the prayer room only. The other rooms are added one at a time from the lobby,
/// and each opens the first time with a short introduction and its few simple settings.
extension AppSession {
    static let roomTabs: [(block: BahwBlock, tab: String)] = [(.salah, "prayer"), (.quran, "quran"), (.notes, "notes"), (.mal, "money"), (.mihbara, "mihbara")]
    static let tabInfo: [String: FoundationTab] = [
        "prayer": .init(id: "prayer", title: "الصلاة", symbol: "MadarPrayer"), "quran": .init(id: "quran", title: "القرآن", symbol: "MadarQuran"),
        "notes": .init(id: "notes", title: "المذكرات", symbol: "MadarDiary"), "money": .init(id: "money", title: "المال", symbol: "banknote"),
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
    func introNeeded(_ block: BahwBlock) -> Bool { !UserDefaults.standard.bool(forKey: introKey(block)) }
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

    /// First launch of this build: every room except the prayer room is put away. Nothing is deleted; adding a room brings its data back.
    func applyProgressiveRoomsOnce() async {
        let key = "Madar.progressiveRooms.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"] != nil { UserDefaults.standard.set(true, forKey: key); return }
        #endif
        var layout = lobbyLayout
        for block in BahwBlock.allCases where block != .salah && BahwBlock.built.contains(block) {
            if !layout.blocks.contains(block.rawValue) { layout.blocks.append(block.rawValue) }
            if !layout.hidden.contains(block.rawValue) { layout.hidden.append(block.rawValue) }
        }
        do { try await applySettingsAndWait(["bahw.layout": layout.json]); UserDefaults.standard.set(true, forKey: key) } catch { }
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
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(content.steps, id: \.self) { step in
                        Label(step, systemImage: "checkmark.circle").font(MadarTypography.body()).labelStyle(.titleAndIcon)
                    }
                }
                if !content.toggles.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(content.toggles, id: \.key) { item in
                            Toggle(item.title, isOn: Binding(get: { session.bool(item.key) }, set: { session.set(.bool($0), key: item.key) }))
                                .frame(minHeight: 48).accessibilityIdentifier("intro-\(item.key)")
                        }
                    }
                }
                if block == .salah && session.canRequestNotificationPermission {
                    Button("اسمح بتنبيهات الصلاة") { session.requestPrayerNotificationPermission() }
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()).accessibilityIdentifier("intro-notifications")
                    Text("ينبّهك مدار عند دخول الوقت، ولا يصلك شيء أثناء الصلاة نفسها.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
                Button("ابدأ") {
                    session.markIntroSeen(block); session.pendingIntro = nil
                    if let tab = block.tab, session.selectedTab == tab { return }
                    session.openRoom(block)
                }.buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("intro-start")
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
            ForEach(ordered, id: \.self) { block in
                Button { session.enableRoom(block); session.requestOpen(block) } label: {
                    HStack(spacing: 12) {
                        MadarGlyph(block.symbol, size: 26).foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.title).font(MadarTypography.body().bold())
                            Text(block.intro.sentence).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "plus.circle").font(.title3).foregroundStyle(theme.accent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.madarPlain).accessibilityIdentifier("bahw-add-" + block.rawValue)
                if block != ordered.last { Divider().overlay(theme.line) }
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
