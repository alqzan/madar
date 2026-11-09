import SwiftUI
import MadarCore
import MadarDesign
import MadarPrayer

private struct PrayerHomeSnapshotKey: Equatable {
    let minute: Int
    let revision: Int
    let generation: Int
    let visit: Int
    let retry: Int
    let active: Bool
}
struct PrayerTodayMinuteTimelineSchedule: TimelineSchedule, Equatable, Sendable {
    let isActive: Bool

    func entries(from startDate: Date, mode: Mode) -> AnySequence<Date> {
        guard isActive else { return AnySequence(EmptyCollection<Date>()) }
        let minuteStart = Date(timeIntervalSince1970: floor(startDate.timeIntervalSince1970 / 60) * 60)
        let schedule = PeriodicTimelineSchedule(from: minuteStart, by: 60)
        return AnySequence(schedule.entries(from: startDate, mode: mode))
    }
}

/// S1 · Prayer home («الرواق والبركة»), matched to `screens/salah/01-S1-Home.jpg` and `-s1`.
/// Not copied from the canonical: the day/night button (prototype only), sample numbers,
/// the heart label under the arches (RP6), and the «تُحسب فائتة» line (RP1).
struct PrayerTodayView: View {
    @Bindable var session: AppSession
    @Environment(\.roomTheme) private var inheritedTheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedSheet: PrayerTodaySheet?
    @State private var prayerSheetIsVisible = false
    @State private var locator = TravelLocator()
    @State private var requestReadFailed = false
    @State private var prayerRequestReadTask: Task<Void, Never>?
    @State private var prayerRequestReadID = UUID()
    @State private var pendingPrayerRoute: Route?
    @State private var pendingPrayerRootRequestID: UUID?
    #if DEBUG
    @State private var injectedReadFailure = false
    @State private var injectedRoute = false
    @State private var debugPrayerRouteOpenedAfterDismissal: Bool?
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.roomVisit) private var roomVisit
    @Environment(\.isFrontRoom) private var isFrontRoom
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var roomWidth: CGFloat = 0

    @State private var homeSnapshot: PrayerSnapshot?
    @State private var loadedHomeSnapshotKey: PrayerHomeSnapshotKey?
    @State private var homeReadFailed = false
    @State private var homeReadRetry = 0
    #if DEBUG
    @State private var injectedHomeReadFailure = false
    #endif
    @State private var onTrip = false
    /// On a trip the home takes the calm-paper palette (cooler sand, same gold ornaments) so travel looks different at a glance.
    private var theme: RoomTheme { RoomTheme(room: "salah", dark: inheritedTheme.dark, calmPaper: inheritedTheme.calmPaper || onTrip) }

    private func snapshotKey(at instant: Date) -> PrayerHomeSnapshotKey {
        PrayerHomeSnapshotKey(minute: Int(instant.timeIntervalSince1970 / 60), revision: session.prayerRevision,
                              generation: session.storeGeneration, visit: roomVisit, retry: homeReadRetry,
                              active: isFrontRoom && scenePhase == .active)
    }

    private var retryHomeRead: some View {
        Button {
            guard homeReadFailed else { return }
            homeReadFailed = false
            homeReadRetry += 1
        } label: {
            Label("حاول مرة أخرى", systemImage: "arrow.clockwise")
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .font(MadarTypography.body())
        .foregroundStyle(theme.accent)
        .buttonStyle(.madarPlain)
        .accessibilityIdentifier("prayer-home-retry")
    }

    private func loadHomeSnapshot(at instant: Date, key: PrayerHomeSnapshotKey) async {
        guard key.active else { return }
        do {
            #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if !injectedHomeReadFailure,
               UUID(uuidString: environment["MADAR_UI_STORE_ID"] ?? "") != nil,
               environment["MADAR_UI_PRAYER_HOME_READ_FAILURE_ONCE"] == "1" {
                injectedHomeReadFailure = true
                throw CocoaError(.fileReadUnknown)
            }
            if UUID(uuidString: environment["MADAR_UI_STORE_ID"] ?? "") != nil,
               let milliseconds = environment["MADAR_UI_PRAYER_SNAPSHOT_HOLD_MS"].flatMap(Int.init),
               (1...5_000).contains(milliseconds) {
                try await Task.sleep(for: .milliseconds(milliseconds))
            }
            #endif
            if homeSnapshot == nil { homeReadFailed = false }
            let snapshot = try await session.prayerSnapshotOffMain(at: instant)
            try Task.checkCancellation()
            guard key == snapshotKey(at: session.prayerNow()), isFrontRoom, scenePhase == .active else { return }
            homeSnapshot = snapshot
            loadedHomeSnapshotKey = key
            homeReadFailed = false
            onTrip = snapshot.activeTrip != nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, key == snapshotKey(at: session.prayerNow()), isFrontRoom else { return }
            homeReadFailed = true
        }
    }

    @ViewBuilder private func heroColumn(_ snapshot: PrayerSnapshot, now instant: Date, current homeSnapshotIsCurrent: Bool) -> some View {
            let pills = travelPillText(snapshot) != nil || snapshot.today.cells.contains(where: { $0.isFriday })
            VStack(spacing: 10) {
                if let text = travelPillText(snapshot) {
                    PrayerTravelPill(text: text) { openTravel(snapshot) }
                        .disabled(!homeSnapshotIsCurrent)
                }
                if snapshot.today.cells.contains(where: { $0.isFriday }) {
                    fridayPill.disabled(!homeSnapshotIsCurrent)
                }
            }
            .padding(.top, pills ? 16 : 0)
            nextPrayer(snapshot, now: instant)
                .padding(.top, pills ? 18 : 26)
            verseDivider
                .padding(.top, 18)
            riwaq(snapshot, now: instant)
                .padding(.top, 18)
                .disabled(!homeSnapshotIsCurrent)
            if snapshot.hasTimes {
                Text(todaySummary(snapshot, now: instant))
                    .font(PrayerHomeType.body)
                    .foregroundStyle(theme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .accessibilityIdentifier("prayer-today-summary")
            }
    }

    private func sideColumn(_ snapshot: PrayerSnapshot, now instant: Date, current homeSnapshotIsCurrent: Bool) -> some View {
            VStack(spacing: 16) {
                ForEach(PrayerHomeLayout(session.values["salah.layout"]).visible, id: \.self) { block in
                    switch block {
                    case "pending":
                        if let pending = notice(snapshot, now: instant) { pending.disabled(!homeSnapshotIsCurrent) }
                        heartNotice(snapshot).disabled(!homeSnapshotIsCurrent)
                    case "hali": haliCard(snapshot).disabled(!homeSnapshotIsCurrent)
                    default: EmptyView()
                    }
                }
            }
    }

    var body: some View {
        TimelineView(PrayerTodayMinuteTimelineSchedule(isActive: isFrontRoom && scenePhase == .active)) { timeline in
            let instant = session.prayerNow(timeline.date)
            let requestKey = snapshotKey(at: instant)
            let homeSnapshotIsCurrent = loadedHomeSnapshotKey == requestKey
            ScrollView {
                VStack(spacing: 0) {
                    if let snapshot = homeSnapshot {
                        header(day: snapshot.today.day)
                            .padding(.top, 8)
                        if homeReadFailed {
                            VStack(spacing: 4) {
                                Text("تعذّر التحديث؛ معروض آخر سجل محفوظ")
                                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                                retryHomeRead
                            }.padding(.top, 8)
                        } else if !homeSnapshotIsCurrent {
                            Text("يُحدّث سجل الصلاة…")
                                .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                                .padding(.top, 8)
                                .accessibilityIdentifier("prayer-home-refreshing")
                        }
                        if isPadWide(sizeClass) && roomWidth >= 960 {
                            // iPad, wide: the arches stand on the right and the day's record sits beside them, instead of one long column.
                            HStack(alignment: .top, spacing: 36) {
                                VStack(spacing: 0) { heroColumn(snapshot, now: instant, current: homeSnapshotIsCurrent) }
                                    .frame(maxWidth: .infinity)
                                sideColumn(snapshot, now: instant, current: homeSnapshotIsCurrent)
                                    .frame(width: 380)
                                    .padding(.top, 26)
                            }
                        } else {
                            heroColumn(snapshot, now: instant, current: homeSnapshotIsCurrent)
                            sideColumn(snapshot, now: instant, current: homeSnapshotIsCurrent)
                                .padding(.top, 20)
                        }
                    } else {
                        header(day: nil)
                        PrayerPaperCard {
                            VStack(spacing: 12) {
                                Text(homeReadFailed ? "تعذّر تحميل صلوات اليوم." : "تُجهّز صلوات اليوم…")
                                    .font(MadarTypography.body())
                                    .accessibilityIdentifier(homeReadFailed ? "prayer-home-read-error" : "prayer-home-loading")
                                if homeReadFailed { retryHomeRead }
                            }.frame(maxWidth: .infinity)
                        }
                        .padding(.top, 24)
                        .transition(.opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: homeSnapshot != nil || homeReadFailed)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: !isPadWide(sizeClass) ? 620 : roomWidth >= 960 ? 1100 : 720)
                .frame(maxWidth: .infinity)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { roomWidth = $0 }
            .madarTopClipped()
            .background(theme.background)
            .foregroundStyle(theme.ink)
            .task(id: requestKey) { await loadHomeSnapshot(at: instant, key: requestKey) }
        }
        .environment(\.roomTheme, theme)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onChange(of: roomVisit, initial: true) {
            detectTravel()
            reconcilePrayerRequestRead()
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if !injectedRoute, env["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
               let raw = env["MADAR_UI_PRAYER_ROUTE"], let url = URL(string: raw) {
                injectedRoute = true
                session.open(url)
            }
            reconcilePrayerRequestRead()
            #endif
        }
        .onChange(of: session.prayerLogRequest) { _, prayer in
            // «صليت المغرب» from Capture: the state was not said, so its log sheet asks instead of guessing.
            prayerRequestReadTask?.cancel()
            prayerRequestReadTask = nil
            if prayer == nil { requestReadFailed = false }
            reconcilePrayerRequestRead()
        }
        .onChange(of: session.prayerRoute, initial: true) { _, route in
            guard let route else { return }
            session.prayerRoute = nil
            pendingPrayerRootRequestID = nil
            pendingPrayerRoute = route
            requestReadFailed = false
            openPrayerRoute(route)
        }
        .onChange(of: session.prayerRootRequestID) { _, requestID in
            guard let requestID else { return }
            pendingPrayerRoute = nil
            pendingPrayerRootRequestID = requestID
            closeForPrayerRootIfSafe()
        }
        .onChange(of: session.prayerRootDraftBlockers.isEmpty) { _, empty in
            if empty { closeForPrayerRootIfSafe(); dispatchPendingPrayerRoute() }
        }
        .onChange(of: session.prayerWriteInProgress) { _, isWriting in
            if !isWriting { closeForPrayerRootIfSafe(); dispatchPendingPrayerRoute() }
        }
        .alert("تعذّر فتح تسجيل الصلاة", isPresented: $requestReadFailed) {
            Button("أعد المحاولة") {
                retryPrayerRead()
            }
            Button("إلغاء", role: .cancel) { session.prayerLogRequest = nil; pendingPrayerRoute = nil }
        } message: { Text("تعذّرت قراءة بيانات الصلاة. يمكنك المحاولة مرة أخرى.") }
        .onChange(of: isFrontRoom, initial: true) { _, _ in reconcilePrayerRequestRead() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active, isFrontRoom { detectTravel() }
            reconcilePrayerRequestRead()
        }
        .onAppear { reconcilePrayerRequestRead() }
        .onDisappear {
            prayerRequestReadTask?.cancel()
            prayerRequestReadTask = nil
        }
        .sheet(item: $selectedSheet, onDismiss: {
            prayerSheetIsVisible = false
            dispatchPendingPrayerRoute()
        }) { route in
            let reportRootDraft: (UUID, Bool) -> Void = { id, active in
                session.setPrayerRootDraftBlocker(id, active: active)
            }
            Group {
            switch route {
            case .travelQuestion(let fix, let km):
                PrayerTravelQuestionSheet(session: session, fix: fix, homeKm: km, finished: { selectedSheet = nil }, rootDraftChanged: reportRootDraft)
            case .trip(let trip):
                PrayerTripSheet(session: session, trip: trip, fix: locator.fix, thresholdKm: travelThresholdKm, finished: { selectedSheet = nil })
            case .pair(let day, let pair, let cell, let timeZone):
                PrayerTravelPairSheet(session: session, day: day, pair: pair, alone: { selectedSheet = .log(cell, timeZone) }, finished: { selectedSheet = nil }, rootDraftChanged: reportRootDraft)
            case .qiyam:
                PrayerSnapshotSheet(revision: session.prayerRevision, isActive: isFrontRoom && scenePhase == .active,
                                    load: { try await sheetSnapshotOffMain() }, close: { selectedSheet = nil }) { snapshot in
                    PrayerNightLoggingSheet(session: session, snapshot: snapshot, finished: { selectedSheet = nil })
                }
            case .qiyamNight(let night):
                PrayerSnapshotSheet(revision: session.prayerRevision, isActive: isFrontRoom && scenePhase == .active,
                                    load: { try await sheetSnapshotOffMain() }, close: { selectedSheet = nil }) { snapshot in
                    PrayerNightLoggingSheet(session: session, snapshot: snapshot, initialNight: night, finished: { selectedSheet = nil })
                }
            case .heart(let cell):
                PrayerHeartAnswerSheet(session: session, cell: cell, finished: { selectedSheet = nil }, rootDraftChanged: reportRootDraft)
            case .streaks:
                PrayerSnapshotSheet(revision: session.prayerRevision, isActive: isFrontRoom && scenePhase == .active,
                                    load: { try await sheetSnapshotOffMain() }, close: { selectedSheet = nil }) { snapshot in
                    PrayerStreaksSheet(snapshot: snapshot, levels: PrayerStreakLevel.shown(congregation: session.bool("salah.showMosqueStreak")),
                                       digits: digits, timeZone: session.activePlace.timeZone, openHali: { selectedSheet = .statistics })
                }
            case .statistics:
                NavigationStack {
                    PrayerSnapshotSheet(revision: session.prayerRevision, isActive: isFrontRoom && scenePhase == .active,
                                        load: { try await sheetSnapshotOffMain() }, close: { selectedSheet = nil }) { snapshot in
                    PrayerStatisticsView(session: session, snapshot: snapshot) { choose($0, snapshot: snapshot) }
                    }
                }
            case .day(let day):
                NavigationStack {
                    PrayerSnapshotSheet(revision: session.prayerRevision, isActive: isFrontRoom && scenePhase == .active,
                                        load: { try await sheetSnapshotOffMain() }, close: { selectedSheet = nil }) { snapshot in
                    PrayerStatisticsView(session: session, snapshot: snapshot, initialDay: day) { choose($0, snapshot: snapshot) }
                    }
                }
            case .log(let cell, let timeZone):
                PrayerTodayLogSheet(cell: cell,
                    clock: (cell.prayerTime ?? cell.time).map { clock($0, timeZone: timeZone) } ?? "",
                    askHeart: session.bool("salah.askHeart"), isSaving: session.prayerWriteInProgress,
                    prefillStatus: nil, prefillHeart: nil,
                    save: { status, fridayKind, _, done in
                        session.recordPrayer(cell.reference, status: status, fridayKind: fridayKind, completion: done)
                    },
                    answerHeart: { heart, done in session.answerPrayerHeart(cell.reference, heart: heart, completion: done) },
                    rootDraftChanged: reportRootDraft)
            case .prefilledLog(let cell, let timeZone, let status, let heart):
                PrayerTodayLogSheet(cell: cell,
                    clock: (cell.prayerTime ?? cell.time).map { clock($0, timeZone: timeZone) } ?? "",
                    askHeart: session.bool("salah.askHeart"), isSaving: session.prayerWriteInProgress,
                    prefillStatus: status, prefillHeart: heart,
                    save: { status, fridayKind, _, done in
                        session.recordPrayer(cell.reference, status: status, fridayKind: fridayKind, completion: done)
                    },
                    answerHeart: { heart, done in session.answerPrayerHeart(cell.reference, heart: heart, completion: done) },
                    rootDraftChanged: reportRootDraft)
            }
            }
            .onAppear { prayerSheetIsVisible = true }
            .dynamicTypeSize(dynamicType)
            .environment(\.roomTheme, theme)
            .madarSheetErrorAlert(session) // AU-37: a failed write inside a prayer sheet is said there.
#if DEBUG
            .overlay(alignment: .topTrailing) {
                if ProcessInfo.processInfo.environment["MADAR_UI_PRAYER_ROOT_ROUTE_HARNESS"] == "1"
                    || ProcessInfo.processInfo.environment["MADAR_UI_PRAYER_ROUTE_DISMISSAL_RACE"] == "1"
                    || ProcessInfo.processInfo.environment["MADAR_UI_PRAYER_SNAPSHOT_REVISION_HARNESS"] == "1" {
                    VStack(alignment: .trailing, spacing: 8) {
                        Button("اختبار رابط جذر الصلاة") { session.open(URL(string: "madar://prayer")!) }
                            .accessibilityIdentifier("prayer-root-test-route")
                        Button("اختبر رابط الإحصاءات") { session.open(URL(string: "madar://salah/hali")!) }
                            .accessibilityIdentifier("prayer-deep-route-test")
                        if ProcessInfo.processInfo.environment["MADAR_UI_PRAYER_SNAPSHOT_REVISION_HARNESS"] == "1" {
                            Button("اختبر تحديث بيانات الصلاة") { session.advancePrayerRevisionForUITest() }
                                .accessibilityIdentifier("prayer-snapshot-test-revision")
                        }
                        if ProcessInfo.processInfo.environment["MADAR_UI_PRAYER_ROUTE_DISMISSAL_RACE"] == "1" {
                            Button("اختبر الرابط أثناء الإغلاق") {
                                debugPrayerRouteOpenedAfterDismissal = nil
                                selectedSheet = nil
                                session.open(URL(string: "madar://salah/hali")!)
                            }
                            .accessibilityIdentifier("prayer-test-route-during-dismissal")
                            if let openedAfterDismissal = debugPrayerRouteOpenedAfterDismissal {
                                Text(openedAfterDismissal ? "بعد إغلاق الورقة" : "قبل إغلاق الورقة")
                                    .accessibilityIdentifier("prayer-route-open-after-dismiss")
                            }
                        }
                    }
                }
            }
#endif
        }
    }

    // MARK: Header and next prayer

    private func sheetSnapshot() throws -> PrayerSnapshot {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if !injectedReadFailure, env["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
           env["MADAR_UI_PRAYER_READ_FAILURE_ONCE"] == "1" {
            injectedReadFailure = true
            throw CocoaError(.fileReadUnknown)
        }
        #endif
        return try session.prayerSnapshot(at: session.prayerNow())
    }

    private func sheetSnapshotOffMain() async throws -> PrayerSnapshot {
#if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
           let milliseconds = env["MADAR_UI_PRAYER_SHEET_READ_HOLD_MS"].flatMap(Int.init),
           (1...5_000).contains(milliseconds) {
            try await Task.sleep(for: .milliseconds(milliseconds))
        }
        if !injectedReadFailure, env["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
           env["MADAR_UI_PRAYER_READ_FAILURE_ONCE"] == "1" {
            injectedReadFailure = true
            throw CocoaError(.fileReadUnknown)
        }
#endif
        return try await session.prayerSnapshotOffMain(at: session.prayerNow())
    }

    private func reconcilePrayerRequestRead() {
        guard isFrontRoom, scenePhase == .active else {
            prayerRequestReadTask?.cancel()
            prayerRequestReadTask = nil
            if session.prayerLogRequest != nil { requestReadFailed = false }
            return
        }
        guard let prayer = session.prayerLogRequest else {
            prayerRequestReadTask?.cancel()
            prayerRequestReadTask = nil
            return
        }
        // Keep a failed request pending until the user explicitly chooses to retry.
        guard !requestReadFailed else { return }
        if let prayerRequestReadTask, !prayerRequestReadTask.isCancelled { return }
        openPrayerRequest(prayer)
    }

    private func openPrayerRequest(_ prayer: Prayer) {
        guard isFrontRoom, scenePhase == .active else { return }
        prayerRequestReadTask?.cancel()
        let requestID = UUID(), revision = session.prayerRevision
        prayerRequestReadID = requestID
        requestReadFailed = false
        prayerRequestReadTask = Task {
            do {
                let snapshot = try await sheetSnapshotOffMain()
                guard !Task.isCancelled, prayerRequestReadID == requestID,
                      session.prayerLogRequest == prayer else { return }
                guard isFrontRoom, scenePhase == .active else {
                    prayerRequestReadTask = nil
                    return
                }
                guard session.prayerRevision == revision else {
                    prayerRequestReadTask = nil
                    openPrayerRequest(prayer)
                    return
                }
                guard let cell = snapshot.today.cells.first(where: { $0.reference.prayer == prayer }) else {
                    prayerRequestReadTask = nil
                    requestReadFailed = true
                    return
                }
                requestReadFailed = false
                // Do not let the request-cleared observer cancel this task between resolving and presenting the sheet.
                prayerRequestReadTask = nil
                session.prayerLogRequest = nil
                choose(cell, snapshot: snapshot)
            } catch is CancellationError {
                guard !Task.isCancelled else { return }
                guard prayerRequestReadID == requestID, session.prayerLogRequest == prayer else { return }
                prayerRequestReadTask = nil
                if session.prayerRevision != revision, isFrontRoom, scenePhase == .active { openPrayerRequest(prayer) }
            } catch {
                guard !Task.isCancelled else { return }
                guard prayerRequestReadID == requestID, session.prayerLogRequest == prayer else { return }
                prayerRequestReadTask = nil
                guard isFrontRoom, scenePhase == .active else { return }
                requestReadFailed = true
            }
        }
    }

    private func retryPrayerRead() {
        let route = pendingPrayerRoute
        let prayer = session.prayerLogRequest
        requestReadFailed = false
        Task { @MainActor in
            // Let SwiftUI dismiss the alert before a repeated failure asks to present it again.
            await Task.yield()
            if let route { openPrayerRoute(route) }
            else if let prayer { openPrayerRequest(prayer) }
        }
    }

    private func closeForPrayerRootIfSafe() {
        guard pendingPrayerRootRequestID != nil, !session.prayerWriteInProgress, session.prayerRootDraftBlockers.isEmpty else { return }
        session.prayerLogRequest = nil
        pendingPrayerRoute = nil
        requestReadFailed = false
        selectedSheet = nil
        pendingPrayerRootRequestID = nil
    }

    private func dispatchPendingPrayerRoute() {
        guard pendingPrayerRootRequestID == nil,
              !session.prayerWriteInProgress,
              session.prayerRootDraftBlockers.isEmpty,
              let route = pendingPrayerRoute else { return }
        if selectedSheet != nil { selectedSheet = nil; return }
        guard !prayerSheetIsVisible else { return }
        openPrayerRoute(route)
    }

    private func openPrayerRoute(_ route: Route) {
        guard pendingPrayerRootRequestID == nil,
              !session.prayerWriteInProgress,
              session.prayerRootDraftBlockers.isEmpty else { return }
        if selectedSheet != nil { selectedSheet = nil; return }
        guard !prayerSheetIsVisible else { return }
#if DEBUG
        if ProcessInfo.processInfo.environment["MADAR_UI_PRAYER_ROUTE_DISMISSAL_RACE"] == "1" {
            debugPrayerRouteOpenedAfterDismissal = !prayerSheetIsVisible
        }
#endif
        pendingPrayerRoute = nil
        guard let routeName = route.path.first else { session.errorMessage = "هذا المسار لا يفتح شاشة صلاة معروفة."; return }
        switch routeName {
        case "day" where route.path.count == 2:
            let rawDay = route.path[1]
            guard let day = try? GregorianDay(rawDay) else { session.errorMessage = "تعذّر فتح يوم الصلاة المطلوب."; return }
            selectedSheet = .day(day)
        case "qiyam" where route.path.count == 2:
            let rawNight = route.path[1]
            _ = rawNight // The night-prayer page left the app (owner, 5 Nov 2026); an old link opens the prayer room itself.
        case "hali" where route.path.count == 1:
            selectedSheet = .statistics
        case "log" where route.path.count == 1:
            guard let prayer = route.parameters["prayer"].flatMap(Prayer.init(rawValue:)) else {
                session.errorMessage = "تعذّر فتح تسجيل الصلاة المطلوب."
                return
            }
            do {
                let current = try sheetSnapshot()
                let targetSnapshot: PrayerSnapshot
                if let rawDay = route.parameters["day"] {
                    let day = try GregorianDay(rawDay)
                    let zone = current.activeTrip?.place.timeZone ?? session.activePlace.timeZone
                    targetSnapshot = try session.prayerSnapshot(at: day.date(in: zone).addingTimeInterval(12 * 60 * 60))
                } else { targetSnapshot = current }
                guard let cell = targetSnapshot.today.cells.first(where: { $0.reference.prayer == prayer }) else {
                    session.errorMessage = "تعذّر فتح تسجيل الصلاة المطلوبة في هذا اليوم."
                    return
                }
                let zone = targetSnapshot.activeTrip?.place.timeZone ?? session.activePlace.timeZone
                let status = route.parameters["status"].flatMap(PrayerStoredStatus.init(rawValue:))
                let heart = route.parameters["heart"].flatMap(PrayerHeart.init(rawValue:))
                selectedSheet = status == nil && heart == nil
                    ? .log(cell, zone)
                    : .prefilledLog(cell, zone, status, heart)
                pendingPrayerRoute = nil
                requestReadFailed = false
            } catch {
                pendingPrayerRoute = route
                requestReadFailed = true
            }
        default:
            session.errorMessage = "هذا المسار لا يفتح شاشة صلاة معروفة."
        }
    }

    private func header(day prayerDay: GregorianDay?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("الصلاة").font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
                MadarDateLabel(session.dateLabels(prayerDay ?? GregorianDay.containing(session.prayerNow(), in: session.activePlace.timeZone), weekday: true), primaryFont: PrayerHomeType.body)
                    .foregroundStyle(theme.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("prayer-today-header")
            NavigationLink { PrayerCustomizeView(session: session) } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 17))
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(.madarPlain).accessibilityLabel("خصّص الصلاة").accessibilityIdentifier("prayer-customize")
        }
    }

    /// Friday greeting. The Quran room has no entry point yet, so the pill carries no link and no Al-Kahf pointer.
    /// §7.2 «سطر الكهف (يقود إلى القرآن)»: now that the Quran room is built, the pill opens the mushaf where Al-Kahf begins (page 293).
    private var fridayPill: some View {
        Button { session.open(URL(string: "madar://quran/page/293")!) } label: {
            HStack(spacing: 8) {
                Image(systemName: "diamond.fill").font(.system(size: 11))
                Text("جمعة مباركة · الكهف في قسم القرآن").font(PrayerHomeType.strong).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(theme.color("accentText"))
            .padding(.horizontal, 22).frame(minHeight: 44)
            .background(theme.color("goldSoft"), in: .capsule)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.madarPlain)
        .accessibilityLabel("جمعة مباركة، افتح سورة الكهف")
        .accessibilityIdentifier("prayer-friday-pill")
    }

    private func nextPrayer(_ snapshot: PrayerSnapshot, now: Date) -> some View {
        VStack(spacing: 6) {
            if let next = snapshot.next {
                // After Isha the next prayer is tomorrow's Fajr; say so above today's earlier Fajr arch.
                let tomorrow = !snapshot.today.cells.contains { $0.reference == next.reference }
                Text(tomorrow ? "الصلاة القادمة غدًا" : "الصلاة القادمة").font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
                Text(nextTitle(next.reference, snapshot: snapshot))
                    .font(PrayerHomeType.hero)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(nextLine(next, now: now))
                    .font(PrayerHomeType.lead)
                    .foregroundStyle(theme.secondaryInk)
                    .multilineTextAlignment(.center)
            } else if snapshot.hasTimes {
                Text("اكتمل يوم الصلاة").font(MadarTypography.cardTitle())
            } else {
                Text("لا مواقيت اليوم").font(MadarTypography.cardTitle())
                Text("سجّل الصلاة كالمعتاد.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("prayer-next")
    }

    private func nextLine(_ next: PrayerOccurrence, now: Date) -> String {
        let time = clock(next.time, timeZone: next.place.timeZone)
        guard next.time > now else { return time }
        return MadarInlineText.joined([time, PrayerCopy.after(seconds: next.time.timeIntervalSince(now), digits: digits)])
    }

    private var verseDivider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(theme.line).frame(height: 1)
            PrayerStar().fill(theme.accent).frame(width: 9, height: 9)
            Text("إِنَّ الصَّلَاةَ كَانَتْ عَلَى الْمُؤْمِنِينَ كِتَابًا مَوْقُوتًا")
                .font(.custom("Amiri-Regular", size: 15, relativeTo: .subheadline))
                .foregroundStyle(theme.secondaryInk)
                .lineLimit(1).minimumScaleFactor(0.74)
                .layoutPriority(1)
            PrayerStar().fill(theme.accent).frame(width: 9, height: 9)
            Rectangle().fill(theme.line).frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("إن الصلاة كانت على المؤمنين كتابًا موقوتًا")
    }

    // MARK: Riwaq

    private func riwaq(_ snapshot: PrayerSnapshot, now: Date) -> some View {
        VStack(spacing: 8) {
            if dynamicType.isAccessibilitySize {
                PrayerPaperCard(tinted: true) {
                    VStack(spacing: 8) {
                        ForEach(snapshot.today.cells, id: \.reference) { cell in prayerEntry(cell, snapshot: snapshot, now: now) }
                    }
                }
            } else {
                PrayerRiwaq(pool: session.bool("salah.pool")) {
                    ForEach(snapshot.today.cells, id: \.reference) { cell in prayerEntry(cell, snapshot: snapshot, now: now) }
                }
            }
            if !snapshot.hasTimes {
                Text("اضغط قوس الصلاة لتسجيلها يدويًا.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).padding(12)
                    .accessibilityIdentifier("prayer-no-times")
            }
        }
    }

    @ViewBuilder private func prayerEntry(_ cell: PrayerCell, snapshot: PrayerSnapshot, now: Date) -> some View {
        let canEditStatus = [.pending, .jamaah, .alone, .qada].contains(cell.status)
            || (cell.time == nil && cell.status == .future)
        let canEdit = cell.canLog && canEditStatus
        let isNext = snapshot.next?.reference == cell.reference
        let arch = PrayerTodayArch(cell: cell, isNext: isNext,
            title: cell.isFriday && cell.reference.prayer == .dhuhr ? "الجمعة" : title(cell.reference.prayer),
            tall: cell.isFriday && cell.reference.prayer == .dhuhr && session.bool("salah.fridayTallArch"),
            timeLabel: (cell.prayerTime ?? cell.time).map { clock($0, timeZone: snapshot.activeTrip?.place.timeZone ?? session.activePlace.timeZone) } ?? "—",
            note: cell.time == nil && cell.status == .future ? "" : pairNote(cell, snapshot: snapshot),
            countdown: isNext && cell.status == .future ? cell.prayerTime.flatMap { PrayerCopy.countdown(until: $0, now: now, digits: digits) } : nil)
        if canEdit {
            Button { choose(cell, snapshot: snapshot) } label: { arch }
                .buttonStyle(.madarPlain)
                .accessibilityElement(children: dynamicType.isAccessibilitySize ? .combine : .ignore)
                .accessibilityLabel(arch.accessibilityText)
                .accessibilityHint("سجّل الصلاة أو غيّر تسجيلها")
                .accessibilityIdentifier("prayer-arch-\(cell.reference.prayer.rawValue)")
        } else {
            arch.accessibilityElement(children: dynamicType.isAccessibilitySize ? .combine : .ignore)
                .accessibilityLabel(arch.accessibilityText)
                .accessibilityIdentifier("prayer-arch-\(cell.reference.prayer.rawValue)")
        }
    }

    /// «سجّلت ٣ من ٥ اليوم، بقيت صلاتان». No «·» (it sat beside the count's digit, RU1), and no «٠ من ٥»
    /// before a tail that already says the same thing.
    private func todaySummary(_ snapshot: PrayerSnapshot, now: Date) -> String {
        let cells = snapshot.today.cells.filter { $0.time != nil }
        let recorded = cells.filter { [.jamaah, .alone, .qada].contains($0.status) }.count
        let remaining = cells.count - recorded
        let afterLastAdhan = cells.compactMap(\.prayerTime).max().map { now >= $0 } ?? false
        let tail = afterLastAdhan && remaining > 0 ? PrayerCopy.pending(remaining, digits: digits) : PrayerCopy.remaining(remaining, digits: digits)
        if cells.isEmpty { return "" }
        if remaining == 0 { return "سجّلت صلوات اليوم كلها" }
        if recorded == 0 { return tail }
        return "سجّلت \(digits.string(recorded)) من \(digits.string(cells.count)) اليوم، " + tail
    }

    // MARK: Notices

    /// A quiet reminder to record an already-performed prayer. Leaving it alone never creates a record.
    private func notice(_ snapshot: PrayerSnapshot, now: Date) -> AnyView? {
        let pending = Set(snapshot.pending)
        let open = currentPrayer(snapshot, now: now)
        let closed = snapshot.history.flatMap(\.cells)
            .filter { pending.contains($0.reference) && $0.canLog && $0.time != nil && $0.reference != open }
        let gap = snapshot.unconfirmed + closed.map(\.reference).filter { !snapshot.unconfirmed.contains($0) }
        guard !gap.isEmpty else { return nil }
        if gap.count == 1, let first = closed.first {
            return AnyView(PrayerNoticeRow(
                title: "مضى وقت \(self.title(first.reference.prayer))\(dayWord(first.reference.day, today: snapshot.today.day)) ولم تُسجِّلها.",
                detail: "إذا صلّيتها، سجّلها. ما لم تصلّه يبقى بلا سجل.",
                action: "سجِّلها", identifier: "prayer-pending-review") { choose(first, snapshot: snapshot) })
        }
        let hasHistoricalGap = gap.contains { $0.day < snapshot.today.day }
        // The line under the arches already counts every unrecorded prayer, the open one included («٥ صلوات»); this note
        // speaks of those whose time has passed, so it names them instead of showing a second, smaller count («٤ صلوات»).
        let passedToday = gap.filter { $0.day == snapshot.today.day }.map { self.title($0.prayer) }
        let named = passedToday.count == gap.count && passedToday.count <= 4
            ? "مضى وقت " + (passedToday.count < 2 ? passedToday.joined() : passedToday.dropLast().joined(separator: " و") + " و" + passedToday.last!) + " ولم تُسجَّل"
            : PrayerCopy.pending(gap.count, digits: digits)
        return AnyView(PrayerNoticeRow(
            // Unrecorded prayers from earlier days are counted as such; «يبدأ سجلّك من اليوم» contradicted the history beside it.
            title: hasHistoricalGap ? PrayerCopy.unconfirmed(gap.filter { $0.day < snapshot.today.day }.count, digits: digits) : named,
            detail: "سجّل الصلاة بعد أدائها. ما لم تصلّه يبقى بلا سجل.",
            action: nil, identifier: "prayer-unconfirmed-note", perform: nil))
    }

    /// The prayer whose window is still open (its time has come and the next prayer has not).
    private func currentPrayer(_ snapshot: PrayerSnapshot, now: Date) -> PrayerReference? {
        snapshot.history.flatMap(\.cells).filter { ($0.prayerTime ?? .distantFuture) <= now }.max { ($0.prayerTime ?? .distantPast) < ($1.prayerTime ?? .distantPast) }?.reference
    }

    private func dayWord(_ day: GregorianDay, today: GregorianDay) -> String {
        if day == today { return "" }
        if day.adding(days: 1) == today { return " أمس" }
        return " يوم " + dateLabel(day)
    }

    @ViewBuilder private func heartNotice(_ snapshot: PrayerSnapshot) -> some View {
        // RP6: optional; the owner chose an on-by-default heart question on 26 October.
        if session.bool("salah.askHeart"), let cell = snapshot.history.flatMap(\.cells).first(where: { snapshot.pendingHeart.contains($0.reference) }) {
            Button { selectedSheet = .heart(cell) } label: {
                HStack(spacing: 12) {
                    PrayerStar().fill(theme.accent).frame(width: 14, height: 14)
                    Text("بقي سؤال القلب عن \(title(cell.reference.prayer)).")
                        .font(PrayerHomeType.strong)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("أجِب").font(PrayerHomeType.strong).foregroundStyle(theme.accent)
                }
                .padding(.horizontal, 18).frame(minHeight: 58)
                .background(theme.color("surface"), in: .rect(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line, lineWidth: 1) }
            }
            .buttonStyle(.madarPlain)
            .accessibilityIdentifier("prayer-heart-review")
        }
    }

    // MARK: Hali and qiyam

    /// «سلاسلك»: the three nested streaks as nested arches (owner decision, 13 October 2026). Tapping opens the details.
    private func haliCard(_ snapshot: PrayerSnapshot) -> some View {
        let stats = snapshot.statistics
        let levels = PrayerStreakLevel.shown(congregation: session.bool("salah.showMosqueStreak"))
        let summary = levels.map { "\($0.title) \(PrayerCopy.days($0.count(stats), digits: digits))" }.joined(separator: "، ")
        return Button { selectedSheet = .streaks } label: {
            PrayerPaperCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("سلاسلك").font(PrayerHomeType.cardHead)
                        Spacer()
                        Image(systemName: "chevron.forward").font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.secondaryInk).accessibilityHidden(true)
                    }
                    PrayerStreakArches(levels: levels, stats: stats, digits: digits)
                }
            }
        }
        .buttonStyle(.madarPlain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("سلاسلك: " + summary)
        .accessibilityHint("افتح تفاصيل السلاسل")
        .accessibilityIdentifier("prayer-streaks")
    }

    // MARK: Formatting

    private var digits: MadarNumberFormatter { MadarNumberFormatter(style: session.string("core.numerals") == "western" ? .western : .hindi) }
    private var numeralLocale: Locale { Locale(identifier: session.string("core.numerals") == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab") }

    private func percent(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = numeralLocale
        formatter.numberStyle = .percent
        return formatter.string(from: NSNumber(value: Double(value) / 100)) ?? digits.string(value)
    }

    /// «الثلاثاء ٢٥ ربيع الآخر» or «الثلاثاء ٦ أكتوبر», following `core.firstCalendar`; never ISO digits.
    private func dateLabel(_ day: GregorianDay) -> String {
        session.dateLabels(day).combined
    }

    private func choose(_ cell: PrayerCell, snapshot: PrayerSnapshot? = nil) {
        let activeSnapshot = snapshot ?? homeSnapshot
        let timeZone = activeSnapshot?.activeTrip?.place.timeZone ?? session.activePlace.timeZone
        if let pair = travelPair(for: cell, hasActiveTrip: activeSnapshot?.activeTrip != nil), [.pending, .future].contains(cell.status) {
            selectedSheet = .pair(cell.reference.day, pair, cell, timeZone)
        } else {
            selectedSheet = .log(cell, timeZone)
        }
    }

    // MARK: Travel (RP4, RP7)

    private var travelDetects: Bool { session.string("core.travelMode") != "manual" && session.bool("salah.travelShortenCombine") }
    private var travelThresholdKm: Double {
        if case .number(let km) = session.values["core.travelKm"] { km } else { 80 }
    }
    private func detectTravel() { if travelDetects { locator.refresh() } }
    private func awayFix() -> TravelFix? {
        guard let fix = locator.fix,
              TravelRule.isAway(home: session.activePlace, current: fix.place, thresholdKm: travelThresholdKm),
              !PrayerTravelCopy.declined(near: fix.place, thresholdKm: travelThresholdKm) else { return nil }
        return fix
    }
    /// «مسافر · جدة · قصرٌ وجمع» on a trip; «خارج مدينتك» until the one question is answered; nothing otherwise.
    private func travelPillText(_ snapshot: PrayerSnapshot) -> String? {
        if let trip = snapshot.activeTrip {
            if let fix = locator.fix, !TravelRule.isAway(home: session.activePlace, current: fix.place, thresholdKm: travelThresholdKm) { return "عدتَ إلى مدينتك؟" }
            // OR-09: in a new city of the same journey, the pill asks before anything changes.
            if let fix = locator.fix, fix.city != trip.city, TravelRule.distanceKm(from: trip.place, to: fix.place) > travelThresholdKm { return "وصلت إلى " + fix.city + "؟" }
        return MadarInlineText.joined(["مسافر", trip.city] + (session.bool("salah.travelShortenCombine") ? ["قصرٌ وجمع"] : []))
        }
        return travelDetects && awayFix() != nil ? "خارج مدينتك" : nil
    }
    private func openTravel(_ snapshot: PrayerSnapshot) {
        if let trip = snapshot.activeTrip { selectedSheet = .trip(trip) }
        else if let fix = awayFix() { selectedSheet = .travelQuestion(fix, max(0, TravelRule.distanceKm(from: session.activePlace, to: fix.place) - TravelRule.homeRadiusKm)) }
    }
    private func travelPair(for cell: PrayerCell, hasActiveTrip: Bool) -> PrayerPair? {
        guard session.bool("salah.travelShortenCombine"), hasActiveTrip else { return nil }
        switch cell.reference.prayer { case .dhuhr, .asr: return .dhuhrAsr; case .maghrib, .isha: return .maghribIsha; default: return nil }
    }
    /// Under the arch of a prayer that can be combined: «قصر · جمع» on the first Dhuhr, «مع الظهر» on Asr, and so on.
    private func pairNote(_ cell: PrayerCell, snapshot: PrayerSnapshot) -> String? {
        guard snapshot.activeTrip != nil, session.bool("salah.travelShortenCombine"), [.pending, .future].contains(cell.status) else { return nil }
        switch cell.reference.prayer {
        case .dhuhr: return "قصر · جمع"
        case .asr: return "مع الظهر"
        case .isha: return "مع المغرب"
        default: return nil
        }
    }

    private func title(_ prayer: Prayer) -> String {
        switch prayer { case .fajr: "الفجر"; case .dhuhr: "الظهر"; case .asr: "العصر"; case .maghrib: "المغرب"; case .isha: "العشاء" }
    }

    private func nextTitle(_ reference: PrayerReference, snapshot: PrayerSnapshot) -> String {
        let friday = snapshot.today.cells.first { $0.reference == reference }?.isFriday ?? false
        return friday && reference.prayer == .dhuhr ? "الجمعة" : title(reference.prayer)
    }

    private func clock(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = numeralLocale
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Type roles measured from the canonical S1 (iOS points at the Large size)

enum PrayerHomeType {
    static let hero = Font.custom("thmanyahserifdisplay-Bold", size: 46, relativeTo: .largeTitle)
    static let number = Font.custom("thmanyahserifdisplay-Bold", size: 36, relativeTo: .title)
    static let cardHead = Font.custom("thmanyahserifdisplay-Bold", size: 20, relativeTo: .title3)
    static let archName = Font.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)
    static let lead = Font.custom("thmanyahsans-Regular", size: 16, relativeTo: .callout)
    static let strong = Font.custom("thmanyahsans-Bold", size: 16, relativeTo: .headline)
    static let body = Font.custom("thmanyahsans-Regular", size: 15, relativeTo: .subheadline)
    static let small = Font.custom("thmanyahsans-Regular", size: 13, relativeTo: .footnote)
    static let smallBold = Font.custom("thmanyahsans-Bold", size: 13, relativeTo: .footnote)
}

// MARK: - Arabic plural copy (RU3: String Catalog variants, digits follow core.numerals)

enum PrayerCopy {
    // Argument 1 chooses the Arabic plural; argument 2 is the count in core.numerals digits.
    static func hours(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.hours", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func minutes(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.minutes", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func days(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.days", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func remaining(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.remaining", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func pending(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.pending", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func unconfirmed(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.unconfirmed", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func rakaat(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.rakaat", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    /// «بعد ساعة و١٤ دقيقة».
    static func after(seconds: TimeInterval, digits: MadarNumberFormatter) -> String {
        let total = max(0, Int(seconds / 60))
        let hours = total / 60, minutes = total % 60
        if total == 0 { return "الآن" }
        if hours == 0 { return "بعد " + self.minutes(minutes, digits: digits) }
        return "بعد " + self.hours(hours, digits: digits) + (minutes > 0 ? " و" + self.minutes(minutes, digits: digits) : "")
    }
    /// RL7: two fields, «بعد ١:١٤».
    static func countdown(until date: Date, now: Date, digits: MadarNumberFormatter) -> String? {
        guard date > now else { return nil }
        let total = Int(date.timeIntervalSince(now) / 60)
        let minutes = total % 60
        return "بعد " + digits.string(total / 60) + ":" + (minutes < 10 ? digits.string(0) : "") + digits.string(minutes)
    }
}

// MARK: - Shared S1 pieces

/// The arcade card: arches stand on a water line; the pool reflects them (§5 HorseshoeArch).
private enum PrayerTodaySheet: Identifiable {
    case travelQuestion(TravelFix, Double)
    case trip(PrayerTrip)
    case pair(GregorianDay, PrayerPair, PrayerCell, TimeZone)
    case log(PrayerCell, TimeZone)
    case prefilledLog(PrayerCell, TimeZone, PrayerStoredStatus?, PrayerHeart?)
    case statistics
    case day(GregorianDay)
    case streaks
    case heart(PrayerCell)
    case qiyam
    case qiyamNight(GregorianDay)
    var id: String {
        switch self {
        case .travelQuestion: "travel-question"
        case .trip(let trip): "trip-\(trip.id.uuidString)"
        case .pair(let day, let pair, _, _): "pair-\(day)-\(pair.rawValue)"
        case .qiyam: "qiyam"
        case .qiyamNight(let night): "qiyam-" + night.description
        case .statistics: "statistics"
        case .day(let day): "day-" + day.description
        case .streaks: "streaks"
        case .heart(let cell): "heart-\(cell.reference.naturalKey)"
        case .log(let cell, _): "log-\(cell.reference.naturalKey)"
        case .prefilledLog(let cell, _, _, _): "prefilled-log-\(cell.reference.naturalKey)"
        }
    }
}

/// S2 · the light log sheet, matched to `screens/salah/02-S2-Log.jpg`.
/// One tap records a performed prayer; qada is available only after the prayer window ends.
/// The heart question is inline and only when
/// `salah.askHeart` is on (RP6); Friday noon records its kind explicitly (RP5).
/// Not built: «امسح التسجيل» (screenshot only; the spec defines no clear command, see DECISIONS).
private struct PrayerTodayLogSheet: View {
    let cell: PrayerCell
    let clock: String
    let askHeart: Bool
    let isSaving: Bool
    let routePrefilled: Bool
    let save: (PrayerStoredStatus, FridayPrayerKind?, Bool, @escaping (Bool) -> Void) -> Void
    let answerHeart: (PrayerHeart?, @escaping (Bool) -> Void) -> Void
    let rootDraftChanged: (UUID, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var selected: PrayerStoredStatus?
    @State private var recorded: Bool
    @State private var heart: PrayerHeart?
    @State private var fridayKind: FridayPrayerKind?
    @State private var committedStatus: PrayerStoredStatus?
    @State private var committedRecorded = false
    @State private var committedHeart: PrayerHeart?
    @State private var committedFridayKind: FridayPrayerKind?
    @State private var rootBlockerID = UUID()
    @State private var contentHeight: CGFloat = 430

    init(cell: PrayerCell, clock: String, askHeart: Bool, isSaving: Bool,
         prefillStatus: PrayerStoredStatus?, prefillHeart: PrayerHeart?,
         save: @escaping (PrayerStoredStatus, FridayPrayerKind?, Bool, @escaping (Bool) -> Void) -> Void,
         answerHeart: @escaping (PrayerHeart?, @escaping (Bool) -> Void) -> Void,
         rootDraftChanged: @escaping (UUID, Bool) -> Void) {
        self.cell = cell; self.clock = clock; self.askHeart = askHeart; self.isSaving = isSaving
        self.routePrefilled = prefillStatus != nil || prefillHeart != nil
        self.save = save; self.answerHeart = answerHeart; self.rootDraftChanged = rootDraftChanged
        let initial: PrayerStoredStatus? = switch cell.status { case .jamaah: .jamaah; case .alone: .alone; case .qada: .qada; default: nil }
        _selected = State(initialValue: prefillStatus ?? initial)
        _recorded = State(initialValue: prefillStatus == nil && initial != nil)
        _heart = State(initialValue: prefillHeart ?? cell.heart)
        _fridayKind = State(initialValue: cell.fridayKind)
        _committedStatus = State(initialValue: initial)
        _committedRecorded = State(initialValue: initial != nil)
        _committedHeart = State(initialValue: cell.heart)
        _committedFridayKind = State(initialValue: cell.fridayKind)
    }

    private var options: [PrayerStoredStatus] {
        [.jamaah, .alone] + (cell.canMakeUp || cell.status == .qada || selected == .qada ? [.qada] : [])
    }
    /// Friday noon: everything but «وحدي» (always the noon prayer) waits for the kind.
    private func needsKind(_ option: PrayerStoredStatus) -> Bool { cell.isFriday && option != .alone && fridayKind == nil }
    private var showsHeart: Bool { askHeart && recorded && [.jamaah, .alone, .qada].contains(selected ?? .jamaah) }
    private var hasUnsavedInput: Bool {
        selected != committedStatus || recorded != committedRecorded || heart != committedHeart || fridayKind != committedFridayKind
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if cell.isFriday { fridayKindRow.padding(.top, 16) }
            // AU-38: the dimmed options say why.
            if cell.isFriday && fridayKind == nil { Text("اختر «جمعة» أو «ظهر» لتسجّلها في جماعة أو قضاءً.").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).padding(.top, 8).accessibilityIdentifier("prayer-friday-kind-hint") }
            optionRow.padding(.top, 20)
            if routePrefilled, !recorded, let selected {
                Button("احفظ التسجيل") { record(selected, kind: cell.isFriday ? (selected == .alone ? .dhuhr : fridayKind) : nil) }
                    .buttonStyle(.madarPlain).frame(maxWidth: .infinity, minHeight: 48)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .padding(.top, 10).accessibilityIdentifier("prayer-log-prefill-save")
            }
            if showsHeart { heartSection.padding(.top, 22) }
        }
        .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 + 20 }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.background)
        .foregroundStyle(theme.ink)
        .presentationDetents([.height(min(max(contentHeight, 160), 640)), .large])
        .presentationBackground(theme.background)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .onChange(of: hasUnsavedInput, initial: true) { _, dirty in rootDraftChanged(rootBlockerID, dirty) }
        .onDisappear { rootDraftChanged(rootBlockerID, false) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            PrayerSheetArch().frame(width: 34, height: 52).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("صلّيتَ \(prayerTitle(cell.reference.prayer))؟")
                    .font(Font.custom("thmanyahserifdisplay-Bold", size: 28, relativeTo: .title))
                    .accessibilityAddTraits(.isHeader)
                if !clock.isEmpty { Text(clock).font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("prayer-log-clock") }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Friday kind (RP5)

    private var fridayKindRow: some View {
        HStack(spacing: 10) {
            Text("ظهر الجمعة:").font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
            ForEach([FridayPrayerKind.jumuah, .dhuhr], id: \.self) { kind in
                let on = fridayKind == kind
                Button { fridayKind = kind } label: {
                    Text(kind == .jumuah ? "صلاة الجمعة" : "الظهر").font(on ? PrayerHomeType.smallBold : PrayerHomeType.small)
                        .foregroundStyle(on ? theme.color("accentText") : theme.ink)
                        .padding(.horizontal, 16).frame(minHeight: 40)
                        .background(on ? theme.color("goldSoft") : .clear, in: .capsule)
                        .overlay { Capsule().stroke(on ? theme.accent : theme.ink.opacity(0.14), lineWidth: on ? 1.5 : 1) }
                        .frame(minHeight: 44).contentShape(.rect)
                }
                .buttonStyle(.madarPlain).accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("prayer-friday-kind-\(kind.rawValue)")
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Prayer status

    private var optionRow: some View {
        HStack(spacing: 8) { ForEach(options, id: \.self) { optionPill($0) } }
    }

    private func optionPill(_ option: PrayerStoredStatus) -> some View {
        let on = selected == option
        let tint = theme.accent
        let (title, detail): (String, String) = switch option {
        case .jamaah: ("في جماعة", "مع الناس")
        case .alone: ("وحدي", "في وقتها")
        case .qada: ("قضاءً", "صلّيتها بعد وقتها")
        case .missed, .unrecordedHistory, .excused: ("", "")
        }
        return Button {
            guard !isSaving else { return }
            if option == .alone, cell.isFriday { fridayKind = .dhuhr }
            record(option, kind: cell.isFriday ? (option == .alone ? .dhuhr : fridayKind) : nil)
        } label: {
            VStack(spacing: 4) {
                Text(title).font(PrayerHomeType.strong)
                    .foregroundStyle(on ? theme.color("accentText") : theme.ink)
                Text(detail).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
            }
            .lineLimit(1).minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(on ? tint.opacity(0.12) : .clear, in: .rect(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(on ? tint : theme.ink.opacity(0.13), lineWidth: on ? 1.5 : 1) }
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.madarPlain)
        .opacity(needsKind(option) ? 0.45 : 1)
        .disabled(needsKind(option) || isSaving)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("prayer-status-\(option.rawValue)")
    }

    /// Records the choice; the sheet closes unless the heart question follows.
    private func record(_ option: PrayerStoredStatus, kind: FridayPrayerKind?) {
        save(option, kind, false) { ok in
            guard ok else { return }
            selected = option; recorded = true
            committedStatus = option; committedRecorded = true
            committedFridayKind = cell.isFriday ? (option == .alone ? .dhuhr : kind) : nil
            fridayKind = committedFridayKind
            if !askHeart { dismiss() }
        }
    }

    // MARK: Heart (RP6: only when `salah.askHeart` is on)

    private var heartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("كيف كان قلبك فيها؟").font(PrayerHomeType.strong)
                Spacer(minLength: 8)
                Button { if heart != nil { answerHeart(nil) { ok in if ok { dismiss() } } } else { dismiss() } } label: {
                    Text("أمرُّ").font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk).frame(minHeight: 44).contentShape(.rect)
                }
                .buttonStyle(.madarPlain).accessibilityIdentifier("prayer-heart-skip")
            }
            HStack(spacing: 8) {
                ForEach(PrayerHeart.allCases, id: \.self) { value in
                    let on = heart == value
                    Button {
                        guard !isSaving else { return }
                        answerHeart(value) { ok in if ok { heart = value; dismiss() } }
                    } label: {
                        VStack(spacing: 3) {
                            Text(heartTitle(value)).font(PrayerHomeType.strong)
                                .foregroundStyle(on ? theme.color("accentText") : theme.ink)
                            Text(heartSentence(value)).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                        }
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(on ? theme.accent.opacity(0.12) : .clear, in: .rect(cornerRadius: 20))
                        .overlay { RoundedRectangle(cornerRadius: 20).stroke(on ? theme.accent : theme.ink.opacity(0.13), lineWidth: on ? 1.5 : 1) }
                        .contentShape(.rect(cornerRadius: 20))
                    }
                    .buttonStyle(.madarPlain)
                    .disabled(isSaving)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("prayer-heart-\(value.rawValue)")
                }
            }
        }
    }
}

func heartTitle(_ heart: PrayerHeart) -> String {
    switch heart { case .distracted: "شارد"; case .present: "حاضر"; case .khashi: "خاشع" }
}
func heartSentence(_ heart: PrayerHeart) -> String {
    switch heart { case .distracted: "كنت في وادٍ آخر"; case .present: "عرفت ما أقول"; case .khashi: "وجدت لها أثرًا" }
}


private struct PrayerNightLoggingSheet: View {
    let session: AppSession
    let snapshot: PrayerSnapshot
    let finished: () -> Void
    @State private var selectedNight: GregorianDay
    @State private var rakaat: Int
    @State private var witr: Bool
    @State private var confirmRestore = false
    @State private var contentHeight: CGFloat = 520
    @State private var wird: (line: String, logged: Bool)?
    @State private var rootBlockerID = UUID()
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    init(session: AppSession, snapshot: PrayerSnapshot, initialNight: GregorianDay? = nil, finished: @escaping () -> Void) {
        self.session = session; self.snapshot = snapshot; self.finished = finished
        let selectedNight = initialNight ?? snapshot.nightDefault
        _selectedNight = State(initialValue: selectedNight)
        let previous = snapshot.nights.first { $0.night == selectedNight }
        _rakaat = State(initialValue: previous?.rakaat ?? 0); _witr = State(initialValue: previous?.witr ?? false)
    }
    private var formatter: MadarNumberFormatter { .init(style: session.string("core.numerals") == "western" ? .western : .hindi) }
    private var eligibleNights: [GregorianDay] {
        let recent = (0..<7).map { snapshot.nightDefault.adding(days: -$0) }
        return recent.contains(selectedNight) ? recent : [selectedNight] + recent
    }
    private var footprint: [GregorianDay] { (0..<30).reversed().map { snapshot.nightDefault.adding(days: -$0) } }
    private var restoreNeeded: Bool { (try? session.qiyamRequiresRestore(selectedNight)) ?? true }
    private var logged: Bool { hasRecord(selectedNight) }
    /// What the reader typed differs from what this night already holds.
    private var hasUnsavedInput: Bool {
        let stored = snapshot.nights.first { $0.night == selectedNight }
        return rakaat != (stored?.rakaat ?? 0) || witr != (stored?.witr ?? false)
    }
    /// The wird link keeps what was typed: it is saved first, then the Quran room opens.
    private func openWird() {
        let go = { finished(); session.open(URL(string: "madar://quran/session/qiyam")!) }
        guard hasUnsavedInput else { go(); return }
        session.recordQiyamNight(selectedNight, rakaat: rakaat, witr: witr, restoreDeleted: false) { succeeded in if succeeded { go() } }
    }
    private func footprintColor(_ night: GregorianDay) -> Color {
        guard let row = snapshot.nights.first(where: { $0.night == night }), row.rakaat > 0 || row.witr else { return theme.ink.opacity(0.1) }
        return row.rakaat >= 8 ? theme.accent : theme.color("goldMid")
    }

    /// S6 · Quran owns its wird; this link opens its built current-night preview. Qiyam remains a footprint.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("قيام الليل").font(.custom("thmanyahserifdisplay-Bold", size: 30, relativeTo: .title)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(logged ? "سُجّلت ليلتك" : "لم تُسجَّل ليلتك").font(PrayerHomeType.smallBold).foregroundStyle(theme.color("accentText"))
            }
            Text("ركعتان تداوم عليهما خيرٌ من إحدى عشرة تنقطع. سجِّل ما صلّيتَ.").font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk).padding(.top, 10)
            if eligibleNights.count > 1 {
                Picker("الليلة", selection: $selectedNight) {
                    ForEach(eligibleNights, id: \.self) { Text(dateTitle($0)).tag($0) }
                }
                .pickerStyle(.menu).tint(theme.secondaryInk).accessibilityIdentifier("prayer-qiyam-night").padding(.top, 2)
            }
            divider.padding(.top, 14)
            HStack(spacing: 14) {
                Text("الركعات").font(PrayerHomeType.strong)
                Spacer(minLength: 8)
                stepButton("minus", id: "prayer-qiyam-minus", disabled: rakaat == 0, label: rakaat == 1 ? "أنقص ركعة" : "أنقص ركعتين") { rakaat = max(0, rakaat - 2) }
                Text(formatter.string(rakaat)).font(.custom("thmanyahserifdisplay-Bold", size: 26, relativeTo: .title2)).monospacedDigit()
                    .frame(minWidth: 44).accessibilityIdentifier("prayer-qiyam-count")
                stepButton("plus", id: "prayer-qiyam-plus", disabled: rakaat >= 99, label: rakaat == 98 ? "زد ركعة" : "زد ركعتين") { rakaat = min(99, rakaat + 2) }
            }
            .frame(minHeight: 76)
            divider
            // S6: «أوترتُ» and the wird link side by side; the line beneath says what tonight's reading gives the Quran room.
            let showWird = selectedNight == snapshot.nightDefault && !restoreNeeded && wird != nil
            HStack(spacing: 10) {
                Toggle("أوترتُ", isOn: $witr).toggleStyle(PrayerPillToggleStyle()).accessibilityIdentifier("prayer-qiyam-witr")
                if showWird, wird?.logged == false {
                    Button { openWird() } label: {
                        HStack(spacing: 8) {
                            Text("ورد القيام من محفوظك").font(PrayerHomeType.strong).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.secondaryInk)
                        }
                        .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 50)
                        .glassEffect(.regular.interactive(), in: .capsule).contentShape(.capsule)
                    }
                    .buttonStyle(.madarPlain).accessibilityIdentifier("prayer-quran-qiyam")
                }
            }.padding(.top, 14)
            if showWird, let line = wird?.line {
                Text(line).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8).accessibilityIdentifier("prayer-qiyam-wird-line")
            }
            footprintStrip.padding(.top, 18)
            Text("آخر ثلاثين ليلة · ليست سلسلة تنكسر، أثرٌ يُرى").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).padding(.top, 10)
            if restoreNeeded {
                Text("تراجعتَ عن تسجيل هذه الليلة؛ يمكنك تسجيلها من جديد.").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).padding(.top, 14)
                primary("أعد تسجيل الليلة", id: "prayer-qiyam-restore") { confirmRestore = true }.padding(.top, 8)
            } else {
                primary("احفظ قيام الليلة", id: "prayer-qiyam-save") { save(restoring: false) }.padding(.top, 16)
            }
        }
        .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 + 20 }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.background).foregroundStyle(theme.ink)
        .presentationDetents([.height(min(max(contentHeight, 300), 760)), .large])
        .presentationBackground(theme.background)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .onChange(of: hasUnsavedInput, initial: true) { _, dirty in session.setPrayerRootDraftBlocker(rootBlockerID, active: dirty) }
        .onDisappear { session.setPrayerRootDraftBlocker(rootBlockerID, active: false) }
        .disabled(session.prayerWriteInProgress)
        .confirmationDialog("أعد تسجيل هذه الليلة؟", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("أعد التسجيل") { save(restoring: true) }
        } message: { Text("يعود تسجيل الركعات والوتر لهذه الليلة؛ يبقى أثر التراجع محفوظًا.") }
        .onAppear { loadWird() }
        .onChange(of: rakaat) { _, _ in loadWird() }
        .onChange(of: selectedNight) { _, night in
            let previous = snapshot.nights.first { $0.night == night }
            rakaat = previous?.rakaat ?? 0; witr = previous?.witr ?? false
        }
    }

    /// «وجه مستحق»، «وجهان مستحقان»، «٣ أوجه مستحقة»، «١١ وجهًا مستحقًا».
    private func duePhrase(_ n: Int) -> String {
        switch n {
        case 1: "وجه مستحق"
        case 2: "وجهان مستحقان"
        case 3...10: formatter.string(n) + " أوجه مستحقة"
        default: formatter.string(n) + " وجهًا مستحقًا"
        }
    }
    /// OR-08: the Quran room owns the wird; this sheet only reads tonight's board. Due pages read in qiyam count as review there.
    private func loadWird() {
        let service = AppQuranService(session: session)
        guard (try? service.snapshot().coverage.completedPages.isEmpty) == false,
              let board = try? service.qiyamBoard(rakaat: max(2, rakaat)) else { wird = nil; return }
        if let unavailable = board.unavailable {
            wird = unavailable.hasPrefix("سُجّل") ? ("قرأت ورد هذه الليلة في قيامك، واحتُسبت أوجهه من مراجعتك في القرآن.", true) : nil
            return
        }
        let due = board.assignments.filter { $0.status == "مستحق" }.count
        wird = (due > 0
            ? "في ركعاتك " + duePhrase(due) + " من مراجعتك؛ ما تقرؤه منها يُحتسب من وردك."
            : "تقرأ في ركعاتك من محفوظك، ويُسجَّل في سجل القرآن.", false)
    }

    private var divider: some View { Rectangle().fill(theme.ink.opacity(0.1)).frame(height: 1) }

    private func stepButton(_ symbol: String, id: String, disabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium)).frame(width: 52, height: 52)
                .glassEffect(.regular.interactive(), in: .circle).contentShape(Circle())
        }
        .buttonStyle(.madarPlain).opacity(disabled ? 0.35 : 1).disabled(disabled)
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    private func primary(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(PrayerHomeType.strong).foregroundStyle(theme.background)
                .frame(maxWidth: .infinity, minHeight: 56).background(theme.ink, in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.madarPlain).accessibilityIdentifier(id)
    }

    /// The last 30 nights, oldest on the right: a footprint, not a streak.
    @ViewBuilder private var footprintStrip: some View {
        if typeSize.isAccessibilitySize {
            DisclosureGroup("سجلّ الليالي") {
                ForEach(footprint.reversed(), id: \.self) { night in
                    Text(dateTitle(night) + (hasRecord(night) ? "، قيام مسجّل" : "، بلا تسجيل"))
                        .font(MadarTypography.caption()).fixedSize(horizontal: false, vertical: true)
                }
            }.accessibilityIdentifier("prayer-qiyam-footprint-list")
        } else {
            HStack(spacing: 3) {
                ForEach(footprint, id: \.self) { night in
                    RoundedRectangle(cornerRadius: 3).fill(footprintColor(night)).frame(maxWidth: .infinity).frame(height: 15)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("آخر ثلاثين ليلة، سُجّل القيام في " + arabicCount(footprint.filter(hasRecord).count, ["ليلة واحدة", "ليلتين", "ليالٍ", "ليلة"], formatter) + " منها")
            .accessibilityIdentifier("prayer-qiyam-footprint-list")
        }
    }

    private func save(restoring: Bool) {
        session.recordQiyamNight(selectedNight, rakaat: rakaat, witr: witr, restoreDeleted: restoring) { succeeded in if succeeded { finished() } }
    }
    private func hasRecord(_ night: GregorianDay) -> Bool { snapshot.nights.contains { $0.night == night && ($0.rakaat > 0 || $0.witr) } }
    private func dateTitle(_ night: GregorianDay) -> String {
        DualDate(instant: night.date(in: session.activePlace.timeZone).addingTimeInterval(12 * 3600), timeZone: session.activePlace.timeZone,
            source: HijriSource(rawValue: session.string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(session.number("core.hijriOffset")))
            .labels(firstCalendar: session.string("core.firstCalendar") == "gregorian" ? .gregorian : .hijri, numerals: formatter.style).combined
    }
}
