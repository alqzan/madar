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
    @Binding var selection: String
    let tabs: [FoundationTab]
    @ViewBuilder let content: (String) -> Content
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @AppStorage("Madar.TabViewCustomization") private var tabCustomization = TabViewCustomization()
    private let bottomShortcuts: Set<String> = ["notes", "money", "mihbara"]

    var body: some View {
        TabView(selection: $selection) {
            ForEach(tabs.filter { !bottomShortcuts.contains($0.id) }) { tab in
                if tab.symbol.hasPrefix("Madar") {
                    Tab(tab.title, image: tab.symbol + (selection == tab.id ? "Selected" : ""), value: tab.id) {
                        content(tab.id).accessibilityIdentifier(tab.id + "-tab")
                    }
                    .customizationID("com.madar.tab.\(tab.id)")
                } else {
                    Tab(tab.title, systemImage: tab.symbol, value: tab.id) {
                        content(tab.id).accessibilityIdentifier(tab.id == "customize" ? "settings-tab" : tab.id + "-tab")
                    }
                    .customizationID("com.madar.tab.\(tab.id)")
                }
            }
            TabSection {
                ForEach(tabs.filter { bottomShortcuts.contains($0.id) }) { tab in
                    if tab.symbol.hasPrefix("Madar") {
                        Tab(tab.title, image: tab.symbol + (selection == tab.id ? "Selected" : ""), value: tab.id) {
                            content(tab.id).accessibilityIdentifier(tab.id + "-tab")
                        }
                        .customizationID("com.madar.tab.\(tab.id)")
                    } else {
                        Tab(tab.title, systemImage: tab.symbol, value: tab.id) {
                            content(tab.id).accessibilityIdentifier(tab.id == "customize" ? "settings-tab" : tab.id + "-tab")
                        }
                        .customizationID("com.madar.tab.\(tab.id)")
                    }
                }
            } header: {
                Label("غرف مدار", systemImage: "square.grid.2x2")
            }
            .customizationID("com.madar.section.quick-access")
            .defaultVisibility(.hidden, for: .tabBar)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($tabCustomization)
        .defaultAdaptableTabBarPlacement(.tabBar)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { bottomAccessory }
        .tint(theme.accent)
    }

    private var bottomAccessory: some View {
        GlassRoomShortcuts(tabs: tabs, persistentShortcutIDs: bottomShortcuts, selection: $selection,
                           accent: theme.accent, secondaryInk: theme.secondaryInk)
    }
}

private struct GlassRoomShortcuts: View {
    let tabs: [FoundationTab]
    let persistentShortcutIDs: Set<String>
    @Binding var selection: String
    let accent: Color
    let secondaryInk: Color
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private var isInline: Bool { placement == .inline }
    private var visibleTabs: [FoundationTab] {
        if isInline { return tabs.filter { $0.id != selection } }
        return tabs.filter { persistentShortcutIDs.contains($0.id) }
    }

    var body: some View {
        GlassEffectContainer(spacing: isInline ? 8 : 6) {
            HStack(spacing: isInline ? 8 : 10) {
                ForEach(visibleTabs) { tab in
                    Button { selection = tab.id } label: {
                        Group {
                            if isInline {
                                roomIcon(tab)
                                    .frame(width: 22, height: 22)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            } else {
                                Label {
                                    Text(tab.title).lineLimit(1).minimumScaleFactor(0.8)
                                } icon: {
                                    roomIcon(tab).frame(width: 18, height: 18)
                                }
                                .font(MadarTypography.caption())
                                .frame(maxWidth: .infinity, minHeight: 44)
                            }
                        }
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.glass)
                    .tint(selection == tab.id ? accent : secondaryInk)
                    .accessibilityLabel(tab.title)
                    .accessibilityIdentifier("tab-\(tab.id)")
                    .accessibilityAddTraits(selection == tab.id ? .isSelected : [])
                }
            }
            .padding(.horizontal, isInline ? 8 : 12)
            .padding(.vertical, 3)
        }
    }

    @ViewBuilder private func roomIcon(_ tab: FoundationTab) -> some View {
        if tab.symbol.hasPrefix("Madar") {
            Image(tab.symbol + (selection == tab.id ? "Selected" : ""))
                .resizable().scaledToFit()
        } else {
            Image(systemName: tab.symbol).font(.system(size: 16, weight: .regular))
        }
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
        TabShell(selection: $session.selectedTab,
                 tabs: [.init(id: "foundation", title: "البهو", symbol: "MadarOrbit"), .init(id: "prayer", title: "الصلاة", symbol: "MadarPrayer"), .init(id: "quran", title: "القرآن", symbol: "MadarQuran"), .init(id: "customize", title: "خصّص", symbol: "MadarCustomize"), .init(id: "notes", title: "المذكرات", symbol: "MadarDiary"), .init(id: "money", title: "المال", symbol: "banknote"), .init(id: "mihbara", title: "المحبرة", symbol: "books.vertical")]) { tab in
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
                    Color.clear
                        .frame(height: dynamicType.isAccessibilitySize ? 88 : 72)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
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
            do {
                try await session.drainInbox()
                try (session.syncService as? AppSyncService)?.processLocalHistory()
                try await (session.backupService as? AppBackupService)?.runScheduledBackup()
            } catch BackupOperationError.busy { }
            catch { session.errorMessage = "لم يكتمل تحديث البيانات. \(error.localizedDescription)" }
            await session.refreshPrayerNotifications()
        }
        .overlay(alignment: .bottom) {
            if session.undoToken != nil { UndoToast(message: session.undoMessage, undo: session.undo).padding(.bottom, 86) }
        }
        .fullScreenCover(isPresented: Binding(get: { !session.onboardingComplete }, set: { _ in })) { FirstRunView(session: session).environment(\.roomTheme, theme) }
        .alert("لم تكتمل العملية", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
            Button("حسنًا") { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
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
