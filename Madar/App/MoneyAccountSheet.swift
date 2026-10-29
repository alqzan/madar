import SwiftUI
import MadarCore
import MadarDesign
import MadarMoney

struct MoneyAccountSheet: View {
    let app: AppSession
    let original: MoneyAccountEdit
    let visible: Bool
    @Binding var revealed: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var draft: MoneyAccountEdit
    @State private var balance: String
    @State private var senders: String
    @State private var saving = false
    @State private var failure: String?
    @State private var confirmingRemoval = false
    @FocusState private var editing: Bool
    private var service: AppMoneyService { .init(app: app) }
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var numbersVisible: Bool { visible || revealed }
    init(app: AppSession, original: MoneyAccountEdit, visible: Bool, revealed: Binding<Bool>) {
        self.app = app; self.original = original; self.visible = visible; self._revealed = revealed; _draft = State(initialValue: original)
        let exp = CurrencyExponents.specified.exponent(original.currency) ?? 2
        var scale = 1; for _ in 0..<exp { scale *= 10 }
        let n = abs(original.openingMinor), fraction = String(n % scale)
        _balance = State(initialValue: !original.openingKnown ? "" : (original.openingMinor < 0 ? "-" : "") + String(n / scale) + (exp > 0 ? "." + String(repeating: "0", count: max(0, exp - fraction.count)) + fraction : ""))
        _senders = State(initialValue: original.senderIDs.joined(separator: "\n"))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text(original.isNew ? "حساب جديد" : draft.name).font(.custom("thmanyahserifdisplay-Bold", size: 25, relativeTo: .title2)); Spacer(); Button("إغلاق") { dismiss() }.frame(minHeight: 44).accessibilityIdentifier("money-account-editor-close") }
                    field("اسم الحساب") { TextField("مثل: حساب الراتب", text: $draft.name).focused($editing).accessibilityIdentifier("money-account-name") }
                    field("البنك أو المحفظة") { TextField("اسم البنك", text: $draft.bank).focused($editing).accessibilityIdentifier("money-account-bank") }
                    field("آخر أربعة أرقام، إن وجدت") { TextField("مثل ١٢٣٤", text: $draft.last4).keyboardType(.numberPad).focused($editing).accessibilityIdentifier("money-account-last4") }
                    Picker("النوع", selection: $draft.kind) { ForEach(["current", "savings", "cash", "wallet"], id: \.self) { Text(AppMoneyService.accountKind($0)).tag($0) } }.pickerStyle(.segmented).disabled(draft.fixedCheckpoint).accessibilityIdentifier("money-account-kind")
                    Toggle("هذا الحساب ملكي", isOn: Binding(get: { draft.ownership == "mine" }, set: { draft.ownership = $0 ? "mine" : "notMine" })).disabled(draft.fixedCheckpoint).accessibilityIdentifier("money-account-owned")
                    Text(draft.ownership == "mine" ? "يدخل رصيده في النقد ولك فعلًا." : "يبقى ظاهرًا بجذر مقطوع، خارج النقد ولك فعلًا والزكاة، ورسائله تُتجاهل.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    if draft.kind == "wallet" { Toggle("أتتبع رصيد المحفظة", isOn: $draft.tracked).disabled(draft.fixedCheckpoint).accessibilityIdentifier("money-account-tracked") }
                    HStack { Text("العملة"); Spacer(); Picker("العملة", selection: $draft.currency) { ForEach(CurrencyExponents.specified.exponents.keys.sorted(), id: \.self) { Text($0).tag($0) } }.labelsHidden().disabled(draft.fixedCheckpoint).accessibilityIdentifier("money-account-currency") }
                    if !original.isNew && original.openingKnown && !numbersVisible {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("رصيد البداية محفوظ ومخفي حتى تُظهر الأرقام.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            Button("أظهر الأرقام") { revealed = true }.font(MadarTypography.caption()).frame(minHeight: 44)
                                .accessibilityIdentifier("money-account-reveal-opening")
                        }
                    } else {
                        field(draft.openingKnown ? "رصيد البداية، بعملة الحساب" : "رصيد البنك عند المطابقة") { TextField("٠", text: $balance).keyboardType(.numbersAndPunctuation).focused($editing).disabled(draft.fixedCheckpoint && draft.openingKnown).accessibilityIdentifier("money-account-opening") }
                    }
                    if !draft.fixedCheckpoint || !draft.openingKnown { DatePicker("تاريخ هذا الرصيد", selection: $draft.openingAt, in: ...app.prayerNow(), displayedComponents: [.date, .hourAndMinute]) }
                    MadarDateLabel(app.dateLabels(.containing(draft.openingAt, in: app.activePlace.timeZone)), primaryFont: MadarTypography.caption(), secondaryFont: MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    if !draft.openingKnown { Text("لم يُعرف رصيدها بعد. أدخل رصيد البنك ووقت المطابقة ليبدأ الحساب منه؛ الحركات الأقدم تبقى محفوظة.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                    if draft.fixedCheckpoint && draft.openingKnown { Text("توجد حركات أو مطابقة على هذا الحساب؛ رصيد البداية ونوعه وملكيته ثابتة لحفظ دفتره. تصحيح الرصيد من «المطابقة».").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-account-checkpoint-fixed") }
                    // An account that is not mine is outside zakat already (the caption above says so).
                    if draft.ownership == "mine" { Toggle("أدخله في حساب الزكاة", isOn: $draft.zakatInclude).accessibilityIdentifier("money-account-zakat") }
                    field("أسماء مرسلي رسائل البنك، اسم في كل سطر") { TextField("أسماء المرسل", text: $senders, axis: .vertical).lineLimit(2...5).focused($editing).accessibilityIdentifier("money-account-senders") }
                    if !balanceReadable { Text("لم أفهم الرصيد؛ اكتب أرقامًا وفاصلة واحدة على الأكثر.").font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")) }
                    if let failure { Text(failure).font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")) }
                    // AU-34: the reason sits beside the dimmed save, not only mid-form.
                    if !saving && !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && balanceIsRequired && balanceIsEmpty { Text(draft.openingKnown ? "أدخل رصيد البداية لتحفظ الحساب" : "أدخل رصيد البنك لتحفظ الحساب").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-account-waiting") }
                    Button(action: save) { Text(saving ? "جارٍ الحفظ…" : "احفظ الحساب").font(MadarTypography.cardTitle()).frame(maxWidth: .infinity, minHeight: 54).background(theme.ink).foregroundStyle(theme.background) }.disabled(saving || !balanceReadable || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (balanceIsRequired && balanceIsEmpty)).accessibilityIdentifier("money-account-save")
                    // Item 34: an account entered by mistake goes, while nothing refers to it; the toast offers undo.
                    if !original.isNew && original.removable {
                        Button(role: .destructive) { confirmingRemoval = true } label: {
                            Label("احذف هذا الحساب", systemImage: "trash").font(MadarTypography.caption())
                                .foregroundStyle(theme.color("dueText")).frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .disabled(saving)
                        .accessibilityIdentifier("money-account-remove")
                        .confirmationDialog("حذف «\(original.name)»؟", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                            Button("احذف الحساب", role: .destructive, action: remove).accessibilityIdentifier("money-account-remove-confirm")
                            Button("إلغاء", role: .cancel) {}
                        } message: { Text("لا حركات ولا بطاقات عليه، فلا يتغيّر شيء من أرقامك سوى رصيد بدايته. يمكنك التراجع بعد الحذف.") }
                    }
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively).background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).buttonStyle(.madarPlain)
                .toolbar(.hidden, for: .navigationBar).toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("تمّ") { editing = false }.accessibilityIdentifier("money-account-keyboard-done") } }
        }
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk); content().font(MadarTypography.body()).padding(10).frame(minHeight: 44).overlay { Rectangle().stroke(theme.line, lineWidth: 1) } }
    }
    private func remove() {
        saving = true; failure = nil
        Task {
            do { try await app.executeMoneyCommand("money.removeAccount", payload: ["id": .string(original.id.uuidString)]); dismiss() }
            catch { saving = false; failure = "لم يُحذف الحساب؛ ربما صار عليه حركة أو بطاقة. أعد فتح الحساب لترى حاله." }
        }
    }
    /// The typed balance reads as an amount (a leading «-» or «−» allowed); a blank field is judged by the opening rule.
    private var balanceIsEmpty: Bool { balance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var balanceIsRequired: Bool { !draft.fixedCheckpoint || !draft.openingKnown }
    private var balanceReadable: Bool {
        let raw = balance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return true }
        let negative = raw.hasPrefix("-") || raw.hasPrefix("−")
        guard let exponent = CurrencyExponents.specified.exponent(draft.currency) else { return false }
        return MoneyAmountInput.minor(negative ? String(raw.dropFirst()) : raw, exponent: exponent) != nil
    }
    private func save() {
        guard !saving else { return }; editing = false
        let raw = balance.trimmingCharacters(in: .whitespacesAndNewlines), negative = raw.hasPrefix("-") || raw.hasPrefix("−")
        let balanceMinor: Int
        if draft.fixedCheckpoint && draft.openingKnown {
            balanceMinor = original.openingMinor
        } else {
            guard let exponent = CurrencyExponents.specified.exponent(draft.currency), let minor = MoneyAmountInput.minor(negative ? String(raw.dropFirst()) : raw, exponent: exponent) else { failure = "راجع مبلغ رصيد البداية."; return }
            balanceMinor = minor * (negative ? -1 : 1)
        }
        let last4 = draft.last4.map { c in c.wholeNumberValue.map(String.init) ?? String(c) }.joined()
        let aliases = Array(Set(senders.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        var payload: [String: MadarCore.JSONValue] = ["id": .string(draft.id.uuidString), "name": .string(draft.name.trimmingCharacters(in: .whitespacesAndNewlines)), "bank": .string(draft.bank.trimmingCharacters(in: .whitespacesAndNewlines)), "last4": .string(last4), "kind": .string(draft.kind), "ownership": .string(draft.ownership), "currency": .string(draft.currency), "balanceMinor": .string(String(balanceMinor)), "balanceAt": .string(ISO8601DateFormatter().string(from: draft.openingAt)), "senderIDs": .array(aliases.map { .string($0) }), "tracked": .bool(draft.tracked), "zakatInclude": .bool(draft.zakatInclude)]
        if !draft.openingKnown { payload["establishBalance"] = .bool(true) }
        saving = true
        Task { do { try await app.executeMoneyCommand("money.saveAccount", payload: payload); dismiss() } catch { saving = false; failure = "لم يُحفظ الحساب. راجع آخر أربعة أرقام واسم البنك؛ يجب أن يميّزا حسابًا واحدًا." } }
    }
}
