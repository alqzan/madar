import SwiftUI
import AppKit
import MadarData
import MadarCore
import MadarDesign

/// The Mac window: the rooms in a sidebar on the leading edge (the right side in Arabic) and the chosen room beside it, laid out as
/// the iPad's wide pages. A room keeps its own navigation stack, so going deeper and back works with the toolbar's back button and ⌘[.
struct MacRootView: View {
    @Bindable var session: AppSession
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columns: NavigationSplitViewVisibility = .all

    private var forcedColorScheme: ColorScheme? {
        session.string("core.theme") == "auto" ? nil : session.string("core.theme") == "dark" ? .dark : .light
    }
    private var dark: Bool { forcedColorScheme == .dark || (forcedColorScheme == nil && colorScheme == .dark) }

    var body: some View {
        let theme = RoomTheme(dark: dark, calmPaper: false)
        NavigationSplitView(columnVisibility: $columns) {
            MacSidebar(session: session)
                .madarTourAnchor(.navigation)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            MacRoomRoot(session: session, tab: session.selectedTab)
                .id(session.selectedTab)
        }
        .madarTourHost(session)
        .sheet(item: $session.moneyExpenseSeed, onDismiss: { session.presentNextMoneyExpenseSeed() }) { seed in
            MoneyQuickExpense(app: session, seed: seed).frame(minWidth: 520, minHeight: 560)
        }
        .sheet(item: $session.pendingIntro) { block in
            RoomIntroSheet(session: session, block: block).environment(\.roomTheme, RoomTheme(room: block.themeRoom, dark: dark))
                .frame(minWidth: 480, minHeight: 520)
        }
        .sheet(isPresented: Binding(get: { !session.onboardingComplete }, set: { _ in }),
               onDismiss: { session.startPendingMadarTour() }) {
            FirstRunView(session: session).environment(\.roomTheme, theme).madarSheetErrorAlert(session)
                .frame(minWidth: 560, minHeight: 640)
                .interactiveDismissDisabled()
        }
        .onChange(of: session.selectedTab) { _, tab in
            if session.madarTour.step == nil { session.prepareRoomTab(tab) }
        }
        .onChange(of: session.mihbaraOpen) { _, open in
            // The Mihbara is a sidebar room on the Mac: a shared screen that asks for it selects that room.
            if open { session.mihbaraOpen = false; session.selectedTab = "mihbara" }
        }
        .font(MadarTypography.body())
        .environment(\.roomTheme, theme)
        .preferredColorScheme(forcedColorScheme)
        .tint(theme.accent)
        .overlay { AnchoredUndo(session: session) }
        .alert("لم تكتمل العملية", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
            Button("حسنًا") { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
        .task {
            session.startPendingMadarTour()
            if !MacRooms.tabs.contains(where: { $0.id == session.selectedTab }) && session.selectedTab != "customize" { session.selectedTab = "foundation" }
            await session.applyProgressiveRoomsOnce()
            session.recordBahwReturnVisit()
            do {
                try await session.drainInbox()
                try (session.syncService as? AppSyncService)?.processLocalHistory()
                try await (session.backupService as? AppBackupService)?.runScheduledBackup()
            } catch BackupOperationError.busy { }
            catch { session.errorMessage = "لم يكتمل تحديث البيانات. \(madarUserMessage(error))" }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.flushPendingSnapshot() }
            guard phase == .active, !session.maintenanceInProgress else { return }
            Task {
                do { try session.reload(); try session.publishSnapshot(); session.recordBahwReturnVisit() }
                catch { session.errorMessage = "تعذّر تحديث الواجهة. \(madarUserMessage(error))" }
                do { try await session.drainInbox() }
                catch BackupOperationError.busy { }
                catch { session.errorMessage = "لم يكتمل تحديث البيانات. \(madarUserMessage(error))" }
                do { try await (session.backupService as? AppBackupService)?.runScheduledBackup() }
                catch BackupOperationError.busy { }
                catch { session.errorMessage = "لم تكتمل النسخة التلقائية. \(madarUserMessage(error))" }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            session.flushPendingSnapshot()
        }
    }
}

/// One room's navigation root on the Mac. The same room screens as iPhone and iPad; the Mac has no bottom bar, so no inset is added.
private struct MacRoomRoot: View {
    let session: AppSession
    let tab: String
    var body: some View {
        NavigationStack {
            Group {
                switch tab {
                case "customize": CustomizeMadar(session: session)
                case "habits": HabitsRoomView(session: session)
                case "quran": QuranHomeView(service: AppQuranService(session: session))
                case "notes": DiaryRoomView(app: session)
                case "money": MoneyRoomView(app: session, isTabRoot: true)
                case "mihbara": MihbaraHomeView(app: session, isTabRoot: true)
                default: BahwLobbyView(session: session)
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }
}

/// The room list: the lobby first, the rooms, then «خصّص» apart at the bottom, the chosen one lit in its room's accent.
private struct MacSidebar: View {
    @Bindable var session: AppSession
    @Environment(\.roomTheme) private var theme
    var body: some View {
        List(selection: Binding(get: { session.selectedTab }, set: { if let tab = $0 { session.selectedTab = tab } })) {
            Section {
                ForEach(MacRooms.tabs) { tab in row(tab).tag(tab.id) }
            } header: {
                Text("مدار").font(.custom("thmanyahserifdisplay-Bold", size: 26, relativeTo: .title)).foregroundStyle(theme.ink)
                    .padding(.bottom, 6)
            }
            Section {
                row(FoundationTab(id: "customize", title: "خصّص", symbol: "MadarCustomize")).tag("customize")
            }
        }
        .listStyle(.sidebar)
    }
    private func row(_ tab: FoundationTab) -> some View {
        Label {
            Text(tab.title).font(MadarTypography.section())
        } icon: {
            if NSImage(named: tab.symbol) != nil { Image(tab.symbol).renderingMode(.template).resizable().scaledToFit().frame(width: 20, height: 20) }
            else { Image(systemName: tab.symbol) }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("tab-" + tab.id)
    }
}
