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
    @State private var categorySource: String?
    @State private var envelopeID: UUID?
    @State private var share = ExpenseEntry.Share.daily
    @State private var showInDiary = true
    @State private var details = false
    @State private var date = Date()
    @State private var expenseDay: GregorianDay?
    @State private var preparedDraft = false
    @State private var paymentChosen = false
    @State private var focusMerchantOnAppear = false
    @State private var saving = false
    @State private var rootBlockerID = UUID()
    @State private var confirmDiscard = false
    @State private var failure: String?
    private enum Field { case merchant, amount }
    @FocusState private var field: Field?
    @State private var commandID = UUID()
    @State private var bigRoute: MoneyBigExpenseRoute?
    private var service: AppMoneyService { .init(app: app) }
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var minor: Int { MoneyAmountInput.minor(raw, exponent: CurrencyExponents.specified.exponent(inputCurrency) ?? 2) ?? 0 }
    private var inputExponent: Int { CurrencyExponents.specified.exponent(inputCurrency) ?? 2 }
    private var inputCurrency: String { foreign ? reading?.tripCurrency ?? reading?.currency ?? "SAR" : reading?.currency ?? "SAR" }
    private var homeMinor: Int { guard let r = reading else { return minor }; return (try? FX.homeAmount(amountMinor: minor, currency: inputCurrency, rate: r.tripRate ?? "1", home: r.currency)) ?? 0 }
    private var method: MoneyPaymentChoice? { reading?.methods.first { $0.id == methodID } }
    private var merchantInput: Binding<String> {
        Binding(get: { merchant }, set: { value in
            guard value != merchant else { return }
            merchant = value
            // A category the user picked for this purchase stays; only a suggestion follows the merchant.
            guard categorySource != "manual" else { return }
            categoryID = nil; categorySource = nil
            if let learning = reading?.merchantLearning(for: value), let suggested = learning.suggestedCategoryID {
                categoryID = suggested; categorySource = "learned"
            }
        })
    }
    private var currentMerchantLearning: MerchantCategoryLearning.Result? {
        guard let reading, !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return reading.merchantLearning(for: merchant)
    }
    private var hasUnsavedInput: Bool {
        !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private func amount(_ value: Int) -> String { visible ? service.amount(value) : "•••" }
    private var split: ExpenseEntry.Split { ExpenseEntry.split(chargeMinor: method?.kind == .cash && reading?.cashCountedAtWithdrawal == true ? 0 : homeMinor, share: share) }
    private var nextHeadline: Headline? {
        guard let cycle = reading?.cycle, let day = expenseDay else { return nil }
        return ExpenseEntry.headlineAfter(elapsedDays: cycle.elapsedDays, cycle.input, dailySpentMinor: cycle.spent,
            expenseDay: MadarCalendarDays.distance(from: cycle.startDay, to: day) + 1, dailyChargeMinor: split.dailyMinor)
    }
    private var duplicate: Bool { reading?.nearby.contains { $0.methodID == methodID && $0.currency == inputCurrency && $0.amountMinor == minor && abs($0.at.timeIntervalSince(date)) <= 600 && ($0.merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == merchant.trimmingCharacters(in: .whitespacesAndNewlines) } == true && minor > 0 }
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Button { if hasUnsavedInput { field = nil; confirmDiscard = true } else { dismiss() } } label: { Image(systemName: "xmark").frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle) }.madarWaitsForSave()
                        .disabled(saving).accessibilityLabel("إغلاق").accessibilityIdentifier("money-expense-close")
                    Text("سجّل مصروفًا").font(.custom("thmanyahserifdisplay-Bold", size: 24, relativeTo: .title2)); Spacer()
                    Button {
                        if details { field = nil }
                        details.toggle()
                    } label: {
                        Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                            .foregroundStyle(details ? theme.background : theme.ink)
                            .background(details ? theme.ink : .clear, in: Circle())
                    }.accessibilityLabel(details ? "أخفِ تفاصيل المصروف" : "تفاصيل المصروف")
                        .accessibilityIdentifier("money-expense-details")
                }
#if DEBUG
                if ProcessInfo.processInfo.environment["MADAR_UI_MONEY_FIFO_HARNESS"] == "1",
                   ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil {
                    Button("اختبر طلبين بعد المصروف") {
                        app.presentMoneyExpenseSeed(.init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!, amount: "٧", merchant: "طلب ثانٍ", homeCurrency: true))
                        app.presentMoneyExpenseSeed(.init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!, amount: "٢٣", merchant: "طلب ثالث", homeCurrency: true))
                    }.accessibilityIdentifier("money-expense-test-queue-two")
                }
#endif
                if let reading {
                    amountHeading(reading)
                    if let code = reading.tripCurrency, code != reading.currency {
                        Picker("عملة المصروف", selection: $foreign) { Text(service.currencyName(code)).tag(true); Text(service.currencyName(reading.currency)).tag(false) }.pickerStyle(.segmented).accessibilityIdentifier("money-expense-currency")
                        if foreign {
                            Text(figure: reading.tripRate == nil ? "أدخل سعر الرحلة أولًا" : "بعملة البيت " + amount(homeMinor))
                                .font(MadarTypography.caption()).accessibilityIdentifier("money-expense-home-equivalent")
                        }
                    }
                    if !raw.isEmpty, MoneyAmountInput.minor(raw, exponent: CurrencyExponents.specified.exponent(inputCurrency) ?? 2) == nil {
                        Text("اكتب مبلغًا صحيحًا، مثل ١٢ أو ١٢٫٥").font(MadarTypography.caption()).foregroundStyle(theme.color("dueText"))
                    }
                    keypad
                    merchantChips(reading)
                    if details { merchantField }
                    payment(reading)
                    categorySuggestion(reading)
                    preferredCardSuggestion(reading)
                    shares(reading)
                    diary(reading)
                    if details { extraDetails(reading) }
                    if !visible {
                        Button { revealed = true } label: {
                            Text("أظهر الأرقام").font(MadarTypography.caption()).frame(minHeight: 44).contentShape(Rectangle())
                        }.accessibilityIdentifier("money-expense-reveal")
                    }
                    if let h = nextHeadline {
                        VStack(spacing: 3) {
                            Text(figure: h.availableNowMinor >= 0 ? "يبقى لك الآن " + amount(h.availableNowMinor) : "تتجاوز الدورة بـ" + amount(-h.availableNowMinor))
                                .font(MadarTypography.section()).foregroundStyle(theme.color(h.availableNowMinor >= 0 ? "surplusText" : "dueText")).contentTransition(.numericText()).accessibilityIdentifier("money-expense-after")
                            Text(figure: "اليوم: صرفت " + amount(h.todaySpentMinor) + " من " + amount(h.todayAllowanceMinor)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        }.padding(.top, 4)
                    }
                } else if let failure { Text(failure); Button("أعِد المحاولة", action: load) }
                else {
                    // B1-6: the number pad is ready at once; accounts and cards load behind it and the rest of the sheet joins when they arrive.
                    amountHeading()
                    keypad
                }
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.accessibilityIdentifier("money-expense")
            .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).buttonStyle(.madarPlain)
            .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar, .tabBar).hidesRoomAccessory(app, id: "money-expense")
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let reading, field == nil { saveBar(reading) }
            }
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("تمّ") { field = nil } } }
            .task {
                if !preparedDraft {
                    preparedDraft = true
                    if let seed {
                        raw = seed.amount; merchant = seed.merchant; commandID = seed.id
                        if seed.homeCurrency { foreign = false }
                    }
                }
                guard reading == nil else { return }
                await app.seedMoneyDefaults()
                guard !Task.isCancelled else { return }
                load()
            }
            .onChange(of: date) { expenseDay = try? service.expenseDay(at: date) }
            .fullScreenCover(item: $bigRoute) { route in
                MoneyBigExpenseView(app: app, route: route, revealed: $revealed) { bigRoute = nil; dismiss() }
            }
            .confirmationDialog("تتجاهل المصروف؟", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("تجاهل المصروف", role: .destructive) { dismiss() }.accessibilityIdentifier("money-expense-discard")
                Button("أكمل التسجيل") { }.accessibilityIdentifier("money-expense-continue")
            } message: { Text("المبلغ أو اسم المتجر غير محفوظ.") }
            .madarSheetLock(saving: saving, draft: hasUnsavedInput)
            .onChange(of: hasUnsavedInput || saving, initial: true) { _, blocked in app.setMoneyRootDraftBlocker(rootBlockerID, active: blocked) }
            .onDisappear { app.setMoneyRootDraftBlocker(rootBlockerID, active: false) }
    }
    private func canUse(_ payment: MoneyPaymentChoice, _ r: MoneyExpenseReading) -> Bool {
        payment.kind == .credit || payment.currency == r.currency || payment.currency == inputCurrency
    }
    private func waiting(_ r: MoneyExpenseReading) -> String? {
        if foreign, inputCurrency != r.currency, r.tripRate == nil { return "أدخل سعر الرحلة أولًا" }
        if r.methods.isEmpty { return "أضف مصدر دفع أولًا" }
        guard let method else { return "اختر مصدر الدفع" }
        if !canUse(method, r) { return "هذا المصدر بعملة أخرى؛ اختر غيره" }
        if share != .daily && envelopeID == nil { return "اختر المظروف الذي يُخصم منه" }
        return nil
    }
    private func saveBar(_ r: MoneyExpenseReading) -> some View {
        let blocked = waiting(r)
        let enabled = !saving && homeMinor > 0 && blocked == nil
        return VStack(spacing: 6) {
            if let failure {
                Text(failure).font(MadarTypography.caption()).foregroundStyle(theme.color("dueText"))
            } else if duplicate {
                Label("تبدو مسجّلة من قبل؛ راجع السجل قبل تسجيلها مرة أخرى.", systemImage: "doc.on.doc")
                    .font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")).accessibilityIdentifier("money-expense-duplicate")
            } else if !saving, minor > 0, let blocked {
                Text(blocked).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-expense-waiting")
            }
            Button(action: save) {
                Text(saving ? "جارٍ التسجيل…" : duplicate ? "سجّل عملية أخرى" : "سجّل")
                    .font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 50)
                    .background(theme.ink.opacity(enabled ? 1 : 0.4)).foregroundStyle(theme.background)
            }.disabled(!enabled).accessibilityIdentifier("money-expense-save")
        }
        .padding(.horizontal, 20).padding(.vertical, 8).frame(maxWidth: 620).frame(maxWidth: .infinity)
        .background(theme.background)
    }
    private func amountHeading(_ r: MoneyExpenseReading? = nil) -> some View {
        VStack(spacing: 0) {
            Text(figure: service.amount(minor, currency: inputCurrency) + (raw.last == "." || raw.last == "٫" ? "٫" : "")).font(.custom("thmanyahserifdisplay-Black", size: 60, relativeTo: .largeTitle)).contentTransition(.numericText()).accessibilityIdentifier("money-expense-amount")
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
        let editTitle = if merchant.isEmpty { "اسم المتجر" }
            else if r.merchants.contains(where: { $0.name == merchant }) { "عدّل الاسم" }
            else { merchant }
        return ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(r.merchants) { item in
                    Button { chooseMerchant(item) } label: { chip(item.name, selected: merchant == item.name) }
                        .accessibilityAddTraits(merchant == item.name ? .isSelected : [])
                        .accessibilityIdentifier("money-expense-merchant-" + item.name)
                }
                Button {
                    if details { field = .merchant }
                    else { focusMerchantOnAppear = true; details = true }
                } label: { chip(editTitle, selected: false) }.accessibilityIdentifier("money-expense-merchant-edit")
            }
        }.scrollIndicators(.hidden)
    }
    private func chip(_ text: String, selected: Bool) -> some View {
        Text(text).font(.custom("thmanyahseriftext-Regular", size: 15, relativeTo: .body)).padding(.horizontal, 13).frame(minHeight: 44).background(selected ? theme.ink : .clear).foregroundStyle(selected ? theme.background : theme.ink).clipShape(.capsule).glassEffect(.regular.interactive(), in: .capsule)
    }
    private func categorySuggestion(_ r: MoneyExpenseReading) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: "square.fill").font(.system(size: 8)).foregroundStyle(theme.color("accentText"))
                Text("التصنيف").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                Menu { ForEach(r.categories) { c in Button(c.name) { categoryID = c.id; categorySource = "manual" } }; Button("بلا تصنيف") { categoryID = nil; categorySource = "manual" } } label: {
                    Text(r.categories.first { $0.id == categoryID }?.name ?? (categorySource == "manual" ? "بلا تصنيف" : "اختر تصنيفًا"))
                        .font(MadarTypography.section()).frame(minHeight: 44)
                }
                    .accessibilityIdentifier("money-expense-category")
                Spacer()
            }
            if categorySource == "learned" {
                Text("اقتراح من اختياراتك السابقة؛ تقدر تغيّره لهذه العملية.").font(MadarTypography.fine()).foregroundStyle(theme.color("surplusText"))
            }
            if currentMerchantLearning?.hasMultipleQualifiedCategories == true {
                Text("سبق أن اخترت لهذا المتجر أكثر من تصنيف؛ اختر ما يناسب هذه العملية.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
        }.padding(11).frame(minHeight: 44).overlay { Rectangle().stroke(theme.color("reserveText"), style: StrokeStyle(lineWidth: 1, dash: [3, 2])) }
    }
    private func chooseMerchant(_ item: MoneyExpenseMerchant) {
        merchant = item.name
        if categorySource != "manual" {
            categoryID = item.categoryID
            categorySource = item.categorySource
        }
        if !paymentChosen, let reading, let suggestion = reading.methods.first(where: { $0.id == item.methodID }),
           canUse(suggestion, reading) { selectPayment(suggestion, reading) }
    }
    private func selectPayment(_ payment: MoneyPaymentChoice, _ r: MoneyExpenseReading) {
        methodID = payment.id
        if payment.kind == .cash && r.cashCountedAtWithdrawal && r.tripEnvelopeID == nil { share = .daily }
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
                    Button { paymentChosen = true; selectPayment(payment, r) } label: {
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
                        Text(shareTitle(s)).font(MadarTypography.fine()).frame(maxWidth: .infinity, minHeight: 44).background(share == s ? theme.ink : .clear).foregroundStyle(share == s ? theme.background : theme.ink).overlay { Rectangle().stroke(theme.color("reserveText"), lineWidth: 1) }
                    }.disabled(s != .daily && (r.envelopes.isEmpty || (method?.kind == .cash && r.cashCountedAtWithdrawal))).accessibilityIdentifier("money-expense-share-" + s.rawValue)
                }
            }
            if share != .daily {
                Menu { ForEach(r.envelopes) { e in Button(e.name) { envelopeID = e.id } } } label: {
                    HStack { Text(r.envelopes.first { $0.id == envelopeID }?.name ?? "اختر المظروف"); Spacer(); Text(figure: "منه " + amount(split.envelopeMinor)); Image(systemName: "chevron.down") }.font(MadarTypography.caption()).frame(minHeight: 44)
                }.accessibilityIdentifier("money-expense-envelope")
            }
        }
    }
    }
    private func shareTitle(_ share: ExpenseEntry.Share) -> String {
        switch share { case .daily: "كله من يومي"; case .quarter: service.digits.percent(25) + " مظروف"; case .half: service.digits.percent(50) + " مظروف"; case .envelope: "كله من مظروف" }
    }
    private var keypad: some View {
        VStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { column in
                        let key = row < 3 ? String(row * 3 + column + 1) : [inputExponent > 0 ? "dot" : "clear", "0", "delete"][column]
                        Button { tap(key) } label: {
                            Group { if key == "delete" { Image(systemName: "delete.backward") } else { Text(key == "clear" ? "مسح" : key == "dot" ? "٫" : service.digits.string(Int(key) ?? 0)) } }.font(.custom("thmanyahserifdisplay-Bold", size: key == "clear" ? 19 : 29, relativeTo: .title2)).frame(maxWidth: .infinity, minHeight: 47).background(theme.surface).overlay { Rectangle().stroke(theme.line, lineWidth: 1) }
                        }.simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in if key == "delete" { tap("clear") } })
                        .accessibilityLabel(key == "clear" ? "مسح المبلغ" : key == "delete" ? "حذف آخر رقم، اضغط مطولًا للمسح" : key == "dot" ? "الفاصلة العشرية" : key).accessibilityIdentifier("money-expense-key-" + key)
                    }
                }
            }
        }.padding(.top, 3)
    }
    private func tap(_ key: String) {
        let update = {
            let decimal = raw.firstIndex { $0 == "." || $0 == "٫" }
            if key == "clear" { raw = "" }
            else if key == "delete" { if !raw.isEmpty { raw.removeLast() } }
            else if key == "dot" { if decimal == nil { raw += raw.isEmpty ? "0." : "." } }
            else if raw.count < 9, decimal.map({ raw[raw.index(after: $0)...].count < inputExponent }) ?? true { raw += key }
        }
        if reduceMotion { update() } else { withAnimation(.easeOut(duration: 0.16), update) }
    }
    private func diary(_ r: MoneyExpenseReading) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if r.diaryOn {
                Button { showInDiary.toggle() } label: {
                    Label(showInDiary ? "يظهر في المذكرات" : "مخفي من المذكرات", systemImage: showInDiary ? "pencil.line" : "eye.slash")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.accessibilityIdentifier("money-expense-diary").accessibilityValue(showInDiary ? "ظاهر" : "مخفي")
            } else {
                Text("سطور المال مخفية من المذكرات في الإعدادات").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }
        }
    }
    private func payment(_ r: MoneyExpenseReading) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("مصدر الدفع").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(r.methods) { m in
                        Button { paymentChosen = true; selectPayment(m, r) } label: { chip(m.title, selected: methodID == m.id) }
                            .disabled(!canUse(m, r)).accessibilityAddTraits(methodID == m.id ? .isSelected : [])
                            .accessibilityIdentifier("money-expense-method-" + m.title)
                    }
                }
            }.scrollIndicators(.hidden)
            if r.methods.isEmpty { Text("أضف حسابًا من «الحسابات» أو بطاقة من «البطاقات» أولًا.").font(MadarTypography.body()) }
            else if let m = method {
                if m.kind == .credit {
                    Text("يُحسب من يومك يوم الشراء، ويخرج النقد عند سداد البطاقة.").font(MadarTypography.fine()).foregroundStyle(theme.color("accentText"))
                    if let due = m.purchaseDue { MadarDateLabel(app.dateLabels(due, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                } else { Text(m.kind == .cash && r.cashCountedAtWithdrawal ? "احتُسب عند السحب؛ لن يُخصم من يومك مرة أخرى." : "يخرج النقد الآن من " + (m.accountName ?? m.title)).font(MadarTypography.fine()).foregroundStyle(theme.color("accentText")) }
            }
        }
    }
    private var merchantField: some View {
        TextField("اسم المتجر، إن أردت", text: merchantInput)
            .textInputAutocapitalization(.never).focused($field, equals: .merchant)
            .submitLabel(.done).onSubmit { field = nil }
            .font(MadarTypography.body()).padding(.horizontal, 12).frame(minHeight: 44)
            .background(theme.surface).accessibilityIdentifier("money-expense-merchant-field")
            .onAppear {
                if focusMerchantOnAppear {
                    focusMerchantOnAppear = false
                    field = .merchant
                }
            }
    }
    private func extraDetails(_ r: MoneyExpenseReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("المبلغ، مع الكسور إن احتجت", text: $raw).keyboardType(.decimalPad).focused($field, equals: .amount)
                .font(MadarTypography.body()).frame(minHeight: 44).accessibilityIdentifier("money-expense-precise-amount")
            DatePicker("وقت المصروف", selection: $date, in: r.earliest...app.prayerNow(), displayedComponents: [.date, .hourAndMinute]).font(MadarTypography.caption())
            MadarDateLabel(app.dateLabels(.containing(date, in: app.activePlace.timeZone)), primaryFont: MadarTypography.caption(), secondaryFont: MadarTypography.fine())
        }.padding(12).background(theme.surface)
    }
    private func load() {
        do {
            let r = try service.loadExpense()
            reading = r
            let requestedMethod = seed?.method.flatMap { requested in r.methods.contains(where: { $0.id == requested }) ? requested : nil }
            if let id = requestedMethod ?? r.defaultMethodID, let payment = r.methods.first(where: { $0.id == id }) {
                selectPayment(payment, r)
            }
            expenseDay = r.today; date = app.prayerNow(); failure = nil
            if let id = r.tripEnvelopeID { envelopeID = id; share = .envelope }
            if let suggestion = currentMerchantLearning?.suggestedCategoryID, categorySource != "manual" {
                categoryID = suggestion; categorySource = "learned"
            }
        }
        catch { failure = "لم تكتمل قراءة مصادر الدفع. حاول مرة أخرى." }
    }
    private func save() {
        guard !saving, homeMinor > 0, let m = method, let r = reading, waiting(r) == nil else { return }
        var p: [String: MadarCore.JSONValue] = ["amountMinor": .string(String(minor)), "currency": .string(inputCurrency), "merchant": .string(merchant), "method": .string(m.kind == .cash ? "cash" : m.cardID == nil ? "transfer" : "card"), "eventAt": .string(ISO8601DateFormatter().string(from: date)), "showInDiary": .bool(showInDiary)]
        if let id = m.cardID { p["cardID"] = .string(id.uuidString) } else if let id = m.accountID { p["fromAccountID"] = .string(id.uuidString) }
        if let id = categoryID { p["categoryID"] = .string(id.uuidString) }
        if categoryID != nil, let categorySource { p["categorySource"] = .string(categorySource) }
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
