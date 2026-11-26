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
    @State private var firstDue: Date
    @State private var initialDueDay: GregorianDay
    @State private var rootBlockerID = UUID()
    @State private var confirmDiscard = false
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
        let due = suggestion?.nextDue ?? app.prayerNow()
        _firstDue = State(initialValue: due)
        _initialDueDay = State(initialValue: .containing(due, in: app.activePlace.timeZone))
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
    private var hasUnsavedInput: Bool {
        let expectedName = suggestion?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let expectedKind = suggestion == nil ? "bill" : "subscription"
        let amountChanged = amountWasEdited && rawAmount.trimmingCharacters(in: .whitespacesAndNewlines) != (suggestedAmountInput ?? "")
        return name.trimmingCharacters(in: .whitespacesAndNewlines) != expectedName ||
            amountChanged || kind != expectedKind || every != 1 || unit != .month ||
            (!recurring && count != 12) || first != initialDueDay
    }
    private var blocksRootRoute: Bool { hasUnsavedInput || saving }
    private var schedule: Recurrence? { Recurrence(every: every, unit: unit, first: first) }
    private enum DraftAmount {
        case empty
        case invalid(String)
        case ready(minor: Int, preview: LadderPreview)

        var canSave: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    private struct LadderPreview {
        var months: [(before: Int, added: Int)] = []
        var peak = 0
    }

    private var draftAmount: DraftAmount {
        guard !rawAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
        guard let exponent = CurrencyExponents.specified.exponent(app.string("core.currency")),
              let amount = MoneyAmountInput.minor(rawAmount, exponent: exponent), amount > 0 else {
            return .invalid("أدخل مبلغًا صحيحًا أكبر من صفر.")
        }
        guard MoneyCommandPayload.acceptsObligationAmount(amount, recurring: recurring) else {
            return .invalid("المبلغ أكبر من الحدّ الممكن لهذا الالتزام. خفّضه ثم احفظ.")
        }
        guard let preview = projectLadder(amountMinor: amount) else {
            return .invalid("المجموع الشهري أكبر من الحدّ الممكن. خفّض المبلغ أو غيّر التكرار.")
        }
        return .ready(minor: amount, preview: preview)
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
    /// Compute the preview once from exact minor units before showing bars or enabling save.
    private func projectLadder(amountMinor: Int) -> LadderPreview? {
        var preview = LadderPreview()
        let currentDay = today
        guard let start = try? GregorianDay(year: currentDay.year, month: currentDay.month, day: 1),
              let months = Recurrence(every: 1, unit: .month, first: start) else { return nil }
        for (index, month) in ladder.enumerated() {
            guard let from = months.occurrence(index), let to = months.occurrence(index + 1) else { return nil }
            let days = dues(before: to).filter { $0 >= from }.count
            let added = amountMinor.multipliedReportingOverflow(by: days)
            guard !added.overflow else { return nil }
            var before = 0
            for part in [month.loanMinor, month.installmentMinor, month.billMinor, month.subscriptionMinor] {
                let subtotal = before.addingReportingOverflow(part)
                guard !subtotal.overflow else { return nil }
                before = subtotal.partialValue
            }
            let total = before.addingReportingOverflow(added.partialValue)
            guard !total.overflow else { return nil }
            preview.months.append((before, added.partialValue))
            preview.peak = max(preview.peak, total.partialValue)
        }
        return preview
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
        NavigationStack { form.toolbar(.hidden, for: .navigationBar) }
            .presentationDetents([.large])
            .madarSheetLock(saving: saving, draft: hasUnsavedInput)
            .alert("تتجاهل الالتزام؟", isPresented: $confirmDiscard) {
                Button("تجاهل الالتزام", role: .destructive) { dismiss() }
                Button("أكمل التعديل", role: .cancel) {}
            }
            .onChange(of: blocksRootRoute, initial: true) { _, blocked in
                app.setMoneyRootDraftBlocker(rootBlockerID, active: blocked)
            }
            .onDisappear { app.setMoneyRootDraftBlocker(rootBlockerID, active: false) }
    }

    private var form: some View {
        let amount = draftAmount
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
#if DEBUG
                if ProcessInfo.processInfo.environment["MADAR_UI_MONEY_ROOT_ROUTE_HARNESS"] == "1" {
                    Button("اختبر رابط المال") { app.open(URL(string: "madar://mal")!) }
                        .accessibilityIdentifier("money-root-test-route")
                }
#endif
                HStack {
                    Text("التزام جديد").font(.custom("thmanyahserifdisplay-Bold", size: 24, relativeTo: .title2))
                    Spacer()
                    Button(action: close) {
                        Text("إلغاء").frame(minHeight: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("money-obligation-cancel").madarWaitsForSave()
                }.contentShape(Rectangle()).onTapGesture { field = nil }
                Picker("النوع", selection: $kind) {
                    Text("فاتورة").tag("bill"); Text("اشتراك").tag("subscription"); Text("قرض").tag("loan"); Text("تقسيط").tag("installment")
                }.pickerStyle(.segmented).disabled(saving).accessibilityIdentifier("money-obligation-kind")
                field("الاسم") {
                    TextField(placeholder, text: $name).focused($field, equals: .name).accessibilityIdentifier("money-obligation-name").onChange(of: name) { errorMessage = nil }
                }.disabled(saving)
                if suggestion != nil && !numbersVisible {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("المبلغ المقترح مخفي حتى تُظهر الأرقام.")
                            .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        Button {
                            revealed = true
                            if !amountWasEdited { rawAmount = suggestedAmountInput ?? "" }
                        } label: { Text("أظهر الأرقام")
                        .font(MadarTypography.caption()).frame(minHeight: 44).contentShape(Rectangle()) }
                        .accessibilityIdentifier("money-obligation-reveal-suggested-amount")
                    }.disabled(saving)
                } else {
                    field(recurring ? "المبلغ في كل مرة" : "مبلغ القسط") {
                        TextField("٠", text: $rawAmount).keyboardType(.decimalPad).focused($field, equals: .amount)
                            .accessibilityIdentifier("money-obligation-amount")
                            .onChange(of: rawAmount) { amountWasEdited = true; errorMessage = nil }
                    }.disabled(saving)
                }
                if case .invalid(let message) = amount {
                    Text(message).font(MadarTypography.caption()).foregroundStyle(theme.color("dueText"))
                        .accessibilityIdentifier("money-obligation-amount-error")
                }
                if !recurring {
                    Stepper(value: $count, in: 1...MoneyCommandPayload.maxObligationInstallments) { Text(instalments(count)).font(MadarTypography.body()) }
                        .disabled(saving).accessibilityIdentifier("money-obligation-count")
                }
                rhythm.disabled(saving)
                if case .ready(_, let preview) = amount, !ladder.isEmpty {
                    if numbersVisible { ladderPreview(preview) }
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
                    .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !amount.canSave)
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
                    .environment(\.timeZone, zone)
                    .accessibilityIdentifier("money-obligation-first")
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(upcoming.enumerated()), id: \.element) { index, day in
                    HStack(alignment: .center, spacing: 12) {
                        Circle().fill(index == 0 ? theme.color("reserve") : Color.clear).glassEffect(.regular.interactive(), in: .circle)
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

    private func ladderPreview(_ preview: LadderPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("أثره على السلّم").font(MadarTypography.cardTitle())
            let peak = CGFloat(max(1, preview.peak))
            HStack(spacing: 14) {
                HStack(spacing: 5) { Rectangle().fill(theme.secondaryInk.opacity(0.35)).frame(width: 8, height: 8).accessibilityHidden(true); Text("قبل الإضافة") }
                HStack(spacing: 5) { Rectangle().fill(theme.color("reserve")).frame(width: 8, height: 8).accessibilityHidden(true); Text("الإضافة") }
            }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(ladder.enumerated()), id: \.element.id) { index, _ in
                    let month = preview.months[index]
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle().fill(theme.color("reserve")).frame(height: 70 * CGFloat(month.added) / peak)
                        Rectangle().fill(theme.secondaryInk.opacity(0.35)).frame(height: 70 * CGFloat(month.before) / peak)
                    }.frame(maxWidth: .infinity).frame(height: 70)
                }
            }.environment(\.layoutDirection, .rightToLeft)
            Text(figure: "أعلى مجموع شهري بعد الإضافة " + service.amount(preview.peak) + " " + service.currencyName(app.string("core.currency")))
                .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-obligation-monthly-peak")
        }.accessibilityElement(children: .contain).accessibilityIdentifier("money-obligation-preview")
    }

    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            content().font(MadarTypography.body()).padding(10).overlay { Rectangle().stroke(theme.line, lineWidth: 1) }
        }
    }
    private func close() {
        guard !saving else { return }
        field = nil
        if hasUnsavedInput { confirmDiscard = true }
        else { dismiss() }
    }

    private func save() {
        guard !saving, case .ready(let amount, _) = draftAmount else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMessage = "اكتب اسم الالتزام."; return }
        var payload: [String: MadarCore.JSONValue] = ["kind": .string(kind), "name": .string(String(trimmed.prefix(60))), "amountMinor": .string(String(amount)),
            "firstDue": .string(first.description), "repeatEvery": .number(Double(every)), "repeatUnit": .string(unit.rawValue)]
        if !recurring { payload["count"] = .number(Double(count)) }
        field = nil
        errorMessage = nil
        saving = true
        Task {
            do { try await app.executeMoneyCommand("money.saveObligation", payload: payload); dismiss() }
            catch { errorMessage = "لم يُحفظ الالتزام."; saving = false }
        }
    }
}
