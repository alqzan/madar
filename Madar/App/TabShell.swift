import SwiftUI
import MadarDesign
import MadarData

struct FoundationTab: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
}

/// Only built destinations enter this shell. Future rooms supply destinations at their milestone.
/// RL8: the one tab bar is the native glass `TabView`; no alternate style is built.
struct TabShell<Content: View>: View {
    let session: AppSession
    @Binding var selection: String
    let tabs: [FoundationTab]
    @ViewBuilder let content: (String) -> Content
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @AppStorage("Madar.TabViewCustomization.v2") private var tabCustomization = TabViewCustomization()
    /// Owner, 21 Oct 2026: «خصّص» and «المزيد» in the bar hid المال and المحبرة. The bar holds the five daily rooms;
    /// the diary and «خصّص» ride the glass accessory beside the next prayer.
    private let bottomShortcuts: Set<String> = ["notes", "customize"]

    var body: some View {
        accessorized.tint(theme.accent)
    }

    /// A focused flow that hides the tab bar (`hidesRoomAccessory`) also hides the accessory, which otherwise
    /// floats over its bottom action (the expense «سجّل»). iOS 26.0 has no switch; those flows pad their bottom instead.
    @ViewBuilder private var accessorized: some View {
        if #available(iOS 26.1, *) {
            baseTabView.tabViewBottomAccessory(isEnabled: session.accessoryHiders.isEmpty) { shortcuts }
        } else {
            baseTabView.tabViewBottomAccessory { shortcuts }
        }
    }

    private var shortcuts: some View {
        GlassRoomShortcuts(tabs: tabs, persistentShortcutIDs: bottomShortcuts,
                           selection: $selection, session: session,
                           ink: theme.ink, secondaryInk: theme.secondaryInk,
                           prayerAccent: RoomTheme(room: "salah", dark: theme.dark).accent)
    }

    /// The room under the bar's highlight while the diary or «خصّص» is open from the accessory.
    @State private var lastRoom = "foundation"
    private var showingShortcut: Bool { bottomShortcuts.contains(selection) }

    private var baseTabView: some View {
        // Only the five rooms are tabs: any further Tab, even hidden or sidebar-only, makes iPhone add «المزيد».
        // A shortcut room renders in the highlighted room's place; tapping any tab (even that one) returns to it.
        TabView(selection: Binding(get: { showingShortcut ? lastRoom : selection }, set: { selection = $0; lastRoom = $0 })) {
            ForEach(tabs.filter { !bottomShortcuts.contains($0.id) }) { tab in
                let shown = showingShortcut && tab.id == lastRoom ? selection : tab.id
                if tab.symbol.hasPrefix("Madar") {
                    Tab(tab.title, image: tab.symbol + (selection == tab.id ? "Selected" : ""), value: tab.id) {
                        content(shown).accessibilityIdentifier(shown == "customize" ? "settings-tab" : shown + "-tab")
                    }
                    .customizationID("com.madar.tab.\(tab.id)")
                } else {
                    Tab(tab.title, systemImage: tab.symbol, value: tab.id) {
                        content(shown).accessibilityIdentifier(shown == "customize" ? "settings-tab" : shown + "-tab")
                    }
                    .customizationID("com.madar.tab.\(tab.id)")
                }
            }
        }
        .onChange(of: selection) { _, value in if !bottomShortcuts.contains(value) { lastRoom = value } }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($tabCustomization)
        .defaultAdaptableTabBarPlacement(.tabBar)
        .tabBarMinimizeBehavior(.onScrollDown)
    }

}

extension View {
    /// Hides the room accessory while this full-screen flow is on screen (see `TabShell.accessorized`).
    func hidesRoomAccessory(_ session: AppSession, id: String) -> some View {
        modifier(RoomAccessoryHider(session: session, id: id))
    }
}

private struct RoomAccessoryHider: ViewModifier {
    let session: AppSession
    let id: String
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.1, *) { content } else { content.safeAreaPadding(.bottom, 72) }
        }
        .onAppear { session.accessoryHiders.insert(id) }
        .onDisappear { session.accessoryHiders.remove(id) }
    }
}

private struct GlassRoomShortcuts: View {
    let tabs: [FoundationTab]
    let persistentShortcutIDs: Set<String>
    @Binding var selection: String
    let session: AppSession
    let ink: Color
    let secondaryInk: Color
    let prayerAccent: Color
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private var isInline: Bool { placement == .inline }
    private var visibleTabs: [FoundationTab] {
        if isInline { return tabs.filter { $0.id != selection } }
        return tabs.filter { persistentShortcutIDs.contains($0.id) && $0.id != selection }
    }

    var body: some View {
        Group {
            if isInline {
                HStack(spacing: 0) {
                    ForEach(visibleTabs) { tab in
                        shortcutButton(tab)
                    }
                }
                .padding(.horizontal, 0)
                .padding(.vertical, 3)
            } else {
                HStack(spacing: 2) {
                    PrayerAccessoryStatus(session: session, ink: ink,
                                          secondaryInk: secondaryInk, accent: prayerAccent)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    ForEach(visibleTabs) { tab in
                        shortcutButton(tab)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
            }
        }
    }

    private func shortcutButton(_ tab: FoundationTab) -> some View {
        Button { selection = tab.id } label: {
            roomIcon(tab)
                .frame(width: 20, height: 20)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(ink)
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("tab-\(tab.id)")
        .accessibilityAddTraits(selection == tab.id ? .isSelected : [])
    }

    @ViewBuilder private func roomIcon(_ tab: FoundationTab) -> some View {
        if tab.symbol.hasPrefix("Madar") {
            Image(tab.symbol + (selection == tab.id ? "Selected" : ""))
                .resizable().scaledToFit()
        } else {
            Image(systemName: tab.symbol).font(.system(size: 20, weight: .regular))
        }
    }
}

/// The expanded glass accessory shows the next useful moment; when the native bar
/// minimizes, the same surface becomes one-tap shortcuts to the other rooms.
private struct PrayerAccessoryStatus: View {
    let session: AppSession
    let ink: Color
    let secondaryInk: Color
    let accent: Color

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let instant = session.prayerNow(timeline.date)
            let prayer = AppBahwService(session: session, evaluationDate: instant).prayer()
            HStack(spacing: 8) {
                MadarGlyph("MadarPrayer", size: 20).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("الصلاة القادمة").font(MadarTypography.caption()).foregroundStyle(secondaryInk)
                    Text(prayer.flatMap { model in model.nextName.map { $0 + " " + (model.nextTime ?? "") } } ?? "المواقيت غير متاحة")
                        .font(MadarTypography.caption())
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    }
            }
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary(prayer))
            .accessibilityIdentifier("tab-accessory-next-prayer")
        }
    }

    private func accessibilitySummary(_ prayer: BahwPrayerModel?) -> String {
        guard let prayer, let name = prayer.nextName else { return "مواقيت الصلاة غير متاحة" }
        return ["الصلاة القادمة", name, prayer.nextTime]
            .compactMap { $0 }.joined(separator: "، ")
    }
}

struct MadarRootView: View {
    @Bindable var session: AppSession
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let dark = forcedColorScheme == .dark || (forcedColorScheme == nil && colorScheme == .dark)
        let theme = RoomTheme(dark: dark, calmPaper: false)
        TabShell(session: session, selection: $session.selectedTab,
                 tabs: [.init(id: "foundation", title: "البهو", symbol: "MadarOrbit"), .init(id: "prayer", title: "الصلاة", symbol: "MadarPrayer"), .init(id: "quran", title: "القرآن", symbol: "MadarQuran"), .init(id: "money", title: "المال", symbol: "banknote"), .init(id: "mihbara", title: "المحبرة", symbol: "books.vertical"), .init(id: "notes", title: "المذكرات", symbol: "MadarDiary"), .init(id: "customize", title: "خصّص", symbol: "MadarCustomize")]) { tab in
            NavigationStack {
                Group {
                    if tab == "customize" { CustomizeMadar(session: session) }
                    else if tab == "prayer" { PrayerTodayView(session: session) }
                    else if tab == "quran" { QuranHomeView(service: AppQuranService(session: session)) }
                    else if tab == "notes" { DiaryRoomView(app: session) }
                    else if tab == "money" { MoneyRoomView(app: session, isTabRoot: true) }
                    else if tab == "mihbara" { MihbaraHomeView(app: session, isTabRoot: true) }
                    // M4-V01: the lobby replaces the M0 foundation home (kept in FoundationHome.swift, unused).
                    else { BahwLobbyView(session: session) }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // Diary already reserves its writing bar above the native
                    // accessory; a second spacer hid the end of the memory card.
                    if tab != "notes" {
                        Color.clear
                            .frame(height: dynamicType.isAccessibilitySize ? 88 : 72)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .fullScreenCover(item: $session.moneyExpenseSeed) { seed in MoneyQuickExpense(app: session, seed: seed) }
        .font(MadarTypography.body())
        .environment(\.roomTheme, theme)
        .dynamicTypeSize(effectiveType)
        .preferredColorScheme(forcedColorScheme)
        .animation(themeAnimation, value: session.string("core.theme"))
        .task {
            #if DEBUG
            await session.runLegacyDiaryTrialIfRequested()
            #endif
            do {
                try await session.drainInbox()
                try (session.syncService as? AppSyncService)?.processLocalHistory()
                try await (session.backupService as? AppBackupService)?.runScheduledBackup()
            } catch BackupOperationError.busy { }
            catch { session.errorMessage = "لم يكتمل تحديث البيانات. \(error.localizedDescription)" }
            await session.refreshPrayerNotifications()
        }
        .overlay(alignment: .bottom) {
            if session.undoToastVisible { UndoToast(message: session.undoMessage, undo: session.undo).padding(.bottom, 86) }
        }
        .fullScreenCover(isPresented: Binding(get: { !session.onboardingComplete }, set: { _ in })) { FirstRunView(session: session).environment(\.roomTheme, theme) }
        .alert("لم تكتمل العملية", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
            Button("حسنًا") { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
        .onChange(of: session.string("core.backup")) { _, _ in
            Task { await (session.backupService as? AppBackupService)?.refreshBackgroundSchedule() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !session.maintenanceInProgress {
                do { try session.reload(); try session.publishSnapshot() }
                catch { session.errorMessage = "تعذّر تحديث الواجهة. \(error.localizedDescription)" }
                Task {
                    do {
                        try await session.drainInbox()
                        try (session.syncService as? AppSyncService)?.processLocalHistory()
                        try await (session.backupService as? AppBackupService)?.runScheduledBackup()
                    } catch BackupOperationError.busy { }
                    catch { session.errorMessage = "لم يكتمل تحديث البيانات. \(error.localizedDescription)" }
                    await session.refreshPrayerNotifications()
                }
            }
        }
    }
    private var themeAnimation: Animation? {
        // RA8: motion is fixed at its agreed default (full); Reduce Motion is still honoured.
        if reduceMotion { return .easeInOut(duration: 0.2) }
        let metrics = MadarMetric.values
        return .timingCurve(metrics["motion.themeSwitch.curve.0"]!, metrics["motion.themeSwitch.curve.1"]!, metrics["motion.themeSwitch.curve.2"]!, metrics["motion.themeSwitch.curve.3"]!, duration: metrics["motion.themeSwitch.duration"]!)
    }
    private var forcedColorScheme: ColorScheme? {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["MADAR_UI_THEME"] { return value == "dark" ? .dark : .light }
        #endif
        return session.string("core.theme") == "auto" ? nil : session.string("core.theme") == "dark" ? .dark : .light
    }
    private var effectiveType: DynamicTypeSize {
        #if DEBUG
        if let size = ProcessInfo.processInfo.environment["MADAR_UI_SIZE"] {
            return size == "AX5" ? .accessibility5 : size == "AX3" ? .accessibility3 : .large
        }
        #endif
        // RA8: core.fontScale is cut; the system's Dynamic Type setting is followed as is.
        return dynamicType
    }
}
