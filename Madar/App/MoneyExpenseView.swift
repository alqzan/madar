import SwiftUI
import MadarCore
import MadarDesign
import MadarMoney

/// The rare manual correction: a calculator, followed by its budget and cash effects before the single write.
struct MoneyExpenseView: View {
    let app: AppSession
    @Binding var revealed: Bool
    var seed: MoneyExpenseSeed? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reading: MoneyExpenseReading?
    @State private var raw = ""
    @State private var foreign = true
    @State private var merchant = ""
    @State private var methodID = ""
    @State private var categoryID: UUID?
    @State private var envelopeID: UUID?
    @State private var share = ExpenseEntry.Share.daily
    @State private var showInDiary = true
    @State private var details = false
    @State private var date = Date()
    @State private var saving = false
    @State private var confirmDiscard = false
    @State private var failure: String?
    @FocusState private var editing: Bool
    @State private var commandID = UUID()
    @State private var bigRoute: MoneyBigExpenseRoute?
    private var service: AppMoneyService { .init(app: app) }
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var minor: Int { MoneyAmountInput.minor(raw, exponent: CurrencyExponents.specified.exponent(inputCurrency) ?? 2) ?? 0 }
    private var inputCurrency: String { foreign ? reading?.tripCurrency ?? reading?.currency ?? "SAR" : reading?.currency ?? "SAR" }
    private var homeMinor: Int { guard let r = reading else { return minor }; return (try? FX.homeAmount(amountMinor: minor, currency: inputCurrency, rate: r.tripRate ?? "1", home: r.currency)) ?? 0 }
    private var method: MoneyPaymentChoice? { reading?.methods.first { $0.id == methodID } }
    private var hasUnsavedInput: Bool {
        !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private func amount(_ value: Int) -> String { visible ? service.amount(value) : "•••" }
    private var split: ExpenseEntry.Split { ExpenseEntry.split(chargeMinor: method?.kind == .cash && reading?.cashCountedAtWithdrawal == true ? 0 : homeMinor, share: share) }
    private var nextHeadline: Headline? {
        guard let cycle = reading?.cycle else { return nil }
        guard let day = try? service.expenseDay(at: date) else { return nil }
        return ExpenseEntry.headlineAfter(elapsedDays: cycle.elapsedDays, cycle.input, dailySpentMinor: cycle.spent,
            expenseDay: MadarCalendarDays.distance(from: cycle.startDay, to: day) + 1, dailyChargeMinor: split.dailyMinor)
    }
    private var duplicate: Bool { reading?.nearby.contains { $0.methodID == methodID && $0.currency == inputCurrency && $0.amountMinor == minor && abs($0.at.timeIntervalSince(date)) <= 600 && ($0.merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == merchant.trimmingCharacters(in: .whitespacesAndNewlines) } == true && minor > 0 }
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Button { if hasUnsavedInput { editing = false; confirmDiscard = true } else { dismiss() } } label: { Image(systemName: "xmark").frame(width: 44, height: 44).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1) } }
                        .disabled(saving).accessibilityLabel("إغلاق").accessibilityIdentifier("money-expense-close")
                    Text("سجّل مصروفًا").font(.custom("thmanyahserifdisplay-Bold", size: 24, relativeTo: .title2)); Spacer()
                    Button { details.toggle() } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.accessibilityLabel("تفاصيل المصروف").accessibilityIdentifier("money-expense-details")
                }
                if let reading {
                    amountHeading(reading)
                    if !visible { Button("أظهر الأرقام") { revealed = true }.font(MadarTypography.caption()).frame(minHeight: 44).accessibilityIdentifier("money-expense-reveal") }
                    if let code = reading.tripCurrency, code != reading.currency {
                        Picker("عملة المصروف", selection: $foreign) { Text(service.currencyName(code)).tag(true); Text(service.currencyName(reading.currency)).tag(false) }.pickerStyle(.segmented).accessibilityIdentifier("money-expense-currency")
                        if foreign { Text(reading.tripRate == nil ? "أدخل سعر الرحلة أولًا" : "بعملة البيت " + service.amount(homeMinor)).font(MadarTypography.caption()) }
                    }
                    merchantChips(reading)
                    categorySuggestion(reading)
                    preferredCardSuggestion(reading)
                    shares(reading)
                    keypad
                    diary(reading)
                    payment(reading)
                    if details { extraDetails(reading) }
                    if duplicate { Label("تبدو مسجّلة من قبل؛ راجع السجل قبل تسجيلها مرة أخرى.", systemImage: "doc.on.doc").font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")).accessibilityIdentifier("money-expense-duplicate") }
                    if let failure { Text(failure).font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")) }
                    if let h = nextHeadline {
                        VStack(spacing: 3) {
                            Text(h.availableNowMinor >= 0 ? "يبقى لك الآن " + amount(h.availableNowMinor) : "تتجاوز الدورة بـ" + amount(-h.availableNowMinor))
                                .font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)).foregroundStyle(theme.color("surplusText")).contentTransition(.numericText()).accessibilityIdentifier("money-expense-after")
                            Text("اليوم: صرفت " + amount(h.todaySpentMinor) + " من " + amount(h.todayAllowanceMinor)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        }.padding(.top, 12)
                    }
                    Button(action: save) {
                        Text(saving ? "جارٍ التسجيل…" : duplicate ? "سجّل عملية أخرى" : "سجّل").font(.custom("thmanyahserifdisplay-Bold", size: 19, relativeTo: .headline)).frame(maxWidth: .infinity, minHeight: 50).background(theme.ink).foregroundStyle(theme.background)
                    }.disabled(saving || homeMinor <= 0 || (foreign && inputCurrency != reading.currency && reading.tripRate == nil) || method == nil || (method?.kind != .credit && method?.currency != reading.currency && method?.currency != inputCurrency) || (share != .daily && envelopeID == nil)).accessibilityIdentifier("money-expense-save")
                    // AU-30: a disabled «سجّل» says what it is waiting for.
                    if !saving, homeMinor > 0 {
                        let waiting: String? = method == nil ? "اختر مصدر الدفع" : (method?.kind != .credit && method?.currency != reading.currency && method?.currency != inputCurrency) ? "هذا المصدر بعملة أخرى؛ اختر غيره" : (share != .daily && envelopeID == nil) ? "اختر المظروف الذي يُخصم منه" : nil
                        if let waiting { Text(waiting).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-expense-waiting") }
                    }
                } else if let failure { Text(failure); Button("أعِد المحاولة", action: load) }
                else { ProgressView().frame(height: 250) }
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).buttonStyle(.madarPlain)
            .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar, .tabBar).hidesRoomAccessory(app, id: "money-expense")
            .scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("تمّ") { editing = false } } }
            .task { await app.seedMoneyDefaults(); load(); if let seed { raw = seed.amount; merchant = seed.merchant; commandID = seed.id; if seed.homeCurrency { foreign = false } } }.accessibilityIdentifier("money-expense")
            .fullScreenCover(item: $bigRoute) { route in
                MoneyBigExpenseView(app: app, route: route, revealed: $revealed) { bigRoute = nil; dismiss() }
            }
            .confirmationDialog("تتجاهل المصروف؟", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("تجاهل المصروف", role: .destructive) { dismiss() }.accessibilityIdentifier("money-expense-discard")
                Button("أكمل التسجيل") { }.accessibilityIdentifier("money-expense-continue")
            } message: { Text("المبلغ أو اسم المتجر غير محفوظ.") }
            .interactiveDismissDisabled(hasUnsavedInput || saving)
    }
    private func amountHeading(_ r: MoneyExpenseReading) -> some View {
        VStack(spacing: 0) {
            Text(figure: service.amount(minor, currency: inputCurrency)).font(.custom("thmanyahserifdisplay-Black", size: 60, relativeTo: .largeTitle)).contentTransition(.numericText()).accessibilityIdentifier("money-expense-amount")
            Text((inputCurrency == "SAR" ? "ريال" : service.currencyName(inputCurrency)) + dailyDescription).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
        }.frame(maxWidth: .infinity).frame(minHeight: 94)
    }
    private var dailyDescription: String {
        guard visible, let part = ExpenseEntry.dailyPart(amountMinor: homeMinor, dailyMinor: reading?.cycle?.headline.todayAllowanceMinor) else { return "" }
        let label: String
        switch part {
        case .lessThanTenth: label = "أقل من عُشر يومك"
        case .dailies(let n): label = "نحو " + service.dailies(n)
        case .about(let f):
            label = switch f { case .tenth: "نحو عُشر يومك"; case .fifth: "نحو خُمس يومك"; case .quarter: "نحو ربع يومك"; case .third: "نحو ثلث يومك"; case .half: "نحو نصف يومك"; case .twoThirds: "نحو ثلثي يومك"; case .threeQuarters: "نحو ثلاثة أرباع يومك"; case .whole: "نحو يومك كاملًا" }
        }
        return "، " + label
    }
    private func merchantChips(_ r: MoneyExpenseReading) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(r.merchants) { item in
                    Button { merchant = item.name; categoryID = item.categoryID; if let id = item.methodID { methodID = id } } label: { chip(item.name, selected: merchant == item.name) }.accessibilityIdentifier("money-expense-merchant-" + item.name)
                }
                Button { details = true } label: { chip(merchant.isEmpty ? "اسم المتجر" : merchant, selected: false) }.accessibilityIdentifier("money-expense-merchant-edit")
            }
        }.scrollIndicators(.hidden)
    }
    private func chip(_ text: String, selected: Bool) -> some View {
        Text(text).font(.custom("thmanyahseriftext-Regular", size: 15, relativeTo: .body)).padding(.horizontal, 13).frame(minHeight: 40).background(selected ? theme.ink : .clear).foregroundStyle(selected ? theme.background : theme.ink).clipShape(.capsule).overlay { Capsule().stroke(theme.line, lineWidth: 1) }
    }
    private func categorySuggestion(_ r: MoneyExpenseReading) -> some View {
        HStack {
            Image(systemName: "square.fill").font(.system(size: 8)).foregroundStyle(theme.color("accentText"))
            Text("التصنيف").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            Menu { ForEach(r.categories) { c in Button(c.name) { categoryID = c.id } }; Button("بلا تصنيف") { categoryID = nil } } label: { Text(r.categories.first { $0.id == categoryID }?.name ?? "اختر تصنيفًا").font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)) }
                .accessibilityIdentifier("money-expense-category")
            Spacer()
        }.padding(11).frame(minHeight: 44).overlay { Rectangle().stroke(theme.color("reserveText"), style: StrokeStyle(lineWidth: 1, dash: [3, 2])) }
    }
    @ViewBuilder private func preferredCardSuggestion(_ r: MoneyExpenseReading) -> some View {
        if let category = r.categories.first(where: { $0.id == categoryID }),
           let cardID = category.preferredCardID, let cardName = category.preferredCardName,
           let payment = r.methods.first(where: { $0.cardID == cardID && $0.kind == .credit }) {
            let selected = methodID == payment.id
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("بطاقتك المفضلة لـ" + category.name).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        Text(cardName).font(MadarTypography.body().weight(.semibold)).lineLimit(1)
                            .accessibilityIdentifier("money-expense-preferred-card-name")
                    }
                    Spacer(minLength: 6)
                    Button { methodID = payment.id } label: {
                        Text(selected ? "مختارة للدفع" : "استخدمها للدفع").font(MadarTypography.fine().weight(.semibold))
                            .frame(minWidth: 96, minHeight: 44)
                    }
                    .buttonStyle(.madarPlain).disabled(selected)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .accessibilityIdentifier("money-expense-preferred-card-use")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("money-expense-preferred-card")
        }
    }
    @ViewBuilder private func shares(_ r: MoneyExpenseReading) -> some View {
        if r.tripEnvelopeID != nil {
            Label("كله من مظروف الرحلة", systemImage: "envelope").font(MadarTypography.caption()).foregroundStyle(theme.color("accentText")).frame(minHeight: 40)
        } else { VStack(spacing: 5) {
            HStack(spacing: 5) {
                ForEach(ExpenseEntry.Share.allCases, id: \.rawValue) { s in
                    Button { share = s; if envelopeID == nil { envelopeID = r.envelopes.first?.id } } label: {
                        Text(shareTitle(s)).font(MadarTypography.fine()).frame(maxWidth: .infinity, minHeight: 33).background(share == s ? theme.ink : .clear).foregroundStyle(share == s ? theme.background : theme.ink).overlay { Rectangle().stroke(theme.color("reserveText"), lineWidth: 1) }
                    }.disabled(s != .daily && (r.envelopes.isEmpty || (method?.kind == .cash && r.cashCountedAtWithdrawal))).accessibilityIdentifier("money-expense-share-" + s.rawValue)
                }
            }
            if share != .daily {
                Menu { ForEach(r.envelopes) { e in Button(e.name) { envelopeID = e.id } } } label: {
                    HStack { Text(r.envelopes.first { $0.id == envelopeID }?.name ?? "اختر المظروف"); Spacer(); Text("منه " + amount(split.envelopeMinor)); Image(systemName: "chevron.down") }.font(MadarTypography.caption()).frame(minHeight: 44)
                }.accessibilityIdentifier("money-expense-envelope")
            }
        }
    }
    }
    private func shareTitle(_ share: ExpenseEntry.Share) -> String {
        switch share { case .daily: "كله من يومي"; case .quarter: "٢٥٪ مظروف"; case .half: "٥٠٪ مظروف"; case .envelope: "كله من مظروف" }
    }
    private var keypad: some View {
        VStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { column in
                        let key = row < 3 ? String(row * 3 + column + 1) : ["clear", "0", "delete"][column]
                        Button { tap(key) } label: {
                            Group { if key == "delete" { Image(systemName: "delete.backward") } else { Text(key == "clear" ? "مسح" : service.digits.string(Int(key) ?? 0)) } }.font(.custom("thmanyahserifdisplay-Bold", size: key == "clear" ? 19 : 29, relativeTo: .title2)).frame(maxWidth: .infinity, minHeight: 47).background(theme.surface).overlay { Rectangle().stroke(theme.line, lineWidth: 1) }
                        }.accessibilityLabel(key == "clear" ? "مسح المبلغ" : key == "delete" ? "حذف آخر رقم" : key).accessibilityIdentifier("money-expense-key-" + key)
                    }
                }
            }
        }.padding(.top, 3)
    }
    private func tap(_ key: String) {
        let update = { if key == "clear" { raw = "" } else if key == "delete" { if !raw.isEmpty { raw.removeLast() } } else if raw.count < 9 { raw += key } }
        if reduceMotion { update() } else { withAnimation(.easeOut(duration: 0.16), update) }
    }
    private func diary(_ r: MoneyExpenseReading) -> some View {
        Button { showInDiary.toggle() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: showInDiary ? "pencil.line" : "eye.slash")
                Text(r.diaryOn ? (showInDiary ? "يدخل صفحة اليوم: «صرفت " + service.amount(minor) + (merchant.isEmpty ? "»" : " في " + merchant + "»") : "لن يظهر في صفحة اليوم") : "سطور المال مخفية من المذكرات في الإعدادات")
            }.font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).frame(maxWidth: .infinity, minHeight: 30)
        }.accessibilityIdentifier("money-expense-diary").accessibilityValue(showInDiary ? "ظاهر" : "مخفي")
    }
    private func payment(_ r: MoneyExpenseReading) -> some View {
        VStack(spacing: 7) {
            ScrollView(.horizontal) { HStack(spacing: 7) { ForEach(r.methods) { m in Button { methodID = m.id; if m.kind == .cash && r.cashCountedAtWithdrawal { share = .daily } } label: { chip(m.title, selected: methodID == m.id) }.disabled(m.kind != .credit && m.currency != r.currency && m.currency != inputCurrency).accessibilityIdentifier("money-expense-method-" + m.title) } } }.scrollIndicators(.hidden)
            if r.methods.isEmpty { Text("أضف حسابًا أو بطاقة من رسائل البنك أولًا.").font(MadarTypography.body()) }
            else if let m = method {
                if m.kind == .credit {
                    Text("يُحسب من يومك يوم الشراء، ويخرج النقد عند سداد البطاقة.").font(MadarTypography.fine()).foregroundStyle(theme.color("accentText"))
                    if let due = m.purchaseDue { MadarDateLabel(app.dateLabels(due, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                } else { Text(m.kind == .cash && r.cashCountedAtWithdrawal ? "احتُسب عند السحب؛ لن يُخصم من يومك مرة أخرى." : "يخرج النقد الآن من " + (m.accountName ?? m.title)).font(MadarTypography.fine()).foregroundStyle(theme.color("accentText")) }
            }
            Text("أغلب عملياتك تدخل من رسائل البنك").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
        }
    }
    private func extraDetails(_ r: MoneyExpenseReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("اسم المتجر، إن أردت", text: $merchant).textInputAutocapitalization(.never).focused($editing).font(MadarTypography.body()).frame(minHeight: 44).accessibilityIdentifier("money-expense-merchant-field")
            TextField("المبلغ، مع الكسور إن احتجت", text: $raw).keyboardType(.decimalPad).focused($editing).font(MadarTypography.body()).frame(minHeight: 44).accessibilityIdentifier("money-expense-precise-amount")
            DatePicker("وقت المصروف", selection: $date, in: r.earliest...app.prayerNow(), displayedComponents: [.date, .hourAndMinute]).font(MadarTypography.caption())
            MadarDateLabel(app.dateLabels(.containing(date, in: app.activePlace.timeZone)), primaryFont: MadarTypography.caption(), secondaryFont: MadarTypography.fine())
        }.padding(12).background(theme.surface)
    }
    private func load() {
        do {
            let r = try service.loadExpense()
            reading = r
            let requestedMethod = seed?.method.flatMap { requested in r.methods.contains(where: { $0.id == requested }) ? requested : nil }
            methodID = requestedMethod ?? r.defaultMethodID ?? ""
            date = app.prayerNow(); failure = nil
            if let id = r.tripEnvelopeID { envelopeID = id; share = .envelope }
        }
        catch { failure = "لم تكتمل قراءة مصادر الدفع. حاول مرة أخرى." }
    }
    private func save() {
        guard !saving, minor > 0, let m = method, let r = reading else { return }
        var p: [String: MadarCore.JSONValue] = ["amountMinor": .string(String(minor)), "currency": .string(inputCurrency), "merchant": .string(merchant), "method": .string(m.kind == .cash ? "cash" : m.cardID == nil ? "transfer" : "card"), "eventAt": .string(ISO8601DateFormatter().string(from: date)), "showInDiary": .bool(showInDiary)]
        if let id = m.cardID { p["cardID"] = .string(id.uuidString) } else if let id = m.accountID { p["fromAccountID"] = .string(id.uuidString) }
        if let id = categoryID { p["categoryID"] = .string(id.uuidString) }
        if r.tripEnvelopeID == nil, share != .daily, let id = envelopeID {
            p["allocations"] = .array(ExpenseEntry.sources(split, envelopeID: id.uuidString).map { target, amount in
                var row: [String: MadarCore.JSONValue] = ["target": .string("daily"), "amountMinor": .string(String(amount))]
                if case .envelope(let id) = target { row["target"] = .string("envelope"); row["targetID"] = .string(id) }
                return .object(row)
            })
        }
        if r.tripCurrency == nil, let threshold = service.bigExpenseThreshold(cycle: r.cycle), homeMinor >= threshold,
           !(m.kind == .cash && r.cashCountedAtWithdrawal) {
            p.removeValue(forKey: "allocations")
            bigRoute = .init(expense: p); return
        }
        saving = true
        Task { do { try await app.executeMoneyCommand("money.logExpense", payload: p, id: commandID); dismiss() } catch { failure = "لم يُسجَّل المصروف. راجع مصدر الدفع والمبلغ ثم حاول مرة أخرى."; saving = false; commandID = UUID() } }
    }
}
