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
    @Namespace private var lens
    @State private var scrubbing: String?
    @State private var tabFrames: [String: CGRect] = [:]

    var body: some View {
        rooms
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A `safeAreaInset` outside the navigation stack never reached the rooms' own layouts, so the bar is an overlay and its
            // measured height is added to the safe area of everything inside.
            .overlay(alignment: .bottom) {
                if barShown {
                    fixedBar
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { session.tabBarHeight = $0 }
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
                        .ignoresSafeArea()
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
                    // Only the fade and a hint of depth animate; nothing inside the room is swept into the transaction.
                    .animation(reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.24)) {
                        $0.opacity(front ? 1 : 0).scaleEffect(front || reduceMotion ? 1 : 0.985)
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

    /// Owner, 5 Nov 2026: «الشريط السفلي تحت لازال غبي وقذر ولاهب مرن». One Liquid Glass capsule that responds to touch, with a glass lens
    /// that glides to the chosen room on a spring; a finger can also slide along the bar and the lens follows it, the way the system bar does.
    private var fixedBar: some View {
        let lit = scrubbing ?? selection
        return GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(barTabs) { tab in
                    tabButton(tab, lit: lit == tab.id)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("madar-tab-bar")) } action: { tabFrames[tab.id] = $0 }
                }
            }
            .padding(4)
            .coordinateSpace(.named("madar-tab-bar"))
            .simultaneousGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .named("madar-tab-bar"))
                    .onChanged { value in
                        let hit = tabFrames.first { $0.value.insetBy(dx: 0, dy: -30).contains(value.location) }?.key
                        if let hit, hit != scrubbing { withAnimation(lensAnimation) { scrubbing = hit } }
                    }
                    .onEnded { _ in
                        if let target = scrubbing { select(target) }
                        withAnimation(lensAnimation) { scrubbing = nil }
                    }
            )
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .animation(lensAnimation, value: selection)
        .sensoryFeedback(.selection, trigger: lit)
        .accessibilityElement(children: .contain).accessibilityAddTraits(.isTabBar).accessibilityIdentifier("fixed-tab-bar")
        .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 2)
        .ignoresSafeArea(.keyboard)
    }

    private var lensAnimation: Animation { reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.78) }

    private func tabButton(_ tab: FoundationTab, lit: Bool) -> some View {
        let selected = selection == tab.id
        return Button { select(tab.id) } label: {
            VStack(spacing: 2) {
                Group {
                    if tab.symbol.hasPrefix("Madar") { Image(tab.symbol + (lit ? "Selected" : "")).renderingMode(.template) }
                    else { Image(systemName: lit ? tab.symbol + ".fill" : tab.symbol).font(.system(size: 22, weight: .light)) }
                }
                .frame(width: 26, height: 26)
                .scaleEffect(lit && !reduceMotion ? 1.08 : 1)
                Text(tab.title).font(MadarTypography.fine()).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(lit ? theme.accent : theme.ink.opacity(0.78))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                if lit {
                    Capsule()
                        .fill(theme.accent.opacity(scrubbing == nil ? 0.13 : 0.2))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.6))
                        .matchedGeometryEffect(id: "lens", in: lens)
                        .scaleEffect(scrubbing != nil && !reduceMotion ? 1.06 : 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.madarPlain)
        .accessibilityIdentifier("tab-" + tab.id)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                // Inside the background grant, so the store write never races suspension (0xDEAD10CC).
                session.flushPendingSnapshot()
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
