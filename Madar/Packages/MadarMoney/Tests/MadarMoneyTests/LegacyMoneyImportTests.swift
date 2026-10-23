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
