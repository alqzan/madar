import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarDesign
import MadarMoney
import MadarCommands

/// A paper booklet. Drafts show their real effect before one settings write; that write also owns tomorrow's policy.
struct MoneySettingsView: View {
    let app: AppSession
    @Binding var revealed: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum Page: Int, CaseIterable { case messages, daily, cycle, deficit, travel, room, reconciliation
        var title: String { switch self { case .messages: "الرسائل"; case .daily: "اليومية"; case .cycle: "الدورة"; case .deficit: "العجز"; case .travel: "السفر"; case .room: "الغرفة"; case .reconciliation: "المطابقة" } }
    }
    @State private var page = Page.daily
    @State private var cycle: MoneyCycleReading?
    @State private var mode = "fixed"
    @State private var rawAmount = ""
    @State private var rawPercent = "30"
    @State private var salaryDay = 0
    @State private var calendar = "gregorian"
    @State private var flexible = false
    @State private var every = 1
    @State private var unit = RecurrenceUnit.month
    @State private var first = Date()
    @State private var rawBigAmount = "1000"
    @State private var rawBigPercent = "10"
    @State private var rawReconcileDays = "90"
    @FocusState private var editing: Bool
    private var service: AppMoneyService { .init(app: app) }
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private var today: GregorianDay { .containing(app.prayerNow(), in: app.activePlace.timeZone) }
    private var amountMinor: Int? { MoneyAmountInput.minor(rawAmount, exponent: CurrencyExponents.specified.exponent(app.string("core.currency")) ?? 2) }
    private var percentBp: Int? { MoneyAmountInput.minor(rawPercent, exponent: 2).flatMap { (0...10000).contains($0) ? $0 : nil } }
    private var proposedInput: CycleInput? {
        guard let c = cycle, let amount = amountMinor, let bp = percentBp else { return nil }
        var input = c.input
        let newMode: AllowanceMode = mode == "percent" ? .percent(basisPoints: bp, incomeMinor: c.incomeMinor) : .fixed(allowanceMinor: amount)
        input.policies = input.policies.filter { $0.effectiveFromDay <= c.elapsedDays } + [.init(effectiveFromDay: c.elapsedDays + 1, mode: newMode, frozenRate: CycleEngine.freeze(newMode, expectedLengthDays: input.expectedLengthDays))]
        return input
    }
    private var proposed: CycleDay? { guard let input = proposedInput, let cycle else { return nil }; return CycleEngine.day(cycle.elapsedDays + 1, input) }
    private var dailiesTotal: Int? { proposedInput.map { CycleEngine.accruedDaily(through: $0.expectedLengthDays, $0) } }
    private var schedule: SalaryRecurrence? { .init(every: every, unit: unit, first: .containing(first, in: app.activePlace.timeZone), hijri: calendar == "hijri") }
    private var nextDates: [GregorianDay] { flexible ? schedule?.preview(from: today) ?? [] : [MoneyRepository.expectedEnd(after: today, salaryDay: salaryDay, hijri: calendar == "hijri", zone: app.activePlace.timeZone)] }
    private func amount(_ n: Int) -> String { visible ? service.amount(n) : "•••" }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack { Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1) } }.accessibilityLabel("إغلاق").accessibilityIdentifier("money-settings-close"); Text("إعدادات المال").font(.custom("thmanyahserifdisplay-Bold", size: 24, relativeTo: .title2)); Spacer() }
                    VStack(spacing: 0) {
                        ScrollView(.horizontal) { HStack(alignment: .bottom, spacing: 4) { ForEach(Page.allCases, id: \.rawValue) { p in
                            Button { editing = false; page = p } label: { VStack(spacing: 3) { Text(service.digits.string(p.rawValue + 1)).font(MadarTypography.fine()).foregroundStyle(theme.color("reserveText")); Text(p.title).font(MadarTypography.caption()); Text(tabValue(p)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }.frame(width: 58, height: p == page ? 76 : 66).background(p == page ? theme.surface : theme.background).clipShape(.rect(topLeadingRadius: 12, topTrailingRadius: 12)).overlay { UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12).stroke(p == page ? theme.color("reserveText") : theme.line, lineWidth: 1) } }.accessibilityIdentifier("money-settings-page-" + String(p.rawValue))
                        } } }.scrollIndicators(.hidden)
                        VStack(alignment: .leading, spacing: 18) {
                            HStack { VStack(alignment: .leading, spacing: 0) { Text("باب " + service.digits.string(page.rawValue + 1)).font(MadarTypography.fine()).foregroundStyle(theme.color("reserveText")); Text(page.title).font(.custom("thmanyahserifdisplay-Bold", size: 24, relativeTo: .title2)) }; Spacer(); Image(systemName: "seal").font(.title).foregroundStyle(theme.color("reserveText")) }
                            if !visible { Button("أظهر الأرقام") { revealed = true }.frame(minHeight: 44).accessibilityIdentifier("money-settings-reveal") }
                            switch page {
                            case .daily: dailyPage
                            case .cycle: cyclePage
                            case .deficit: deficitPage
                            case .messages: messagesPage
                            case .travel: toggle("تتوقف اليومية أثناء الرحلة", "mal.travelPausesDaily"); note("القطرة تتوقف مع اليومية؛ الحركات السابقة تبقى بسعرها يوم تسجيلها.")
                            case .room: roomPage
                            case .reconciliation: reconciliationPage
                            }
                            Button("أعد إعدادات هذا الباب إلى المتفق عليه") { editing = false; app.reset(keys) }.font(MadarTypography.caption()).frame(minHeight: 44).accessibilityIdentifier("money-settings-reset")
                            Text("— " + service.digits.string(page.rawValue + 1) + " —").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).frame(maxWidth: .infinity)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface).overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.color("reserveText"), lineWidth: 1) }
                    }
                    Text(page == .daily || page == .cycle ? "معاينة أولًا، ثم حفظ واحد وتراجع" : "كل تغيير له تراجع").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 28).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively).background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).buttonStyle(.plain).toolbar(.hidden, for: .navigationBar, .tabBar)
                .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("تم") { editing = false }.accessibilityIdentifier("money-settings-keyboard-done") } }
                .task { load() }.onChange(of: app.prayerRevision) { load() }.onChange(of: unit) { every = min(every, unit.maxEvery) }
                .accessibilityIdentifier("money-settings")
        }
    }
    private var dailyPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("طريقة اليومية", selection: $mode) { Text("من الدخل").tag("percent"); Text("مبلغ ثابت").tag("fixed") }.pickerStyle(.segmented).accessibilityIdentifier("money-settings-daily-mode")
            VStack(spacing: 12) {
                if visible {
                    if mode == "percent" { HStack { Text(figure: amount(cycle?.incomeMinor ?? 0)); Text("×"); TextField("النسبة", text: $rawPercent).keyboardType(.decimalPad).focused($editing).frame(width: 60).accessibilityIdentifier("money-settings-percent"); Text("٪ ÷ " + service.digits.string(cycle?.input.expectedLengthDays ?? 30) + " يومًا") }.font(MadarTypography.body()).multilineTextAlignment(.center) }
                    else { HStack { Text("البدل المضبوط").font(MadarTypography.caption()); TextField("المبلغ", text: $rawAmount).keyboardType(.decimalPad).focused($editing).font(MadarTypography.body()).multilineTextAlignment(.center).frame(width: 110).accessibilityIdentifier("money-settings-allowance") } }
                }
                Rectangle().fill(theme.line).frame(height: 1)
                HStack {
                    nudge("−", id: "minus", delta: -1); Spacer()
                    VStack(spacing: 0) { Text(proposed.map { amount($0.dailyMinor) } ?? cycle.map { amount($0.headline.todayAllowanceMinor) } ?? "—").font(.custom("thmanyahserifdisplay-Black", size: 44, relativeTo: .largeTitle)).accessibilityIdentifier("money-settings-preview"); Text("يومك بعد قسمة الخطط").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                    Spacer(); nudge("+", id: "plus", delta: 1)
                }.padding(.vertical, 12)
                if let p = proposed { Text("للخطط " + amount(p.allowanceMinor - p.dailyMinor)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
            }.padding(18).background(theme.background).overlay { Rectangle().stroke(theme.color("reserveText"), lineWidth: 1).padding(3) }.overlay { if !dynamicType.isAccessibilitySize { MoneyBookRosette().stroke(theme.color("reserveText").opacity(0.13), lineWidth: 1).padding(24).allowsHitTesting(false) } }
            if let c = cycle {
                HStack { Text("من دخلك"); Spacer(); Text(figure: amount(c.incomeMinor)) }.font(MadarTypography.body())
                GeometryReader { g in HStack(spacing: 0) { Rectangle().fill(theme.color("reserve")).frame(width: g.size.width * (visible && c.incomeMinor > 0 ? min(1, CGFloat(dailiesTotal ?? 0) / CGFloat(c.incomeMinor)) : 0.5)); Rectangle().fill(theme.color("accent").opacity(0.7)) }.clipShape(.capsule) }.frame(height: 12).accessibilityHidden(true)
                HStack { Text("يوميات الدورة " + amount(dailiesTotal ?? 0)); Spacer(); Text("باقي الدخل " + amount(c.incomeMinor - (dailiesTotal ?? 0))) }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
            note("أي تغيير يبدأ غدًا؛ ما مضى من يومياتك والترحيل والخطط محفوظ.")
            MadarDateLabel(app.dateLabels((cycle?.today ?? today).adding(days: 1)), primaryFont: MadarTypography.caption(), secondaryFont: MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            saveButton("احفظ اليومية", id: "daily-save", enabled: visible && amountMinor != nil && percentBp != nil) {
                app.setMany(["mal.dailyAllowance": .object(["mode": .string(mode), "amountMinor": mode == "fixed" ? .number(Double(amountMinor ?? 0)) : .null, "percentBp": mode == "percent" ? .number(Double(percentBp ?? 0)) : .null])])
            }
        }
    }
    private var cyclePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("تقويم الدورة", selection: $calendar) { Text("ميلادي").tag("gregorian"); Text("هجري").tag("hijri") }.pickerStyle(.segmented).accessibilityIdentifier("money-settings-cycle-calendar")
            if !dynamicType.isAccessibilitySize {
                GeometryReader { geometry in
                    let side = min(geometry.size.width, 360)
                    astrolabe.frame(width: 238, height: 238)
                        .scaleEffect(side / 238)
                        .frame(width: geometry.size.width, height: side)
                }.aspectRatio(1, contentMode: .fit).frame(maxHeight: 360)
            }
            Toggle("موعد وفاصل أختارهما", isOn: $flexible).accessibilityIdentifier("money-settings-flexible")
            if flexible {
                HStack { Stepper(value: $every, in: 1...unit.maxEvery) { Text(Recurrence(every: every, unit: unit, first: today).map { RecurrencePhrase.every($0, digits: service.digits) } ?? "التكرار") }; Picker("الوحدة", selection: $unit) { Text("يوم").tag(RecurrenceUnit.day); Text("أسبوع").tag(RecurrenceUnit.week); Text("شهر").tag(RecurrenceUnit.month); Text("سنة").tag(RecurrenceUnit.year) } }.accessibilityIdentifier("money-settings-interval")
                DatePicker("أول موعد", selection: $first, displayedComponents: .date).environment(\.calendar, Calendar(identifier: calendar == "hijri" ? .islamicUmmAlQura : .gregorian)).accessibilityIdentifier("money-settings-first-date")
                MadarDateLabel(app.dateLabels(.containing(first, in: app.activePlace.timeZone)), primaryFont: MadarTypography.caption(), secondaryFont: MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            } else { Stepper(value: $salaryDay, in: 0...31) { Text(salaryDay == 0 ? "من يوم وصول الراتب" : "يوم نزول الراتب: " + service.digits.string(salaryDay)) }.accessibilityIdentifier("money-settings-salary-day") }
            ForEach(nextDates, id: \.description) { d in MadarDateLabel(app.dateLabels(d), primaryFont: MadarTypography.body(), secondaryFont: MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
            note("تبدأ الدورة بالراتب الذي يصل فعلًا. المواعيد للتوقع؛ سياسة الدورة الجارية تبقى محفوظة.")
            saveButton("احفظ مواعيد الدورة", id: "cycle-save", enabled: !flexible || schedule != nil) {
                app.setMany(["mal.salaryDay": .number(Double(salaryDay)), "mal.cycleCalendar": .string(calendar), "mal.salarySchedule": .object(["enabled": .bool(flexible), "every": .number(Double(every)), "unit": .string(unit.rawValue), "firstDayKey": flexible ? .string(GregorianDay.containing(first, in: app.activePlace.timeZone).description) : .null])])
            }
        }
    }
    private var astrolabe: some View {
        ZStack {
            Circle().stroke(theme.color("reserveText"), lineWidth: 1); Circle().stroke(theme.color("reserveText"), lineWidth: 1).padding(8)
            MoneyBookRosette().stroke(theme.color("reserveText").opacity(0.55), lineWidth: 0.7).padding(18)
            ForEach(1...dialDays, id: \.self) { n in Rectangle().fill(theme.color("reserveText").opacity(n.isMultiple(of: 5) ? 1 : 0.4)).frame(width: 1, height: n.isMultiple(of: 5) ? 14 : 6).offset(y: -109).rotationEffect(.degrees(Double(n) * 360 / Double(dialDays))) }
            ForEach([1,5,10,15,20,25,30].filter { $0 <= dialDays }, id: \.self) { n in Text(service.digits.string(n)).font(MadarTypography.fine()).foregroundStyle(theme.color("reserveText")).position(x: 119 + sin(Double(n) * 2 * .pi / Double(dialDays)) * 94, y: 119 - cos(Double(n) * 2 * .pi / Double(dialDays)) * 94) }
            Circle().trim(from: 0, to: min(1, CGFloat(cycle?.elapsedDays ?? 0) / CGFloat(cycle?.input.expectedLengthDays ?? 30))).stroke(theme.color("accent"), lineWidth: 7).rotationEffect(.degrees(-90)).padding(13).environment(\.layoutDirection, .leftToRight)
            Path { path in
                path.move(to: CGPoint(x: 119, y: 119))
                path.addLine(to: CGPoint(x: 119 + sin(Double(dialDay) * 2 * .pi / Double(dialDays)) * 113,
                                        y: 119 - cos(Double(dialDay) * 2 * .pi / Double(dialDays)) * 113))
            }.stroke(theme.color("reserveText"), lineWidth: 2)
            Image(systemName: "seal.fill").foregroundStyle(theme.color("reserveText")).position(x: 119 + sin(Double(dialDay) * 2 * .pi / Double(dialDays)) * 113, y: 119 - cos(Double(dialDay) * 2 * .pi / Double(dialDays)) * 113).animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: dialDay)
            VStack(spacing: 4) { Text(flexible ? "أول موعد" : "يوم الراتب").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk); Text(service.digits.string(dialDay)).font(.custom("thmanyahserifdisplay-Bold", size: 42, relativeTo: .largeTitle)).foregroundStyle(theme.color("reserveText")); Text(calendar == "hijri" ? "بالتقويم الهجري" : "بالتقويم الميلادي").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }.padding(20).background(theme.surface, in: .circle)
        }.frame(width: 238).frame(maxWidth: .infinity).accessibilityHidden(true)
    }
    private var deficitPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            toggle("المقاصة من الفائض", "mal.autoOffset")
            Stepper(value: Binding(get: { Int(app.number("mal.offsetCapDailies")) }, set: { app.set(.number(Double($0)), key: "mal.offsetCapDailies") }), in: 0...365) { Text(app.number("mal.offsetCapDailies") == 0 ? "بلا مقاصة" : "سقف الدورة: " + service.dailies(Int(app.number("mal.offsetCapDailies")))) }.accessibilityIdentifier("money-settings-offset-cap")
            note("السقف لكل الدورة، وليس لكل مرة. وما لا يُسدّ يبقى ترحيلًا ظاهرًا؛ لا تختفي هللة.")
            Picker("باقي الراتب", selection: stringBinding("mal.salaryRemainder")) { Text("للفوائض ثم الاحتياطي").tag("surplusThenReserve"); Text("للاحتياطي").tag("reserve"); Text("اسألني").tag("ask") }
            toggle("السحب النقدي يُحسب مصروفًا", "mal.cashWithdrawalAsSpend")
        }
    }
    private var messagesPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            note("مدار يستقبل ما تمرّره له أتمتة «الاختصارات»، ولا يقرأ صندوق رسائلك.")
            toggle("تنبيه حدود التصنيف", "mal.alert80")
            toggle("افتح منذ آخر زيارة بعد الغياب", "mal.sinceLastVisit")
            Picker("تذكير سداد البطاقة", selection: stringBinding("mal.cardDue")) { Text("قبل ثلاثة أيام").tag("3days"); Text("قبل يوم").tag("1day"); Text("بلا تذكير").tag("off") }
            Picker("تذكير موعد الزكاة", selection: stringBinding("mal.zakatReminder")) {
                Text("بلا تذكير").tag("off"); Text("قبل يوم").tag("1day"); Text("قبل أسبوع").tag("1week"); Text("قبل شهر").tag("1month")
            }.accessibilityIdentifier("money-settings-zakat-reminder")
            note("يبدأ بعد اختيار تاريخ الحول من شاشة الزكاة، ويظهر الموعد بالتقويمين.")
        }
    }
    private var roomPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            toggle("إخفاء المبالغ خارج مدار", "core.hideMoneyOutside"); toggle("إخفاؤها حتى ألمسها", "core.hideMoneyUntilTouch")
            Picker("شكل الأرقام", selection: stringBinding("mal.figureStyle")) { Text("عريضة").tag("heritage"); Text("حديثة").tag("modern"); Text("كلاسيكية").tag("classic") }.pickerStyle(.segmented).disabled(app.settingsWriteInProgress).accessibilityIdentifier("money-settings-figure-style")
            MoneyFigure(value: service.digits.amount(minorUnits: 321250, fractionDigits: 2, signed: false), style: MoneyFigureStyle(app), size: 34).frame(maxWidth: .infinity).accessibilityIdentifier("money-settings-figure-sample")
            Picker("رسم الحول", selection: stringBinding("mal.hawlStyle")) { Text("الأهلّة").tag("crescents"); Text("دورة القمر").tag("orbit"); Text("تقويم الأشهر").tag("calendar") }.pickerStyle(.segmented).disabled(app.settingsWriteInProgress).accessibilityIdentifier("money-settings-hawl-style")
            Picker("المصروف الكبير", selection: stringBinding("mal.bigExpenseRule")) { Text("يوميات").tag("dailies"); Text("من الراتب").tag("salaryPercent"); Text("مبلغ").tag("amount") }.pickerStyle(.segmented).accessibilityIdentifier("money-settings-big-rule")
            if visible {
            if app.string("mal.bigExpenseRule") == "salaryPercent" {
                HStack { TextField("النسبة من الراتب", text: $rawBigPercent).keyboardType(.decimalPad).focused($editing).accessibilityIdentifier("money-settings-big-percent"); Text("٪") }
                saveButton("احفظ الحد", id: "big-save", enabled: MoneyAmountInput.minor(rawBigPercent, exponent: 2).map { (1...10000).contains($0) } == true) { app.set(.number(Double(MoneyAmountInput.minor(rawBigPercent, exponent: 2) ?? 1000)), key: "mal.bigExpenseSalaryBp") }
            }
            else if app.string("mal.bigExpenseRule") == "amount" {
                TextField("المبلغ بعملة البيت", text: $rawBigAmount).keyboardType(.decimalPad).focused($editing).accessibilityIdentifier("money-settings-big-amount")
                saveButton("احفظ الحد", id: "big-save", enabled: MoneyAmountInput.minor(rawBigAmount, exponent: homeExponent).map { $0 > 0 && $0 <= 10000000000000 } == true) { app.set(.number(Double(MoneyAmountInput.minor(rawBigAmount, exponent: homeExponent) ?? 100000)), key: "mal.bigExpenseMinor") }
            }
            else { Stepper(value: Binding(get: { Int(app.number("mal.bigExpenseDays")) }, set: { app.set(.number(Double($0)), key: "mal.bigExpenseDays") }), in: 2...8) { Text(service.digits.string(Int(app.number("mal.bigExpenseDays"))) + " يوميات") } }
            }
            if let threshold = service.bigExpenseThreshold(cycle: cycle) { Text("يفتح موجّه التوزيع من " + amount(threshold)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-settings-big-threshold") }
            else { note("حدّد اليومية أو الراتب، أو اختر مبلغًا ثابتًا.") }
        }
    }
    private var reconciliationPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ذكّرني بمطابقة الرصيد كل").font(MadarTypography.body())
            if visible {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("٩٠", text: $rawReconcileDays).keyboardType(.numberPad).focused($editing)
                        .multilineTextAlignment(.center).font(MadarTypography.cardTitle()).frame(width: 88)
                        .accessibilityIdentifier("money-settings-reconcile-days")
                    Text("يومًا").font(MadarTypography.body())
                }.frame(maxWidth: .infinity)
                saveButton("احفظ مدة التذكير", id: "reconcile-cadence-save", enabled: reconcileDaysInput.map { (1...365).contains($0) } == true) {
                    guard let days = reconcileDaysInput else { return }
                    app.set(.number(Double(days)), key: "mal.reconcileEveryDays") { load() }
                }
            } else {
                Text("••• يومًا").font(MadarTypography.cardTitle()).frame(maxWidth: .infinity)
                Button("أظهر الأرقام") { revealed = true }.font(MadarTypography.caption()).frame(minHeight: 44)
                    .accessibilityIdentifier("money-settings-reconcile-reveal")
            }
            note("اختر أي مدة من يوم إلى سنة. يبدأ العد من تاريخ أول مطابقة تحفظها، ثم يتجدد من كل مطابقة. يصل تذكير واحد بعد حلول الموعد، ويحترم أوقات السكينة وموازنة تذكيرات مدار.")
        }
    }
    private var reconcileDaysInput: Int? { MoneyAmountInput.minor(rawReconcileDays, exponent: 0) }
    private var homeExponent: Int { CurrencyExponents.specified.exponent(app.string("core.currency")) ?? 2 }
    private var dialDate: Date { flexible ? first : cycle?.expectedEndDay.date(in: app.activePlace.timeZone) ?? app.prayerNow() }
    private var dialCalendar: Calendar { var c = Calendar(identifier: calendar == "hijri" ? .islamicUmmAlQura : .gregorian); c.timeZone = app.activePlace.timeZone; return c }
    private var dialDays: Int { dialCalendar.range(of: .day, in: .month, for: dialDate)?.count ?? 30 }
    private var dialDay: Int { !flexible && salaryDay > 0 ? min(salaryDay, dialDays) : dialCalendar.component(.day, from: dialDate) }
    private func input(_ n: Int, exponent: Int) -> String { var scale = 1; for _ in 0..<exponent { scale *= 10 }; let fraction = String(abs(n) % scale); let raw = String(n / scale) + (exponent > 0 ? "." + String(repeating: "0", count: max(0, exponent - fraction.count)) + fraction : ""); if app.string("core.numerals") == "western" { return raw }; let digits = Array("٠١٢٣٤٥٦٧٨٩"); return raw.map { c in c.wholeNumberValue.map { String(digits[$0]) } ?? (c == "." ? "٫" : String(c)) }.joined() }
    private func nudge(_ label: String, id: String, delta: Int) -> some View { Button { if mode == "fixed" { var scale = 1; for _ in 0..<homeExponent { scale *= 10 }; rawAmount = input(max(0, (amountMinor ?? 0) + delta * 10 * scale), exponent: homeExponent) } else { rawPercent = input(min(10000, max(0, (percentBp ?? 0) + delta * 100)), exponent: 2) } } label: { Text(label).font(.title2).frame(width: 44, height: 44).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1) } }.disabled(!visible).accessibilityIdentifier("money-settings-" + id) }
    private func note(_ text: String) -> some View { Text(text).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(theme.background).overlay(alignment: .leading) { Rectangle().fill(theme.color("reserveText")).frame(width: 3) } }
    private func saveButton(_ title: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View { Button { editing = false; action() } label: { Text(title).font(MadarTypography.body()).frame(maxWidth: .infinity, minHeight: 48).background(theme.ink).foregroundStyle(theme.background) }.disabled(!enabled || app.settingsWriteInProgress).accessibilityIdentifier("money-settings-" + id) }
    private func toggle(_ title: String, _ key: String) -> some View { Toggle(title, isOn: Binding(get: { app.bool(key) }, set: { app.set(.bool($0), key: key) })).font(MadarTypography.body()).disabled(app.settingsWriteInProgress) }
    private func stringBinding(_ key: String) -> Binding<String> { .init(get: { app.string(key) }, set: { app.set(.string($0), key: key) }) }
    private func tabValue(_ p: Page) -> String { switch p { case .daily: cycle.map { amount($0.headline.todayAllowanceMinor) } ?? "—"; case .cycle: salaryDay > 0 ? service.digits.string(salaryDay) : "الراتب"; case .deficit: service.digits.string(Int(app.number("mal.offsetCapDailies"))); case .travel: app.bool("mal.travelPausesDaily") ? "تتوقف" : "تستمر"; case .messages: "الاختصار"; case .room: "خصوصيتك"; case .reconciliation: service.digits.string(Int(app.number("mal.reconcileEveryDays"))) + " يوم" } }
    private var keys: [String] { switch page { case .daily: ["mal.dailyAllowance"]; case .cycle: ["mal.salaryDay", "mal.cycleCalendar", "mal.salarySchedule"]; case .deficit: ["mal.autoOffset", "mal.offsetCapDailies", "mal.salaryRemainder", "mal.cashWithdrawalAsSpend"]; case .messages: ["mal.alert80", "mal.sinceLastVisit", "mal.cardDue", "mal.zakatReminder"]; case .travel: ["mal.travelPausesDaily"]; case .room: ["core.hideMoneyOutside", "core.hideMoneyUntilTouch", "mal.figureStyle", "mal.hawlStyle", "mal.bigExpenseRule", "mal.bigExpenseDays", "mal.bigExpenseSalaryBp", "mal.bigExpenseMinor"]; case .reconciliation: ["mal.reconcileEveryDays"] } }
    private func load() {
        cycle = try? MoneyRepository(context: ModelContext(app.container)).cycle(at: app.prayerNow())
        let value = app.values["mal.dailyAllowance"]?.object ?? [:]; mode = value["mode"]?.string ?? "fixed"
        if value["amountMinor"] == .null && value["percentBp"] == .null {
            mode = cycle?.input.policies.last.map { if case .percent = $0.mode { "percent" } else { "fixed" } } ?? "fixed"
        }
        let n = value["amountMinor"]?.number.map(Int.init) ?? cycle?.input.policies.last.flatMap { if case .fixed(let n) = $0.mode { n } else { nil } } ?? 0
        rawAmount = value["amountMinor"] == .null && cycle == nil ? "" : input(n, exponent: homeExponent)
        let previousBp = cycle?.input.policies.last.flatMap { if case .percent(let bp, _) = $0.mode { bp } else { nil } }
        rawPercent = input(value["percentBp"]?.number.map(Int.init) ?? previousBp ?? 3000, exponent: 2)
        rawBigAmount = input(Int(app.number("mal.bigExpenseMinor")), exponent: homeExponent)
        rawBigPercent = input(Int(app.number("mal.bigExpenseSalaryBp")), exponent: 2)
        rawReconcileDays = input(Int(app.number("mal.reconcileEveryDays")), exponent: 0)
        salaryDay = Int(app.number("mal.salaryDay")); calendar = app.string("mal.cycleCalendar")
        let schedule = app.values["mal.salarySchedule"]?.object ?? [:]; flexible = schedule["enabled"] == .bool(true); every = schedule["every"]?.number.map(Int.init) ?? 1; unit = RecurrenceUnit(rawValue: schedule["unit"]?.string ?? "month") ?? .month
        first = schedule["firstDayKey"]?.string.flatMap { try? GregorianDay($0) }?.date(in: app.activePlace.timeZone) ?? cycle?.expectedEndDay.date(in: app.activePlace.timeZone) ?? app.prayerNow()
    }
}
private struct MoneyBookRosette: Shape {
    func path(in r: CGRect) -> Path { var p = Path(); for i in 0..<16 { let a = Double(i) * .pi / 8, radius = i.isMultiple(of: 2) ? 0.5 : 0.33; let q = CGPoint(x: r.midX + cos(a) * r.width * radius, y: r.midY + sin(a) * r.height * radius); if i == 0 { p.move(to: q) } else { p.addLine(to: q) } }; p.closeSubpath(); return p }
}
