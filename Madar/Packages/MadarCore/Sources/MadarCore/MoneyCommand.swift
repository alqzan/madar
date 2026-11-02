import Foundation

/// M5 command boundary. Decimal integer strings avoid a floating-point conversion on input.
/// The shared record bridge currently uses Double-backed JSON, so values beyond its exact integer
/// range are refused explicitly before a stored amount can lose a minor unit.
public enum MoneyCommandPayload {
    public static let intakeName = "money.ingestBankMessage"
    public static let names: Set<String> = [intakeName, "money.pasteBankMessages", "money.logExpense",
        "money.confirmTransaction", "money.deleteTransaction", "money.saveAccount", "money.saveCard", "money.accruePlans", "money.setReserveGoal", "money.repayEnvelopeNow", "money.setEnvelopeSaving", "money.adoptRepayment",
        "money.applyStatement", "money.ignoreMessage", "money.removeAccount", "money.confirmClear", "money.markVisit", "money.seedCategories",
        "money.categorize", "money.saveMerchantRule", "money.forgetMerchantRule", "money.confirmSalary", "money.saveObligation", "money.setCategoryLimit", "money.setCategoryPreferredCard", "money.setBudgetExclusion", "money.reconcile", "money.setCardCashback", "money.distributeBigExpense", "money.configureTrip", "money.fundTrip", "money.repriceTrip", "money.saveZakat", "money.prepareGoal"]
    /// §7.5 maxRepayCycles: the longest salary repayment (the envelope sheet offers 1–6).
    public static let maxRepaySalaries = 12
    /// M5-X00: the budget-ignore stamp's optional reason.
    public static let maxReasonLength = 120

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

    /// A split's rows: 1–50 targets, each a non-negative amount; an envelope or goal names its envelope.
    static func allocationRows(_ value: JSONValue?) -> Bool {
        guard case .array(let rows) = value, !rows.isEmpty, rows.count <= 50 else { return false }
        return rows.allSatisfy { item in
            guard case .object(let row) = item, Set(row.keys).isSubset(of: ["target", "targetID", "amountMinor"]),
                  case .string(let target) = row["target"], ["daily", "envelope", "reserve", "surplus", "goal"].contains(target),
                  let amount = integer(row["amountMinor"]), amount >= 0 else { return false }
            if target == "envelope" || target == "goal" {
                guard case .string(let raw) = row["targetID"], UUID(uuidString: raw) != nil else { return false }
            } else if row["targetID"] != nil && row["targetID"] != .null { return false }
            return true
        }
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
        case "money.prepareGoal":
            guard Set(p.keys) == ["name", "totalMinor", "paidIDs", "upfrontMinor", "dailyMinor", "source", "due", "signature"],
                  text("name"), positive("totalMinor"), text("signature", max: 64), choices("source", ["surplus", "reserve"]), date(p["due"]) != nil,
                  ["upfrontMinor", "dailyMinor"].allSatisfy({ integer(p[$0]).map { $0 >= 0 } == true }), case .array(let ids) = p["paidIDs"], ids.count <= 100 else { return false }
            let values = ids.compactMap { if case .string(let raw) = $0 { UUID(uuidString: raw) } else { nil } }
            return values.count == ids.count && Set(values).count == values.count
        case "money.saveZakat":
            return Set(p.keys) == ["signature", "basis", "debts", "goldPriceMinor", "silverPriceMinor", "goldMg", "silverMg", "otherMinor", "hawl"]
                && text("signature", max: 64) && choices("basis", ["gold", "silver"])
                && choices("debts", ["unset", "none", "dueNow", "allOwed", "allOwedAndLoan"])
                && ["goldPriceMinor", "silverPriceMinor"].allSatisfy { p[$0] == .null || positive($0) }
                && positive("goldMg") && positive("silverMg") && integer(p["otherMinor"]).map { $0 >= 0 } == true && text("hawl", max: 13, empty: true)
        case "money.repriceTrip":
            return Set(p.keys) == ["id", "rate", "signature"] && id("id") && text("rate", max: 40) && text("signature", max: 64)
        case "money.configureTrip":
            return Set(p.keys) == ["id", "currency", "rate", "expectedRate", "expectedCurrency"] && id("id") && text("currency", max: 3)
                && optionalText("rate", max: 40) && optionalText("expectedRate", max: 40) && optionalText("expectedCurrency", max: 3)
        case "money.fundTrip":
            return Set(p.keys) == ["id", "amountMinor", "source", "due", "expectedBalanceMinor"] && id("id") && positive("amountMinor")
                && choices("source", ["reserve", "surplus"]) && integer(p["expectedBalanceMinor"]) != nil && date(p["due"]) != nil
        case "money.setBudgetExclusion":
            // M5-X00 (owner 16 Oct): an optional free-text reason, only when stamping.
            return Set(p.keys).subtracting(["reason"]) == ["id", "excluded", "expectedExcluded"] && id("id")
                && ["excluded", "expectedExcluded"].allSatisfy { p[$0] == .bool(true) || p[$0] == .bool(false) }
                && (p["reason"] == nil || (p["excluded"] == .bool(true) && text("reason", max: maxReasonLength, empty: true)))
        case "money.setCardCashback":
            // §7.5 «يدخل يدويًا مرة: نسبة الاسترداد»: basis points 0…10 000, or null to make it unknown again.
            return Set(p.keys) == ["id", "cashbackBp"] && id("id") && (p["cashbackBp"] == .null || (integer(p["cashbackBp"]).map { (0...10_000).contains($0) } ?? false))
        case "money.setCategoryPreferredCard":
            // The optional reference only guides future expense entry; null clears it.
            return Set(p.keys) == ["categoryID", "cardID"] && id("categoryID") && optionalID("cardID")
        case "money.setEnvelopeSaving": return Set(p.keys) == ["id", "amountMinor", "expectedMinor"] && id("id") && integer(p["expectedMinor"]) != nil && (integer(p["amountMinor"]).map { $0 >= 0 } ?? false)
        case "money.adoptRepayment": return Set(p.keys) == ["id", "debtMinor", "salaries"] && id("id") && positive("debtMinor") && (integer(p["salaries"]).map { (1...maxRepaySalaries).contains($0) } ?? false)
        case "money.repayEnvelopeNow": return Set(p.keys) == ["id", "source", "debtMinor"] && id("id") && choices("source", ["surplus", "reserve"]) && positive("debtMinor")
        case "money.applyStatement", "money.ignoreMessage", "money.removeAccount": return Set(p.keys) == ["id"] && id("id")
        case "money.confirmClear":
            guard Set(p.keys) == ["ids"], case .array(let rows) = p["ids"], !rows.isEmpty, rows.count <= 100 else { return false }
            let ids = rows.compactMap { if case .string(let raw) = $0 { UUID(uuidString: raw) } else { nil } }
            return ids.count == rows.count && Set(ids).count == ids.count
        case "money.accruePlans", "money.markVisit", "money.seedCategories": return p.isEmpty
        case "money.categorize":
            let keys = Set(p.keys)
            let hasRequiredKeys: Set<String> = ["id", "categoryID"]
            let allowedKeys: Set<String> = ["id", "categoryID", "remember", "categorySource"]
            let validLegacyRemember = p["remember"] == nil || p["remember"] == .bool(true) || p["remember"] == .bool(false)
            let validSource = p["categorySource"] == nil || choices("categorySource", ["manual", "rule"])
            // `remember` remains accepted while already-queued v1 commands drain; it no longer creates a merchant rule.
            return hasRequiredKeys.isSubset(of: keys) && keys.isSubset(of: allowedKeys) && id("id") && optionalID("categoryID") && validLegacyRemember && validSource
        case "money.saveMerchantRule":
            return Set(p.keys) == ["merchant", "categoryID", "ignore"] && text("merchant") && optionalID("categoryID") && (p["ignore"] == .bool(true) || p["ignore"] == .bool(false))
        case "money.setCategoryLimit":
            // §7.5: none | fixed (minor units) | percent (basis points of the cycle's income or its dailies).
            guard Set(p.keys).isSubset(of: ["categoryID", "mode", "limitMinor", "percentBp", "base"]), id("categoryID") else { return false }
            if choices("mode", ["none"]) { return p["limitMinor"] == nil && p["percentBp"] == nil && p["base"] == nil }
            if choices("mode", ["fixed"]) { return p["percentBp"] == nil && p["base"] == nil && (integer(p["limitMinor"]).map { $0 >= 0 } ?? false) }
            return choices("mode", ["percent"]) && p["limitMinor"] == nil && choices("base", ["income", "allowance"]) && (integer(p["percentBp"]).map { (1...10_000).contains($0) } ?? false)
        case "money.saveObligation":
            // A bill or subscription repeating every N days/weeks/months/years from a free first due day (M5-X00), or the
            // older monthly bill on a day; a loan / instalment plan of equal instalments from a first due day, monthly
            // unless an interval is given.
            guard Set(p.keys).isSubset(of: ["kind", "name", "amountMinor", "dueDay", "count", "firstDue", "repeatEvery", "repeatUnit"]), text("name", max: 60), positive("amountMinor") else { return false }
            let hasFirst: Bool = { if case .string(let first) = p["firstDue"] { (try? GregorianDay(first)) != nil } else { false } }()
            let interval: Bool? = {
                if p["repeatEvery"] == nil && p["repeatUnit"] == nil { return nil }
                guard case .string(let raw) = p["repeatUnit"], let unit = RecurrenceUnit(rawValue: raw), let every = integer(p["repeatEvery"]) else { return false }
                return (1...unit.maxEvery).contains(every)
            }()
            if interval == false { return false }
            if choices("kind", ["bill", "subscription"]) {
                guard p["count"] == nil else { return false }
                if interval == true { return p["dueDay"] == nil && hasFirst }
                return choices("kind", ["bill"]) && p["firstDue"] == nil && (integer(p["dueDay"]).map { (1...31).contains($0) } ?? false)
            }
            guard choices("kind", ["loan", "installment"]), p["dueDay"] == nil, (integer(p["count"]).map { (1...120).contains($0) } ?? false), hasFirst else { return false }
            return integer(p["amountMinor"]).map { $0 <= 9_007_199_254_740_991 / 120 } ?? false
        case "money.confirmSalary":
            return Set(p.keys).isSubset(of: ["id", "remainderTo"]) && id("id") && (p["remainderTo"] == nil || choices("remainderTo", ["surplus", "reserve"]))
        case "money.forgetMerchantRule": return Set(p.keys) == ["id"] && id("id")
        case "money.setReserveGoal": return Set(p.keys) == ["targetMinor"] && (p["targetMinor"] == .null || positive("targetMinor"))
        case intakeName:
            return Set(p.keys).isSubset(of: ["text", "sender", "receivedAt"]) && text("text", max: 2000)
                && optionalText("sender") && (p["receivedAt"] == nil || date(p["receivedAt"]) != nil)
        case "money.pasteBankMessages":
            guard Set(p.keys).isSubset(of: ["messages", "batchID"]), optionalID("batchID"),
                  case .array(let rows) = p["messages"], !rows.isEmpty, rows.count <= 500 else { return false }
            return rows.allSatisfy { if case .object(let item) = $0 { validate(name: intakeName, payload: item) } else { false } }
        case "money.distributeBigExpense":
            guard Set(p.keys).isSubset(of: ["transactionID", "expense", "mode", "cycles", "envelopeID", "envelopeName", "availableMinor", "surplusMinor", "reserveMinor"]),
                  choices("mode", ["mixed", "installments", "daily", "reserve"]), optionalID("envelopeID"), optionalText("envelopeName"),
                  ["availableMinor", "surplusMinor", "reserveMinor"].allSatisfy({ integer(p[$0]) != nil }),
                  p["cycles"] == nil || integer(p["cycles"]).map({ (1...12).contains($0) }) == true else { return false }
            if p["transactionID"] != nil { return id("transactionID") && p["expense"] == nil }
            guard case .object(let expense) = p["expense"], expense["allocations"] == nil else { return false }
            return validate(name: "money.logExpense", payload: expense)
        case "money.logExpense":
            // M5-V17: the sheet may split the charge over an envelope and «يومك» (F02); rows as in confirmTransaction.
            return Set(p.keys).isSubset(of: ["amountMinor", "currency", "merchant", "method", "categoryID", "fromAccountID", "cardID", "eventAt", "rateAtTime", "showInDiary", "allocations", "categorySource"])
                && (p["allocations"] == nil || allocationRows(p["allocations"]))
                && (p["categorySource"] == nil || choices("categorySource", ["manual", "learned"]))
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
            return allocationRows(splits)
        case "money.deleteTransaction": return Set(p.keys) == ["id"] && id("id")
        case "money.reconcile":
            // M5-V15: every line of one «محضر» in one command and one undo. A line names one account, card, or
            // installment obligation; the handler rechecks the shown book before it records the provider's figure.
            guard Set(p.keys) == ["rows"], case .array(let rows) = p["rows"], !rows.isEmpty, rows.count <= 60 else { return false }
            var targets = Set<String>()
            for value in rows {
                guard case .object(let row) = value, Set(row.keys).isSubset(of: ["accountID", "cardID", "obligationID", "expectedMinor", "observedMinor", "name", "at"]),
                      integer(row["expectedMinor"]) != nil, let observed = integer(row["observedMinor"]), observed >= 0,
                      row["name"] == nil || { if case .string(let raw) = row["name"] { ["missedSpend", "bankFee", "unexplained"].contains(raw) } else { false } }(),
                      row["at"] == nil || date(row["at"]) != nil else { return false }
                func rowID(_ key: String) -> UUID? { if case .string(let raw) = row[key] { UUID(uuidString: raw) } else { nil } }
                let account = rowID("accountID"), card = rowID("cardID"), obligation = rowID("obligationID")
                let identifiers = [account, card, obligation].compactMap { $0 }
                guard identifiers.count == 1,
                      row.keys.contains("accountID") == (account != nil), row.keys.contains("cardID") == (card != nil),
                      row.keys.contains("obligationID") == (obligation != nil),
                      targets.insert(identifiers[0].uuidString).inserted else { return false }
            }
            return true
        case "money.saveAccount":
            return Set(p.keys).isSubset(of: ["id", "name", "bank", "kind", "ownership", "currency", "balanceMinor", "balanceAt", "last4", "senderIDs", "tracked", "zakatInclude", "establishBalance"])
                && id("id") && text("name") && optionalText("bank") && choices("kind", ["current", "savings", "cash", "wallet"])
                && choices("ownership", ["mine", "notMine"]) && text("currency", max: 3) && integer(p["balanceMinor"]) != nil
                && date(p["balanceAt"]) != nil && optionalText("last4", max: 4)
                && ["tracked", "zakatInclude", "establishBalance"].allSatisfy { p[$0] == nil || p[$0] == .bool(true) || p[$0] == .bool(false) }
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
