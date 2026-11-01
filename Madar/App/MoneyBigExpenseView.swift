import SwiftUI
import MadarCore
import MadarDesign
import MadarMoney

struct MoneyBigExpenseView: View {
    let app: AppSession
    let route: MoneyBigExpenseRoute
    @Binding var revealed: Bool
    let completed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var reading: MoneyBigExpenseReading?
    @State private var mode = BigExpense.Mode.mixed
    @State private var cycles: Int?
    @State private var envelopeID: UUID?
    @State private var newEnvelopeID = UUID()
    @State private var name = ""
    @State private var failure: String?
    @State private var saving = false
    @State private var editingName = false
    @FocusState private var editing: Bool
    private var service: AppMoneyService { .init(app: app) }
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private func amount(_ n: Int) -> String { visible ? service.amount(n) : "•••" }
    private var plan: BigExpense.Plan? {
        guard let r = reading, let c = r.home.cycle else { return nil }
        return BigExpense.plan(amountMinor: r.amountMinor, mode: mode, availableMinor: c.headline.availableNowMinor,
            surplusMinor: r.home.surplusMinor, reserveMinor: r.home.reserveMinor, dailyMinor: c.headline.todayAllowanceMinor,
            cycleDays: c.input.expectedLengthDays, cycles: cycles, envelopeBalanceMinor: r.home.envelopes.first { $0.id == envelopeID }?.balanceMinor ?? 0)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1) } }.disabled(saving).accessibilityLabel("إغلاق").accessibilityIdentifier("money-big-close")
                        Text("مصروف كبير").font(.custom("thmanyahserifdisplay-Bold", size: 24, relativeTo: .title2)); Spacer()
                    }
                    if let r = reading {
                        heading(r)
                        HStack(spacing: 0) { ForEach(BigExpense.Mode.allCases, id: \.rawValue) { m in
                            Button { mode = m; cycles = nil; failure = nil } label: { Text(title(m)).font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 44).background(m == mode ? theme.ink : .clear).foregroundStyle(m == mode ? theme.background : theme.ink) }.accessibilityIdentifier("money-big-mode-" + m.rawValue)
                        } }.overlay { Rectangle().stroke(theme.color("reserveText"), lineWidth: 1) }
                        if !visible { Button("أظهر الأرقام") { revealed = true }.frame(minHeight: 44).accessibilityIdentifier("money-big-reveal") }
                        if let p = plan {
                            distribution(p, amount: r.amountMinor)
                            effect(p, reading: r)
                            if p.futureMinor > 0 {
                                VStack(alignment: .leading, spacing: 12) {
                                    if p.repaymentMinor > 0 {
                                    HStack { Text("سداده على").font(MadarTypography.caption()); Spacer();
                                        Menu { ForEach(1...12, id: \.self) { n in Button(service.counted(n, ("دورة واحدة", "دورتان", "دورات", "دورةً"))) { cycles = n } } } label: { Text(service.counted(p.cycles, ("دورة واحدة", "دورتان", "دورات", "دورةً"))).font(MadarTypography.body()); Image(systemName: "chevron.down") }.accessibilityIdentifier("money-big-cycles")
                                    }
                                    Text("سداد مستقل، لا يزيد على ثلث يومك.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                                    } else { Text("يغطيه رصيد المظروف؛ لا اقتطاع قادم.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                                    ScrollView(.horizontal) { HStack(spacing: 7) {
                                        Button { if envelopeID == nil { editingName.toggle() }; envelopeID = nil } label: { envelopeChip("مظروف جديد: " + name, selected: envelopeID == nil) }.accessibilityIdentifier("money-big-new-envelope")
                                        ForEach(r.home.envelopes) { e in Button { envelopeID = e.id } label: { envelopeChip(e.name, selected: envelopeID == e.id) }.accessibilityIdentifier("money-big-envelope-" + e.name) }
                                    } }.scrollIndicators(.hidden)
                                    if envelopeID == nil && editingName { TextField("اسم المظروف", text: $name).focused($editing).font(MadarTypography.body()).frame(minHeight: 44).accessibilityIdentifier("money-big-name") }
                                }
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text("دفعته بـ").font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)); Text(r.payment).font(MadarTypography.body()) }
                                Text(route.transactionID == nil ? "مصدر الدفع الذي اخترته" : "من رسالة البنك؛ الشراء حركة واحدة").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                                MadarDateLabel(app.dateLabels(.containing(r.at, in: app.activePlace.timeZone)), primaryFont: MadarTypography.caption(), secondaryFont: MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                            }.padding(.top, 10)
                            if let failure { Text(failure).font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")) }
                            Button { save(p, r) } label: { Text(saving ? "جارٍ الاعتماد…" : "اعتمد التوزيع").font(MadarTypography.cardTitle()).frame(maxWidth: .infinity, minHeight: 54).background(theme.ink).foregroundStyle(theme.background) }.disabled(saving || !visible || (p.futureMinor > 0 && envelopeID == nil && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)).accessibilityIdentifier("money-big-save")
                        } else {
                            Text(reading?.home.cycle == nil ? "تحتاج دورة مالية لحساب أثر التوزيع." : mode == .reserve ? "الاحتياطي لا يكفي لهذا المبلغ. اختر توزيعًا آخر." : "هذا السداد يتجاوز ثلث يومك أو اثنتي عشرة دورة. جرّب المزج أو الاحتياطي.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).padding(.vertical, 30).accessibilityIdentifier("money-big-unavailable")
                            if cycles != nil { Button("اختر أقصر مدة ممكنة") { cycles = nil }.frame(minHeight: 44) }
                        }
                    } else if let failure { Text(failure); Button("أعِد المحاولة", action: load) }
                    else { ProgressView().frame(height: 200) }
                }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively).background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).buttonStyle(.madarPlain)
                .interactiveDismissDisabled(saving)
                .toolbar(.hidden, for: .navigationBar).toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("تمّ") { editing = false } } }
                .task { load() }.accessibilityIdentifier("money-big")
        }
    }
    private func heading(_ r: MoneyBigExpenseReading) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(r.title).font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
            HStack(alignment: .firstTextBaseline) {
                MoneyFigure(value: amount(r.amountMinor), style: MoneyFigureStyle(app), size: 52).accessibilityIdentifier("money-big-amount")
                if visible, case .dailies(let count) = ExpenseEntry.dailyPart(amountMinor: r.amountMinor, dailyMinor: r.home.cycle?.headline.todayAllowanceMinor) {
                    Text("نحو " + service.dailies(count)).font(MadarTypography.caption()).foregroundStyle(theme.color("dueText"))
                }
                Spacer(minLength: 0)
            }
        }
    }
    private func title(_ m: BigExpense.Mode) -> String { switch m { case .mixed: "المزيج"; case .installments: "كله على دورات"; case .daily: "كله من يومي الآن"; case .reserve: "من الاحتياطي" } }
    private func envelopeChip(_ text: String, selected: Bool) -> some View {
        Text(text).font(MadarTypography.caption()).padding(.horizontal, 12).frame(minHeight: 40).background(selected ? theme.ink : .clear).foregroundStyle(selected ? theme.background : theme.ink).clipShape(.capsule).overlay { Capsule().stroke(theme.color("reserveText"), lineWidth: 1) }
    }
    private func distribution(_ p: BigExpense.Plan, amount total: Int) -> some View {
        let parts: [(String, Int, Color)] = [("من رصيد دورتك", p.dailyMinor, theme.color("surplus")), ("من الفائض", p.surplusMinor, theme.color("reserve")), (envelopeID == nil ? "من يومك القادم" : "من المظروف", p.futureMinor, theme.color("accent")), ("من الاحتياطي", p.reserveMinor, theme.color("reserve"))].filter { $0.1 > 0 }
        return VStack(spacing: 10) {
            if !dynamicType.isAccessibilitySize {
            GeometryReader { proxy in HStack(spacing: 2) { ForEach(parts, id: \.0) { part in
                let width = max(1, (proxy.size.width - CGFloat(parts.count - 1) * 2) * CGFloat(part.1) / CGFloat(max(1, total)))
                Rectangle().fill(part.2).frame(width: width, height: 64).overlay {
                    if width > 68 { Text(figure: amount(part.1)).font(MadarTypography.caption()).foregroundStyle(theme.ink).padding(4).background(theme.surface) }
                }
            } } }.frame(height: 64).accessibilityHidden(true)
            }
            HStack(alignment: .top) { ForEach(parts, id: \.0) { part in VStack(spacing: 3) { Text(part.0); Text(figure: amount(part.1)) }.font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).frame(maxWidth: .infinity) } }
        }.padding(.vertical, 3).animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: mode)
    }
    private func effect(_ p: BigExpense.Plan, reading r: MoneyBigExpenseReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("الأثر").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            Text(p.repaymentMinor > 0 ? "يومك في الدورات القادمة لا يقل عن " + amount(p.lowestDailyMinor) + "." : "يبقى لك في الدورة " + amount((r.home.cycle?.headline.availableNowMinor ?? 0) - p.dailyMinor) + ".").font(.custom("thmanyahserifdisplay-Bold", size: 20, relativeTo: .title2)).contentTransition(.numericText()).accessibilityIdentifier("money-big-effect")
            Text("يبقى في الفائض " + amount(r.home.surplusMinor - p.surplusMinor) + "، وفي الاحتياطي " + amount(r.home.reserveMinor - p.reserveMinor)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            if p.repaymentMinor > 0 { Text("يبدأ مع الراتب الفعلي؛ تقدير على طول دورتك الحالي.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface).overlay(alignment: .leading) { Rectangle().fill(theme.color("reserveText")).frame(width: 3) }.padding(.vertical, 8)
    }
    private func load() {
        do { let r = try service.loadBigExpense(route); reading = r; if name.isEmpty { name = String(r.title.prefix(80)) }; failure = nil }
        catch { failure = "لم تكتمل قراءة المصروف ومصادره." }
    }
    private func save(_ p: BigExpense.Plan, _ r: MoneyBigExpenseReading) {
        guard !saving, let c = r.home.cycle else { return }
        var payload: [String: MadarCore.JSONValue] = ["mode": .string(mode.rawValue), "availableMinor": .string(String(c.headline.availableNowMinor)), "surplusMinor": .string(String(r.home.surplusMinor)), "reserveMinor": .string(String(r.home.reserveMinor))]
        if let id = route.transactionID { payload["transactionID"] = .string(id.uuidString) } else if let expense = route.expense { payload["expense"] = .object(expense) }
        if p.futureMinor > 0 { if p.cycles > 0 { payload["cycles"] = .number(Double(p.cycles)) }; payload["envelopeID"] = .string((envelopeID ?? newEnvelopeID).uuidString); if envelopeID == nil { payload["envelopeName"] = .string(String(name.prefix(80))) } }
        saving = true
        Task { do { try await app.executeMoneyCommand("money.distributeBigExpense", payload: payload, id: route.id); completed() } catch { saving = false; failure = "تغيّر أحد الأرصدة. أغلق المعاينة وافتحها مجددًا قبل الاعتماد." } }
    }
}
