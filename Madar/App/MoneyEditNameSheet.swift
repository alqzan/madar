import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarDesign
import MadarMoney
import MadarCommands

/// FB-45: correct a commitment or an envelope after saving it. A commitment changes its name, and a bill or
/// subscription its amount (its next reservations follow; paid movements keep theirs). An instalment plan keeps its
/// amount because its ladder is already written. An envelope changes its name only. One command, one undo.
struct MoneyEditNameSheet: View {
    enum Target: Identifiable {
        case obligation(UUID), envelope(UUID)
        var id: String { switch self { case .obligation(let id): "o-" + id.uuidString; case .envelope(let id): "e-" + id.uuidString } }
    }
    let app: AppSession
    let target: Target
    /// The room's hidden numbers stay hidden: the amount field starts empty until the user reveals them.
    let visible: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var name = ""
    @State private var rawAmount = ""
    @State private var original = (name: "", amount: 0)
    @State private var recurring = false
    /// The commitment's own currency, not today's home currency (it may have changed since it was saved).
    @State private var currency: String?
    @State private var loaded = false
    @State private var saving = false
    @State private var failure: String?
    @FocusState private var focused: Bool

    private var exponent: Int? { CurrencyExponents.specified.exponent(currency ?? app.string("core.currency")) }
    private var amountMinor: Int? { exponent.flatMap { MoneyAmountInput.minor(rawAmount, exponent: $0) }.flatMap { $0 > 0 ? $0 : nil } }
    private var isObligation: Bool { if case .obligation = target { true } else { false } }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var newAmount: Int { recurring ? (amountMinor ?? original.amount) : original.amount }
    private var changed: Bool { trimmed != original.name || (isObligation && newAmount != original.amount) }
    private var canSave: Bool { loaded && !saving && !trimmed.isEmpty && trimmed.count <= 60 && changed && (!recurring || rawAmount.isEmpty || amountMinor != nil) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(isObligation ? "عدّل الالتزام" : "عدّل اسم المظروف").font(.custom("thmanyahserifdisplay-Bold", size: 24, relativeTo: .title2))
                        Spacer()
                        Button("تمّ") { dismiss() }.frame(minHeight: 44).accessibilityIdentifier("money-edit-close")
                    }
                    field("الاسم") { TextField("الاسم", text: $name).focused($focused).submitLabel(.done).onSubmit(save).accessibilityIdentifier("money-edit-name") }
                    if isObligation && recurring {
                        field("المبلغ في كل موعد") {
                            TextField(visible ? "" : "اكتب المبلغ الجديد إن تغيّر", text: $rawAmount).keyboardType(.decimalPad).focused($focused).accessibilityIdentifier("money-edit-amount")
                        }
                        Text("يتغيّر ما يُحجز من الراتب للمواعيد القادمة؛ ما دفعته من قبل يبقى كما هو.")
                            .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                    } else if isObligation {
                        Text("مبلغ القسط ثابت لأن جدول الأقساط مكتوب؛ يتغيّر الاسم فقط.")
                            .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                    }
                    if let failure { Text(failure).font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")).accessibilityIdentifier("money-edit-error") }
                    Button(action: save) {
                        Text(saving ? "جارٍ الحفظ…" : "احفظ التعديل").font(MadarTypography.cardTitle()).frame(maxWidth: .infinity, minHeight: 54)
                            .background(theme.ink.opacity(canSave ? 1 : 0.35)).foregroundStyle(theme.background)
                    }.buttonStyle(.madarPlain).disabled(!canSave).accessibilityIdentifier("money-edit-save")
                }.padding(20)
            }
            .scrollDismissesKeyboard(.interactively).background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
            .toolbar(.hidden, for: .navigationBar)
            .task { load() }
            .madarSheetLock(saving: saving, draft: loaded && changed)
        }
        .presentationDetents([.medium, .large])
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            content().font(MadarTypography.body()).padding(10).frame(minHeight: 44).overlay { Rectangle().stroke(theme.line, lineWidth: 1) }
        }.disabled(saving)
    }

    private func load() {
        let context = ModelContext(app.container)
        switch target {
        case .obligation(let id):
            guard let row = try? context.fetch(FetchDescriptor<Obligation>()).first(where: { $0.id == id && $0.deletedAt == nil && $0.mergedInto == nil }) else { failure = "لم يعد هذا الالتزام موجودًا."; return }
            original = (row.name, row.amountMinor); recurring = row.kind == "bill" || row.kind == "subscription"; currency = row.currency
            rawAmount = visible && recurring ? Self.decimal(row.amountMinor, exponent: exponent) : ""
        case .envelope(let id):
            guard let row = try? context.fetch(FetchDescriptor<Envelope>()).first(where: { $0.id == id && $0.deletedAt == nil && $0.mergedInto == nil }) else { failure = "لم يعد هذا المظروف موجودًا."; return }
            original = (row.name, row.balanceMinor)
        }
        name = original.name; loaded = true
    }

    private func save() {
        guard canSave else { return }
        focused = false; saving = true; failure = nil
        let command: String, payload: [String: MadarCore.JSONValue]
        switch target {
        case .obligation(let id): command = "money.editObligation"; payload = ["id": .string(id.uuidString), "name": .string(trimmed), "amountMinor": .string(String(newAmount))]
        case .envelope(let id): command = "money.renameEnvelope"; payload = ["id": .string(id.uuidString), "name": .string(trimmed)]
        }
        Task {
            do { try await app.executeMoneyCommand(command, payload: payload); dismiss() }
            catch { saving = false; failure = "لم يُحفظ التعديل الآن. حاول مرة أخرى بعد قليل." }
        }
    }

    static func decimal(_ minor: Int, exponent: Int?) -> String {
        guard let exponent, exponent > 0 else { return String(minor) }
        var scale = 1; for _ in 0..<exponent { scale *= 10 }
        let fraction = String(minor % scale), padded = String(repeating: "0", count: max(0, exponent - fraction.count)) + fraction
        let trimmed = padded.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return String(minor / scale) + (trimmed.isEmpty ? "" : "." + trimmed)
    }
}
