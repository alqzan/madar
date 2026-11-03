import SwiftUI
import MadarCore
import MadarDesign
import MadarPrayer

/// S1 · Prayer home («الرواق والبركة»), matched to `screens/salah/01-S1-Home.jpg` and `-s1`.
/// Not copied from the canonical: the day/night button (prototype only), sample numbers,
/// the heart label under the arches (RP6), and the «تُحسب فائتة» line (RP1).
struct PrayerTodayView: View {
    @Bindable var session: AppSession
    @Environment(\.roomTheme) private var inheritedTheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var selectedSheet: PrayerTodaySheet?
    @State private var prayerSheetIsVisible = false
    @State private var locator = TravelLocator()
    @State private var requestReadFailed = false
    @State private var pendingPrayerRoute: Route?
    @State private var pendingPrayerRootRequestID: UUID?
    #if DEBUG
    @State private var injectedReadFailure = false
    @State private var injectedRequest = false
    @State private var injectedRoute = false
    @State private var debugPrayerRouteOpenedAfterDismissal: Bool?
    #endif
    @Environment(\.scenePhase) private var scenePhase

    @State private var onTrip = false
    /// On a trip the home takes the calm-paper palette (cooler sand, same gold ornaments) so travel looks different at a glance.
    private var theme: RoomTheme { RoomTheme(room: "salah", dark: inheritedTheme.dark, calmPaper: inheritedTheme.calmPaper || onTrip) }
    private func refreshTrip() { onTrip = (try? session.prayerSnapshot(at: session.prayerNow()))?.activeTrip != nil }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let instant = session.prayerNow(timeline.date)
            ScrollView {
                VStack(spacing: 0) {
                    if let snapshot = try? session.prayerSnapshot(at: instant) {
                        header(day: snapshot.today.day)
                            .padding(.top, 8)
                        let pills = travelPillText(snapshot) != nil || snapshot.today.cells.contains(where: { $0.isFriday })
                        VStack(spacing: 10) {
                            if let text = travelPillText(snapshot) {
                                PrayerTravelPill(text: text) { openTravel(snapshot) }
                            }
                            if snapshot.today.cells.contains(where: { $0.isFriday }) { fridayPill }
                        }
                        .padding(.top, pills ? 16 : 0)
                        nextPrayer(snapshot, now: instant)
                            .padding(.top, pills ? 18 : 26)
                        verseDivider
                            .padding(.top, 18)
                        riwaq(snapshot, now: instant)
                            .padding(.top, 18)
                        if snapshot.hasTimes {
                            Text(todaySummary(snapshot, now: instant))
                                .font(PrayerHomeType.body)
                                .foregroundStyle(theme.secondaryInk)
                                .multilineTextAlignment(.center)
                                .padding(.top, 14)
                                .accessibilityIdentifier("prayer-today-summary")
                        }
                        VStack(spacing: 16) {
                            ForEach(PrayerHomeLayout(session.values["salah.layout"]).visible, id: \.self) { block in
                                switch block {
                                case "pending":
                                    if let pending = notice(snapshot, now: instant) { pending }
                                    heartNotice(snapshot)
                                case "hali": haliCard(snapshot)
                                case "qada": qadaCard(snapshot)
                                default: qiyamCard(snapshot)
                                }
                            }
                        }
                        .padding(.top, 20)
                    } else {
                        header(day: nil)
                        PrayerPaperCard {
                            Text("تعذّر حساب صلاة اليوم. راجع المدينة وطريقة الحساب في خصّص مدار.")
                                .font(MadarTypography.body())
                        }
                        .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .clipped()
            .background(theme.background)
            .foregroundStyle(theme.ink)
        }
        .environment(\.roomTheme, theme)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear {
            detectTravel(); refreshTrip()
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if !injectedRequest, env["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
               let prayer = env["MADAR_UI_PRAYER_OPEN_REQUEST"].flatMap(Prayer.init(rawValue:)) {
                injectedRequest = true
                session.prayerLogRequest = prayer
            }
            if !injectedRoute, env["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
               let raw = env["MADAR_UI_PRAYER_ROUTE"], let url = URL(string: raw) {
                injectedRoute = true
                session.open(url)
            }
            #endif
        }
        .onChange(of: selectedSheet == nil) { _, _ in refreshTrip() }
        .onChange(of: session.prayerLogRequest, initial: true) { _, prayer in
            // «صليت المغرب» from Capture: the state was not said, so its log sheet asks instead of guessing.
            guard let prayer else { return }
            openPrayerRequest(prayer)
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
        .onChange(of: scenePhase) { _, phase in if phase == .active { detectTravel() } }
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
            case .oldMissed:
                PrayerSnapshotSheet(revision: session.prayerRevision, load: sheetSnapshot, close: { selectedSheet = nil }) { snapshot in
                    PrayerOldMissedSheet(session: session, trackingStart: snapshot.tracking.day, finished: { selectedSheet = nil }, rootDraftChanged: reportRootDraft)
                }
            case .qiyam:
                PrayerSnapshotSheet(revision: session.prayerRevision, load: sheetSnapshot, close: { selectedSheet = nil }) { snapshot in
                    PrayerNightLoggingSheet(session: session, snapshot: snapshot, finished: { selectedSheet = nil })
                }
            case .qiyamNight(let night):
                PrayerSnapshotSheet(revision: session.prayerRevision, load: sheetSnapshot, close: { selectedSheet = nil }) { snapshot in
                    PrayerNightLoggingSheet(session: session, snapshot: snapshot, initialNight: night, finished: { selectedSheet = nil })
                }
            case .heart(let cell):
                PrayerHeartAnswerSheet(session: session, cell: cell, finished: { selectedSheet = nil }, rootDraftChanged: reportRootDraft)
            case .streaks:
                PrayerSnapshotSheet(revision: session.prayerRevision, load: sheetSnapshot, close: { selectedSheet = nil }) { snapshot in
                    PrayerStreaksSheet(snapshot: snapshot, levels: PrayerStreakLevel.shown(congregation: session.bool("salah.showMosqueStreak")),
                                       digits: digits, timeZone: session.activePlace.timeZone, openHali: { selectedSheet = .statistics })
                }
            case .statistics:
                NavigationStack {
                    PrayerSnapshotSheet(revision: session.prayerRevision, load: sheetSnapshot, close: { selectedSheet = nil }) { snapshot in
                        PrayerStatisticsView(session: session, snapshot: snapshot) { choose($0) }
                    }
                }
            case .day(let day):
                NavigationStack {
                    PrayerSnapshotSheet(revision: session.prayerRevision, load: sheetSnapshot, close: { selectedSheet = nil }) { snapshot in
                        PrayerStatisticsView(session: session, snapshot: snapshot, initialDay: day) { choose($0) }
                    }
                }
            case .qadaList:
                PrayerQadaListSheet(session: session, dateLabel: qadaDate, loadSnapshot: sheetSnapshot,
                    rootDraftChanged: reportRootDraft,
                    makeUp: { item in
                        let continuationBlocker = UUID()
                        reportRootDraft(continuationBlocker, true)
                        selectedSheet = .makeUp(item, isFridayNoon: item.isFriday,
                            dateLabel: qadaDate(item.reference.day), rootBlockerID: continuationBlocker)
                    },
                    addOld: { selectedSheet = .oldMissed })
            case .log(let cell, let timeZone):
                PrayerTodayLogSheet(cell: cell,
                    clock: (cell.prayerTime ?? cell.time).map { clock($0, timeZone: timeZone) } ?? "",
                    askHeart: session.bool("salah.askHeart"), isSaving: session.prayerWriteInProgress,
                    prefillStatus: nil, prefillHeart: nil,
                    save: { status, fridayKind, makeUpNow, done in
                        if status == .qada {
                            session.makeUpPrayer(cell.reference, fridayKind: fridayKind, completion: done)
                        } else if status == .missed && makeUpNow {
                            session.recordPrayer(cell.reference, status: .missed, fridayKind: fridayKind) { succeeded in
                                if succeeded { session.makeUpPrayer(cell.reference, fridayKind: fridayKind, completion: done) } else { done(false) }
                            }
                        } else {
                            session.recordPrayer(cell.reference, status: status, fridayKind: fridayKind, completion: done)
                        }
                    },
                    answerHeart: { heart, done in session.answerPrayerHeart(cell.reference, heart: heart, completion: done) },
                    rootDraftChanged: reportRootDraft)
            case .prefilledLog(let cell, let timeZone, let status, let heart):
                PrayerTodayLogSheet(cell: cell,
                    clock: (cell.prayerTime ?? cell.time).map { clock($0, timeZone: timeZone) } ?? "",
                    askHeart: session.bool("salah.askHeart"), isSaving: session.prayerWriteInProgress,
                    prefillStatus: status, prefillHeart: heart,
                    save: { status, fridayKind, makeUpNow, done in
                        if status == .qada {
                            session.makeUpPrayer(cell.reference, fridayKind: fridayKind, completion: done)
                        } else if status == .missed && makeUpNow {
                            session.recordPrayer(cell.reference, status: .missed, fridayKind: fridayKind) { succeeded in
                                if succeeded { session.makeUpPrayer(cell.reference, fridayKind: fridayKind, completion: done) } else { done(false) }
                            }
                        } else {
                            session.recordPrayer(cell.reference, status: status, fridayKind: fridayKind, completion: done)
                        }
                    },
                    answerHeart: { heart, done in session.answerPrayerHeart(cell.reference, heart: heart, completion: done) },
                    rootDraftChanged: reportRootDraft)
            case .makeUp(let item, let isFridayNoon, let dateLabel, let rootBlockerID):
                PrayerMakeUpSheet(item: item, isFridayNoon: isFridayNoon, dateLabel: dateLabel,
                    isSaving: session.prayerWriteInProgress, rootBlockerID: rootBlockerID,
                    rootDraftChanged: reportRootDraft) { kind, done in
                    session.makeUpPrayer(item.reference, fridayKind: kind, completion: done)
                }
            case .recovery(let references, let fridayReferences, _):
                PrayerGapResolutionSheet(references: references, fridayReferences: fridayReferences, dateLabel: qadaDate, digits: digits, rootDraftChanged: reportRootDraft) { resolutions, done in
                    session.resolvePrayerGap(resolutions, completion: done)
                }
            }
            }
            .onAppear { prayerSheetIsVisible = true }
            .dynamicTypeSize(dynamicType)
            .environment(\.roomTheme, theme)
            .madarSheetErrorAlert(session) // AU-37: a failed write inside a prayer sheet is said there.
#if DEBUG
            .overlay(alignment: .topTrailing) {
                if ProcessInfo.processInfo.environment["MADAR_UI_PRAYER_ROOT_ROUTE_HARNESS"] == "1"
                    || ProcessInfo.processInfo.environment["MADAR_UI_PRAYER_ROUTE_DISMISSAL_RACE"] == "1" {
                    VStack(alignment: .trailing, spacing: 8) {
                        Button("اختبار رابط جذر الصلاة") { session.open(URL(string: "madar://prayer")!) }
                            .accessibilityIdentifier("prayer-root-test-route")
                        Button("اختبر رابط الإحصاءات") { session.open(URL(string: "madar://salah/hali")!) }
                            .accessibilityIdentifier("prayer-deep-route-test")
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

    private func openPrayerRequest(_ prayer: Prayer) {
        do {
            guard let cell = try sheetSnapshot().today.cells.first(where: { $0.reference.prayer == prayer }) else {
                requestReadFailed = true; return
            }
            session.prayerLogRequest = nil
            requestReadFailed = false
            choose(cell)
        } catch { requestReadFailed = true }
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
            guard let night = try? GregorianDay(rawNight) else { session.errorMessage = "تعذّر فتح ليلة القيام المطلوبة."; return }
            selectedSheet = .qiyamNight(night)
        case "hali" where route.path.count == 1:
            selectedSheet = .statistics
        case "qada" where route.path.count == 1:
            selectedSheet = .qadaList
        case "qada" where route.path.count == 2:
            let rawID = route.path[1]
            guard let id = UUID(uuidString: rawID) else {
                session.errorMessage = "لم تعد هذه الفائتة موجودة في سجل الصلاة."
                pendingPrayerRoute = nil
                return
            }
            do {
                guard let item = try sheetSnapshot().qada.first(where: { $0.id == id && $0.madeUpAt == nil }) else {
                    session.errorMessage = "لم تعد هذه الفائتة موجودة في سجل الصلاة."
                    pendingPrayerRoute = nil
                    return
                }
                pendingPrayerRoute = nil
                requestReadFailed = false
                selectedSheet = .makeUp(item, isFridayNoon: item.isFriday, dateLabel: qadaDate(item.reference.day), rootBlockerID: nil)
            } catch {
                pendingPrayerRoute = route
                requestReadFailed = true
            }
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
                    .overlay { Circle().stroke(theme.ink.opacity(0.14), lineWidth: 1) }
                    .contentShape(Circle())
            }
            .buttonStyle(.madarPlain).accessibilityLabel("خصّص الصلاة").accessibilityIdentifier("prayer-customize")
        }
    }

    /// «الأربعاء ٢٦ ربيع الآخر ١٤٤٨، ٧ أكتوبر». RU1: «،» separates the two dates, never «·».
    private func headerDate(_ day: GregorianDay) -> String {
        session.dateLabels(day).combined
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
            .overlay { Capsule().stroke(theme.line, lineWidth: 1) }
        }
        .buttonStyle(.madarPlain)
        .accessibilityLabel("جمعة مباركة، افتح سورة الكهف")
        .accessibilityIdentifier("prayer-friday-pill")
    }

    private func nextPrayer(_ snapshot: PrayerSnapshot, now: Date) -> some View {
        VStack(spacing: 6) {
            if let next = snapshot.next {
                Text("الصلاة القادمة").font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
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
        let canEditStatus = [.pending, .jamaah, .alone, .missed].contains(cell.status)
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
            Button { choose(cell) } label: { arch }
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
        let recorded = cells.filter { [.jamaah, .alone, .qada, .missed, .excused].contains($0.status) }.count
        let remaining = cells.count - recorded
        let afterLastAdhan = cells.compactMap(\.prayerTime).max().map { now >= $0 } ?? false
        let tail = afterLastAdhan && remaining > 0 ? PrayerCopy.pending(remaining, digits: digits) : PrayerCopy.remaining(remaining, digits: digits)
        if cells.isEmpty { return "" }
        if remaining == 0 { return "سجّلت صلوات اليوم كلها" }
        if recorded == 0 { return tail }
        return "سجّلت \(digits.string(recorded)) من \(digits.string(cells.count)) اليوم، " + tail
    }

    // MARK: Notices

    /// One quiet notice: an unrecorded prayer whose window has ended, or an older unresolved gap.
    /// RP1: neither ever turns into a missed prayer by itself.
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
                detail: first.reference.day == snapshot.tracking.firstRun
                    ? "إن صلّيتها قبل أن تفتح مدار فسجِّلها متى شئت؛ لا يُحسب عليك شيء."
                    : "تبقى معلّقة حتى تختار حالها.",
                action: "سجِّلها", identifier: "prayer-pending-review") { choose(first) })
        }
        let historical = gap.filter { $0.day < snapshot.today.day && $0.day >= snapshot.tracking.day }
        let fridays = snapshot.unconfirmedFridayNoon.union(closed.filter { $0.isFriday && $0.reference.prayer == .dhuhr }.map(\.reference))
        return AnyView(PrayerNoticeRow(
            title: gap.count > 10 ? "فترة لم تُسجَّل فيها صلواتك: " + PrayerCopy.days(Set(gap.map(\.day)).count, digits: digits)
                    : historical.isEmpty ? PrayerCopy.pending(gap.count, digits: digits) : PrayerCopy.unconfirmed(historical.count, digits: digits),
            detail: gap.count > 10 ? "لا يلزمك تسجيلها واحدة واحدة: اختر «لم أسجّل هذه الفترة» وتبدأ من اليوم، ولا يُحسب عليك شيء." : "لا تُحسب فائتة إلا باختيارك.",
            action: gap.count > 10 ? "ابدأ من اليوم" : "سجِّلها", identifier: historical.isEmpty ? "prayer-pending-review" : "prayer-recovery") {
                selectedSheet = .recovery(gap, fridays, session.activePlace.timeZone)
            })
    }

    /// The prayer whose window is still open (its time has come and the next prayer has not).
    private func currentPrayer(_ snapshot: PrayerSnapshot, now: Date) -> PrayerReference? {
        snapshot.history.flatMap(\.cells).filter { ($0.prayerTime ?? .distantFuture) <= now }.max { ($0.prayerTime ?? .distantPast) < ($1.prayerTime ?? .distantPast) }?.reference
    }

    private func dayWord(_ day: GregorianDay, today: GregorianDay) -> String {
        if day == today { return "" }
        if day.adding(days: 1) == today { return " أمس" }
        return " يوم " + qadaDate(day)
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

    // MARK: Hali, qada and qiyam

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

    @ViewBuilder private func qadaCard(_ snapshot: PrayerSnapshot) -> some View {
        let outstanding = snapshot.qada.filter { $0.madeUpAt == nil }
        if let first = outstanding.first {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    PrayerStar().fill(theme.color("missed")).frame(width: 15, height: 15)
                    Text(digits.string(outstanding.count)).font(PrayerHomeType.number)
                    Text(PrayerCopy.owed(outstanding.count)).font(PrayerHomeType.strong)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                HStack(alignment: .top, spacing: 12) {
                    Rectangle().fill(theme.color("missed")).frame(width: 2)
                    PrayerQadaCitation()
                }
                .fixedSize(horizontal: false, vertical: true)
                buttonsRow(first: first)
            }
            .padding(20)
            .background(theme.color("missed").opacity(0.05), in: .rect(cornerRadius: 22))
            .background(theme.background, in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.color("missed").opacity(0.28), lineWidth: 1) }
        } else {
            Button { selectedSheet = .oldMissed } label: {
                HStack {
                    Text(snapshot.qada.isEmpty ? "لا فوائت مسجّلة عليك" : "قضيتَ ما سجّلتَه من الفوائت")
                        .font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("أضف فائتة قديمة").font(PrayerHomeType.strong).foregroundStyle(theme.accent)
                }
                .padding(.horizontal, 18).frame(minHeight: 54)
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line, lineWidth: 1) }
                .contentShape(.rect(cornerRadius: 18))
            }
            .buttonStyle(.madarPlain)
            .accessibilityIdentifier("prayer-old-missed")
        }
    }

    @ViewBuilder private func buttonsRow(first: PrayerQada) -> some View {
        let makeUp = Button { selectedSheet = .makeUp(first, isFridayNoon: first.isFriday, dateLabel: qadaDate(first.reference.day), rootBlockerID: nil) } label: {
            Text("قضيتُ واحدة").font(PrayerHomeType.strong).frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(theme.background).background(theme.ink, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.madarPlain).disabled(session.prayerWriteInProgress)
        .accessibilityIdentifier("prayer-qada-makeup")
        let places = Button { selectedSheet = .qadaList } label: {
            Text("مواضعها").font(PrayerHomeType.strong).frame(minHeight: 54).padding(.horizontal, 26)
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.ink.opacity(0.18), lineWidth: 1) }
                .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.madarPlain)
        .accessibilityIdentifier("prayer-qada-places")
        if dynamicType.isAccessibilitySize {
            VStack(spacing: 10) { makeUp; places.frame(maxWidth: .infinity) }
        } else {
            HStack(spacing: 12) { makeUp; places }
        }
    }

    private func qiyamCard(_ snapshot: PrayerSnapshot) -> some View {
        let night = snapshot.nights.first { $0.night == snapshot.nightDefault }
        let summary = night.map { PrayerCopy.rakaat($0.rakaat, digits: digits) + ($0.witr ? "، أوترتُ" : "") } ?? "لم تُسجَّل ليلتك"
        return Button { selectedSheet = .qiyam } label: {
            PrayerPaperCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("قيام الليل").font(PrayerHomeType.cardHead)
                        Spacer(minLength: 8)
                        Text(summary).font(PrayerHomeType.strong).foregroundStyle(theme.accent)
                            .accessibilityIdentifier("prayer-qiyam-summary")
                    }
                    if !dynamicType.isAccessibilitySize {
                        PrayerNightFootprint(nights: snapshot.nights, last: snapshot.nightDefault)
                    }
                    Text("آخر ثلاثين ليلة")
                        .font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                }
            }
        }
        .buttonStyle(.madarPlain)
        .accessibilityIdentifier("prayer-qiyam")
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
    private func qadaDate(_ day: GregorianDay) -> String {
        session.dateLabels(day).combined
    }

    private func choose(_ cell: PrayerCell) {
        let timeZone = (try? session.prayerSnapshot(at: session.prayerNow()))?.activeTrip?.place.timeZone ?? session.activePlace.timeZone
        if let pair = travelPair(for: cell), [.pending, .future].contains(cell.status) {
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
    private func travelPair(for cell: PrayerCell) -> PrayerPair? {
        guard session.bool("salah.travelShortenCombine"), (try? session.prayerSnapshot(at: session.prayerNow()))?.activeTrip != nil else { return nil }
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
    /// The count is shown large beside this phrase, so the phrase carries no digits.
    static func owed(_ count: Int, bundle: Bundle = .main) -> String {
        String(localized: "prayer.owed", defaultValue: "\(count)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
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
    case oldMissed
    case qadaList
    case makeUp(PrayerQada, isFridayNoon: Bool, dateLabel: String, rootBlockerID: UUID?)
    case recovery([PrayerReference], Set<PrayerReference>, TimeZone)
    var id: String {
        switch self {
        case .travelQuestion: "travel-question"
        case .trip(let trip): "trip-\(trip.id.uuidString)"
        case .pair(let day, let pair, _, _): "pair-\(day)-\(pair.rawValue)"
        case .oldMissed: "old-missed"
        case .qadaList: "qada-list"
        case .qiyam: "qiyam"
        case .qiyamNight(let night): "qiyam-" + night.description
        case .statistics: "statistics"
        case .day(let day): "day-" + day.description
        case .streaks: "streaks"
        case .heart(let cell): "heart-\(cell.reference.naturalKey)"
        case .log(let cell, _): "log-\(cell.reference.naturalKey)"
        case .prefilledLog(let cell, _, _, _): "prefilled-log-\(cell.reference.naturalKey)"
        case .makeUp(let item, _, _, _): "makeup-\(item.id.uuidString)"
        case .recovery(let references, _, _): "recovery-\(references.first?.naturalKey ?? "empty")"
        }
    }
}

/// S2 · the light log sheet, matched to `screens/salah/02-S2-Log.jpg` and `03-S2b-Missed.jpg`.
/// One tap on a state records it (RP2: «فاتتني» is offered only once the window has ended and
/// opens its make-up panel instead of saving); the heart question is inline and only when
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
        let initial: PrayerStoredStatus? = switch cell.status { case .jamaah: .jamaah; case .alone: .alone; case .qada: .qada; case .missed: .missed; default: nil }
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
        [.jamaah, .alone] + (cell.canMakeUp || cell.status == .qada || selected == .qada ? [.qada] : []) + (cell.canMarkMissed || cell.status == .missed || selected == .missed ? [.missed] : [])
    }
    /// Friday noon: everything but «وحدي» (always the noon prayer) waits for the kind.
    private func needsKind(_ option: PrayerStoredStatus) -> Bool { cell.isFriday && option != .alone && fridayKind == nil }
    private var showsHeart: Bool { askHeart && recorded && [.jamaah, .alone, .qada].contains(selected ?? .missed) }
    private var hasUnsavedInput: Bool {
        selected != committedStatus || recorded != committedRecorded || heart != committedHeart || fridayKind != committedFridayKind
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if cell.isFriday { fridayKindRow.padding(.top, 16) }
            // AU-38: the dimmed options say why.
            if cell.isFriday && fridayKind == nil { Text("اختر «جمعة» أو «ظهر» لتسجّلها في جماعة أو فائتة.").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).padding(.top, 8).accessibilityIdentifier("prayer-friday-kind-hint") }
            optionRow.padding(.top, 20)
            if routePrefilled, !recorded, let selected, selected != .missed {
                Button("احفظ التسجيل") { record(selected, kind: cell.isFriday ? (selected == .alone ? .dhuhr : fridayKind) : nil) }
                    .buttonStyle(.madarPlain).frame(maxWidth: .infinity, minHeight: 48)
                    .overlay { Capsule().stroke(theme.accent, lineWidth: 1) }
                    .padding(.top, 10).accessibilityIdentifier("prayer-log-prefill-save")
            }
            if selected == .missed { missedPanel.padding(.top, 14) }
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

    // MARK: The four states

    private var optionRow: some View {
        HStack(spacing: 8) { ForEach(options, id: \.self) { optionPill($0) } }
    }

    private func optionPill(_ option: PrayerStoredStatus) -> some View {
        let on = selected == option
        let missed = option == .missed
        let tint = missed ? theme.color("missed") : theme.accent
        let (title, detail): (String, String) = switch option {
        case .jamaah: ("في جماعة", "مع الناس")
        case .alone: ("وحدي", "في وقتها")
        case .qada: ("قضاءً", "بعد وقتها")
        default: ("فاتتني", "تبقى لقضائها")
        }
        return Button {
            guard !isSaving else { return }
            if option == .alone, cell.isFriday { fridayKind = .dhuhr }
            if missed { selected = .missed; return }
            record(option, kind: cell.isFriday ? (option == .alone ? .dhuhr : fridayKind) : nil)
        } label: {
            VStack(spacing: 4) {
                Text(title).font(PrayerHomeType.strong)
                    .foregroundStyle(on ? (missed ? theme.color("missedTextOnSurface") : theme.color("accentText")) : theme.ink)
                Text(detail).font(PrayerHomeType.small).foregroundStyle(on && missed ? theme.color("missedTextOnSurface") : theme.secondaryInk)
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

    // MARK: «فاتتني»: explicit, never automatic (RP1, RP2)

    private var missedPanel: some View {
        let kind = cell.isFriday ? fridayKind : nil
        return VStack(alignment: .leading, spacing: 12) {
            Text("نزلت في القضاء، وهي عليك حتى تصلّيها.").font(PrayerHomeType.strong)
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(theme.color("missed")).frame(width: 2)
                PrayerQadaCitation()
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    save(.missed, kind, true) { ok in if ok { dismiss() } }
                } label: {
                    Text("قضيتُها الآن").font(PrayerHomeType.strong).foregroundStyle(theme.background)
                        .frame(maxWidth: .infinity, minHeight: 54).background(theme.ink, in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.madarPlain).accessibilityIdentifier("prayer-makeup-now")
                Button {
                    save(.missed, kind, false) { ok in if ok { dismiss() } }
                } label: {
                    Text("لاحقًا").font(PrayerHomeType.strong)
                        .padding(.horizontal, 22).frame(minHeight: 54)
                        .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.ink.opacity(0.14), lineWidth: 1) }
                }
                .buttonStyle(.madarPlain).accessibilityIdentifier("prayer-missed-later")
            }
            .disabled(isSaving || (cell.isFriday && fridayKind == nil))
        }
        .padding(16)
        .background(theme.color("missed").opacity(0.07), in: .rect(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.color("missed").opacity(0.35), lineWidth: 1) }
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

/// «صلوات بلا تسجيل»: settle a gap in one tap, a day at a time, or prayer by prayer.
/// RP1: nothing here is chosen for the user; what is left unchosen stays as it is.
private struct PrayerGapResolutionSheet: View {
    let references: [PrayerReference]
    let fridayReferences: Set<PrayerReference>
    let dateLabel: (GregorianDay) -> String
    let digits: MadarNumberFormatter
    let rootDraftChanged: (UUID, Bool) -> Void
    let resolve: ([PrayerGapResolution], @escaping (Bool) -> Void) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var choices: [PrayerReference: Choice] = [:]
    @State private var rootBlockerID = UUID()

    /// One choice as the user reads it; Friday noon carries its kind explicitly (RP5).
    struct Choice: Hashable {
        let status: PrayerStoredStatus
        var fridayKind: FridayPrayerKind? = nil
    }

    private var days: [GregorianDay] { Array(Set(references.map(\.day))).sorted() }
    private var hasUnsavedInput: Bool { !choices.isEmpty }
    private func prayers(on day: GregorianDay) -> [PrayerReference] {
        references.filter { $0.day == day }.sorted { $0.prayer.rawValue.order < $1.prayer.rawValue.order }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                quickActions
                ForEach(days, id: \.self) { day in dayCard(day) }
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .background(theme.background)
        .foregroundStyle(theme.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(hasUnsavedInput)
        .onChange(of: hasUnsavedInput, initial: true) { _, dirty in rootDraftChanged(rootBlockerID, dirty) }
        .onDisappear { rootDraftChanged(rootBlockerID, false) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("صلوات بلا تسجيل").font(PrayerHomeType.cardHead).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("إغلاق") { dismiss() }.font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
                    .frame(minHeight: 44)
            }
            Text(references.count > 10 ? "فترة لم تُسجَّل فيها صلواتك: " + PrayerCopy.days(Set(references.map(\.day)).count, digits: digits) : PrayerCopy.unconfirmed(references.count, digits: digits))
                .font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
            if !rangeText.isEmpty {
                Text(rangeText).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
            }
            Text("لا يُحسب شيء منها فائتة إلا باختيارك، وما تتركه يبقى كما هو.")
                .font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
        }
    }

    private var rangeText: String {
        guard let first = days.first, let last = days.last else { return "" }
        return first == last ? dateLabel(first) : "من " + dateLabel(first) + " إلى " + dateLabel(last)
    }

    /// One tap settles the whole gap and closes; the undo bar on the home page reverses it.
    private var quickActions: some View {
        VStack(spacing: 10) {
            Button { apply(Choice(status: .alone, fridayKind: nil), to: references, saveNow: true) } label: {
                quickLabel("صلّيتها كلها", detail: "تُسجَّل في وقتها، وحدي")
            }
            .buttonStyle(.madarPlain).accessibilityIdentifier("prayer-gap-alone-all")
            Button { apply(Choice(status: .unrecordedHistory), to: references, saveNow: true) } label: {
                quickLabel("لم أسجّل هذه الفترة", detail: "لا قضاء ولا نسبة ولا سلسلة")
            }
            .buttonStyle(.madarPlain).accessibilityIdentifier("prayer-gap-unrecorded-all")
        }
    }

    private func quickLabel(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(PrayerHomeType.strong)
            Spacer(minLength: 8)
            Text(detail).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
        }
        .padding(.horizontal, 18).frame(maxWidth: .infinity, minHeight: 56)
        .background(theme.color("goldSoft"), in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line, lineWidth: 1) }
        .contentShape(.rect(cornerRadius: 18))
    }

    private func dayCard(_ day: GregorianDay) -> some View {
        let refs = prayers(on: day)
        return PrayerPaperCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(dateLabel(day)).font(PrayerHomeType.strong)
                    Spacer(minLength: 8)
                    Menu {
                        ForEach(dayOptions, id: \.self) { choice in
                            Button(title(choice, friday: false)) { apply(choice, to: refs, saveNow: false) }
                        }
                    } label: {
                        Text("اليوم كله").font(PrayerHomeType.smallBold).foregroundStyle(theme.accent)
                            .frame(minHeight: 44).contentShape(.rect)
                    }
                    .accessibilityIdentifier("prayer-gap-day-\(day)")
                }
                ForEach(refs, id: \.self) { ref in
                    prayerRow(ref)
                    if ref != refs.last { Divider().overlay(theme.line) }
                }
            }
        }
    }

    private func prayerRow(_ ref: PrayerReference) -> some View {
        let friday = fridayReferences.contains(ref)
        let chosen = choices[ref]
        return HStack {
            Text(friday ? "الجمعة" : prayerTitle(ref.prayer)).font(PrayerHomeType.body)
            Spacer(minLength: 8)
            Menu {
                ForEach(options(friday: friday), id: \.self) { choice in
                    Button(title(choice, friday: friday)) { choices[ref] = choice }
                }
                if chosen != nil {
                    Divider()
                    Button("اتركها كما هي") { choices[ref] = nil }
                }
            } label: {
                Text(chosen.map { title($0, friday: friday) } ?? "اختر")
                    .font(chosen == nil ? PrayerHomeType.small : PrayerHomeType.smallBold)
                    .foregroundStyle(chosen == nil ? theme.secondaryInk : chosenColor(chosen!))
                    .padding(.horizontal, 14).frame(minHeight: 36)
                    .overlay { Capsule().stroke(chosen == nil ? theme.ink.opacity(0.14) : theme.line, lineWidth: 1) }
                    .frame(minHeight: 44).contentShape(.rect)
            }
            .accessibilityIdentifier("prayer-gap-status-\(ref.day)-\(ref.prayer.rawValue)")
        }
        .frame(minHeight: 48)
    }

    private var saveBar: some View {
        let count = choices.count
        return Button {
            save()
        } label: {
            Text(count == 0 ? "اختر حال صلاة لتحفظها" : "احفظ ما اخترت")
                .font(PrayerHomeType.strong).frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(count == 0 ? theme.secondaryInk : theme.background)
                .background(count == 0 ? theme.color("surface") : theme.ink, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.madarPlain).disabled(count == 0)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(theme.background)
        .accessibilityIdentifier("prayer-gap-save")
    }

    // MARK: Choices

    private var dayOptions: [Choice] {
        [.init(status: .jamaah, fridayKind: nil), .init(status: .alone), .init(status: .missed), .init(status: .unrecordedHistory), .init(status: .excused)]
    }
    private func options(friday: Bool) -> [Choice] {
        guard friday else { return dayOptions }
        return [.init(status: .jamaah, fridayKind: .jumuah), .init(status: .jamaah, fridayKind: .dhuhr), .init(status: .alone, fridayKind: .dhuhr),
                .init(status: .missed, fridayKind: .jumuah), .init(status: .missed, fridayKind: .dhuhr), .init(status: .unrecordedHistory), .init(status: .excused)]
    }

    /// A whole-day or whole-gap choice; Friday noon gets the kind the choice implies, and
    /// «في جماعة» or «فاتتني» on a Friday is left for the user to pick explicitly (RP5).
    private func apply(_ choice: Choice, to refs: [PrayerReference], saveNow: Bool) {
        for ref in refs {
            guard fridayReferences.contains(ref) else { choices[ref] = Choice(status: choice.status); continue }
            switch choice.status {
            case .alone: choices[ref] = Choice(status: .alone, fridayKind: .dhuhr)
            case .unrecordedHistory, .excused: choices[ref] = Choice(status: choice.status)
            default: if saveNow { choices[ref] = nil }
            }
        }
        if saveNow { save() }
    }

    private func save() {
        let resolutions = references.compactMap { ref -> PrayerGapResolution? in
            guard let choice = choices[ref] else { return nil }
            return .init(reference: ref, status: choice.status, fridayKind: choice.fridayKind)
        }
        guard !resolutions.isEmpty else { return }
        resolve(resolutions) { ok in if ok { dismiss() } } // AU-41: a failed save keeps the choices on screen.
    }

    private func title(_ choice: Choice, friday: Bool) -> String {
        switch (choice.status, choice.fridayKind) {
        case (.jamaah, .jumuah?): "صلّيت الجمعة"
        case (.jamaah, .dhuhr?): "الظهر في جماعة"
        case (.alone, .dhuhr?) where friday: "الظهر وحدي"
        case (.missed, .jumuah?): "فاتتني الجمعة"
        case (.missed, .dhuhr?): "فاتني الظهر"
        case (.jamaah, _): "في جماعة"
        case (.alone, _): "وحدي"
        case (.missed, _): "فاتتني"
        case (.unrecordedHistory, _): "لم أسجّل"
        case (.excused, _): "لي عذر"
        default: choice.status.rawValue
        }
    }
    private func chosenColor(_ choice: Choice) -> Color {
        switch choice.status {
        case .missed: theme.color("missedTextOnSurface")
        case .unrecordedHistory, .excused: theme.secondaryInk
        default: theme.accent
        }
    }
}

private extension String {
    /// Day order of the five prayers by raw value.
    var order: Int { ["fajr", "dhuhr", "asr", "maghrib", "isha"].firstIndex(of: self) ?? 9 }
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
                        .overlay { Capsule().stroke(theme.ink.opacity(0.14), lineWidth: 1) }.contentShape(.capsule)
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
                .overlay { Circle().stroke(theme.ink.opacity(0.14), lineWidth: 1) }.contentShape(Circle())
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

private struct PrayerOldMissedSheet: View {
    @Bindable var session: AppSession
    let trackingStart: GregorianDay
    let finished: () -> Void
    let rootDraftChanged: (UUID, Bool) -> Void
    @State private var date: Date
    @State private var prayer: Prayer = .fajr
    @State private var fridayKind: FridayPrayerKind? = nil
    @State private var confirmRestore = false
    @State private var rootBlockerID = UUID()
    private var hasUnsavedInput: Bool {
        GregorianDay.containing(date, in: session.activePlace.timeZone) != trackingStart.adding(days: -1)
            || prayer != .fajr || fridayKind != nil
    }
    init(session: AppSession, trackingStart: GregorianDay, finished: @escaping () -> Void,
         rootDraftChanged: @escaping (UUID, Bool) -> Void) {
        self.session = session; self.trackingStart = trackingStart; self.finished = finished; self.rootDraftChanged = rootDraftChanged
        _date = State(initialValue: trackingStart.adding(days: -1).date(in: session.activePlace.timeZone).addingTimeInterval(12 * 3600))
    }
    private var reference: PrayerReference { .init(day: GregorianDay.containing(date, in: session.activePlace.timeZone), prayer: prayer) }
    private var fridayNoon: Bool { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = session.activePlace.timeZone; return prayer == .dhuhr && calendar.component(.weekday, from: date) == 6 }
    private var restoring: Bool { (try? session.oldMissedRequiresRestore(reference)) ?? true }
    private var calendar: Calendar { var c = Calendar(identifier: session.string("core.firstCalendar") == "gregorian" ? .gregorian : .islamicUmmAlQura); c.timeZone = session.activePlace.timeZone; return c }
    private var sightingOffset: Int {
        session.string("core.firstCalendar") != "gregorian" && session.string("core.hijriSource") == "sighting" ? Int(session.number("core.hijriOffset")) : 0
    }
    private func shifted(_ value: Date, by days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: value) ?? value }
    private var pickerDate: Binding<Date> { Binding(get: { shifted(date, by: sightingOffset) }, set: { date = shifted($0, by: -sightingOffset) }) }
    private var maximumDate: Date { shifted(trackingStart.date(in: session.activePlace.timeZone).addingTimeInterval(-1), by: sightingOffset) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("الفوائت القديمة لا تُضاف إلا باختيارك؛ ما قبل بداية التتبّع يبقى بلا تسجيل.")
                    DatePicker("التاريخ", selection: pickerDate, in: ...maximumDate, displayedComponents: .date)
                        .environment(\.calendar, calendar).environment(\.timeZone, session.activePlace.timeZone)
                        .accessibilityIdentifier("prayer-old-date")
                    MadarDateLabel(session.dateLabels(.containing(date, in: session.activePlace.timeZone)), primaryFont: MadarTypography.caption(), secondaryFont: MadarTypography.fine())
                    Picker("الصلاة", selection: $prayer) {
                        ForEach(Prayer.allCases, id: \.self) { Text(title($0)).tag($0) }
                    }.accessibilityIdentifier("prayer-old-prayer")
                    if fridayNoon {
                        Picker("فرض ظهر الجمعة", selection: $fridayKind) {
                            Text("اختر النوع").tag(Optional<FridayPrayerKind>.none)
                            Text("الجمعة").tag(Optional(FridayPrayerKind.jumuah))
                            Text("الظهر").tag(Optional(FridayPrayerKind.dhuhr))
                        }.accessibilityIdentifier("prayer-old-friday")
                    }
                }
                Section {
                    if restoring {
                        Text("حذفتَ هذا التسجيل أو تراجعتَ عنه؛ يمكنك إعادته من الزر أدناه.")
                        Button("أعد تسجيل الفائتة") { confirmRestore = true }.accessibilityIdentifier("prayer-old-restore")
                    } else {
                        Button("أضف الفائتة") { save(false) }.accessibilityIdentifier("prayer-old-save")
                    }
                }.disabled(session.prayerWriteInProgress || (fridayNoon && fridayKind == nil))
            }
            .navigationTitle("فائتة قديمة").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { finished() } } }
            .confirmationDialog("أعد تسجيل هذه الفائتة؟", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("أعد التسجيل") { save(true) }
            }
            .onChange(of: date) { _, _ in fridayKind = nil }
            .onChange(of: prayer) { _, _ in fridayKind = nil }
            .onChange(of: hasUnsavedInput, initial: true) { _, dirty in rootDraftChanged(rootBlockerID, dirty) }
            .onDisappear { rootDraftChanged(rootBlockerID, false) }
        }
    }
    private func save(_ restore: Bool) { session.addOldMissedPrayer(reference, fridayKind: fridayNoon ? fridayKind : nil, restoreDeleted: restore) { success in if success { finished() } } }
    private func title(_ prayer: Prayer) -> String { switch prayer { case .fajr: "الفجر"; case .dhuhr: "الظهر"; case .asr: "العصر"; case .maghrib: "المغرب"; case .isha: "العشاء" } }
}
