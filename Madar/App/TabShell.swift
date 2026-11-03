import SwiftUI
import UIKit
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

    var body: some View {
        baseTabView.tint(theme.accent)
    }


    /// Owner, 3 Nov 2026: «اختفاء الأقسام خلف المزيد، مهب زين، ابيه ثابت الي تحت». The system bar lists at most five tabs and
    /// folds the rest into «المزيد», so it is hidden and Madar draws one fixed bar with every room the user turned on.
    /// «خصّص» stays a tab so the lobby can open it, but it is not in the bar.
    /// Owner, 3 Nov 2026 (TestFlight 4): the hidden `TabView` kept every room alive and made the app hang on each switch. Only the
    /// room on screen is built now; the bar below is Madar's own floating glass capsule.
    private var baseTabView: some View {
        content(selection)
            .id(selection)
            .accessibilityIdentifier(selection == "customize" ? "settings-tab" : selection + "-tab")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) { if session.accessoryHiders.isEmpty { fixedBar } }
    }

    private var fixedBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs.filter { $0.id != "customize" }) { tab in
                let selected = selection == tab.id
                Button { selection = tab.id } label: {
                    VStack(spacing: 3) {
                        Group {
                            if tab.symbol.hasPrefix("Madar") { Image(tab.symbol + (selected ? "Selected" : "")).renderingMode(.template) }
                            else { Image(systemName: selected ? tab.symbol + ".fill" : tab.symbol).font(.system(size: 23, weight: .light)) }
                        }.frame(width: 26, height: 26)
                        Text(tab.title).font(MadarTypography.fine())
                    }
                    .foregroundStyle(selected ? theme.accent : theme.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background { if selected { Capsule().fill(theme.accent.opacity(0.14)).padding(.vertical, 3) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.madarPlain).accessibilityIdentifier("tab-" + tab.id)
            }
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .contain).accessibilityAddTraits(.isTabBar).accessibilityIdentifier("fixed-tab-bar")
        #if DEBUG
        // UI tests reach «خصّص» from any room; the bar no longer lists it, so tests get a tiny invisible handle at the top-centre of the bar (never in a release build).
        .overlay(alignment: .top) {
            if ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"] != nil {
                Button { selection = "customize" } label: { Rectangle().fill(.black.opacity(0.02)).frame(width: 14, height: 14) }
                    .accessibilityIdentifier("tab-customize").accessibilityLabel("خصّص")
            }
        }
        #endif
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 2)
        .ignoresSafeArea(.keyboard)
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
        content
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
        .buttonStyle(.madarPlain)
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
    /// The whole prayer history is recomputed to find the next prayer, so it is done once per minute and per
    /// committed prayer write, not on every parent redraw.
    private final class Cache { var key: [Int] = []; var model: BahwPrayerModel? }
    @State private var cache = Cache()

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let instant = session.prayerNow(timeline.date)
            let key = [Int(instant.timeIntervalSince1970 / 60), session.prayerRevision]
            let prayer: BahwPrayerModel? = {
                if cache.key != key { cache.model = AppBahwService(session: session, evaluationDate: instant).prayer(); cache.key = key }
                return cache.model
            }()
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
        let readingSaveCoordinator = MihbaraReadingSaveCoordinator.forSession(session)
        let dark = forcedColorScheme == .dark || (forcedColorScheme == nil && colorScheme == .dark)
        let theme = RoomTheme(dark: dark, calmPaper: false)
        // Owner, 3 Nov 2026: every room sits in the bottom bar from the start; opening one for the first time turns it on and shows its short intro.
        let enabledTabs = AppSession.roomTabs.map(\.tab)
        let allTabs: [FoundationTab] = ([FoundationTab(id: "foundation", title: "البهو", symbol: "MadarOrbit")]
            + enabledTabs.compactMap { id in AppSession.tabInfo[id] } + [FoundationTab(id: "customize", title: "خصّص", symbol: "MadarCustomize")])
        TabShell(session: session, selection: $session.selectedTab, tabs: allTabs) { tab in
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
            }
        }
        // Owner, 30 Oct 2026: the «افتح المحبرة» door in «خصّص» used to hang this cover on the settings page, which is rebuilt after every write,
        // so saving a note closed the whole room. Hosted here at the root it stays up until the reader leaves.
        .fullScreenCover(isPresented: $session.mihbaraOpen) { MihbaraHomeView(app: session).environment(\.roomTheme, theme) }
        .fullScreenCover(item: $session.moneyExpenseSeed, onDismiss: { session.presentNextMoneyExpenseSeed() }) { seed in MoneyQuickExpense(app: session, seed: seed) }
        .sheet(item: $session.pendingIntro) { block in RoomIntroSheet(session: session, block: block).environment(\.roomTheme, RoomTheme(room: block.themeRoom, dark: dark)) }
        .onChange(of: session.selectedTab) { _, tab in
            guard let block = AppSession.roomTabs.first(where: { $0.tab == tab })?.block else { return }
            if !session.roomEnabled(block) { session.enableRoom(block) }
            if session.introNeeded(block) { session.pendingIntro = block }
        }
        .font(MadarTypography.body())
        .environment(\.roomTheme, theme)
        .dynamicTypeSize(effectiveType)
        .preferredColorScheme(forcedColorScheme)
        .animation(themeAnimation, value: session.string("core.theme"))
        .task {
            #if DEBUG
            session.seedBahwReturnPlanFixtureIfRequested()
            #endif
            await session.applyProgressiveRoomsOnce()
            session.recordBahwReturnVisit()
            #if DEBUG
            await session.runLegacyDiaryTrialIfRequested()
            #endif
            do {
                try await session.drainInbox()
                try (session.syncService as? AppSyncService)?.processLocalHistory()
                try await (session.backupService as? AppBackupService)?.runScheduledBackup()
            } catch BackupOperationError.busy { }
            catch { session.errorMessage = "لم يكتمل تحديث البيانات. \(madarUserMessage(error))" }
            await session.refreshPrayerNotifications()
        }
        .overlay { AnchoredUndo(session: session) }
        .task { MadarTouchTracker.install() }
        .fullScreenCover(isPresented: Binding(get: { !session.onboardingComplete }, set: { _ in })) { FirstRunView(session: session).environment(\.roomTheme, theme).madarSheetErrorAlert(session) }
        .alert("لم تكتمل العملية", isPresented: Binding(get: {
            session.errorMessage != nil && !(session.mihbaraOpen && readingSaveCoordinator.canRetryPendingWriteErrorNow)
        }, set: { if !$0 { session.errorMessage = nil } })) {
            if readingSaveCoordinator.canRetryPendingWriteErrorNow {
                Button("إعادة المحاولة") {
                    readingSaveCoordinator.dismissPendingWriteError()
                    readingSaveCoordinator.retryPendingWritesNow()
                }
                .accessibilityIdentifier("mihbara-reading-save-retry")
            }
            Button("حسنًا") { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
        .onChange(of: session.string("core.backup")) { _, _ in
            Task { await (session.backupService as? AppBackupService)?.refreshBackgroundSchedule() }
        }
        // A new time zone moves every prayer time: plan the reminders again while the app is open (on return it already does).
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            Task { await session.refreshPrayerNotifications() }
        }
        .onChange(of: scenePhase) { _, phase in
            // The crash log from the owner's iPhone (3 Nov, termination 0xDEAD10CC) shows the app suspended while a SwiftData read
            // held the store's file lock. Asking the system for a few seconds when the app leaves the screen lets that work finish first.
            if phase != .active {
                var task = UIBackgroundTaskIdentifier.invalid
                task = UIApplication.shared.beginBackgroundTask(withName: "madar.store.settle") { UIApplication.shared.endBackgroundTask(task) }
                Task { try? await Task.sleep(for: .seconds(8)); UIApplication.shared.endBackgroundTask(task) }
            }
            if phase == .active && !session.maintenanceInProgress {
                do {
                    try session.reload()
                    try session.publishSnapshot()
                    session.recordBahwReturnVisit()
                }
                catch { session.errorMessage = "تعذّر تحديث الواجهة. \(madarUserMessage(error))" }
                Task {
                    do {
                        try await session.drainInbox()
                        try (session.syncService as? AppSyncService)?.processLocalHistory()
                        try await (session.backupService as? AppBackupService)?.runScheduledBackup()
                    } catch BackupOperationError.busy { }
                    catch { session.errorMessage = "لم يكتمل تحديث البيانات. \(madarUserMessage(error))" }
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

extension View {
    /// AU-36/37: the root alert cannot show over a sheet, so a sheet carries its own for `session.errorMessage`.
    func madarSheetErrorAlert(_ session: AppSession) -> some View {
        let readingSaveCoordinator = MihbaraReadingSaveCoordinator.forSession(session)
        return alert("لم تكتمل العملية", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
            if readingSaveCoordinator.canRetryPendingWriteErrorNow {
                Button("إعادة المحاولة") {
                    readingSaveCoordinator.dismissPendingWriteError()
                    readingSaveCoordinator.retryPendingWritesNow()
                }
                .accessibilityIdentifier("mihbara-reading-save-retry")
            }
            Button("حسنًا") { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
    }
}

/// Owner, 3 Nov 2026 (option B, «التراجع بشكل عام»): undo is a small «تراجع» chip beside the spot the user just touched, in every room,
/// instead of a bar above the tab bar. A passive window-level recognizer only remembers where the last touch began.
final class MadarTouchTracker: UIGestureRecognizer, UIGestureRecognizerDelegate {
    nonisolated(unsafe) static var last = CGPoint(x: 200, y: 400)
    nonisolated(unsafe) private static var installed = false
    @MainActor static func install() {
        guard !installed,
              let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow) else { return }
        installed = true
        window.addGestureRecognizer(MadarTouchTracker(target: nil, action: nil))
    }
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false; delaysTouchesBegan = false; delaysTouchesEnded = false; delegate = self
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { Self.last = touch.location(in: nil) }
        state = .failed
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

private struct AnchoredUndo: View {
    let session: AppSession
    @Environment(\.roomTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the chip sits is fixed when it appears, so it never drifts while the user keeps tapping.
    @State private var anchor = CGPoint(x: 200, y: 400)
    var body: some View {
        GeometryReader { proxy in
            if session.undoToastVisible {
                let x = min(max(anchor.x, 70), proxy.size.width - 70)
                let y = min(max(anchor.y - 52, proxy.safeAreaInsets.top + 36), proxy.size.height - proxy.safeAreaInsets.bottom - 110)
                Button { session.undo() } label: {
                    Label("تراجع", systemImage: "arrow.uturn.backward").font(MadarTypography.body().bold()).foregroundStyle(theme.accent)
                        .padding(.horizontal, 16).frame(minHeight: 44).contentShape(Capsule())
                }
                .buttonStyle(.madarPlain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .position(x: x, y: y)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                .accessibilityIdentifier("undo-button")
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(session.undoToastVisible)
        .onChange(of: session.undoToastVisible) { _, visible in if visible { anchor = MadarTouchTracker.last } }
    }
}
