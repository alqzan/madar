import Foundation

/// M5 command boundary. Decimal integer strings avoid a floating-point conversion on input.
/// The shared record bridge currently uses Double-backed JSON, so values beyond its exact integer
/// range are refused explicitly before a stored amount can lose a minor unit.
public enum MoneyCommandPayload {
    public static let intakeName = "money.ingestBankMessage"
    public static let names: Set<String> = [intakeName, "money.pasteBankMessages", "money.logExpense",
        "money.confirmTransaction", "money.deleteTransaction", "money.saveAccount", "money.saveCard", "money.accruePlans", "money.setReserveGoal", "money.repayEnvelopeNow", "money.setEnvelopeSaving", "money.adoptRepayment",
        "money.applyStatement", "money.ignoreMessage", "money.confirmClear"]
    /// §7.5 maxRepayCycles: the longest salary repayment (the envelope sheet offers 1–6).
    public static let maxRepaySalaries = 12

    public static func integer(_ value: JSONValue?) -> Int? {
        switch value {
        case .string(let raw):
            guard let n = Int(raw), n >= -9_007_199_254_740_991, n <= 9_007_199_254_740_991 else { return nil }
            return n
        case .number(let n) where n.isFinite && n.rounded() == n && abs(n) <= 9_007_199_254_740_991: return Int(n)
        default: return nil
        }
    }

    public static func date(_ value: JSONValue?) -> Date? {
        guard case .string(let raw) = value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }

    public static func validate(name: String, payload p: [String: JSONValue]) -> Bool {
        func text(_ key: String, max: Int = 80, empty: Bool = false) -> Bool {
            guard case .string(let raw) = p[key] else { return false }
            return raw.count <= max && (empty || !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        func id(_ key: String) -> Bool { if case .string(let raw) = p[key] { UUID(uuidString: raw) != nil } else { false } }
        func optionalID(_ key: String) -> Bool { p[key] == nil || p[key] == .null || id(key) }
        func positive(_ key: String) -> Bool { integer(p[key]).map { $0 > 0 } ?? false }
        func choices(_ key: String, _ options: Set<String>) -> Bool { if case .string(let raw) = p[key] { options.contains(raw) } else { false } }
        func optionalText(_ key: String, max: Int = 80) -> Bool { p[key] == nil || p[key] == .null || text(key, max: max, empty: true) }
        switch name {
        case "money.setEnvelopeSaving": return Set(p.keys) == ["id", "amountMinor", "expectedMinor"] && id("id") && integer(p["expectedMinor"]) != nil && (integer(p["amountMinor"]).map { $0 >= 0 } ?? false)
        case "money.adoptRepayment": return Set(p.keys) == ["id", "debtMinor", "salaries"] && id("id") && positive("debtMinor") && (integer(p["salaries"]).map { (1...maxRepaySalaries).contains($0) } ?? false)
        case "money.repayEnvelopeNow": return Set(p.keys) == ["id", "source", "debtMinor"] && id("id") && choices("source", ["surplus", "reserve"]) && positive("debtMinor")
        case "money.applyStatement", "money.ignoreMessage": return Set(p.keys) == ["id"] && id("id")
        case "money.confirmClear":
            guard Set(p.keys) == ["ids"], case .array(let rows) = p["ids"], !rows.isEmpty, rows.count <= 100 else { return false }
            let ids = rows.compactMap { if case .string(let raw) = $0 { UUID(uuidString: raw) } else { nil } }
            return ids.count == rows.count && Set(ids).count == ids.count
        case "money.accruePlans": return p.isEmpty
        case "money.setReserveGoal": return Set(p.keys) == ["targetMinor"] && (p["targetMinor"] == .null || positive("targetMinor"))
        case intakeName:
            return Set(p.keys).isSubset(of: ["text", "sender", "receivedAt"]) && text("text", max: 2000)
                && optionalText("sender") && (p["receivedAt"] == nil || date(p["receivedAt"]) != nil)
        case "money.pasteBankMessages":
            guard Set(p.keys).isSubset(of: ["messages", "batchID"]), optionalID("batchID"),
                  case .array(let rows) = p["messages"], !rows.isEmpty, rows.count <= 500 else { return false }
            return rows.allSatisfy { if case .object(let item) = $0 { validate(name: intakeName, payload: item) } else { false } }
        case "money.logExpense":
            return Set(p.keys).isSubset(of: ["amountMinor", "currency", "merchant", "method", "categoryID", "fromAccountID", "cardID", "eventAt", "rateAtTime", "showInDiary"])
                && positive("amountMinor") && text("currency", max: 3) && optionalText("merchant")
                && (p["method"] == nil || choices("method", ["cash", "card", "transfer"]))
                && ["categoryID", "fromAccountID", "cardID"].allSatisfy(optionalID)
                && (p["eventAt"] == nil || date(p["eventAt"]) != nil) && optionalText("rateAtTime", max: 40)
                && (p["showInDiary"] == nil || p["showInDiary"] == .bool(true) || p["showInDiary"] == .bool(false))
        case "money.confirmTransaction":
            guard Set(p.keys).isSubset(of: ["id", "fromAccountID", "toAccountID", "cardID", "relatedTransactionID", "obligationID", "installmentID", "rateAtTime", "allocations", "ignoredFromBudget"]), id("id"),
                  ["fromAccountID", "toAccountID", "cardID", "relatedTransactionID", "obligationID", "installmentID"].allSatisfy(optionalID), optionalText("rateAtTime", max: 40),
                  p["ignoredFromBudget"] == nil || p["ignoredFromBudget"] == .bool(true) || p["ignoredFromBudget"] == .bool(false) else { return false }
            guard let splits = p["allocations"] else { return true }
            guard case .array(let rows) = splits, !rows.isEmpty, rows.count <= 50 else { return false }
            return rows.allSatisfy { item in
                guard case .object(let row) = item, Set(row.keys).isSubset(of: ["target", "targetID", "amountMinor"]),
                      case .string(let target) = row["target"], ["daily", "envelope", "reserve", "surplus", "goal"].contains(target),
                      let amount = integer(row["amountMinor"]), amount >= 0 else { return false }
                if target == "envelope" || target == "goal" {
                    guard case .string(let raw) = row["targetID"], UUID(uuidString: raw) != nil else { return false }
                } else if row["targetID"] != nil && row["targetID"] != .null { return false }
                return true
            }
        case "money.deleteTransaction": return Set(p.keys) == ["id"] && id("id")
        case "money.saveAccount":
            return Set(p.keys).isSubset(of: ["id", "name", "bank", "kind", "ownership", "currency", "balanceMinor", "balanceAt", "last4", "senderIDs", "tracked", "zakatInclude"])
                && id("id") && text("name") && optionalText("bank") && choices("kind", ["current", "savings", "cash", "wallet"])
                && choices("ownership", ["mine", "notMine"]) && text("currency", max: 3) && integer(p["balanceMinor"]) != nil
                && date(p["balanceAt"]) != nil && optionalText("last4", max: 4)
                && ["tracked", "zakatInclude"].allSatisfy { p[$0] == nil || p[$0] == .bool(true) || p[$0] == .bool(false) }
                && (p["senderIDs"] == nil || { if case .array(let list) = p["senderIDs"] { list.count <= 20 && list.allSatisfy { if case .string(let s) = $0 { !s.isEmpty && s.count <= 80 } else { false } } } else { false } }())
        case "money.saveCard":
            return Set(p.keys).isSubset(of: ["id", "name", "bank", "last4", "kind", "accountID", "aliases"])
                && id("id") && text("name") && text("bank") && text("last4", max: 4)
                && choices("kind", ["debit", "credit", "prepaid"]) && optionalID("accountID")
                && (p["aliases"] == nil || { if case .array(let list) = p["aliases"] { list.count <= 20 && list.allSatisfy { if case .string(let s) = $0 { !s.isEmpty && s.count <= 80 } else { false } } } else { false } }())
        default: return false
        }
    }
}
