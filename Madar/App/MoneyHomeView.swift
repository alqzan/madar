import SwiftUI
import MadarCore
import MadarData
import MadarDesign
import MadarMoney
import MadarCommands

struct MoneyHomeView: View {
    @Bindable var app: AppSession
    var isTabRoot = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.scenePhase) private var scenePhase
    @State private var reading: MoneyHomeReading?
    @State private var failure: String?
    @State private var revealed = false
    @State private var basisOpen = false
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
    private var service: AppMoneyService { .init(app: app) }
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var amountsVisible: Bool { !app.bool("core.hideMoneyUntilTouch") || revealed }
    /// Owner, «تعمّق وحسّن» 22 Oct 2026: the daily action sits under «لك الآن», not at the foot of ten equal buttons.
    private var expenseButton: some View {
        Button { expenseOpen = true } label: {
            Label("سجّل مصروفًا", systemImage: "plus").font(MadarTypography.body().weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(theme.onAccent).background(theme.accent, in: .capsule)
        }.buttonStyle(.plain).padding(.vertical, 4).accessibilityIdentifier("money-expense-open")
    }
    /// The room's other doors as drawers of one desk, two to a row, most used first; settings close the desk.
    private var doors: some View {
        VStack(spacing: 10) {
            // Not lazy: eight drawers are cheap, and every door must exist before it scrolls into view.
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    drawer("السجل", "book.pages", "money-log-open") { logOpen = true }
                    drawer("التحليل", "chart.bar.xaxis", "money-analysis-open") { analysisOpen = true }
                }
                GridRow {
                    drawer("البطاقات", "creditcard", "money-cards-open") { cardsOpen = true }
                    drawer("الحسابات", "tree", "money-accounts-open", fact: accountsFact) { accountsOpen = true }
                }
                GridRow {
                    drawer("المطابقة مع البنك", "checkmark.seal", "money-reconcile-open", fact: reconcileFact) { reconcileOpen = true }
                    drawer("جهّز لشيء قادم", "sparkles", "money-goal-open", fact: goalFact) { goalOpen = true }
                }
                GridRow {
                    drawer("الاسترداد النقدي", "drop", "money-cashback-open") { cashbackOpen = true }
                    drawer("الزكاة", "scalemass", "money-zakat-open") { zakatOpen = true }
                }
            }
            Button { settingsOpen = true } label: {
                Label("إعدادات المال", systemImage: "slider.horizontal.3").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).frame(minHeight: 44)
            }.buttonStyle(.plain).accessibilityIdentifier("money-settings-open")
        }.padding(.top, 8)
    }
    // «تعمّق وحسّن», all-data walk 24 Oct 2026: a drawer with something in it says one fact; counts only, never amounts.
    private var accountsFact: String? {
        guard let r = reading, r.hasAccounts else { return nil }
        return service.counted(r.knownBalanceCount + r.unknownBalanceCount, ("حساب واحد", "حسابان", "حسابات", "حسابًا"))
    }
    private var reconcileFact: String? {
        guard let n = reading?.pendingCount, n > 0 else { return nil }
        return service.counted(n, ("قرار واحد ينتظرك", "قراران ينتظرانك", "قرارات تنتظرك", "قرارًا ينتظرك"))
    }
    private var goalFact: String? {
        guard let n = reading?.envelopes.count, n > 0 else { return nil }
        return service.counted(n, ("هدف واحد", "هدفان", "أهداف", "هدفًا"))
    }
    private func drawer(_ title: String, _ symbol: String, _ id: String, fact: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.system(size: 18, weight: .regular)).foregroundStyle(theme.color("reserveText"))
                Text(title).font(MadarTypography.body()).lineLimit(2).minimumScaleFactor(0.85).multilineTextAlignment(.leading)
                if let fact { Text(fact).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.85) }
                // The drawer's brass pull.
                Capsule().fill(theme.color("reserveText").opacity(0.55)).frame(width: 22, height: 3).frame(maxWidth: .infinity).accessibilityHidden(true)
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(theme.surface, in: .rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.color("reserveText").opacity(0.45), lineWidth: 1) }
            .contentShape(.rect(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(fact ?? "").accessibilityIdentifier(id)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                if let reading {
                    if let cycle = reading.cycle {
                        if dynamicType.isAccessibilitySize { cycleSummary(cycle) }
                        else { MoneyScrollChart(cycle: cycle, app: app, visible: amountsVisible, obligations: reading.obligations).frame(height: 224) }
                        headline(reading, cycle: cycle)
                    } else { firstPage(reading) }
                    if reading.unknownBalanceCount > 0 {
                        Text("بعض الحسابات لم يُعرف رصيدها بعد؛ لا تدخل في المجموع.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        Button("المطابقة مع البنك") { reconcileOpen = true }.font(MadarTypography.body()).frame(minHeight: 44).accessibilityIdentifier("money-unknown-balance-reconcile")
                    }
                    expenseButton
                    envelopeSection(reading)
                    lowerDesk(reading)
                    doors
                } else if let failure {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("لم تكتمل قراءة المال").font(MadarTypography.cardTitle())
                        Text(failure).font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                        Button("أعِد المحاولة", action: load).frame(minHeight: 44)
                        Button("الحسابات") { accountsOpen = true }.frame(minHeight: 44).accessibilityIdentifier("money-accounts-open")
                    }.padding(20)
                } else { ProgressView().frame(maxWidth: .infinity, minHeight: 300) }
            }.padding(.horizontal, 16).padding(.top, 0).padding(.bottom, 30).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .clipped().background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
        .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $envelopesOpen) { MoneyEnvelopesView(app: app, revealed: $revealed) }
        .navigationDestination(isPresented: $messagesOpen) { MoneyMessagesView(app: app, revealed: $revealed) }
        .navigationDestination(isPresented: $obligationsOpen) { MoneyObligationsView(app: app) }
        .navigationDestination(isPresented: $categoriesOpen) { MoneyCategoriesView(app: app) }
        .navigationDestination(isPresented: $cardsOpen) { MoneyCardsView(app: app, revealed: $revealed) }
        .navigationDestination(isPresented: $logOpen) { MoneyLogView(app: app, revealed: $revealed) }
        .navigationDestination(isPresented: $analysisOpen) { MoneyAnalysisView(app: app, revealed: $revealed) }
        .navigationDestination(isPresented: $reconcileOpen) { MoneyReconcileView(app: app, revealed: $revealed) }
        .onChange(of: reconcileOpen) { if !reconcileOpen { load() } }
        .navigationDestination(isPresented: $cashbackOpen) { MoneyCashbackView(app: app, revealed: $revealed) }
        .navigationDestination(isPresented: $sinceOpen) {
            if let reading { MoneySinceView(app: app, home: reading, revealed: $revealed) { sinceOpen = false; messagesOpen = true; Task { try? await app.executeMoneyCommand("money.markVisit") } } }
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
        .task {
            await app.seedMoneyDefaults()
            do { try await app.executeMoneyCommand("money.accruePlans") } catch { }
            load()
            // §7.5 «بعد غياب»: «منذ آخر زيارة» opens first; otherwise this visit is the new mark.
            guard !visitChecked, let reading else { return }
            visitChecked = true
            if service.sinceDue(today: reading.cycle?.today ?? GregorianDay.containing(app.prayerNow(), in: app.activePlace.timeZone)) { sinceOpen = true }
            else { try? await app.executeMoneyCommand("money.markVisit") }
        }.onChange(of: app.prayerRevision) { load() }
        .onChange(of: messagesOpen) { if !messagesOpen { load() } }
        .onChange(of: app.bool("core.hideMoneyUntilTouch")) { revealed = false }
        .onChange(of: app.selectedTab) { revealed = false }
        .onChange(of: scenePhase) { if scenePhase != .active { revealed = false } }
        .accessibilityIdentifier("money-home")
    }
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("المال").font(MadarTypography.title()).accessibilityIdentifier("money-title")
            if let cycle = reading?.cycle {
                let left = max(0, MadarCalendarDays.distance(from: cycle.today, to: cycle.expectedEndDay))
                Text(left == 0 ? "موعد الراتب اليوم" : "بقي للراتب " + service.days(left)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }
            Spacer(minLength: 0)
            if let reading {
                // Always reachable: «الصق رسائل» lives inside, for when the Shortcut has stopped.
                let count = reading.pendingCount
                Button { messagesOpen = true } label: {
                    HStack(spacing: 5) { Image(systemName: "tray"); if count > 0 { Text(service.digits.string(count)) } }
                        .font(MadarTypography.fine()).padding(.horizontal, 9).padding(.vertical, 7).frame(minHeight: 44)
                        .overlay { Capsule().stroke(theme.color("reserveText"), lineWidth: 1).padding(.vertical, 6) }
                }.buttonStyle(.plain).accessibilityElement(children: .ignore)
                    .accessibilityLabel(count > 0 ? "رسائل البنك، " + service.pending(count) : "رسائل البنك").accessibilityAddTraits(.isButton).accessibilityIdentifier("money-pending")
            }
            if !isTabRoot {
                Button { dismiss() } label: { Image(systemName: "chevron.backward").font(.body).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("العودة").accessibilityIdentifier("money-back")
            }
        }.frame(minHeight: 48)
    }
    private func headline(_ reading: MoneyHomeReading, cycle: MoneyCycleReading) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("اليوم").font(MadarTypography.section())
                Spacer()
                Text(figure: "صرفت " + amount(cycle.headline.todaySpentMinor) + " من " + amount(cycle.headline.todayAllowanceMinor))
                    .font(MadarTypography.body()).accessibilityIdentifier("money-today")
            }
            HStack(alignment: .center) {
                Button { basisOpen = true } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("لك الآن").font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)).foregroundStyle(theme.color("reserveText"))
                    displayFigure(amount(cycle.headline.availableNowMinor), "thmanyahserifdisplay-Black", size: 54, relativeTo: .largeTitle)
                        .contentTransition(.numericText()).minimumScaleFactor(0.55).lineLimit(1).accessibilityIdentifier("money-available")
                }
                }.buttonStyle(.plain).accessibilityIdentifier("money-basis-open")
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 7) {
                    Text("لك فعلًا").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    Text(figure: reading.knownBalanceCount == 0 && reading.unknownBalanceCount > 0 ? "—" : amount(reading.basis.netMinor)).font(MadarTypography.cardTitle()).accessibilityIdentifier("money-net")
                    Text(reading.currency == "SAR" ? "ريال سعودي" : reading.currency).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }
            }
            if let over = cycle.headline.overTodayMinor {
                Text(figure: "تجاوزت يومك بـ" + amount(over)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-over-today")
            }
            if let over = cycle.headline.overCycleMinor {
                Text(figure: "تجاوزت استحقاق الدورة بـ" + amount(over)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-over-cycle")
            }
            if !amountsVisible {
                Button("أظهر الأرقام") { revealed = true }.font(MadarTypography.caption()).frame(minHeight: 44).accessibilityIdentifier("money-reveal")
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
                Button("ابدأ دورتك برسالة الراتب") { messagesOpen = true }.font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 48).background(theme.ink, in: Capsule()).foregroundStyle(theme.background).accessibilityIdentifier("money-first-salary")
                Button("إعداد استقبال رسائل البنك") { guideOpen = true }.font(MadarTypography.body()).frame(minHeight: 44).accessibilityIdentifier("money-guide-open")
            } else {
                Button("إعداد استقبال رسائل البنك") { guideOpen = true }.font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 48).background(theme.ink, in: Capsule()).foregroundStyle(theme.background).accessibilityIdentifier("money-guide-open")
                Button("أضف حسابك يدويًا") { accountsOpen = true }.font(MadarTypography.body()).frame(minHeight: 44).accessibilityIdentifier("money-first-account")
                Button("ابدأ برسالة الراتب") { messagesOpen = true }.font(MadarTypography.body()).frame(minHeight: 44).accessibilityIdentifier("money-first-salary")
            }
            if reading.hasAccounts {
                Button { basisOpen = true } label: {
                    HStack { Text(reading.unknownBalanceCount > 0 ? "الأرصدة المعروفة" : "في حسابك"); Spacer(); Text(figure: reading.knownBalanceCount == 0 && reading.unknownBalanceCount > 0 ? "—" : amount(reading.basis.inAccountMinor)).font(MadarTypography.cardTitle()); Image(systemName: "chevron.left").font(.caption) }.frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel(reading.knownBalanceCount == 0 && reading.unknownBalanceCount > 0 ? "على أي أساس، لم يُعرف رصيد الحسابات بعد" : "على أي أساس، الأرصدة المعروفة " + amount(reading.basis.inAccountMinor))
                if !amountsVisible { Button("أظهر الأرقام") { revealed = true }.frame(minHeight: 44).accessibilityIdentifier("money-reveal") }
            }
        }
    }
    private func envelopeSection(_ reading: MoneyHomeReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { envelopesOpen = true } label: { HStack { sectionTitle("المظاريف", color: theme.color("accent")); Image(systemName: "chevron.left").font(.caption) }.frame(minHeight: 44) }.buttonStyle(.plain).accessibilityIdentifier("money-envelopes-open")
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("الاحتياطي").font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)).foregroundStyle(theme.color("reserveText"))
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(figure: amountsVisible && reading.envelopes.isEmpty && reading.reserveMinor == 0 ? "لم يبدأ بعد" : amount(reading.reserveMinor)).font(MadarTypography.cardTitle()).accessibilityIdentifier("money-reserve")
                        if amountsVisible, let runway = reading.reserveRunway {
                            Text(service.days(runway.days)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
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
                }.buttonStyle(.plain).accessibilityIdentifier("money-envelope-empty-create")
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
            .buttonStyle(.plain).accessibilityIdentifier("money-categories-open")
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
                                .stroke(theme.color("surplus"), style: .init(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                        }.frame(width: 26, height: 26).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(limit.title).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        Text(figure: amount(limit.spentMinor)).font(MadarTypography.section())
                    }
                }.accessibilityElement(children: .combine)
            }
            }
        }
    }
    private func obligations(_ reading: MoneyHomeReading) -> some View {
        Button { obligationsOpen = true } label: { obligationsList(reading).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityIdentifier("money-obligations-open")
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
    private func load() {
        do { reading = try service.load(); failure = nil }
        catch MoneyCommandError.missingRate { failure = "يلزم سعر تحويل يدوي لجمع أرصدتك بعملة البيت."; reading = nil }
        catch { failure = "تعذّرت قراءة البيانات الآن. أعد المحاولة."; reading = nil }
    }
}

struct DoubleRule: Shape {
    func path(in rect: CGRect) -> Path { Path { p in p.move(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: rect.width, y: 0)); p.move(to: .init(x: 0, y: 3)); p.addLine(to: .init(x: rect.width, y: 3)) } }
}
struct DiamondMark: Shape {
    func path(in r: CGRect) -> Path { Path { p in p.move(to: .init(x: r.midX, y: r.minY)); p.addLine(to: .init(x: r.maxX, y: r.midY)); p.addLine(to: .init(x: r.midX, y: r.maxY)); p.addLine(to: .init(x: r.minX, y: r.midY)); p.closeSubpath() } }
}
