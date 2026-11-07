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
extension EnvironmentValues {
    /// Counts how many times this room has come to the front. Rooms stay alive between visits (no rebuild on every tap), so a room
    /// that refreshed itself on appear refreshes on `.task(id: roomVisit)` instead.
    @Entry var roomVisit = 0
    /// False for a room kept alive behind the one on screen: its refresh triggers (a write elsewhere, a return to the app) wait,
    /// and `roomVisit` catches it up when it comes to the front, so four rooms never refresh at once.
    @Entry var isFrontRoom = true
}

/// Only built destinations enter this shell. Future rooms supply destinations at their milestone.
struct TabShell<Content: View>: View {
    let session: AppSession
    @Binding var selection: String
    let tabs: [FoundationTab]
    @ViewBuilder let content: (String) -> Content
    @Environment(\.roomTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Rooms already built, most recent last. Owner, 5 Nov 2026: «الترانزشن بين الاقسام غبيه ويعلق التطبيق… قاسي صلب». Each tap used
    /// to destroy the room on screen and build the next one from nothing (`.id(selection)`), with a hard cut. Now a room is built on its
    /// first visit and kept, so going back is instant and the switch is a short cross-fade. At most four stay alive (the lobby always).
    @State private var alive: [String] = []
    @State private var visits: [String: Int] = [:]

    @State private var barHeight: CGFloat = 0
    @State private var bottomInset: CGFloat = 0

    var body: some View {
        rooms
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0; session.tabBarHeight = max(0, barHeight - $0) }
            // A `safeAreaInset` outside the navigation stack never reached the rooms' own layouts, so the bar is an overlay and its
            // measured height is added to the safe area of everything inside.
            .overlay(alignment: .bottom) {
                if barShown {
                    fixedBar
                        // The system bar reaches down over the home indicator; only the part above it is added to the rooms' safe area.
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0; session.tabBarHeight = max(0, $0 - bottomInset) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: barShown)
            #if DEBUG
            // UI tests reach «خصّص» from any room; the bar no longer lists it, so tests get a tiny invisible handle (never in a release
            // build). It sits in the corner under the bar: on the bar it lay over the Quran tab, and a tap there opened the Quran.
            .overlay(alignment: .bottomLeading) {
                if barShown, ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"] != nil {
                    Button { selection = "customize" } label: { Rectangle().fill(.black.opacity(0.02)).frame(width: 14, height: 14) }
                        .accessibilityIdentifier("tab-customize").accessibilityLabel("خصّص")
                        // Just above the system bar: a UIKit bar takes every touch inside its own frame.
                        .padding(.bottom, max(0, barHeight - bottomInset) + 2)
                }
            }
            #endif
            .tint(theme.accent)
            .onChange(of: selection, initial: true) { _, tab in remember(tab) }
    }

    private var rooms: some View {
        ZStack {
            ForEach(alive, id: \.self) { tab in
                let front = tab == selection
                content(tab)
                    .environment(\.roomVisit, visits[tab] ?? 0)
                    .environment(\.isFrontRoom, front)
                    .accessibilityIdentifier(tab == "customize" ? "settings-tab" : tab + "-tab")
                    .allowsHitTesting(front)
                    .accessibilityHidden(!front)
                    .zIndex(front ? 1 : 0)
                    // The room arriving lifts out of a lighter focus on a shorter, more settled spring; the one leaving sinks back.
                    // Keeping the transform small makes switches feel direct and avoids blurring an entire live room at full strength.
                    .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.86)) {
                        $0.opacity(front ? 1 : 0)
                            .scaleEffect(front || reduceMotion ? 1 : 0.98)
                            .blur(radius: front || reduceMotion ? 0 : 5)
                            .offset(y: front || reduceMotion ? 0 : 8)
                    }
            }
        }
    }

    private func remember(_ tab: String) {
        visits[tab, default: 0] += 1
        alive.removeAll { $0 == tab }
        alive.append(tab)
        // The lobby is home and stays; the oldest other room is released when a fifth would be kept.
        while alive.count > 4, let oldest = alive.first(where: { $0 != "foundation" && $0 != tab }) { alive.removeAll { $0 == oldest } }
    }

    private var barShown: Bool { session.accessoryHiders.isEmpty }
    private var barTabs: [FoundationTab] { tabs.filter { $0.id != "customize" } }

    private func select(_ id: String) {
        guard id != selection else { return }
        selection = id
    }

    /// Owner, 6 Nov 2026: «الجلاس ضعيف… ولاهب بالمرونه اطلاقاً». The hand-drawn capsule never refracted or moved like the system bar, so the
    /// bar is now the system's own `UITabBar` (Liquid Glass, the liquid selection lens, press and drag-to-switch), holding every room with no
    /// «More» (a standalone bar has no More tab; owner FB-15). «خصّص» stays out of it and lights no tab.
    private var fixedBar: some View {
        MadarSystemTabBar(tabs: barTabs, selection: selection, accent: theme.accent, ink: theme.ink, select: select)
            .accessibilityIdentifier("fixed-tab-bar")
            .ignoresSafeArea(.container, edges: .bottom)
            .ignoresSafeArea(.keyboard)
            .sensoryFeedback(.selection, trigger: selection)
    }
}

/// The system tab bar hosted alone: it draws, refracts and animates itself; Madar only feeds it rooms and reads the tap.
private struct MadarSystemTabBar: UIViewRepresentable {
    let tabs: [FoundationTab]
    let selection: String
    let accent: Color
    let ink: Color
    let select: (String) -> Void
    @Environment(\.layoutDirection) private var layoutDirection

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITabBar {
        let bar = UITabBar()
        bar.delegate = context.coordinator
        bar.isTranslucent = true
        return bar
    }

    func updateUIView(_ bar: UITabBar, context: Context) {
        let coordinator = context.coordinator
        coordinator.select = select
        bar.semanticContentAttribute = layoutDirection == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        bar.tintColor = UIColor(accent)
        bar.unselectedItemTintColor = UIColor(ink.opacity(0.72))
        if coordinator.ids != tabs.map(\.id) {
            coordinator.ids = tabs.map(\.id)
            bar.setItems(tabs.map(Self.item), animated: false)
            bar.standardAppearance = Self.appearance
            bar.scrollEdgeAppearance = Self.appearance
        }
        let target = bar.items?.first { $0.accessibilityIdentifier == "tab-" + selection }
        if bar.selectedItem !== target { bar.selectedItem = target }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITabBar, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.window?.bounds.width ?? 390
        return CGSize(width: width, height: uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }

    private static func item(_ tab: FoundationTab) -> UITabBarItem {
        // Owner, 6 Nov 2026: «مضغوط النص… المذكرات داخله بالشعار». Madar's own glyphs were drawn taller than system symbols, so the
        // Arabic ascenders of the label touched them; every icon now fits the system's 24-point box and the label sits a little lower.
        let custom = tab.symbol.hasPrefix("Madar")
        let symbol = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let image = custom ? fitted(UIImage(named: tab.symbol)) : UIImage(systemName: tab.symbol, withConfiguration: symbol)
        let selected = custom ? fitted(UIImage(named: tab.symbol + "Selected")) : UIImage(systemName: tab.symbol + ".fill", withConfiguration: symbol)
        let item = UITabBarItem(title: tab.title, image: image, selectedImage: selected ?? image)
        item.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 2)
        item.accessibilityIdentifier = "tab-" + tab.id
        return item
    }

    /// Scales a glyph to fit 24 × 24 points, keeping its proportions, as a template the bar tints.
    private static func fitted(_ image: UIImage?) -> UIImage? {
        guard let image, image.size.width > 0, image.size.height > 0 else { return image }
        let box: CGFloat = 24
        let scale = min(box / image.size.width, box / image.size.height)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.withRenderingMode(.alwaysTemplate)
    }

    private static var appearance: UITabBarAppearance {
        let appearance = UITabBarAppearance()
        // Fixed size, as the system bar keeps it: a label that grew with the owner's larger text ran into its icon. Larger text
        // still reads through the system's long-press large-content view on the bar.
        let font = UIFont(name: "thmanyahsans-Medium", size: 11) ?? .systemFont(ofSize: 11, weight: .medium)
        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            layout.normal.titleTextAttributes = [.font: font]
            layout.selected.titleTextAttributes = [.font: font]
        }
        return appearance
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var ids: [String] = []
        var select: (String) -> Void = { _ in }
        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard let id = item.accessibilityIdentifier?.replacingOccurrences(of: "tab-", with: "") else { return }
            select(id)
        }
    }
}

extension View {
    /// A screen's own undo line: while it shows, the root one stays away, so a removal never shows two.
    func hostsUndo(_ session: AppSession) -> some View {
        onAppear { session.localUndoHosts += 1 }.onDisappear { session.localUndoHosts = max(0, session.localUndoHosts - 1) }
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

/// One room's navigation root. Its only inputs are the session (a stable reference) and the tab, so when the app root redraws after a
/// write the rooms kept alive behind the one on screen are not rebuilt with it; each redraws only for what it reads itself.
struct MadarRoomRoot: View {
    let session: AppSession
    let tab: String
    var body: some View {
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
            .safeAreaPadding(.bottom, session.accessoryHiders.isEmpty ? session.tabBarHeight : 0)
            // Every scrolling page in the room, settings and pushed pages included, fades softly under the clock instead of a hard cut.
            .scrollEdgeEffectStyle(.soft, for: .top)
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
        let readingSaveCoordinator = MihbaraReadingSaveCoordinator.forSession(session)
        let dark = forcedColorScheme == .dark || (forcedColorScheme == nil && colorScheme == .dark)
        let theme = RoomTheme(dark: dark, calmPaper: false)
        // Owner, 3 Nov 2026: every room sits in the bottom bar from the start; opening one for the first time turns it on and shows its short intro.
        let enabledTabs = AppSession.roomTabs.map(\.tab)
        let allTabs: [FoundationTab] = ([FoundationTab(id: "foundation", title: "البهو", symbol: "MadarOrbit")]
            + enabledTabs.compactMap { id in AppSession.tabInfo[id] } + [FoundationTab(id: "customize", title: "خصّص", symbol: "MadarCustomize")])
        TabShell(session: session, selection: $session.selectedTab, tabs: allTabs) { tab in
            MadarRoomRoot(session: session, tab: tab)
        }
        // Owner, 30 Oct 2026: the «افتح المحبرة» door in «خصّص» used to hang this cover on the settings page, which is rebuilt after every write,
        // so saving a note closed the whole room. Hosted here at the root it stays up until the reader leaves.
        .fullScreenCover(isPresented: $session.mihbaraOpen) { MihbaraHomeView(app: session).environment(\.roomTheme, theme) }
        .fullScreenCover(item: $session.moneyExpenseSeed, onDismiss: { session.presentNextMoneyExpenseSeed() }) { seed in MoneyQuickExpense(app: session, seed: seed) }
        .sheet(item: $session.pendingIntro) { block in RoomIntroSheet(session: session, block: block).environment(\.roomTheme, RoomTheme(room: block.themeRoom, dark: dark)) }
        .onChange(of: session.selectedTab) { _, tab in
            guard let block = AppSession.roomTabs.first(where: { $0.tab == tab })?.block else { return }
            if !session.roomEnabled(block) && !session.roomWasOpenedBefore(block) { session.enableRoom(block) }
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
            session.requestPrayerNotificationRefresh()
        }
        .overlay { AnchoredUndo(session: session) }
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
            session.requestPrayerNotificationRefresh()
        }
        .onChange(of: scenePhase) { _, phase in
            // The crash log from the owner's iPhone (3 Nov, termination 0xDEAD10CC) shows the app suspended while a SwiftData read
            // held the store's file lock. Asking the system for a few seconds when the app leaves the screen lets that work finish first.
            if phase != .active {
                var task = UIBackgroundTaskIdentifier.invalid
                task = UIApplication.shared.beginBackgroundTask(withName: "madar.store.settle") { UIApplication.shared.endBackgroundTask(task) }
                // Inside the background grant, so the store write never races suspension (0xDEAD10CC).
                session.flushPendingSnapshot()
                // A reminder plan still waiting for saves to settle runs now, so leaving the app never strands an old request.
                if phase == .background { Task { await session.prayerNotifications?.flushPendingRefresh() } }
                Task { try? await Task.sleep(for: .seconds(8)); UIApplication.shared.endBackgroundTask(task) }
            }
            if phase == .active && !session.maintenanceInProgress {
                // Returning to the app used to reload, rebuild every widget and drain the inbox before the first frame moved.
                // The first frame now shows what is already on screen; the refresh follows once the system animation has settled.
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    do {
                        try session.reload()
                        try session.publishSnapshot()
                        session.recordBahwReturnVisit()
                    }
                    catch { session.errorMessage = "تعذّر تحديث الواجهة. \(madarUserMessage(error))" }
                    do {
                        try await session.drainInbox()
                        try (session.syncService as? AppSyncService)?.processLocalHistory()
                        try await (session.backupService as? AppBackupService)?.runScheduledBackup()
                    } catch BackupOperationError.busy { }
                    catch { session.errorMessage = "لم يكتمل تحديث البيانات. \(madarUserMessage(error))" }
                    session.requestPrayerNotificationRefresh()
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

/// Owner, 5 Nov 2026: the chip that jumped up beside the finger after every tap is gone. A removal (the only thing that still offers undo)
/// shows one quiet glass line just above the bottom bar; it glides in, leaves on its own after four seconds, and a swipe down puts it away.
private struct AnchoredUndo: View {
    let session: AppSession
    @Environment(\.roomTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack {
            Spacer()
            if session.undoToastVisible && session.localUndoHosts == 0 {
                HStack(spacing: 14) {
                    Text(session.undoMessage).font(MadarTypography.caption()).foregroundStyle(theme.ink).lineLimit(1)
                    Button { session.undo() } label: {
                        Text("تراجع").font(MadarTypography.caption().bold()).foregroundStyle(theme.accent)
                            .frame(minWidth: 44, minHeight: 40).contentShape(Rectangle())
                    }
                    .buttonStyle(.madarPlain)
                    .accessibilityIdentifier("undo-button")
                }
                .padding(.horizontal, 18)
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.bottom, session.tabBarHeight + 10)
                .gesture(DragGesture(minimumDistance: 12).onEnded { if $0.translation.height > 0 { session.hideUndoToast() } })
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(session.undoToastVisible)
    }
}


/// Owner, 6 Nov 2026: «الجلاس ابدا مهب موجود». A room's scroll view was clipped to its frame, so nothing ever passed under the
/// bottom Liquid Glass bar and the glass read as a flat capsule. This clip keeps scrolling ink out of the status bar only; below,
/// the content runs on under the glass bar (and any floating glass button) for the glass to refract.
struct MadarTopClip: Shape {
    func path(in rect: CGRect) -> Path { Path(CGRect(x: rect.minX - 400, y: rect.minY, width: rect.width + 800, height: rect.height + 2000)) }
}
extension View {
    /// Owner, 6 Nov 2026: «مشطوف». The hard cut under the clock is gone: the system's soft scroll edge fades the ink out under the status bar.
    func madarTopClipped() -> some View { scrollEdgeEffectStyle(.soft, for: .top) }
}
