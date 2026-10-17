import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
import MadarMoney
@testable import MadarCommands

/// M5-V17 «سجّل مصروفًا»: the effect the sheet shows before saving is exactly what saving does; a split lands on the
/// envelope and «يومك» to the halala; cash already counted when withdrawn is not counted again; one undo restores all;
/// and a bank message for the same purchase waits for a decision instead of counting twice (RM8).
@MainActor struct MoneyExpenseEntryTests {
    @MainActor private final class Store {
        let root = FileManager.default.temporaryDirectory.appending(path: "MoneyExpense-\(UUID())")
        let container: ModelContainer, bus: CommandBus, zone = ActivePlace.riyadh.timeZone
        let start = try! GregorianDay("2026-10-01")
        /// Day 3 of the cycle, noon in Riyadh.
        var now: Date { start.adding(days: 2).date(in: zone).addingTimeInterval(12 * 3600) }
        let bank = UUID(), wallet = UUID(), debit = UUID(), credit = UUID(), envelope = UUID()
        init() throws {
            container = try MadarContainerFactory.makeLocal(at: root)
            bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
            let c = ModelContext(container)
            _ = try SettingsStore(context: c).stage(["core.dayStart": .string("midnight")])
            let cycle = Cycle(); cycle.start = start.date(in: zone); cycle.expectedEnd = start.adding(days: 30).date(in: zone); cycle.dailyAllowanceMinor = 40_000; c.insert(cycle)
            let policy = CyclePolicy(); policy.cycleID = cycle.id; policy.effectiveFromDayKey = start.description; policy.allowanceMinor = 40_000; policy.dailyRateMinor = 40_000; c.insert(policy)
            for (id, kind, balance) in [(bank, "current", 2_000_000), (wallet, "cash", 30_000)] {
                let a = Account(); a.id = id; a.name = kind; a.kind = kind; a.balanceMinor = balance; a.balanceAt = start.date(in: zone); a.bank = "Bank"; a.senderIDs = ["Bank"]; c.insert(a)
            }
            for (id, kind, last4) in [(debit, "debit", "3333"), (credit, "credit", "4444")] {
                let card = Card(); card.id = id; card.name = kind; card.kind = kind; card.bank = "Bank"; card.last4 = last4; card.accountID = bank; c.insert(card)
            }
            let e = Envelope(); e.id = envelope; e.name = "الطوارئ"; e.role = "goal"; c.insert(e)
            let fund = Allocation(); fund.target = "envelope"; fund.targetID = envelope; fund.amountMinor = 100_000; fund.kind = "fund"; fund.idempotencyKey = "fixture"; c.insert(fund)
            let earlier = MoneyTransaction(); earlier.dayKey = start.adding(days: 2).description; earlier.eventAt = now.addingTimeInterval(-7200); earlier.cycleID = cycle.id
            earlier.amountMinor = 12_000; earlier.homeAmountMinor = 12_000; earlier.fromAccountID = bank; earlier.reviewState = "ok"; earlier.showInDiary = false; c.insert(earlier)
            let spend = Allocation(); spend.transactionID = earlier.id; spend.cycleID = cycle.id; spend.target = "daily"; spend.amountMinor = -12_000; spend.kind = "spend"; spend.idempotencyKey = "earlier"; c.insert(spend)
            try c.save()
        }
        deinit { try? FileManager.default.removeItem(at: root) }
        func run(_ name: String, _ p: [String: MadarCore.JSONValue], id: UUID = UUID(), source: CommandSource = .app) async throws -> CommandOutcome {
            try await bus.execute(.init(commandID: id, name: name, payload: .object(p), source: source, issuedAt: now), now: now)
        }
        func cycle() throws -> MoneyCycleReading { try #require(try MoneyRepository(context: ModelContext(container)).cycle(at: now)) }
        func envelopeBalance() throws -> Int { try MoneyRepository(context: ModelContext(container)).allocationRows().filter { $0.target == .envelope(envelope.uuidString) }.reduce(0) { $0 + $1.amountMinor } }
        func diary() throws -> [DiaryAutoLine] { try DiaryLineRenderer.live(day: start.adding(days: 2), context: ModelContext(container)).filter { $0.kind == "mal" } }
    }

    @Test func previewMatchesTheSavedHeadlineAndOneUndoRestoresEverything() async throws {
        let s = try Store(), before = try s.cycle()
        // Day 3: accrued 3 × 400 = 1200, spent 120 → «لك الآن» 1080; today 120 of 400.
        #expect(before.headline.availableNowMinor == 108_000); #expect(before.headline.todaySpentMinor == 12_000)
        // 42.01 on the debit card, a quarter from «الطوارئ»: 1050 from the envelope, 3151 from «يومك» (L12).
        let split = ExpenseEntry.split(chargeMinor: 4_201, share: .quarter)
        let preview = ExpenseEntry.headlineAfter(elapsedDays: before.elapsedDays, before.input, dailySpentMinor: before.spent, expenseDay: before.elapsedDays, dailyChargeMinor: split.dailyMinor)
        #expect(preview.todaySpentMinor == 15_151); #expect(preview.availableNowMinor == 104_849)
        let rows: [MadarCore.JSONValue] = ExpenseEntry.sources(split, envelopeID: s.envelope.uuidString).map { target, amount in
            if case .envelope(let id) = target { return .object(["target": .string("envelope"), "targetID": .string(id), "amountMinor": .string(String(amount))]) }
            return .object(["target": .string("daily"), "amountMinor": .string(String(amount))])
        }
        let command = UUID()
        let payload: [String: MadarCore.JSONValue] = ["amountMinor": .string("4201"), "currency": .string("SAR"), "merchant": .string("البيك"), "method": .string("card"),
            "cardID": .string(s.debit.uuidString), "eventAt": .string(ISO8601DateFormatter().string(from: s.now)), "allocations": .array(rows)]
        #expect(try await s.run("money.logExpense", payload, id: command).status == .applied)
        _ = try await s.run("money.logExpense", payload, id: command)
        #expect(try ModelContext(s.container).fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.source == "manual" && $0.deletedAt == nil }.count == 1, "A second tap on «سجّل» is the same command")
        let after = try s.cycle()
        #expect(after.headline == preview, "The sheet showed exactly what saving does")
        #expect(try s.envelopeBalance() == 98_950)
        #expect(try await s.run("system.undo", ["undoToken": .string(command.uuidString)]).status == .applied)
        #expect(try s.cycle().headline == before.headline); #expect(try s.envelopeBalance() == 100_000); #expect(try s.diary().isEmpty)
    }

    @Test func cashAlreadyCountedAtWithdrawalIsNotChargedAgainAndSplitsAreRefused() async throws {
        let s = try Store(), before = try s.cycle()
        let cash: [String: MadarCore.JSONValue] = ["amountMinor": .string("2000"), "currency": .string("SAR"), "merchant": .string("بقالة"), "method": .string("cash"),
            "fromAccountID": .string(s.wallet.uuidString), "showInDiary": .bool(false)]
        var split = cash; split["allocations"] = .array([.object(["target": .string("daily"), "amountMinor": .string("2000")])])
        #expect(try await s.run("money.logExpense", split).status == .rejected, "No charge to split under «السحب يُخصم من يومك»")
        #expect(try await s.run("money.logExpense", cash).status == .applied)
        #expect(try s.cycle().headline == before.headline)
        #expect(try MoneyRepository(context: ModelContext(s.container)).basis(at: s.now).inAccountMinor == 2_000_000 + 30_000 - 2_000 - 12_000)
        #expect(try s.diary().isEmpty, "Its own switch kept it out of the diary")
        // A split that does not add up to the charge is refused, and a split is decided only in the app.
        let bad: [String: MadarCore.JSONValue] = ["amountMinor": .string("4200"), "currency": .string("SAR"), "method": .string("card"), "cardID": .string(s.credit.uuidString),
            "allocations": .array([.object(["target": .string("envelope"), "targetID": .string(s.envelope.uuidString), "amountMinor": .string("1000")])])]
        #expect(try await s.run("money.logExpense", bad).status == .rejected)
        #expect(try await s.run("money.logExpense", bad, source: .shortcut).status == .rejected)
        // A foreign amount needs a manual rate: 10.00 USD × 3.75 = 37.50 SAR on «يومك».
        let usd: [String: MadarCore.JSONValue] = ["amountMinor": .string("1000"), "currency": .string("USD"), "method": .string("card"), "cardID": .string(s.credit.uuidString)]
        #expect(try await s.run("money.logExpense", usd).status == .rejected)
        var rated = usd; rated["rateAtTime"] = .string("3.75")
        #expect(try await s.run("money.logExpense", rated).status == .applied)
        #expect(try s.cycle().headline.todaySpentMinor == 12_000 + 3_750)
    }

    @Test func aBankMessageForAPurchaseRecordedByHandWaitsForADecision() async throws {
        let s = try Store()
        let at = ISO8601DateFormatter().date(from: "2026-10-03T11:57:00+03:00")!
        #expect(try await s.run("money.logExpense", ["amountMinor": .string("4200"), "currency": .string("SAR"), "merchant": .string("مقهى الزاوية"), "method": .string("card"),
            "cardID": .string(s.debit.uuidString), "eventAt": .string(ISO8601DateFormatter().string(from: at))]).status == .applied)
        let intake = try await s.run("money.ingestBankMessage", ["text": .string("شراء مدى Apple Pay\nبطاقة *3333\n42.00 SAR\nلدى: مقهى الزاوية\n2026-10-03 12:00"), "sender": .string("Bank")], source: .shortcut)
        #expect(intake.status == .applied, "\(intake.reason ?? "")")
        let drafts = try ModelContext(s.container).fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.messageID != nil && $0.deletedAt == nil }
        #expect(drafts.count == 1); #expect(drafts.first?.reviewState == "possibleDuplicate", "Three minutes apart, same card, amount and merchant")
    }
}
