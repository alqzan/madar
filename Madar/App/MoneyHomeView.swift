import SwiftUI
import Combine
import MadarCore
import MadarData
import MadarDesign
import MadarMoney
import MadarCommands

struct MoneyHomeView: View {
    private static var lastAccrual = Date.distantPast
    @Bindable var app: AppSession
    var isTabRoot = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.roomVisit) private var roomVisit
    @Environment(\.isFrontRoom) private var isFrontRoom
    @State private var reading: MoneyHomeReading?
    @State private var readingLoadTask: Task<Void, Never>?
    @State private var readingLoadID = UUID()
    @State private var cardCount = 0
    @State private var hawlKey: String?
    @State private var failure: String?
    @State private var isAccruingPlans = false
    @State private var revealed = false
    @State private var basisOpen = false
    @State private var pendingRootRequest = false
    @State private var envelopesOpen = false
    @State private var messagesOpen = false
    @State private var sinceOpen = false
    @State private var obligationsOpen = false
    @State private var categoriesOpen = false
    @State private var cardsOpen = false
    @State private var logOpen = false
    @State private var analysisOpen = false
    @State private var reconcileOpen = false
    @State private var cashbackOpen = false
    @State private var settingsOpen = false
    @State private var accountsOpen = false
    @State private var expenseOpen = false
    @State private var zakatOpen = false
    @State private var goalOpen = false
    @State private var guideOpen = false
    @State private var visitChecked = false
    @State private var routedCardID: UUID?
    @State private var routedCardTab: String?
    @State private var routedCardRequestID: UUID?
    @State private var routedEnvelopeID: UUID?
    @State private var routedEnvelopeRequestID: UUID?
    @State private var routedTransactionID: UUID?
    @State private var routedLogQuery: String?
    @State private var routedLogRequestID: UUID?
    private var service: AppMoneyService { .init(app: app) }
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var amountsVisible: Bool { !app.bool("core.hideMoneyUntilTouch") || revealed }
    /// The daily action. 22 Oct put it as a full-width bar under «لك الآن»; DA-03 (27 Oct) returns it to the canonical
    /// «+» in the header, always in reach, so the envelopes are back on the first screen.
    private var expenseButton: some View {
        Button {
#if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if environment["MADAR_UI_MONEY_FIFO_HARNESS"] == "1",
               environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil {
                app.presentMoneyExpenseSeed(.init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, amount: "١٨", merchant: "طلب أول", homeCurrency: true))
            } else { expenseOpen = true }
#else
            expenseOpen = true
#endif
        } label: {
            Image(systemName: "plus").font(.system(size: 20, weight: .medium)).foregroundStyle(theme.ink)
                .frame(width: 46, height: 46).glassEffect(.regular.interactive(), in: .circle).contentShape(Circle())
        }.buttonStyle(.madarPlain).accessibilityLabel("سجّل مصروفًا").accessibilityIdentifier("money-expense-open")
    }
    /// The room's other doors as drawers of one desk, two to a row, most used first; settings close the desk.
    private var doors: some View {
        MoneyHomeDoors(
            accountsFact: accountsFact,
            reconcileFact: reconcileFact,
            goalFact: goalFact,
            cardsFact: cardsFact,
            zakatFact: zakatFact,
            openLog: openLog,
            openAnalysis: { analysisOpen = true },
            openCards: { cardsOpen = true },
            openAccounts: { accountsOpen = true },
            openReconcile: { reconcileOpen = true },
            openGoal: { goalOpen = true },
            openCashback: { cashbackOpen = true },
            openZakat: { zakatOpen = true },
            openSettings: { settingsOpen = true }
        )
    }
    // «تعمّق وحسّن», all-data walk 24 Oct 2026: a drawer with something in it says one fact; counts only, never amounts.
    private var accountsFact: String? {
        guard let r = reading, r.hasAccounts else { return nil }
        let base = service.counted(r.knownBalanceCount + r.unknownBalanceCount, ("حساب واحد", "حسابان", "حسابات", "حسابًا"))
        // Decision 3: a foreign account with no rate is not guessed into the total; say so.
        guard let first = r.unratedAccountNames.first else { return base }
        let more = r.unratedAccountNames.count - 1
        return base + "، «" + first + "»" + (more > 0 ? " و" + service.counted(more, ("حساب آخر", "حسابان آخران", "حسابات أخرى", "حسابًا آخر")) : "") + " خارج المجموع لأنه بلا سعر صرف"
    }
    private var reconcileFact: String? {
        guard let n = reading?.pendingCount, n > 0 else { return nil }
        return service.counted(n, ("قرار واحد ينتظرك", "قراران ينتظرانك", "قرارات تنتظرك", "قرارًا ينتظرك"))
    }
    private var goalFact: String? {
        guard let n = reading?.envelopes.count, n > 0 else { return nil }
        return service.counted(n, ("هدف واحد", "هدفان", "أهداف", "هدفًا"))
    }
    private var cardsFact: String? {
        cardCount > 0 ? service.counted(cardCount, ("بطاقة واحدة", "بطاقتان", "بطاقات", "بطاقة")) : nil
    }
    /// Go deeper, 25 Oct 2026: the zakat drawer anticipates the hawl instead of sitting silent.
    private var zakatFact: String? {
        guard let key = hawlKey, let hawl = MoneyHawl.read(key, app: app) else { return nil }
        return hawl.daysLeft == 0 ? "حولك اليوم" : "حولك بعد " + service.days(hawl.daysLeft)
    }
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var roomWidth: CGFloat = 0
    private var wide: Bool { isPadWide(sizeClass) && roomWidth >= 960 }
    var body: some View {
        ScrollView { homeContent }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { roomWidth = $0 }
        .madarTopClipped().background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
        .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $envelopesOpen) { MoneyEnvelopesView(app: app, revealed: $revealed, initialEnvelopeID: $routedEnvelopeID, initialRouteRequestID: $routedEnvelopeRequestID) }
        .onChange(of: envelopesOpen) { _, isOpen in if !isOpen { routedEnvelopeID = nil; routedEnvelopeRequestID = nil } }
        .navigationDestination(isPresented: $messagesOpen) { MoneyMessagesView(app: app, revealed: $revealed) }
        .navigationDestination(isPresented: $obligationsOpen) { MoneyObligationsView(app: app) }
        .navigationDestination(isPresented: $categoriesOpen) { MoneyCategoriesView(app: app) }
        .navigationDestination(isPresented: $cardsOpen) { MoneyCardsView(app: app, revealed: $revealed, initialCardID: $routedCardID, initialTab: $routedCardTab, initialRouteRequestID: $routedCardRequestID) }
        .onChange(of: cardsOpen) { _, isOpen in if !isOpen { routedCardID = nil; routedCardTab = nil; routedCardRequestID = nil } }
        .navigationDestination(isPresented: $logOpen) { MoneyLogView(app: app, revealed: $revealed, initialTransactionID: routedTransactionID, initialQuery: routedLogQuery, initialRouteRequestID: routedLogRequestID) }
        .onChange(of: logOpen) { _, isOpen in if !isOpen { routedTransactionID = nil; routedLogQuery = nil; routedLogRequestID = nil } }
        .navigationDestination(isPresented: $analysisOpen) { MoneyAnalysisView(app: app, revealed: $revealed) }
        .navigationDestination(isPresented: $reconcileOpen) { MoneyReconcileView(app: app, revealed: $revealed) }
        .onChange(of: reconcileOpen) { if !reconcileOpen { load() } }
        .navigationDestination(isPresented: $cashbackOpen) { MoneyCashbackView(app: app, revealed: $revealed) }
        .navigationDestination(isPresented: $sinceOpen) {
            if let reading { MoneySinceView(app: app, home: reading, revealed: $revealed) { sinceOpen = false; messagesOpen = true } }
        }
        .navigationDestination(isPresented: $guideOpen) { MoneyShortcutGuideView(app: app) }
        .navigationDestination(isPresented: $goalOpen) { MoneyGoalView(app: app, revealed: $revealed) }
        .onChange(of: goalOpen) { if !goalOpen { load() } }
        .navigationDestination(isPresented: $zakatOpen) { MoneyZakatView(app: app, revealed: $revealed) }
        .navigationDestination(isPresented: $settingsOpen) { MoneySettingsView(app: app, revealed: $revealed) }
        .navigationDestination(isPresented: $accountsOpen) { MoneyAccountsView(app: app, revealed: $revealed) }
        .onChange(of: accountsOpen) { if !accountsOpen { load() } }
        .navigationDestination(isPresented: $expenseOpen) { MoneyExpenseView(app: app, revealed: $revealed) }
        .onChange(of: expenseOpen) { if !expenseOpen { load() } }
        .sheet(isPresented: $basisOpen) { MoneyBasisView(app: app, revealed: $revealed) }
        .task(id: roomVisit) {
            await app.seedMoneyDefaults()
            // Show the saved reading before the bounded accrual command; refresh it when that write settles.
            await loadAndWait()
            guard !Task.isCancelled else { return }
            // Opening the room must not write on every visit (hangs on tab switches): accrue at most once every 5 minutes.
            if Date().timeIntervalSince(Self.lastAccrual) > 300 {
                isAccruingPlans = true
                defer { isAccruingPlans = false }
                do {
                    #if DEBUG
                    let environment = ProcessInfo.processInfo.environment
                    if UUID(uuidString: environment["MADAR_UI_STORE_ID"] ?? "") != nil,
                       let milliseconds = environment["MADAR_UI_MONEY_ACCRUAL_HOLD_MS"].flatMap(Int.init),
                       (1...5_000).contains(milliseconds) {
                        try await Task.sleep(for: .milliseconds(milliseconds))
                    }
                    #endif
                    try await app.executeMoneyCommand("money.accruePlans")
                    Self.lastAccrual = Date()
                }
                catch is CancellationError { return }
                catch { app.errorMessage = "تعذّر تحديث الخطط اليوم: " + madarUserMessage(error) }
                await loadAndWait()
                guard !Task.isCancelled else { return }
            }
            if app.moneyOpensMessages { app.moneyOpensMessages = false; messagesOpen = true; return }
            if app.moneyOpensSettings { app.moneyOpensSettings = false; settingsOpen = true; return }
            // §7.5 «بعد غياب»: «منذ آخر زيارة» opens first; otherwise this visit is the new mark.
            guard !visitChecked, let reading else { return }
            visitChecked = true
            if service.sinceDue(today: reading.cycle?.today ?? GregorianDay.containing(app.prayerNow(), in: app.activePlace.timeZone)) { sinceOpen = true }
            else { try? await app.executeMoneyCommand("money.markVisit") }
        }.onChange(of: app.prayerRevision) { if isFrontRoom { load() } }
        .onChange(of: app.moneyRoute, initial: true) { _, route in if let route { openMoneyRoute(route) } }
        .onChange(of: app.moneyRootRequestID) { _, requestID in
            guard requestID != nil else { return }
            pendingRootRequest = true
            closeForMoneyRootIfSafe()
        }
        .onChange(of: app.moneyRootDraftBlockers.isEmpty) { _, _ in closeForMoneyRootIfSafe() }
        .onChange(of: app.searchRoute, initial: true) { _, route in
            guard let route, route.parameters["room"] == "mal" else { return }
            app.searchRoute = nil
            visitChecked = true
            routedTransactionID = nil
            routedLogQuery = route.parameters["q"] ?? ""
            routedLogRequestID = UUID()
            logOpen = true
        }
        .onChange(of: messagesOpen) { if !messagesOpen { load() } }
        .onChange(of: app.bool("core.hideMoneyUntilTouch")) { revealed = false }
        .onChange(of: app.selectedTab) { revealed = false }
        .onChange(of: scenePhase) { if scenePhase != .active { revealed = false; cancelReadingLoad() } else if isFrontRoom { load() } }
        .onChange(of: isFrontRoom) { _, front in if !front { cancelReadingLoad() } }
        // Left open past midnight, «اليوم» and the cycle day follow the day it is now.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in if isFrontRoom { load() } }
        .accessibilityIdentifier("money-home")
    }
    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if isAccruingPlans {
                Text("جارٍ تحديث الخطط")
                    .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    .accessibilityIdentifier("money-accrual-progress")
                    .transition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isAccruingPlans)
            }
            if let reading {
                dashboard(reading).transition(.opacity)
            } else if let failure {
                readFailure(failure).transition(.opacity)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 300).transition(.opacity)
            }
        }
        .padding(.horizontal, 16).padding(.top, 0).padding(.bottom, 30).frame(maxWidth: wide ? 1100 : 620).frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: reading != nil || failure != nil)
    }
    @ViewBuilder private func dashboard(_ reading: MoneyHomeReading) -> some View {
        let blocks = RoomHomeLayout(session: app, key: "mal.layout").visible
        if wide {
            // iPad landscape: the scroll and today's balance on the right, the desk (envelopes, limits, dues) beside them.
            let lead = blocks.filter { ["curve", "now"].contains($0) }
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) { ForEach(lead, id: \.self) { block($0, reading, blocks) } }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 10) { ForEach(blocks.filter { !lead.contains($0) }, id: \.self) { block($0, reading, blocks) }; doors }.frame(maxWidth: .infinity)
            }
        } else {
            ForEach(blocks, id: \.self) { block($0, reading, blocks) }
            doors
        }
    }
    @ViewBuilder private func block(_ id: String, _ reading: MoneyHomeReading, _ blocks: [String]) -> some View {
            switch id {
            case "curve":
                if let cycle = reading.cycle {
                    if dynamicType.isAccessibilitySize { cycleSummary(cycle) }
                    else { MoneyScrollChart(cycle: cycle, app: app, visible: amountsVisible, obligations: reading.obligations).frame(height: wide ? 300 : 224) }
                }
            case "now":
                if let cycle = reading.cycle { headline(reading, cycle: cycle) }
                else { firstPage(reading) }
                if reading.unknownBalanceCount > 0 {
                    Text("بعض الحسابات لم يُعرف رصيدها بعد؛ لا تدخل في المجموع.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    Button { reconcileOpen = true } label: { Text("المطابقة مع البنك").font(MadarTypography.body()).frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("money-unknown-balance-reconcile")
                }
            case "envelopes": envelopeSection(reading)
            case "limits":
                if blocks.firstIndex(of: "obligations") == blocks.firstIndex(of: "limits").map({ $0 + 1 }) { lowerDesk(reading) }
                else { limits(reading) }
            case "obligations":
                if blocks.firstIndex(of: "obligations") != blocks.firstIndex(of: "limits").map({ $0 + 1 }) { obligations(reading) }
            default: EmptyView()
            }
    }
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("المال").font(MadarTypography.title()).accessibilityIdentifier("money-title")
            if let cycle = reading?.cycle {
                let left = max(0, MadarCalendarDays.distance(from: cycle.today, to: cycle.expectedEndDay))
                Text(left == 0 ? "موعد الراتب اليوم" : "بقي للراتب " + service.days(left)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }
            Spacer(minLength: 0)
            expenseButton.alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
            if let reading {
                // Always reachable: «الصق رسائل» lives inside, for when the Shortcut has stopped.
                let count = reading.pendingCount
                Button { messagesOpen = true } label: {
                    HStack(spacing: 5) { Image(systemName: "tray"); if count > 0 { Text(service.digits.string(count)) } }
                        .font(MadarTypography.fine()).padding(.horizontal, 9).padding(.vertical, 7).frame(minHeight: 44)
                        .overlay { Capsule().stroke(theme.color("reserveText"), lineWidth: 1).padding(.vertical, 6) }
                }.buttonStyle(.madarPlain).accessibilityElement(children: .ignore)
                    .accessibilityLabel(count > 0 ? "رسائل البنك، " + service.pending(count) : "رسائل البنك").accessibilityAddTraits(.isButton).accessibilityIdentifier("money-pending")
            }
            if !isTabRoot {
                Button { dismiss() } label: { Image(systemName: "chevron.backward").font(.body).frame(width: 44, height: 44) }
                    .buttonStyle(.madarPlain).accessibilityLabel("العودة").accessibilityIdentifier("money-back")
            }
        }.frame(minHeight: 48)
    }
    private func headline(_ reading: MoneyHomeReading, cycle: MoneyCycleReading) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Button { basisOpen = true } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("لك الآن").font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)).foregroundStyle(theme.color("reserveText"))
                    displayFigure(amount(cycle.headline.availableNowMinor), "thmanyahserifdisplay-Black", size: 54, relativeTo: .largeTitle)
                        .contentTransition(.numericText()).minimumScaleFactor(0.55).lineLimit(1).accessibilityIdentifier("money-available")
                }
                }.buttonStyle(.madarPlain).accessibilityIdentifier("money-basis-open")
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 7) {
                    Text("صافي رصيدك").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    Text(figure: !reading.hasKnownBalance ? "—" : amount(reading.basis.netMinor)).font(MadarTypography.cardTitle()).accessibilityIdentifier("money-net")
                    // DA-03: today's spending takes the currency line's place, so the hero is one row as in the canonical.
                    Text(figure: "اليوم: صرفت " + amount(cycle.headline.todaySpentMinor) + " من " + amount(cycle.headline.todayAllowanceMinor))
                        .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-today")
                }
            }
            if let over = cycle.headline.overTodayMinor {
                Text(figure: "تجاوزت يومك بـ" + amount(over)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-over-today")
            }
            if let over = cycle.headline.overCycleMinor {
                Text(figure: "تجاوزت استحقاق الدورة بـ" + amount(over)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-over-cycle")
            }
            if !amountsVisible {
                Button { revealed = true } label: { Text("أظهر الأرقام").font(MadarTypography.caption()).frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("money-reveal")
            }
        }.accessibilityElement(children: .contain)
    }
    private func firstPage(_ reading: MoneyHomeReading) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                Capsule().fill(theme.color("rod2")).frame(width: 14)
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "sparkle").foregroundStyle(theme.color("reserveText"))
                    Text(reading.hasAccounts ? "مالك جاهز لدورته" : "صفحة مالك الأولى").font(MadarTypography.title())
                    Text(reading.hasAccounts ? "حساباتك وحركاتك هنا. يظهر يومك ومنحنى الصرف حين يصل راتبك وتبدأ دورتك." : "سيجتمع هنا يومك، وما تدّخره، وما يستحق قريبًا. تبدأ الأرقام من بياناتك.")
                        .font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                }.padding(22).frame(maxWidth: .infinity, minHeight: 200).background(theme.surface)
                Capsule().fill(theme.color("rod2")).frame(width: 14)
            }.accessibilityIdentifier("money-empty")
            // With accounts already here, the one missing step is the salary that opens the cycle: it leads, and
            // adding an account is no longer offered as if the room were empty (owner data trial, 23 Oct).
            if reading.hasAccounts {
                Button { messagesOpen = true } label: { Text("ابدأ دورتك برسالة الراتب").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 48).background(theme.ink, in: Capsule()).foregroundStyle(theme.background).contentShape(Rectangle()) }.accessibilityIdentifier("money-first-salary")
                Button { guideOpen = true } label: { Text("إعداد استقبال رسائل البنك").font(MadarTypography.body()).frame(maxWidth: .infinity, minHeight: 46).glassEffect(.regular.interactive(), in: .capsule).contentShape(Rectangle()) }.accessibilityIdentifier("money-guide-open")
            } else {
                Button { guideOpen = true } label: { Text("إعداد استقبال رسائل البنك").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 48).background(theme.ink, in: Capsule()).foregroundStyle(theme.background).contentShape(Rectangle()) }.accessibilityIdentifier("money-guide-open")
                Button { accountsOpen = true } label: { Text("أضف حسابك يدويًا").font(MadarTypography.body()).frame(maxWidth: .infinity, minHeight: 46).glassEffect(.regular.interactive(), in: .capsule).contentShape(Rectangle()) }.accessibilityIdentifier("money-first-account")
                Button { messagesOpen = true } label: { Text("ابدأ برسالة الراتب").font(MadarTypography.body()).frame(maxWidth: .infinity, minHeight: 46).glassEffect(.regular.interactive(), in: .capsule).contentShape(Rectangle()) }.accessibilityIdentifier("money-first-salary")
            }
            if reading.hasAccounts {
                Button { basisOpen = true } label: {
                    HStack {
                        Text(reading.unknownBalanceCount > 0 ? "الأرصدة المعروفة" : "في حسابك")
                        Spacer()
                        Text(figure: !reading.hasKnownBalance ? "—" : amount(reading.basis.inAccountMinor))
                            .font(MadarTypography.cardTitle())
                        Image(systemName: "chevron.left").font(.caption)
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect) // the whole row, Spacer included (owner-data walk 25 Oct)
                }
                .buttonStyle(.madarPlain)
                .accessibilityLabel(!reading.hasKnownBalance ? "على أي أساس، لم يُعرف رصيد الحسابات بعد" : "على أي أساس، الأرصدة المعروفة " + amount(reading.basis.inAccountMinor))
                .accessibilityIdentifier("money-basis-open")
                if !amountsVisible { Button { revealed = true } label: { Text("أظهر الأرقام").frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("money-reveal") }
            }
        }
    }
    private func envelopeSection(_ reading: MoneyHomeReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { envelopesOpen = true } label: { HStack { sectionTitle("المظاريف", color: theme.color("accent")); Image(systemName: "chevron.left").font(.caption) }.frame(minHeight: 44) }.buttonStyle(.madarPlain).accessibilityIdentifier("money-envelopes-open")
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("الاحتياطي").font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)).foregroundStyle(theme.color("reserveText"))
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(figure: amountsVisible && reading.envelopes.isEmpty && reading.reserveMinor == 0 ? "لم يبدأ بعد" : amount(reading.reserveMinor)).font(MadarTypography.cardTitle()).accessibilityIdentifier("money-reserve")
                        if amountsVisible, let runway = reading.reserveRunway {
                            Text(Self.runwayPhrase(runway.days, digits: service.digits, days: service.days)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(2)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicType.isAccessibilitySize && amountsVisible && reading.reserveMinor > 0 {
                    MoneyReserveSquares(days: reading.reserveDailies ?? 0).frame(width: 152, height: 42)
                }
            }
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("الفائض").font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)).foregroundStyle(theme.color("surplusText"))
                    Text(figure: amountsVisible && reading.envelopes.isEmpty && reading.surplusMinor == 0 ? "يتجمع مع دوراتك" : amount(reading.surplusMinor)).font(MadarTypography.cardTitle()).accessibilityIdentifier("money-surplus")
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicType.isAccessibilitySize && amountsVisible && reading.surplusHistory.contains(where: { $0 != 0 }) {
                    MoneyWaterfall(values: reading.surplusHistory).frame(width: 152, height: 38)
                }
            }
            if reading.envelopes.isEmpty {
                Button { goalOpen = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "envelope.open").font(.title2).foregroundStyle(theme.color("accentText"))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("لشيء تخطّط له").font(MadarTypography.body())
                            Text("أضف مظروفًا وخصّص له من مالك").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.left").font(.caption)
                    }.padding(14).frame(maxWidth: .infinity, minHeight: 64).background(theme.surface, in: .rect(cornerRadius: 12))
                }.buttonStyle(.madarPlain).accessibilityIdentifier("money-envelope-empty-create")
            } else {
                ForEach(reading.envelopes) { envelope in MoneyEnvelopeLine(envelope: envelope, app: app, visible: amountsVisible) }
            }
        }
    }
    private func lowerDesk(_ reading: MoneyHomeReading) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                limits(reading).frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(theme.line).frame(width: 1, height: 126)
                obligations(reading).frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 16) { limits(reading); obligations(reading) }
        }.padding(.top, 12).overlay(alignment: .top) { DoubleRule().stroke(theme.color("reserveText"), lineWidth: 0.8).frame(height: 3) }
    }
    private func limits(_ reading: MoneyHomeReading) -> some View {
        Button { categoriesOpen = true } label: { limitsList(reading).contentShape(Rectangle()) }
            .buttonStyle(.madarPlain).accessibilityIdentifier("money-categories-open")
    }
    /// «يكفيك ٦ أشهر و١١ يومًا» matches the month rods; under a month it stays in days.
    static func runwayPhrase(_ total: Int, digits: MadarNumberFormatter, days: (Int) -> String) -> String {
        let m = total / 30, rest = total % 30
        guard m > 0 else { return "يكفيك " + days(total) }
        let months = m == 1 ? "شهرًا" : m == 2 ? "شهرين" : digits.string(m) + ((3...10).contains(m % 100) ? " أشهر" : " شهرًا")
        return "يكفيك " + months + (rest > 0 ? " و" + days(rest) : "")
    }
    private func limitsList(_ reading: MoneyHomeReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("حدود الصرف").font(MadarTypography.cardTitle()).foregroundStyle(theme.color("surplusText"))
            if reading.limits.isEmpty { Text("لا حدود مضافة").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
            ForEach(reading.limits.prefix(4)) { limit in
                HStack(spacing: 8) {
                    if !dynamicType.isAccessibilitySize && amountsVisible {
                        ZStack {
                            Circle().stroke(theme.line, lineWidth: 4)
                            Circle().trim(from: 0, to: limit.limitMinor > 0 ? min(1, Double(max(0, limit.spentMinor)) / Double(limit.limitMinor)) : limit.spentMinor > 0 ? 1 : 0)
                                .stroke(theme.color(limit.limitMinor > 0 && limit.spentMinor > limit.limitMinor ? "debt" : "surplus"), style: .init(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                        }.frame(width: 26, height: 26).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(limit.title).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        Text(figure: amount(limit.spentMinor)).font(MadarTypography.section())
                        // The bare figure did not say spent or left; the limit beside it does.
                        if limit.limitMinor > 0 { Text(figure: "من " + amount(limit.limitMinor)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.8) }
                    }
                }.accessibilityElement(children: .combine)
            }
            }
        }
    }
    private func obligations(_ reading: MoneyHomeReading) -> some View {
        Button { obligationsOpen = true } label: { obligationsList(reading).contentShape(Rectangle()) }
            .buttonStyle(.madarPlain).accessibilityIdentifier("money-obligations-open")
    }
    private func obligationsList(_ reading: MoneyHomeReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text("الالتزامات").font(MadarTypography.cardTitle()).foregroundStyle(theme.color("bills"))
                Image(systemName: "chevron.left").font(.caption.bold()).foregroundStyle(theme.color("bills"))
            }
            if reading.obligations.isEmpty { Text("لا مواعيد مسجّلة").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
            ForEach(reading.obligations.prefix(3)) { obligation in
                HStack(alignment: .top, spacing: 7) {
                    DiamondMark().stroke(theme.color("reserveText"), lineWidth: 1).frame(width: 12, height: 14).padding(.top, 3).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(obligation.name).font(MadarTypography.caption()).lineLimit(1)
                        MadarDateLabel(app.dateLabels(obligation.due, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    }
                    Spacer(minLength: 0)
                    Text(figure: amount(obligation.amountMinor)).font(MadarTypography.section()).fixedSize()
                }.accessibilityElement(children: .combine)
            }
        }
    }
    private func sectionTitle(_ title: String, color: Color) -> some View {
        HStack { Text(title).font(MadarTypography.cardTitle()).foregroundStyle(color); Rectangle().fill(theme.line).frame(height: 1) }
    }
    private func cycleSummary(_ cycle: MoneyCycleReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("دورتك").font(MadarTypography.cardTitle())
            MadarDateLabel(app.dateLabels(cycle.startDay))
            Text("حتى").font(MadarTypography.caption())
            MadarDateLabel(app.dateLabels(cycle.expectedEndDay))
        }.padding(16).background(theme.surface, in: .rect(cornerRadius: 16))
    }
    private func amount(_ value: Int) -> String { amountsVisible ? service.amount(value) : "•••" }
    private func beginReadingLoad() -> UUID {
        readingLoadTask?.cancel()
        let id = UUID()
        readingLoadID = id
        return id
    }
    private func load() {
        let id = beginReadingLoad()
        readingLoadTask = Task { await applyReadingLoad(id) }
    }
    private func loadAndWait() async {
        let id = beginReadingLoad()
        let task = Task { await applyReadingLoad(id) }
        readingLoadTask = task
        await task.value
    }
    private func applyReadingLoad(_ id: UUID) async {
        do {
            let value = try await service.loadOffMain()
            guard !Task.isCancelled, readingLoadID == id else { return }
            reading = value
            cardCount = value.cardCount
            hawlKey = value.hawlKey
            failure = nil
            if let route = app.moneyRoute { openMoneyRoute(route) }
        }
        catch is CancellationError { return }
        catch MoneyCommandError.missingRate {
            guard !Task.isCancelled, readingLoadID == id else { return }
            failure = "عندك حساب بعملة غير عملة البيت بلا سعر تحويل، ومدار لا يخمّن الأرقام. افتح «الحسابات» وصحّح عملة الحساب إن كانت خطأ، أو أدخل سعر الصرف من «السفر»."
            reading = nil
        }
        catch {
            // A passing failure (busy store, locked data) keeps the last good reading on screen; only a first load shows the failure page.
            guard !Task.isCancelled, readingLoadID == id else { return }
            if reading == nil { failure = "تعذّرت قراءة البيانات الآن. أعد المحاولة." }
        }
    }
    private func cancelReadingLoad() {
        readingLoadID = UUID()
        readingLoadTask?.cancel()
        readingLoadTask = nil
    }
    private func closeForMoneyRootIfSafe() {
        guard pendingRootRequest, app.moneyRootDraftBlockers.isEmpty else { return }
        pendingRootRequest = false
        basisOpen = false; envelopesOpen = false; messagesOpen = false; sinceOpen = false; obligationsOpen = false
        categoriesOpen = false; cardsOpen = false; logOpen = false; analysisOpen = false; reconcileOpen = false
        cashbackOpen = false; settingsOpen = false; accountsOpen = false; expenseOpen = false; zakatOpen = false
        goalOpen = false; guideOpen = false
    }
    private func openMoneyRoute(_ route: Route) {
        guard route.room == .mal else { return }
        switch route.path.first {
        case "categories" where route.path.count == 1:
            app.moneyRoute = nil
            categoriesOpen = true
        case "reconcile" where route.path.count == 1:
            app.moneyRoute = nil
            reconcileOpen = true
        case "zakat" where route.path.count == 1:
            app.moneyRoute = nil
            zakatOpen = true
        case "messages" where route.path.count == 1:
            app.moneyRoute = nil
            messagesOpen = true
        case "card" where route.path.count == 2:
            guard let rawID = route.path.last, let id = UUID(uuidString: rawID) else { app.moneyRoute = nil; return }
            routedCardID = id
            routedCardTab = ["overview": "نظرة", "cash": "متى يخرج النقد", "calendar": "تقويم السداد", "match": "المطابقة"][route.parameters["tab"] ?? "overview"]
            routedCardRequestID = UUID()
            app.moneyRoute = nil
            cardsOpen = true
        case "envelope" where route.path.count == 2:
            guard let rawID = route.path.last, let id = UUID(uuidString: rawID) else { app.moneyRoute = nil; return }
            routedEnvelopeID = id
            routedEnvelopeRequestID = UUID()
            app.moneyRoute = nil
            envelopesOpen = true
        case "tx" where route.path.count == 2:
            guard let rawID = route.path.last, let id = UUID(uuidString: rawID) else { app.moneyRoute = nil; return }
            routedTransactionID = id
            routedLogQuery = nil
            routedLogRequestID = UUID()
            app.moneyRoute = nil
            logOpen = true
        default:
            app.moneyRoute = nil
        }
    }
    private func openLog() {
        routedTransactionID = nil
        routedLogQuery = nil
        routedLogRequestID = UUID()
        logOpen = true
    }
    private func readFailure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("لم تكتمل قراءة المال").font(MadarTypography.cardTitle())
            Text(message).font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
            Button("أعِد المحاولة", action: load).frame(minHeight: 44)
            Button { accountsOpen = true } label: { Text("الحسابات").frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("money-accounts-open")
        }.padding(20)
    }
}

struct DoubleRule: Shape {
    func path(in rect: CGRect) -> Path { Path { p in p.move(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: rect.width, y: 0)); p.move(to: .init(x: 0, y: 3)); p.addLine(to: .init(x: rect.width, y: 3)) } }
}
struct DiamondMark: Shape {
    func path(in r: CGRect) -> Path { Path { p in p.move(to: .init(x: r.midX, y: r.minY)); p.addLine(to: .init(x: r.maxX, y: r.midY)); p.addLine(to: .init(x: r.midX, y: r.maxY)); p.addLine(to: .init(x: r.minX, y: r.midY)); p.closeSubpath() } }
}
