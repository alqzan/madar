import Foundation
import Testing
@testable import MadarMoney

/// Item 17 golden fixture: a synthetic old backup with hand-worked expectations (never the owner's data).
@Suite struct LegacyMoneyImportTests {
    final class Keys { var names: [UUID: String] = [:]; var next = 1
        func uuid(_ key: String) -> UUID {
            if let hit = names.first(where: { $0.value == key }) { return hit.key }
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", next))!; next += 1; names[id] = key; return id
        }
    }
    static let riyadh = TimeZone(identifier: "Asia/Riyadh")!
    static let fixture = """
    {"categories":[{"id":"c-fuel","label":" بنزين "},{"id":"c-cafe","label":"مقاهي"},{"id":"c-gone","label":"قديم"},{"id":"c-blank","label":"  "}],
     "accounts":[{"id":"a1","kind":"card","last4":"1234","bank":"sab","fundingKind":"credit"},{"id":"a2","kind":"account","last4":"9999","bank":"sab"}],
     "merchantRules":{"jahez":"c-cafe","nowhere":"c-missing"},
     "deleted":{"c-gone":1,"t-dead":1},
     "transactions":[
       {"id":"t-man","date":"2026-07-03","amount":12.3,"category":"c-fuel","note":" وقود "},
       {"id":"t-int","date":"2026-07-04","amount":45,"category":"c-cafe"},
       {"id":"t-msg","date":"2026-09-30","time":"21:05","amount":19.99,"category":"c-cafe","rawText":"شراء","bank":"SAB"},
       {"id":"t-dead","date":"2026-07-05","amount":1,"category":"c-cafe"},
       {"id":"t-zero","date":"2026-07-06","amount":0}
     ]}
    """

    @Test func minorUnitsAreExact() {
        #expect(LegacyMoneyImport.minor(12.3) == 1230); #expect(LegacyMoneyImport.minor(0.07) == 7)
        #expect(LegacyMoneyImport.minor(19.99) == 1999); #expect(LegacyMoneyImport.minor(45) == 4500)
        #expect(LegacyMoneyImport.minor(0) == nil); #expect(LegacyMoneyImport.minor(-3) == nil)
    }

    @Test func spellingOnlyNameMatch() {
        #expect(LegacyMoneyImport.normalize(" بنزين ") == LegacyMoneyImport.normalize("بنزين"))
        #expect(LegacyMoneyImport.normalize("مقاضى البيت") == LegacyMoneyImport.normalize("مقاضي  البيت"))
        #expect(LegacyMoneyImport.normalize("مطاعم") != LegacyMoneyImport.normalize("مطاعم وقهوة"))
    }

    @Test func goldenPlan() throws {
        let keys = Keys()
        let seededFuel = UUID(uuidString: "D2CB3CF3-C553-504F-9343-3A75C7C63FAA")!
        let existing = [LegacyMoneyImport.Category(id: seededFuel, name: "بنزين", order: 2), .init(id: UUID(), name: "مطاعم وقهوة", order: 0)]
        let plan = try LegacyMoneyImport.plan(backup: Data(Self.fixture.utf8), existing: existing, timeZone: Self.riyadh, uuid: keys.uuid)

        // «بنزين» reuses the seeded row; «مقاهي» is new after the highest order (2); the deleted and the blank are not created.
        let cafe = keys.uuid("LegacyCategory:c-cafe")
        #expect(plan.createCategories == [.init(id: cafe, name: "مقاهي", order: 3)])
        #expect(plan.counts["category.matched"] == 1 && plan.counts["category.created"] == 1 && plan.counts["category.unnamed"] == 1)

        let midnight = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: Self.riyadh, year: 2026, month: 7, day: 3, hour: 0).date!
        let noon = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: Self.riyadh, year: 2026, month: 7, day: 3, hour: 12).date!
        let noon4 = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: Self.riyadh, year: 2026, month: 7, day: 4, hour: 12).date!
        let evening = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: Self.riyadh, year: 2026, month: 9, day: 30, hour: 21, minute: 5).date!
        let command = keys.uuid("LegacyMessage:t-msg")
        let message = keys.uuid("BankMessage:\(command.uuidString):0")
        #expect(plan.steps == [
            .saveAccount(command: keys.uuid("LegacyAccountCommand:earlier"), id: keys.uuid("LegacyAccount:earlier"), kind: "earlier", bank: nil, last4: nil, balanceAt: midnight),
            .saveCard(command: keys.uuid("LegacyCardCommand:sab|1234"), id: keys.uuid("LegacyCard:sab|1234"), last4: "1234", bank: "sab", kind: "credit", accountID: nil),
            .saveRule(command: keys.uuid("LegacyRule:jahez"), merchant: "jahez", categoryID: cafe),
            .logExpense(command: keys.uuid("LegacyExpense:t-man"), amountMinor: 1230, merchant: "وقود", categoryID: seededFuel, eventAt: noon, accountID: keys.uuid("LegacyAccount:earlier")),
            .logExpense(command: keys.uuid("LegacyExpense:t-int"), amountMinor: 4500, merchant: nil, categoryID: cafe, eventAt: noon4, accountID: keys.uuid("LegacyAccount:earlier")),
            .ingest(command: command, text: "شراء", sender: "SAB", receivedAt: evening, transactionID: keys.uuid("BankMovement:\(message.uuidString)"), categoryID: cafe),
        ])
        #expect(plan.counts["row.deleted"] == 1 && plan.counts["row.badAmount"] == 1 && plan.counts["rule.skipped"] == 1  && plan.counts["account.skipped"] == nil)
    }

    /// A message naming a debit card with no account: one account for that bank is opened and the card draws on it;
    /// a message naming an account's digits makes that account, and an old «card» with the same digits stays an account.
    @Test func cardsAndAccountsComeFromTheMessages() throws {
        let keys = Keys()
        let debit = BankMessageTests.samples[0].text   // mada, card 1111
        let backup: [String: Any] = ["accounts": [["id": "old", "kind": "card", "last4": "7777", "bank": "sab", "fundingKind": "credit"]],
                                     "transactions": [["id": "m", "date": "2026-09-30", "time": "21:05", "amount": 42, "rawText": debit, "bank": "SAB"]]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: backup), as: UTF8.self)
        let plan = try LegacyMoneyImport.plan(backup: Data(json.utf8), existing: [], timeZone: Self.riyadh, uuid: keys.uuid)
        let names = plan.steps.compactMap { step -> String? in
            switch step { case let .saveAccount(_, id, kind, bank, last4, _): "account \(kind) \(bank ?? "-") \(last4 ?? "-") \(keys.names[id]!)"
            case let .saveCard(_, _, last4, bank, kind, account): "card \(last4) \(bank) \(kind) \(account.flatMap { keys.names[$0] } ?? "-")"
            default: nil }
        }
        #expect(names.contains("card 1111 SAB debit LegacyAccount:SAB") && names.contains("account current SAB - LegacyAccount:SAB"), "\(names)")
        #expect(names.contains("card 7777 sab credit -"), "\(names)")
    }

    @Test func secondPlanIsTheSameSteps() throws {
        let keys = Keys()
        let a = try LegacyMoneyImport.plan(backup: Data(Self.fixture.utf8), existing: [], timeZone: Self.riyadh, uuid: keys.uuid)
        let created = a.createCategories
        let b = try LegacyMoneyImport.plan(backup: Data(Self.fixture.utf8), existing: created, timeZone: Self.riyadh, uuid: keys.uuid)
        // After the first run the owner's categories exist, so nothing new is created and every command id repeats.
        #expect(b.createCategories.isEmpty && a.steps == b.steps)
    }
}

extension LegacyMoneyImportTests {
    private func importPlan(_ rows: [[String: Any]], keys: Keys) throws -> LegacyMoneyImport.Plan {
        let data = try JSONSerialization.data(withJSONObject: ["transactions": rows])
        return try LegacyMoneyImport.plan(backup: data, existing: [], timeZone: Self.riyadh, uuid: keys.uuid)
    }
    private func purchase(_ id: String, _ card: String, _ merchant: String, account: String? = nil, credit: Bool = false, balance: Int? = nil) -> [String: Any] {
        var text = "شراء عبر نقاط البيع بـ SAR 10.00\nمن \(merchant)\nبطاقة \(credit ? "ائتمانية" : "مدى") \(card)*\n"
        if let account { text += "حساب \(account)*\n" }
        if let balance { text += "الرصيد المتوفر: SAR \(balance).00\n" }
        text += "2026-09-30 12:00"
        return ["id": id, "date": "2026-09-30", "time": "12:00", "amount": 10, "bank": "SAB", "rawText": text,
                "balanceKind": credit ? "credit_available" : "unknown"]
    }
    @Test func debitUsesExplicitAccountAmongSeveralAccounts() throws {
        let keys = Keys()
        let plan = try importPlan([purchase("a", "1111", "Cafe", account: "2222"), purchase("b", "3333", "Shop", account: "4444")], keys: keys)
        let linked = plan.steps.compactMap { step -> UUID? in
            if case let .saveCard(_, _, last4, _, _, account) = step, last4 == "1111" { return account }; return nil
        }
        #expect(linked == [keys.uuid("LegacyAccount:SAB|2222")])
        #expect(plan.counts["card.unlinked"] == nil)
        #expect(LegacyMoneyImport.fundingLast4(in: "بطاقة 1111*\nإلى حساب 9999*\nحساب ٢٢٢٢*") == "2222")
    }
    @Test func onlyCashEvidenceEstablishesOpeningBalance() throws {
        let keys = Keys()
        let plan = try importPlan([purchase("d", "1111", "Cafe", account: "2222", balance: 90),
                                   purchase("c", "3333", "Shop", account: "4444", credit: true, balance: 700)], keys: keys)
        #expect(plan.balanceEvidence.count == 1)
        #expect(plan.balanceEvidence[keys.uuid("LegacyAccount:SAB|2222")]?.amountMinor == 9000)
        // Opening 100.00, spend 20.00, receive 10.00, printed 90.00.
        #expect(LegacyMoneyImport.openingBalance(printed: 9000, signedMovements: [-2000, 1000]) == 10000)
        #expect(LegacyMoneyImport.openingBalance(printed: Int.max, signedMovements: [-1]) == nil)
        let unknown = try importPlan([purchase("u", "5555", "Other", account: "6666")], keys: Keys())
        #expect(unknown.balanceEvidence.isEmpty)
    }
    @Test func earlierRowsUseUniqueMerchantAndLeaveAmbiguityUnknown() throws {
        let keys = Keys()
        let old: [[String: Any]] = [
            ["id": "e1", "date": "2026-07-03", "amount": 10, "note": "Cafe"],
            ["id": "e2", "date": "2026-07-03", "amount": 10, "note": "Shared"],
            ["id": "e3", "date": "2026-07-03", "amount": 10, "note": "Unseen"]]
        let plan = try importPlan(old + [purchase("m1", "1111", "Cafe"), purchase("m2", "1111", "Shared"), purchase("m3", "3333", "Shared")], keys: keys)
        #expect(plan.earlierCards == [keys.uuid("LegacyExpense:e1"): keys.uuid("LegacyCard:SAB|1111")])
        #expect(plan.counts["earlier.cardUnknown"] == 2)
    }
}

extension LegacyMoneyImportTests {
    @Test func unnamedDebitFundingIsSeparateFromSeveralNamedAccounts() throws {
        let keys = Keys()
        let plan = try importPlan([purchase("a", "1111", "Cafe", account: "2222"), purchase("b", "3333", "Shop", account: "4444"),
                                   purchase("c", "5555", "Market", balance: 50)], keys: keys)
        let unnamed = keys.uuid("LegacyAccount:unidentified:SAB|5555")
        #expect(plan.steps.contains { if case .saveAccount(_, unnamed, "unidentified", "SAB", nil, _) = $0 { true } else { false } })
        #expect(plan.steps.contains { if case .saveCard(_, _, "5555", "SAB", "debit", unnamed) = $0 { true } else { false } })
        #expect(plan.balanceEvidence[unnamed] == nil)
        #expect(plan.counts["account.unidentifiedFunding"] == 1)
    }
}

extension LegacyMoneyImportTests {
    private func settingsPlan(_ root: [String: Any], keys: Keys = Keys()) throws -> LegacyMoneyImport.Plan {
        try LegacyMoneyImport.plan(backup: JSONSerialization.data(withJSONObject: root), existing: [], timeZone: Self.riyadh, uuid: keys.uuid)
    }
    @Test func legacyFixedDailyAndGregorianSalaryDayAreSettingsOnly() throws {
        let plan = try settingsPlan(["dailyBudget": ["amount": 12.3, "startDate": "2026-07-03", "carryAdjust": 7.5], "salaryDay": 31, "budgetWindow": "salary"])
        let settings = try #require(plan.cycleSettings)
        #expect(settings.daily == .init(mode: "fixed", amountMinor: 1230, percentBp: nil))
        #expect(settings.salaryDay == 31 && settings.gregorian)
        #expect(plan.steps.isEmpty, "Configuration cannot manufacture a salary or an opening cycle")
        let archive = try #require(JSONSerialization.jsonObject(with: settings.archive) as? [String: Any])
        let daily = try #require(archive["dailyBudget"] as? [String: Any])
        #expect(daily["startDate"] as? String == "2026-07-03")
        #expect(daily["carryAdjust"] as? Double == 7.5)
    }
    @Test func percentProvenancePreservesResolvedAmountWithoutInventingIncome() throws {
        let plan = try settingsPlan(["dailyBudget": ["amount": 120.37, "incomePct": 30.25, "monthlyIncome": 12000], "monthlyIncome": 15000, "salaryDay": 27, "budgetWindow": "month"])
        let settings = try #require(plan.cycleSettings)
        // 30.25% = 3025 basis points. The old resolved 120.37 is retained, never replaced by a recomputation
        // from either of the two income values (which are settings, not evidence of a salary credit).
        #expect(settings.daily == .init(mode: "percent", amountMinor: 12037, percentBp: 3025))
        #expect(plan.steps.isEmpty)
        let archive = try #require(JSONSerialization.jsonObject(with: settings.archive) as? [String: Any])
        #expect(archive["monthlyIncome"] as? Int == 15000)
        #expect((archive["dailyBudget"] as? [String: Any])?["monthlyIncome"] as? Int == 12000)
        #expect(archive["budgetWindow"] as? String == "month")
    }
    @Test func invalidOrUnsetLegacySettingsStayRawNeverCoercedToZero() throws {
        for budget in [["amount": 0], ["amount": "12"], ["amount": 12, "incomePct": true], ["amount": 12, "incomePct": 101], ["amount": 12, "incomePct": 0.001]] as [[String: Any]] {
            let plan = try settingsPlan(["dailyBudget": budget, "salaryDay": 1.5, "monthlyIncome": 12000])
            let settings = try #require(plan.cycleSettings)
            #expect(settings.daily == nil && settings.salaryDay == nil && !settings.gregorian)
            #expect(!settings.archive.isEmpty && plan.steps.isEmpty)
        }
        let zeroPercent = try settingsPlan(["dailyBudget": ["amount": 12, "incomePct": 0]])
        #expect(zeroPercent.cycleSettings?.daily == .init(mode: "fixed", amountMinor: 1200, percentBp: nil))
        #expect(try settingsPlan([:]).cycleSettings == nil)
    }
    @Test func categoryWindowAloneDoesNotOverwriteCycleCalendar() throws {
        let plan = try settingsPlan(["budgetWindow": "month"])
        let settings = try #require(plan.cycleSettings)
        #expect(!settings.gregorian && settings.salaryDay == nil && settings.daily == nil)
        let archive = try #require(JSONSerialization.jsonObject(with: settings.archive) as? [String: Any])
        #expect(archive["budgetWindow"] as? String == "month")
        #expect(plan.steps.isEmpty)
    }
    @Test func settingsArchiveAndCommandsAreStableAcrossKeyOrderAndReplay() throws {
        let keys = Keys()
        let a = try settingsPlan(["dailyBudget": ["amount": 12.3], "salaryDay": 27], keys: keys)
        let b = try settingsPlan(["salaryDay": 27, "dailyBudget": ["amount": 12.3]], keys: keys)
        #expect(a.cycleSettings == b.cycleSettings)
        let changed = try settingsPlan(["salaryDay": 28, "dailyBudget": ["amount": 12.3]], keys: keys)
        #expect(changed.cycleSettings?.command != a.cycleSettings?.command)
        #expect(changed.cycleSettings?.archiveID != a.cycleSettings?.archiveID)
    }
}
