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
    var body: some View {
        TabView(selection: $selection) {
            ForEach(tabs) { tab in
                Tab(tab.title, systemImage: tab.symbol, value: tab.id) {
                    content(tab.id).accessibilityIdentifier(tab.id == "customize" ? "settings-tab" : tab.id == "prayer" ? "prayer-tab" : tab.id == "quran" ? "quran-tab" : "foundation-tab")
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(theme.accent)
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
        TabShell(selection: $session.selectedTab, tabs: [.init(id: "foundation", title: "مدار", symbol: "circle.hexagongrid"), .init(id: "prayer", title: "الصلاة", symbol: "moon.stars"), .init(id: "quran", title: "القرآن", symbol: "book.closed"), .init(id: "customize", title: "خصّص", symbol: "slider.horizontal.3")]) { tab in
            NavigationStack {
                if tab == "customize" { CustomizeMadar(session: session) }
                else if tab == "prayer" { PrayerTodayView(session: session) }
                else if tab == "quran" { QuranHomeView(service: AppQuranService(session: session)) }
                else { FoundationHome(session: session) }
            }
        }
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
