import SwiftUI
import MadarDesign
import MadarData

struct FoundationTab: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
}

/// Only built destinations enter this shell. Future rooms supply destinations at their milestone.
struct TabShell<Content: View>: View {
    @Binding var selection: String
    let tabs: [FoundationTab]
    let style: String
    let labels: String
    let minimize: Bool
    @ViewBuilder let content: (String) -> Content
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        if style == "glass" {
            TabView(selection: $selection) {
                ForEach(tabs) { tab in
                    Tab(tab.title, systemImage: tab.symbol, value: tab.id) {
                        content(tab.id).accessibilityIdentifier(tab.id == "customize" ? "settings-tab" : "foundation-tab")
                    }
                }
            }
            .tabBarMinimizeBehavior(minimize ? .onScrollDown : .never)
            .tint(theme.accent)
        } else {
            content(selection).safeAreaInset(edge: .bottom, spacing: 8) {
                HStack(spacing: style == "capsule" ? 4 : 8) {
                    ForEach(tabs) { tab in
                        Button { selection = tab.id } label: {
                            VStack(spacing: 4) {
                                Image(systemName: tab.symbol).font(.title3)
                                if labels == "all" || tab.id == selection || dynamicType.isAccessibilitySize {
                                    Text(tab.title).font(MadarTypography.fine()).fixedSize(horizontal: false, vertical: true)
                                }
                            }.frame(maxWidth: .infinity, minHeight: 48)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .foregroundStyle(tab.id == selection ? theme.onAccent : theme.ink)
                                .background(tab.id == selection ? theme.accentFill : theme.surface, in: .rect(cornerRadius: style == "capsule" ? 32 : 16))
                        }
                        .buttonStyle(.plain).accessibilityLabel(tab.title)
                        .accessibilityAddTraits(tab.id == selection ? .isSelected : [])
                        .accessibilityIdentifier(tab.id == "customize" ? "settings-tab" : "foundation-tab")
                    }
                }
                .padding(style == "capsule" ? 8 : 0)
                .background(style == "capsule" ? theme.surface : .clear, in: .capsule)
                .padding(.horizontal, style == "capsule" ? 24 : 16).padding(.bottom, 8)
            }
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
        let theme = RoomTheme(dark: dark, calmPaper: session.string("core.roomIdentity") == "calmPaper")
        TabShell(selection: $session.selectedTab, tabs: [.init(id: "foundation", title: "مدار", symbol: "circle.hexagongrid"), .init(id: "customize", title: "خصّص", symbol: "slider.horizontal.3")], style: session.string("tabbar.style"), labels: session.string("tabbar.labels"), minimize: session.bool("tabbar.minimizeOnScroll")) { tab in
            NavigationStack {
                if tab == "customize" { CustomizeMadar(session: session) }
                else { FoundationHome(session: session) }
            }
        }
        .font(MadarTypography.body())
        .environment(\.roomTheme, theme)
        .dynamicTypeSize(effectiveType)
        .preferredColorScheme(forcedColorScheme)
        .animation(themeAnimation, value: session.string("core.theme"))
        .animation(themeAnimation, value: session.string("core.roomIdentity"))
        .animation(themeAnimation, value: session.string("tabbar.style"))
        .task {
            do {
                try await session.drainInbox()
                try (session.syncService as? AppSyncService)?.processLocalHistory()
                try await (session.backupService as? AppBackupService)?.runScheduledBackup()
            } catch BackupOperationError.busy { }
            catch { session.errorMessage = "لم يكتمل تحديث البيانات. \(error.localizedDescription)" }
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
                }
            }
        }
    }
    private var themeAnimation: Animation? {
        guard session.string("core.motion") != "none" else { return nil }
        if reduceMotion || session.string("core.motion") == "calm" { return .easeInOut(duration: 0.2) }
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
        let minimum: DynamicTypeSize = switch session.string("core.fontScale") { case "large": .xLarge; case "xlarge": .xxxLarge; default: .large }
        return max(dynamicType, minimum)
    }
}
