import AppIntents
import Foundation
import MadarCore
import MadarInbox
import MadarMoney

/// F09: a Shortcuts message automation supplies its content explicitly; Madar never reads SMS.
/// The producer cannot open the store. Its generic dialog never speaks an amount or message text.
struct IngestBankMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "سجّل رسالة بنك في مدار"
    static let description = IntentDescription("يحفظ رسالة البنك للمراجعة في مدار، من أتمتة تختارها في الاختصارات.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    // F09 guide exposes bank intake once the money room is built.
    static let isDiscoverable = true
    @Parameter(title: "نص الرسالة", inputOptions: .init(multiline: true)) var text: String
    @Parameter(title: "المرسل") var sender: String?
    @Parameter(title: "وقت الورود") var receivedAt: Date?
    init() {}
    init(text: String, sender: String? = nil, receivedAt: Date? = nil) { self.text = text; self.sender = sender; self.receivedAt = receivedAt }
    static var parameterSummary: some ParameterSummary { Summary("سجّل رسالة البنك \(\.$text)") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try MoneyInboxCommandWriter.ingest(inbox: Self.inbox(), text: text, sender: sender, receivedAt: receivedAt)
        } catch MoneyInboxError.invalidPayload { throw MoneyIntentError.invalidMessage }
        await MainActor.run { NotificationCenter.default.post(name: .madarInboxChanged, object: nil) }
        return .result(dialog: "استُلمت.")
    }
    static func inbox() throws -> PendingInbox {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.alqzan.madar2") else { throw MoneyIntentError.openMadar }
        return PendingInbox(directory: group.appending(path: "PendingInbox", directoryHint: .isDirectory))
    }
}

enum MoneyExpenseMethod: String, AppEnum {
    case cash, card, transfer
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "طريقة الدفع")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.cash: "نقدًا", .card: "بطاقة", .transfer: "تحويل"]
}
struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "سجّل مصروفًا في مدار"
    static let description = IntentDescription("يحفظ مصروفًا للمراجعة، وتختار حسابه وتوزيعه داخل مدار.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let isDiscoverable = true
    @Parameter(title: "المبلغ") var amount: String
    @Parameter(title: "العملة", default: "SAR") var currency: String
    @Parameter(title: "التاجر") var merchant: String?
    @Parameter(title: "طريقة الدفع") var method: MoneyExpenseMethod?
    init() {}
    init(amount: String, currency: String = "SAR", merchant: String? = nil, method: MoneyExpenseMethod? = nil) {
        self.amount = amount; self.currency = currency; self.merchant = merchant; self.method = method
    }
    static var parameterSummary: some ParameterSummary { Summary("سجّل مصروف \(\.$amount) \(\.$currency)") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let code = currency.uppercased(), raw = BankMessageParser.clean(amount).replacingOccurrences(of: ",", with: "")
        guard let exp = CurrencyExponents.specified.exponent(code), let minor = MoneyAmountInput.minor(raw, exponent: exp), minor > 0 else { throw MoneyIntentError.invalidAmount }
        try MoneyInboxCommandWriter.logExpense(inbox: IngestBankMessageIntent.inbox(), amountMinor: minor, currency: code, merchant: merchant, method: method?.rawValue)
        await MainActor.run { NotificationCenter.default.post(name: .madarInboxChanged, object: nil) }
        return .result(dialog: "حُفظ للمراجعة.")
    }
}
private enum MoneyIntentError: LocalizedError {
    case invalidMessage, invalidAmount, openMadar
    var errorDescription: String? {
        switch self {
        case .invalidMessage: "مرّر رسالة من حرف إلى ٢٠٠٠ حرف."
        case .invalidAmount: "أدخل مبلغًا موجبًا بعملة مدعومة."
        case .openMadar: "افتح مدار أولًا ثم أعد المحاولة."
        }
    }
}
