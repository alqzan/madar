import SwiftUI
import MadarCore
import MadarCommands
import MadarDesign
import MadarMoney

struct MoneyEnvelopeDetailView: View {
    let app: AppSession
    let id: UUID
    @Binding var revealed: Bool
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var reading: MoneyEnvelopeDetailReading?
    @State private var repayOpen = false
    @State private var savingOpen = false
    @State private var savingAdd = true
    @State private var errorMessage: String?
    private var service: AppMoneyService { .init(app: app) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button { dismiss() } label: { Label("المظاريف", systemImage: "chevron.backward").font(MadarTypography.body()).foregroundStyle(theme.color("reserveText")).frame(minHeight: 44) }.buttonStyle(.plain)
                if let reading {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(reading.envelope.name).font(MadarTypography.title()); Spacer()
                            Text(figure: amount(reading.envelope.balanceMinor)).font(MadarTypography.title()).foregroundStyle(reading.envelope.balanceMinor < 0 ? theme.color("debt") : theme.ink).accessibilityIdentifier("money-detail-balance")
                        }
                        if let target = reading.envelope.targetMinor, visible {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("الهدف " + amount(target) + (reading.envelope.due == nil ? "" : " قبل")).font(MadarTypography.caption())
                                if let due = reading.envelope.due { MadarDateLabel(app.dateLabels(due, compact: true), primaryFont: MadarTypography.caption(), secondaryFont: MadarTypography.fine()) }
                            }.foregroundStyle(theme.secondaryInk)
                        }
                    }
                    if visible { MoneyEnvelopeRoad(app: app, reading: reading) }
                    if !visible { Button("أظهر الأرقام") { revealed = true }.frame(minHeight: 44) }
                    if reading.savingMinor > 0 || (visible && reading.savingPlanID != nil) {
                        HStack(spacing: 10) {
                            Label { Text("الادخار: ") + Text(figure: amount(reading.savingMinor)).font(MadarTypography.cardTitle()) + Text(" من كل راتب") } icon: { Image(systemName: "diamond.fill").foregroundStyle(theme.color("reserveText")) }.font(MadarTypography.body()).accessibilityLabel("الادخار: " + amount(reading.savingMinor) + " من كل راتب")
                            Spacer(minLength: 0)
                            if visible && reading.savingPlanID != nil {
                                Button { savingAdd = false; savingOpen = true } label: { Image(systemName: "minus").frame(width: 48, height: 48).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1) } }.accessibilityLabel("قلّل ادخار المظروف").buttonStyle(.plain)
                                Button { savingAdd = true; savingOpen = true } label: { Image(systemName: "plus").frame(width: 48, height: 48).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1) } }.accessibilityLabel("زد ادخار المظروف").buttonStyle(.plain)
                            }
                        }
                    }
                    if reading.envelope.balanceMinor < 0 && visible { debtRow(reading) }
                    if visible, let short = shortfall(reading), let due = reading.envelope.due {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("بحسب خطتك، يوم"); MadarDateLabel(app.dateLabels(due, compact: true), primaryFont: MadarTypography.body(), secondaryFont: MadarTypography.fine()); Text("ينقصه " + service.amount(short))
                        }.font(MadarTypography.body()).fontWeight(.semibold).foregroundStyle(theme.color("dueText")).accessibilityElement(children: .combine).accessibilityIdentifier("money-detail-shortfall")
                    }
                    HStack { Text("السجل").font(MadarTypography.cardTitle()); Rectangle().fill(theme.line).frame(height: 1); Text("الرصيد بعدها").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }.padding(.top, 8)
                    if reading.entries.isEmpty { Text("يظهر هنا كل تخصيص وصرف وردّ إلى المظروف.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk) }
                    ForEach(reading.entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                MadarDateLabel(app.dateLabels(.containing(entry.at, in: app.activePlace.timeZone), compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()).frame(width: 80, alignment: .leading)
                                Text(entry.title).font(MadarTypography.caption()).frame(maxWidth: .infinity, alignment: .leading)
                                Text(figure: signed(entry.amountMinor)).font(MadarTypography.cardTitle()).foregroundStyle(entry.amountMinor < 0 ? theme.color("debt") : theme.color("surplusText"))
                                Text(figure: signed(entry.balanceMinor)).font(MadarTypography.fine()).foregroundStyle(entry.balanceMinor < 0 ? theme.color("debt") : theme.ink).frame(width: 62, alignment: .trailing)
                            }
                            Rectangle().fill(theme.line).frame(height: 0.6)
                        }.accessibilityElement(children: .combine)
                    }
                } else if let errorMessage { Text(errorMessage); Button("أعِد المحاولة", action: load) }
                else { ProgressView().frame(maxWidth: .infinity) }
            }.padding(18).padding(.bottom, 22).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).toolbarVisibility(.hidden, for: .navigationBar)
            .accessibilityIdentifier("money-envelope-detail").task { load() }.onChange(of: app.prayerRevision) { load() }
            .sheet(isPresented: $repayOpen) {
                if let reading { MoneyRepaymentView(app: app, reading: reading, initialSalaries: suggestedSalaries(reading)).environment(\.roomTheme, theme) }
            }
            .sheet(isPresented: $savingOpen) {
                if let reading, let plan = reading.savingPlanID { MoneySavingChangeView(app: app, plan: plan, currentMinor: reading.savingMinor, add: savingAdd).environment(\.roomTheme, theme) }
            }
    }
    @ViewBuilder private func debtRow(_ reading: MoneyEnvelopeDetailReading) -> some View {
        let debt = -reading.envelope.balanceMinor
        HStack(alignment: .center, spacing: 8) {
            MoneyHatch().frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                if let plan = reading.repayment, let next = plan.nextMinor {
                    Text("الدين " + service.amount(debt) + "، يُسدّد " + service.amount(next) + " من الراتب القادم")
                    Text(plan.remainingMinor.count == 1 ? "آخر دفعة في الخطة" : "باقي " + salariesText(plan.remainingMinor.count) + " في الخطة").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                } else { Text("الدين " + service.amount(debt) + " بلا خطة سداد") }
            }.font(MadarTypography.body()).foregroundStyle(theme.color("debt")).accessibilityIdentifier("money-detail-debt")
            Spacer(minLength: 8)
            Button(reading.repayment?.nextMinor != nil ? "غيّر الخطة" : "سدّه على " + salariesText(suggestedSalaries(reading))) { repayOpen = true }
                .font(MadarTypography.caption()).padding(.horizontal, 14).frame(minHeight: 44).overlay { Capsule().stroke(theme.color("debt"), lineWidth: 1.2) }.foregroundStyle(theme.color("debt")).accessibilityIdentifier("money-repay-open")
        }
    }
    /// The salaries that land before the envelope's due date (1…6); with no date, three.
    private func suggestedSalaries(_ reading: MoneyEnvelopeDetailReading) -> Int {
        guard let due = reading.envelope.due else { return 3 }
        let count = (0..<6).filter { service.salaryForecast($0, home: reading.home).map { $0 <= due } ?? false }.count
        return min(6, max(1, count))
    }
    private func salariesText(_ count: Int) -> String {
        switch count { case 1: "راتب واحد"; case 2: "راتبين"; default: service.digits.string(count) + (count <= 10 ? " رواتب" : " راتبًا") }
    }
    /// One read projection for the overview and detail, including expiry, daily caps and conditional sources.
    private func shortfall(_ reading: MoneyEnvelopeDetailReading) -> Int? {
        guard let due = reading.envelope.due, let projected = reading.envelope.fundingProjection?.balance(on: due) else { return nil }
        let lack = (reading.envelope.targetMinor ?? 0) - projected
        return lack > 0 ? lack : nil
    }
    private func amount(_ value: Int) -> String { visible ? service.amount(value) : "•••" }
    private func signed(_ value: Int) -> String { visible ? (value > 0 ? "+" : "") + service.amount(value) : "•••" }
    private func load() { do { reading = try service.loadEnvelope(id); errorMessage = reading == nil ? "لم يعد هذا المظروف موجودًا." : nil } catch { errorMessage = "لم تكتمل قراءة المظروف." } }
}

/// Shared debt texture: the home rail and the detail legend show the same meaning.
struct MoneyHatch: View {
    @Environment(\.roomTheme) private var theme
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.stroke(Path(rect), with: .color(theme.color("debt")), lineWidth: 1)
            context.clip(to: Path(rect))
            for x in stride(from: -size.height, through: size.width, by: 5) {
                var line = Path(); line.move(to: .init(x: x, y: size.height)); line.addLine(to: .init(x: x + size.height, y: 0)); context.stroke(line, with: .color(theme.color("debt")), lineWidth: 1.4)
            }
        }.accessibilityHidden(true)
    }
}

/// «سدّه، على كم راتب؟»: a read-only preview until «اعتمد» stores the plan (debt total and salary count, schema V6).
/// Adopting never alters today's frozen allowance or the saving plan.
struct MoneyRepaymentView: View {
    let app: AppSession
    let reading: MoneyEnvelopeDetailReading
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var salaries: Int
    @State private var working = false
    @State private var errorMessage: String?
    init(app: AppSession, reading: MoneyEnvelopeDetailReading, initialSalaries: Int) {
        self.app = app; self.reading = reading; _salaries = State(initialValue: initialSalaries)
    }
    private var service: AppMoneyService { .init(app: app) }
    private var debt: Int { max(0, -reading.envelope.balanceMinor) }
    private var preview: RepaymentPreview? {
        guard let cycle = reading.home.cycle else { return nil }
        return RepaymentEngine.preview(debtMinor: debt, salaries: salaries, dailyMinor: cycle.headline.todayAllowanceMinor, cycleDays: cycle.input.expectedLengthDays)
    }
    /// The spend that put the envelope in debt, from its own ledger.
    private var cause: MoneyEnvelopeEntry? { reading.entries.first { $0.amountMinor < 0 && $0.isSpend } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(reading.envelope.name + " عليه " + service.amount(debt)).font(MadarTypography.title()).foregroundStyle(theme.color("debt"))
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.body).frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel("إغلاق").foregroundStyle(theme.secondaryInk)
                }
                if let cause {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(cause.title + " " + service.amount(-cause.amountMinor) + " في ")
                        MadarDateLabel(app.dateLabels(.containing(cause.at, in: app.activePlace.timeZone), compact: true), primaryFont: MadarTypography.caption(), secondaryFont: MadarTypography.fine())
                        Text("، وكان في المظروف " + service.amount(cause.balanceMinor - cause.amountMinor) + ".")
                    }.font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
                // Design: the question and its six answers on one row, so the choices below stay in view.
                HStack(spacing: 0) {
                    Text("على كم راتب؟").font(MadarTypography.body()).fixedSize().padding(.trailing, 6)
                    ForEach(1...6, id: \.self) { count in
                        Button { salaries = count } label: {
                            Text(service.digits.string(count)).font(MadarTypography.cardTitle()).frame(width: 40, height: 40)
                                .foregroundStyle(salaries == count ? theme.background : theme.ink).background(salaries == count ? theme.ink : .clear, in: .circle)
                                .overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1) }.frame(maxWidth: .infinity)
                        }.buttonStyle(.plain).accessibilityIdentifier("money-repay-count-\(count)").accessibilityAddTraits(salaries == count ? .isSelected : [])
                    }
                }
                Rectangle().fill(theme.line).frame(height: 1)
                if let preview {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(figure: service.amount(preview.installmentsMinor[0])).font(.custom("thmanyahsans-Bold", size: 40, relativeTo: .largeTitle)).accessibilityIdentifier("money-repay-per-salary")
                        Text("من كل راتب").font(MadarTypography.body())
                        Spacer()
                        Text("يومك بعدها").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        Text(figure: service.amount(preview.dailyAfterMinor[0])).font(MadarTypography.title()).foregroundStyle(preview.dailyAfterMinor[0] < 0 ? theme.color("dueText") : theme.color("surplusText")).accessibilityIdentifier("money-repay-daily-after")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 10) {
                        ForEach(Array(preview.installmentsMinor.enumerated()), id: \.offset) { index, amount in
                            VStack(spacing: 6) {
                                if let date = service.salaryForecast(index, home: reading.home) { MadarDateLabel(app.dateLabels(date, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()) }
                                Text(figure: service.amount(amount)).font(MadarTypography.cardTitle())
                            }.padding(10).frame(maxWidth: .infinity).overlay { Rectangle().stroke(theme.color("reserveText"), style: .init(lineWidth: 1, dash: [3, 2])) }
                        }
                    }
                    Text("المواعيد متوقعة بطول الدورة الحالية؛ آخر راتب يدفع الباقي بالهللة، ويومك الحالي لا يتغيّر.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    Button { adopt() } label: {
                        Text("اعتمد: " + service.amount(preview.installmentsMinor[0]) + " من كل راتب").font(MadarTypography.cardTitle()).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).frame(minHeight: 60)
                            .foregroundStyle(theme.background).background(theme.ink)
                    }.buttonStyle(.plain).disabled(working).accessibilityIdentifier("money-repay-adopt")
                } else { Text("تظهر اليومية ومواعيد الرواتب بعد بدء الدورة.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk) }
                outlined("خذ " + service.amount(debt) + " من الفائض الآن", note: reading.home.surplusMinor < debt ? "الفائض " + service.amount(reading.home.surplusMinor) + " لا يكفي" : nil, id: "money-repay-from-surplus") { repay("surplus") }
                    .disabled(working || reading.home.surplusMinor < debt)
                outlined("من الاحتياطي الأساسي", note: reading.home.reserveMinor < debt ? "الاحتياطي " + service.amount(reading.home.reserveMinor) + " لا يكفي" : nil, id: "money-repay-from-reserve") { repay("reserve") }
                    .disabled(working || reading.home.reserveMinor < debt)
                if let errorMessage { Text(errorMessage).font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")) }
            }.padding(18)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).presentationDetents([.fraction(0.78), .large]).presentationDragIndicator(.visible).accessibilityIdentifier("money-repayment-preview")
    }
    private func outlined(_ title: String, note: String?, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(MadarTypography.cardTitle())
                if let note { Text(note).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).frame(minHeight: 60).overlay { Rectangle().stroke(theme.line, lineWidth: 1.2) }.contentShape(.rect)
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
    private func adopt() {
        working = true
        Task {
            defer { working = false }
            do {
                try await app.executeMoneyCommand("money.adoptRepayment", payload: ["id": .string(reading.envelope.id.uuidString), "debtMinor": .string(String(debt)), "salaries": .string(String(salaries))])
                dismiss()
            } catch { errorMessage = "لم تُعتمد الخطة؛ أعد فتح المظروف لتحديث دينه." }
        }
    }
    private func repay(_ source: String) {
        working = true
        Task {
            defer { working = false }
            do {
                try await app.executeMoneyCommand("money.repayEnvelopeNow", payload: ["id": .string(reading.envelope.id.uuidString), "source": .string(source), "debtMinor": .string(String(debt))])
                dismiss()
            } catch { errorMessage = "لم يُنقل المبلغ؛ أعد فتح المظروف لتحديث رصيده." }
        }
    }
}

private struct MoneyEnvelopeRoad: View {
    let app: AppSession
    let reading: MoneyEnvelopeDetailReading
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var service: AppMoneyService { .init(app: app) }
    var body: some View {
        let dates = (0..<6).map { service.salaryForecast($0, home: reading.home) }
        let dueSlot = dueSlot(dates: dates)
        let pieces = reading.repayment?.remainingMinor.count ?? 0
        VStack(alignment: .leading, spacing: 8) {
            if !dynamicType.isAccessibilitySize {
                GeometryReader { proxy in
                    let right = proxy.size.width - 16, left: CGFloat = 8, width = right - left, slot = width / 6
                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            let band = CGRect(x: left, y: 30, width: width, height: 22)
                            context.stroke(Path(band), with: .color(theme.color("reserveText")), style: .init(lineWidth: 1, dash: [3, 2]))
                            if reading.envelope.balanceMinor < 0 {
                                let debt = CGRect(x: right - slot * 0.32, y: 30, width: slot * 0.32, height: 22)
                                context.stroke(Path(debt), with: .color(theme.color("debt")), lineWidth: 1)
                                var hatch = context; hatch.clip(to: Path(debt))
                                for x in stride(from: debt.minX - 24, through: debt.maxX + 24, by: 7) {
                                    var line = Path(); line.move(to: .init(x: x, y: 52)); line.addLine(to: .init(x: x + 22, y: 30)); hatch.stroke(line, with: .color(theme.color("debt")), lineWidth: 2)
                                }
                                // The plan's remaining salary payments: one dotted piece per salary (§7.5).
                                for index in 0..<min(pieces, 6) {
                                    let piece = CGRect(x: right - slot * CGFloat(index) - slot * 0.82, y: 32, width: slot * 0.64, height: 18)
                                    context.stroke(Path(piece), with: .color(theme.color("debt")), style: .init(lineWidth: 1, dash: [2, 2]))
                                }
                            }
                            if let dueSlot {
                                let x = right - slot * dueSlot
                                var line = Path(); line.move(to: .init(x: x, y: 27)); line.addLine(to: .init(x: x, y: 70))
                                context.stroke(line, with: .color(theme.color(reading.envelope.balanceMinor < 0 ? "debt" : "due")), lineWidth: 2)
                            }
                        }.accessibilityHidden(true)
                        ForEach(0..<6, id: \.self) { index in
                            VStack(spacing: 10) {
                                Image(systemName: "diamond.fill").font(.system(size: 11)).foregroundStyle(theme.color("reserveText")).frame(height: 18)
                                if let date = dates[index] { MadarDateLabel(app.dateLabels(date, compact: true), primaryFont: .custom("thmanyahsans-Regular", size: 11), secondaryFont: .custom("thmanyahsans-Regular", size: 11)) }
                            }.frame(width: slot, height: 80, alignment: .top).position(x: right - slot * CGFloat(index) - slot / 2, y: 72)
                        }
                        if let dueSlot, let due = reading.envelope.due {
                            let labels = app.dateLabels(due, compact: true)
                            VStack(spacing: 0) {
                                Text(labels.primary).font(.custom("thmanyahsans-Bold", size: 11, relativeTo: .caption2))
                                Text(labels.secondary).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2))
                            }
                            .foregroundStyle(theme.color("dueText"))
                            .multilineTextAlignment(.center)
                            .fixedSize()
                            .position(x: right - slot * dueSlot, y: 13)
                        }
                        Capsule().fill(LinearGradient(colors: [theme.color("rod2"), theme.color("rod"), theme.color("rod2")], startPoint: .leading, endPoint: .trailing)).frame(width: 12, height: 48).position(x: right + 8, y: 41)
                    }
                }.environment(\.layoutDirection, .leftToRight).frame(height: 112).accessibilityHidden(true)
            }
            HStack {
                Text("كل مُعيّن راتب قادم متوقع")
                Spacer()
                if let target = reading.envelope.targetMinor { Text("الهدف " + service.amount(target)) }
            }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
        }
    }
    /// The deadline lies between salary occurrences; it is not snapped to the preceding salary's diamond.
    private func dueSlot(dates: [GregorianDay?]) -> CGFloat? {
        guard let due = reading.envelope.due else { return nil }
        var previous = reading.envelope.fundingProjection?.today ?? GregorianDay.containing(app.prayerNow(), in: app.activePlace.timeZone)
        guard due >= previous else { return nil }
        var previousSlot: CGFloat = 0
        for (index, date) in dates.enumerated() {
            guard let date, date > previous else { continue }
            let nextSlot = CGFloat(index) + 0.5
            if due <= date {
                let fraction = CGFloat(MadarCalendarDays.distance(from: previous, to: due)) / CGFloat(MadarCalendarDays.distance(from: previous, to: date))
                return previousSlot + (nextSlot - previousSlot) * fraction
            }
            previous = date; previousSlot = nextSlot
        }
        return nil
    }
}

private struct MoneySavingChangeView: View {
    let app: AppSession
    let plan: UUID
    let currentMinor: Int
    let add: Bool
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var working = false
    @State private var errorMessage: String?
    private var service: AppMoneyService { .init(app: app) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MoneyPageHeader(title: add ? "زد الادخار" : "قلّل الادخار", close: { dismiss() })
            Text("الآن " + service.amount(currentMinor) + " من كل راتب. التعديل للرواتب القادمة.").font(MadarTypography.body())
            TextField("مقدار التغيير", text: $input).keyboardType(.decimalPad).font(MadarTypography.cardTitle()).padding(14).overlay { Rectangle().stroke(theme.color("reserveText"), lineWidth: 1) }
            Text("خطة السداد والحركات السابقة تبقى كما هي.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            if let errorMessage { Text(errorMessage).font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")) }
            Button("احفظ التعديل", action: save).buttonStyle(MadarPrimaryButton()).disabled(working)
            Spacer(minLength: 0)
        }.padding(20).background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).presentationDetents([.medium]).presentationDragIndicator(.visible)
    }
    private func save() {
        let raw = BankMessageParser.clean(input).replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let exponent = CurrencyExponents.specified.exponent(app.string("core.currency")), let delta = MoneyAmountInput.minor(raw, exponent: exponent), delta > 0 else { errorMessage = "أدخل مبلغًا موجبًا."; return }
        let (next, overflow) = currentMinor.addingReportingOverflow(add ? delta : -delta)
        guard !overflow, next >= 0, MoneyCommandPayload.integer(.string(String(next))) != nil else { errorMessage = "التخفيض أكبر من ادخارك، أو المبلغ خارج الحد المتاح."; return }
        working = true
        Task {
            defer { working = false }
            do { try await app.executeMoneyCommand("money.setEnvelopeSaving", payload: ["id": .string(plan.uuidString), "amountMinor": .string(String(next)), "expectedMinor": .string(String(currentMinor))]); dismiss() }
            catch { errorMessage = "لم يُحفظ التعديل. أعد فتح المظروف لتحديثه." }
        }
    }
}
