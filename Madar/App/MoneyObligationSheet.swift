import SwiftUI
import MadarCore
import MadarDesign
import MadarMoney

/// Adds a bill, subscription, loan or instalment plan (M5-V09, M5-X00). Anything recurring takes a free interval and a
/// free first due day; the next due days show live in both calendars, with the ladder's months before and after.
struct MoneyObligationSheet: View {
    let app: AppSession
    let ladder: [MoneyLadderMonth]
    let visible: Bool
    @Binding var revealed: Bool
    let suggestion: SubscriptionSuggestionEngine.Suggestion?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var saving = false
    @State private var kind = "bill"
    @State private var name = ""
    @State private var rawAmount = ""
    @State private var amountWasEdited = false
    @State private var count = 12
    @State private var every = 1
    @State private var unit = RecurrenceUnit.month
    @State private var firstDue = Date()
    @State private var errorMessage: String?
    /// The decimal pad has no return key: «تم» above it, a scroll or a tap on the title closes it.
    private enum Field { case name, amount }
    @FocusState private var field: Field?
    private let suggestedAmountInput: String?

    private var numbersVisible: Bool { visible || revealed }

    init(app: AppSession, ladder: [MoneyLadderMonth], visible: Bool, revealed: Binding<Bool>, suggestion: SubscriptionSuggestionEngine.Suggestion? = nil) {
        self.app = app
        self.ladder = ladder
        self.visible = visible
        self._revealed = revealed
        self.suggestion = suggestion
        let suggestedAmount = suggestion.map { Self.decimalInput($0.amountMinor, currency: $0.currency) }
        self.suggestedAmountInput = suggestedAmount
        _kind = State(initialValue: suggestion == nil ? "bill" : "subscription")
        _name = State(initialValue: suggestion?.name ?? "")
        // A suggested amount is passive account data. Keep it out of the editable field and
        // accessibility tree until the user explicitly reveals the room's hidden numbers.
        _rawAmount = State(initialValue: visible || revealed.wrappedValue ? suggestedAmount ?? "" : "")
        _firstDue = State(initialValue: suggestion?.nextDue ?? .now)
    }

    private static func decimalInput(_ amountMinor: Int, currency: String) -> String {
        guard let exponent = CurrencyExponents.specified.exponent(currency), (0...3).contains(exponent) else { return "" }
        guard exponent > 0 else { return String(amountMinor) }
        let digits = String(amountMinor)
        let padded = String(repeating: "0", count: max(0, exponent + 1 - digits.count)) + digits
        let whole = String(padded.dropLast(exponent))
        let fraction = String(padded.suffix(exponent)).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return fraction.isEmpty ? whole : whole + "." + fraction
    }
    private var service: AppMoneyService { .init(app: app) }
    private var digits: MadarNumberFormatter { service.digits }
    private var zone: TimeZone { app.activePlace.timeZone }
    private var today: GregorianDay { .containing(app.prayerNow(), in: zone) }
    private var first: GregorianDay { .containing(firstDue, in: zone) }
    private var recurring: Bool { kind == "bill" || kind == "subscription" }
    private var schedule: Recurrence? { Recurrence(every: every, unit: unit, first: first) }
    private var amountMinor: Int? {
        CurrencyExponents.specified.exponent(app.string("core.currency")).flatMap { MoneyAmountInput.minor(rawAmount, exponent: $0) }.flatMap { $0 > 0 ? $0 : nil }
    }
    /// Every due day this obligation adds: the open-ended schedule from today, or the plan's instalments.
    private func dues(before end: GregorianDay) -> [GregorianDay] {
        guard let schedule else { return [] }
        if recurring { return schedule.occurrences(from: today, before: end) }
        return (0..<count).compactMap { schedule.occurrence($0) }.filter { $0 >= today && $0 < end }
    }
    /// The next three due days the user will see.
    private var upcoming: [GregorianDay] {
        guard let schedule else { return [] }
        return recurring ? schedule.preview(from: today) : (0..<min(3, count)).compactMap { schedule.occurrence($0) }
    }
    /// What the ladder's month `index` (from this month) gains once the obligation is saved.
    private func added(_ index: Int) -> Int {
        guard let amount = amountMinor, let start = try? GregorianDay(year: today.year, month: today.month, day: 1),
              let month = Recurrence(every: 1, unit: .month, first: start), let from = month.occurrence(index), let to = month.occurrence(index + 1) else { return 0 }
        let days = dues(before: to).filter { $0 >= from }
        return amount * days.count
    }
    private func instalments(_ n: Int) -> String {
        if n == 1 { return "قسط واحد" }
        if n == 2 { return "قسطان" }
        switch n % 100 {
        case 3...10: return digits.string(n) + " أقساط"
        case 11...99: return digits.string(n) + " قسطًا"
        default: return digits.string(n) + " قسط"
        }
    }
    private func unitName(_ unit: RecurrenceUnit) -> String {
        switch unit { case .day: "يوم"; case .week: "أسبوع"; case .month: "شهر"; case .year: "سنة" }
    }

    var body: some View {
        // A navigation container only so the keyboard's «تم» bar can show; its own bar stays hidden.
        NavigationStack { form.toolbar(.hidden, for: .navigationBar) }.presentationDetents([.large]).madarSheetLock(saving: saving)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("التزام جديد").font(.custom("thmanyahserifdisplay-Bold", size: 24, relativeTo: .title2))
                    Spacer()
                    Button("إلغاء") { dismiss() }.frame(minHeight: 44).accessibilityIdentifier("money-obligation-cancel").madarWaitsForSave()
                }.contentShape(Rectangle()).onTapGesture { field = nil }
                Picker("النوع", selection: $kind) {
                    Text("فاتورة").tag("bill"); Text("اشتراك").tag("subscription"); Text("قرض").tag("loan"); Text("تقسيط").tag("installment")
                }.pickerStyle(.segmented).accessibilityIdentifier("money-obligation-kind")
                field("الاسم") {
                    TextField(placeholder, text: $name).focused($field, equals: .name).accessibilityIdentifier("money-obligation-name").onChange(of: name) { errorMessage = nil }
                }
                if suggestion != nil && !numbersVisible {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("المبلغ المقترح مخفي حتى تُظهر الأرقام.")
                            .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        Button("أظهر الأرقام") {
                            revealed = true
                            if !amountWasEdited { rawAmount = suggestedAmountInput ?? "" }
                        }
                        .font(MadarTypography.caption()).frame(minHeight: 44)
                        .accessibilityIdentifier("money-obligation-reveal-suggested-amount")
                    }
                } else {
                    field(recurring ? "المبلغ في كل مرة" : "مبلغ القسط") {
                        TextField("٠", text: $rawAmount).keyboardType(.decimalPad).focused($field, equals: .amount)
                            .accessibilityIdentifier("money-obligation-amount")
                            .onChange(of: rawAmount) { amountWasEdited = true; errorMessage = nil }
                    }
                }
                if !recurring {
                    Stepper(value: $count, in: 1...120) { Text(instalments(count)).font(MadarTypography.body()) }
                        .accessibilityIdentifier("money-obligation-count")
                }
                rhythm
                if amountMinor != nil, !ladder.isEmpty {
                    if numbersVisible { ladderPreview }
                    else {
                        Text("أرقامك مخفية؛ أظهرها من صفحة الالتزامات لترى أثر الإضافة.")
                            .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            .accessibilityIdentifier("money-obligation-preview-hidden")
                    }
                }
                if let errorMessage { Text(errorMessage).font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")) }
                Button(action: save) {
                    Text("احفظ الالتزام").font(.custom("thmanyahsans-Bold", size: 18, relativeTo: .headline)).foregroundStyle(theme.background)
                        .frame(maxWidth: .infinity, minHeight: 54).background(theme.ink)
                }.buttonStyle(.madarPlain)
                    .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || amountMinor == nil)
                    .accessibilityIdentifier("money-obligation-save")
            }.padding(16)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("تمّ") { field = nil }.accessibilityIdentifier("money-obligation-keyboard-done")
                }
            }
            .onChange(of: unit) { every = min(every, unit.maxEvery) }
    }

    private var placeholder: String {
        switch kind { case "subscription": "مثل: الإيجار أو النادي"; case "loan": "مثل: قرض السيارة"; case "installment": "مثل: تقسيط الجوال"; default: "مثل: الكهرباء" }
    }

    /// «يتكرر كل»: the interval, the first due day, and the next three due days in both calendars.
    private var rhythm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recurring ? "يتكرر" : "الأقساط").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            HStack(spacing: 10) {
                Text(schedule.map { RecurrencePhrase.every($0, digits: digits) } ?? "")
                    .font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title3)).lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityIdentifier("money-obligation-rhythm")
                Spacer(minLength: 8)
                Stepper("", value: $every, in: 1...unit.maxEvery).labelsHidden().accessibilityLabel("عدد المرات بين كل موعدين")
                    .accessibilityValue(digits.string(every)).accessibilityIdentifier("money-obligation-every")
            }
            Picker("الوحدة", selection: $unit) {
                ForEach(RecurrenceUnit.allCases, id: \.self) { Text(unitName($0)).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("money-obligation-unit")
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(recurring ? "أول موعد" : "أول قسط").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    Text(RecurrencePhrase.relative(from: today, to: first, digits: digits)).font(.custom("thmanyahsans-Bold", size: 15, relativeTo: .callout))
                        .accessibilityIdentifier("money-obligation-first-relative")
                    MadarDateLabel(app.dateLabels(first), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }
                Spacer(minLength: 8)
                DatePicker("أول موعد", selection: $firstDue, displayedComponents: .date).labelsHidden()
                    .accessibilityIdentifier("money-obligation-first")
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(upcoming.enumerated()), id: \.element) { index, day in
                    HStack(alignment: .center, spacing: 12) {
                        Circle().fill(index == 0 ? theme.color("reserve") : Color.clear).overlay { Circle().stroke(theme.color("reserve"), lineWidth: 1.2) }
                            .frame(width: 10, height: 10)
                        MadarDateLabel(app.dateLabels(day), primaryFont: .custom("thmanyahsans-Bold", size: 16, relativeTo: .body), secondaryFont: MadarTypography.fine())
                        Spacer(minLength: 8)
                        Text(RecurrencePhrase.relative(from: today, to: day, digits: digits)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    }.padding(.vertical, 8).overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 0.6) }
                }
                if !recurring, count > 3, let last = schedule?.occurrence(count - 1) {
                    HStack(spacing: 6) {
                        Text("وآخرها").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        MadarDateLabel(app.dateLabels(last, compact: true), primaryFont: MadarTypography.caption(), secondaryFont: MadarTypography.fine())
                    }.padding(.top, 8)
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("money-obligation-upcoming")
        }.padding(14).background(theme.surface).overlay(alignment: .trailing) { Rectangle().fill(theme.color(kind == "subscription" ? "reserve" : kind == "bill" ? "surplus" : kind == "loan" ? "accent" : "bills")).frame(width: 4) }
    }

    private var ladderPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("أثره على السلّم").font(MadarTypography.cardTitle())
            let totals = ladder.enumerated().map { $0.element.total + added($0.offset) }
            let monthlyPeak = totals.max() ?? 0
            let peak = max(1, monthlyPeak)
            HStack(spacing: 14) {
                HStack(spacing: 5) { Rectangle().fill(theme.secondaryInk.opacity(0.35)).frame(width: 8, height: 8).accessibilityHidden(true); Text("قبل الإضافة") }
                HStack(spacing: 5) { Rectangle().fill(theme.color("reserve")).frame(width: 8, height: 8).accessibilityHidden(true); Text("الإضافة") }
            }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(ladder.enumerated()), id: \.element.id) { index, month in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle().fill(theme.color("reserve")).frame(height: 70 * CGFloat(added(index)) / CGFloat(peak))
                        Rectangle().fill(theme.secondaryInk.opacity(0.35)).frame(height: 70 * CGFloat(month.total) / CGFloat(peak))
                    }.frame(maxWidth: .infinity).frame(height: 70)
                }
            }.environment(\.layoutDirection, .rightToLeft)
            Text(figure: "أعلى مجموع شهري بعد الإضافة " + service.amount(monthlyPeak) + " " + service.currencyName(app.string("core.currency")))
                .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-obligation-monthly-peak")
        }.accessibilityElement(children: .contain).accessibilityIdentifier("money-obligation-preview")
    }

    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            content().font(MadarTypography.body()).padding(10).overlay { Rectangle().stroke(theme.line, lineWidth: 1) }
        }
    }
    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMessage = "اكتب اسم الالتزام."; return }
        guard let amount = amountMinor else { errorMessage = "أدخل مبلغًا أكبر من صفر."; return }
        var payload: [String: MadarCore.JSONValue] = ["kind": .string(kind), "name": .string(String(trimmed.prefix(60))), "amountMinor": .string(String(amount)),
            "firstDue": .string(first.description), "repeatEvery": .number(Double(every)), "repeatUnit": .string(unit.rawValue)]
        if !recurring { payload["count"] = .number(Double(count)) }
        guard !saving else { return }
        saving = true
        Task {
            do { try await app.executeMoneyCommand("money.saveObligation", payload: payload); dismiss() }
            catch { errorMessage = "لم يُحفظ الالتزام."; saving = false }
        }
    }
}
