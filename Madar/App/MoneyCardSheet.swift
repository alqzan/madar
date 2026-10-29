import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarDesign
import MadarMoney
import MadarCommands

/// The one way a card enters «البطاقات» (found 21 Oct 2026: `money.saveCard` had no screen, so cards existed
/// only in test fixtures). Same paper form as the account sheet; the command keeps its own rules: four digits,
/// one live card per bank + digits, and a debit or prepaid card names the account it draws from.
struct MoneyCardSheet: View {
    let app: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var id = UUID()
    @State private var name = ""
    @State private var bank = ""
    @State private var last4 = ""
    @State private var kind = "debit"
    @State private var accountID: UUID?
    @State private var senders = ""
    @State private var accounts: [(id: UUID, name: String, bank: String)] = []
    @State private var saving = false
    @State private var failure: String?
    @FocusState private var editing: Bool
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var digits: String { last4.map { c in c.wholeNumberValue.map(String.init) ?? String(c) }.joined() }
    private var canSave: Bool {
        !saving && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !bank.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.count <= 80 && bank.count <= 80 && digits.count == 4 && digits.allSatisfy(\.isASCII) && (kind == "credit" || accountID != nil)
    }

    private var waiting: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "اكتب اسم البطاقة لتحفظها" }
        if bank.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "اكتب اسم البنك لتحفظها" }
        if digits.count != 4 || !digits.allSatisfy(\.isASCII) { return "اكتب آخر أربعة أرقام من البطاقة" }
        if kind != "credit" && accountID == nil && !accounts.isEmpty { return "اختر الحساب الذي تُخصم منه" }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("بطاقة جديدة").font(.custom("thmanyahserifdisplay-Bold", size: 25, relativeTo: .title2)); Spacer(); Button("إغلاق") { dismiss() }.frame(minHeight: 44).accessibilityIdentifier("money-card-editor-close") }
                    field("اسم البطاقة") { TextField("مثل: بطاقة المشتريات", text: $name).focused($editing).accessibilityIdentifier("money-card-name") }
                    field("البنك") { TextField("اسم البنك", text: $bank).focused($editing).accessibilityIdentifier("money-card-bank") }
                    field("آخر أربعة أرقام") { TextField("آخر ٤", text: $last4).keyboardType(.numberPad).focused($editing).accessibilityIdentifier("money-card-last4") }
                    Picker("النوع", selection: $kind) {
                        Text("مدى").tag("debit"); Text("ائتمانية").tag("credit"); Text("مسبقة الدفع").tag("prepaid")
                    }.pickerStyle(.segmented).accessibilityIdentifier("money-card-kind")
                    Text(kind == "credit" ? "مشترياتها دين عليك حتى تسددها، ويظهر موعد سدادها في «تقويم السداد»." : "تُخصم مشترياتها من حسابك مباشرة، فاختر الحساب.")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(kind == "credit" ? "تُسدَّد من حساب (اختياري)" : "تُخصم من حساب").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        if accounts.isEmpty {
                            Text(kind == "credit" ? "لا حسابات بعد؛ يمكنك حفظها بلا حساب سداد." : "لا حسابات بعد. أضف حسابك من «الحسابات» أولًا، أو اختر «ائتمانية» إن لم يكن لها حساب.").font(MadarTypography.body()).accessibilityIdentifier("money-card-no-accounts")
                        } else {
                            ForEach(accounts, id: \.id) { account in
                                Button { accountID = accountID == account.id && kind == "credit" ? nil : account.id } label: {
                                    HStack {
                                        Image(systemName: accountID == account.id ? "checkmark.circle.fill" : "circle").foregroundStyle(theme.color("reserveText"))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(account.name).font(MadarTypography.body())
                                            if !account.bank.isEmpty { Text(account.bank).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                                        }
                                        Spacer(minLength: 0)
                                    }.padding(10).frame(minHeight: 48).overlay { Rectangle().stroke(theme.line, lineWidth: 1) }.contentShape(Rectangle())
                                }.accessibilityAddTraits(accountID == account.id ? .isSelected : []).accessibilityIdentifier("money-card-account-\(account.id.uuidString)")
                            }
                        }
                    }
                    field("كيف يكتب البنك اسمها في الرسائل، اسم في كل سطر (اختياري)") { TextField("مثل: مدى ٣٣١٧", text: $senders, axis: .vertical).lineLimit(1...4).focused($editing).accessibilityIdentifier("money-card-aliases") }
                    if let failure { Text(failure).font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")).accessibilityIdentifier("money-card-error") }
                    // AU-34: a dimmed save names the first thing it still waits for.
                    if !canSave && !saving, let waiting { Text(waiting).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-card-waiting") }
                    Button(action: save) { Text(saving ? "جارٍ الحفظ…" : "احفظ البطاقة").font(MadarTypography.cardTitle()).frame(maxWidth: .infinity, minHeight: 54).background(theme.ink.opacity(canSave ? 1 : 0.35)).foregroundStyle(theme.background) }
                        .disabled(!canSave).accessibilityIdentifier("money-card-save")
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively).background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).buttonStyle(.madarPlain)
                .toolbar(.hidden, for: .navigationBar).toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("تمّ") { editing = false }.accessibilityIdentifier("money-card-keyboard-done") } }
                .task { loadAccounts() }
                .onChange(of: kind) { _, value in if value != "credit", accountID == nil, accounts.count == 1 { accountID = accounts[0].id } }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk); content().font(MadarTypography.body()).padding(10).frame(minHeight: 44).overlay { Rectangle().stroke(theme.line, lineWidth: 1) } }
    }

    private func loadAccounts() {
        let rows = (try? ModelContext(app.container).fetch(FetchDescriptor<Account>())) ?? []
        accounts = rows.filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.ownership == "mine" && $0.tracked }
            .sorted { $0.name < $1.name }.map { (id: $0.id, name: $0.name, bank: $0.bank) }
        if accounts.count == 1, kind != "credit" { accountID = accounts[0].id }
    }

    private func save() {
        guard canSave else { return }; editing = false
        let aliases = Array(Set(senders.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0.count <= 80 })).sorted().prefix(20)
        var payload: [String: MadarCore.JSONValue] = ["id": .string(id.uuidString), "name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)),
                                                      "bank": .string(bank.trimmingCharacters(in: .whitespacesAndNewlines)), "last4": .string(digits), "kind": .string(kind)]
        if let accountID { payload["accountID"] = .string(accountID.uuidString) }
        if !aliases.isEmpty { payload["aliases"] = .array(aliases.map { .string($0) }) }
        saving = true; failure = nil
        Task {
            do { try await app.executeMoneyCommand("money.saveCard", payload: payload); dismiss() }
            catch { saving = false; failure = error is MoneyCommandError ? "لم تُحفظ البطاقة. قد تكون عندك بطاقة بالبنك والأرقام نفسها، أو حُذف الحساب المختار." : "لم تُحفظ البطاقة الآن. حاول مرة أخرى بعد قليل." }
        }
    }
}
