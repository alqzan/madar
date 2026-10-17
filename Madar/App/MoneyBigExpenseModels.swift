import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

struct MoneyBigExpenseRoute: Identifiable {
    var id = UUID()
    var transactionID: UUID?
    var expense: [String: MadarCore.JSONValue]?
}
struct MoneyBigExpenseReading {
    var home: MoneyHomeReading
    var amountMinor: Int
    var title: String
    var payment: String
    var at: Date
}
extension AppMoneyService {
    func loadBigExpense(_ route: MoneyBigExpenseRoute) throws -> MoneyBigExpenseReading {
        let home = try load(), methods = try loadExpense().methods
        let amount: Int, title: String, at: Date, card: UUID?, account: UUID?
        if let id = route.transactionID {
            let row = try ModelContext(app.container).fetch(FetchDescriptor<MoneyTransaction>()).first { $0.id == id && $0.deletedAt == nil && $0.mergedInto == nil }
            guard let row, row.reviewState != "ok", row.kind == "expense" else { throw CocoaError(.fileReadCorruptFile) }
            amount = try FX.homeAmount(amountMinor: row.amountMinor, currency: row.currency, rate: row.rateAtTime ?? (row.currency == home.currency ? "1" : ""), home: home.currency)
            title = row.merchant ?? row.counterparty ?? "مصروف"; at = row.eventAt; card = row.cardID; account = row.fromAccountID
        } else {
            guard let p = route.expense, let n = MoneyCommandPayload.integer(p["amountMinor"]), case .string(let currency) = p["currency"] else { throw CocoaError(.fileReadCorruptFile) }
            let rate: String = if case .string(let s) = p["rateAtTime"] { s } else { currency == home.currency ? "1" : "" }
            amount = try FX.homeAmount(amountMinor: n, currency: currency, rate: rate, home: home.currency)
            title = if case .string(let s) = p["merchant"], !s.isEmpty { s } else { "مصروف" }
            at = MoneyCommandPayload.date(p["eventAt"]) ?? app.prayerNow()
            card = if case .string(let s) = p["cardID"] { UUID(uuidString: s) } else { nil }
            account = if case .string(let s) = p["fromAccountID"] { UUID(uuidString: s) } else { nil }
        }
        let method = methods.first { card != nil ? $0.cardID == card : $0.cardID == nil && $0.accountID == account }
        return .init(home: home, amountMinor: amount, title: title, payment: method?.title ?? "مصدر الدفع المسجّل", at: at)
    }
}
