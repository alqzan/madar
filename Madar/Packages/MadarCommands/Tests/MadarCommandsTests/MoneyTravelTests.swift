import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
import MadarMoney
@testable import MadarCommands

@MainActor struct MoneyTravelTests {
    @MainActor private final class Store {
        let root = FileManager.default.temporaryDirectory.appending(path: "MoneyTravel-\(UUID())")
        let container: ModelContainer
        let bus: CommandBus
        let tripID = UUID(), bankID = UUID()
        let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00+03:00")!
        init() throws {
            container = try MadarContainerFactory.makeLocal(at: root)
            bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
            let c = ModelContext(container); _ = try SettingsStore(context: c).stage(["core.dayStart": .string("midnight")])
            let a = Account(); a.id = bankID; a.balanceMinor = 2_000_000; a.balanceAt = now.addingTimeInterval(-20*86400); a.bank = "Bank"; a.last4 = "5512"; a.senderIDs = ["Bank"]; c.insert(a)
            let t = Trip(); t.id = tripID; t.city = "مدينة الاختبار"; t.currency = "USD"; t.fxRateToHome = "3.75"; t.fxSetAt = now.addingTimeInterval(-86400); t.start = now.addingTimeInterval(-3*86400); t.lat = 40.7; t.lon = -74; t.tzID = "America/New_York"; c.insert(t)
            let cyc = Cycle(); cyc.start = now.addingTimeInterval(-5*86400); cyc.expectedEnd = now.addingTimeInterval(25*86400); cyc.dailyAllowanceMinor = 40000; c.insert(cyc)
            let p = CyclePolicy(); p.cycleID = cyc.id; p.effectiveFromDayKey = "2026-10-12"; p.allowanceMinor = 40000; p.dailyRateMinor = 40000; c.insert(p)
            let e = Envelope(); e.role = "reserve"; e.name = "الاحتياطي"; c.insert(e)
            let f = Allocation(); f.target = "reserve"; f.amountMinor = 500_000; f.kind = "fund"; f.idempotencyKey = "fixture"; c.insert(f); try c.save()
        }
        deinit { try? FileManager.default.removeItem(at: root) }
        func run(_ name: String, _ p: [String: MadarCore.JSONValue], id: UUID = UUID()) async throws -> CommandOutcome { try await bus.execute(.init(commandID: id, name: name, payload: .object(p), issuedAt: now), now: now) }
        var ratePayload: [String: MadarCore.JSONValue] { ["id": .string(tripID.uuidString), "currency": .string("USD"), "rate": .string("4"), "expectedRate": .string("3.75"), "expectedCurrency": .string("USD")] }
        func expense(_ amount: Int, id: UUID) async throws -> CommandOutcome { try await run("money.logExpense", ["currency": .string("USD"), "amountMinor": .string(String(amount)), "fromAccountID": .string(bankID.uuidString), "method": .string("transfer")], id: id) }
    }
    @Test func tripPriceIsFrozenAndBudgetIsChargedOnceWithUndo() async throws {
        let s = try Store(), purchase = UUID(), priceChange = UUID()
        #expect(try await s.expense(1234, id: purchase).status == .applied)
        let c = ModelContext(s.container), repo = MoneyRepository(context: c)
        let tx = try #require(try repo.confirmedTransactions().first { $0.id == purchase })
        #expect(tx.homeAmountMinor == 4628); #expect(tx.rateAtTime == "3.75"); #expect(tx.rateSource == "trip"); #expect(tx.tripID == s.tripID)
        #expect(try repo.allocationRows(transactionID: purchase).map(\.target) == [.envelope(s.tripID.uuidString)])
        #expect(try repo.cycle(at: s.now)?.headline.todaySpentMinor == 0)
        #expect(try await s.run("money.configureTrip", s.ratePayload, id: priceChange).status == .applied)
        let fresh = MoneyRepository(context: ModelContext(s.container))
        #expect(try fresh.confirmedTransactions().first?.homeAmountMinor == 4628)
        #expect(try await s.run("system.undo", ["undoToken": .string(priceChange.uuidString)]).status == .applied)
        #expect(try await s.run("money.configureTrip", s.ratePayload).status == .applied)
        let next = UUID(); #expect(try await s.expense(1234, id: next).status == .applied)
        #expect(try MoneyRepository(context: ModelContext(s.container)).confirmedTransactions().first { $0.id == next }?.homeAmountMinor == 4936)
        #expect(try await s.run("system.undo", ["undoToken": .string(next.uuidString)]).status == .applied)
        let undoStore = try Store(), isolated = UUID()
        #expect(try await undoStore.expense(1234, id: isolated).status == .applied)
        #expect(try await undoStore.run("system.undo", ["undoToken": .string(isolated.uuidString)]).status == .applied)
        #expect(try MoneyRepository(context: ModelContext(undoStore.container)).confirmedTransactions().isEmpty)
    }
    /// OR-09: the second country of one journey charges the same trip envelope, in its own currency and price.
    @Test func aSecondLegChargesTheJourneyEnvelopeAtItsOwnPrice() async throws {
        let s = try Store(), first = UUID(), second = UUID(), legID = UUID()
        #expect(try await s.expense(1234, id: first).status == .applied)
        let c = ModelContext(s.container), leg1 = try #require(try c.fetch(FetchDescriptor<Trip>()).first { $0.id == s.tripID })
        leg1.end = s.now.addingTimeInterval(-3600)
        let leg2 = Trip(); leg2.id = legID; leg2.journeyID = s.tripID; leg2.city = "المدينة الثانية"; leg2.currency = "EUR"; leg2.fxRateToHome = "4.1"; leg2.fxSetAt = leg1.end; leg2.start = leg1.end; leg2.lat = 48.8; leg2.lon = 2.3; leg2.tzID = "Europe/Paris"; c.insert(leg2); try c.save()
        #expect(try await s.run("money.logExpense", ["currency": .string("EUR"), "amountMinor": .string("1000"), "fromAccountID": .string(s.bankID.uuidString), "method": .string("transfer")], id: second).status == .applied)
        let repo = MoneyRepository(context: ModelContext(s.container))
        let tx = try #require(try repo.confirmedTransactions().first { $0.id == second })
        #expect(tx.tripID == legID); #expect(tx.homeAmountMinor == 4100); #expect(tx.rateAtTime == "4.1")
        #expect(try repo.allocationRows(transactionID: second).map(\.target) == [.envelope(s.tripID.uuidString)], "Both legs spend from the one journey envelope")
        let now2 = try #require(try repo.trip(at: s.now))
        #expect(now2.id == legID); #expect(now2.journeyKey == s.tripID)
        #expect(try repo.tripEnvelope(now2)?.id == s.tripID)
        #expect(try repo.journeyLegs(of: now2).map(\.id) == [s.tripID, legID])
        #expect(try repo.allocationRows().filter { $0.target == .envelope(s.tripID.uuidString) }.reduce(0) { $0 + $1.amountMinor } == -(4628 + 4100))
        #expect(try await s.run("system.undo", ["undoToken": .string(second.uuidString)]).status == .applied)
        #expect(try MoneyRepository(context: ModelContext(s.container)).allocationRows().filter { $0.target == .envelope(s.tripID.uuidString) }.reduce(0) { $0 + $1.amountMinor } == -4628)
    }
    @Test func repricingPreviewsAllHalalasAndRefundsAndOneUndoRestoresTheOriginalGraph() async throws {
        let s = try Store(), original = UUID(), refundID = UUID()
        #expect(try await s.expense(1234, id: original).status == .applied)
        // A full foreign refund restores exactly 46.28, even after the trip's current price changes.
        let c = ModelContext(s.container), refund = MoneyTransaction(); refund.id = refundID; refund.kind = "refund"; refund.currency = "USD"; refund.amountMinor = 1234; refund.homeCurrency = "SAR"; refund.relatedTransactionID = original; refund.toAccountID = s.bankID; refund.reviewState = "needsLook"; refund.eventAt = s.now; refund.dayKey = "2026-10-17"; c.insert(refund); try c.save()
        #expect(try await s.run("money.confirmTransaction", ["id": .string(refundID.uuidString)]).status == .applied)
        #expect(try await s.run("money.configureTrip", s.ratePayload).status == .applied)
        let repo = MoneyRepository(context: ModelContext(s.container)), preview = try repo.previewTripReprice(id: s.tripID, rate: "4", at: s.now)
        #expect(preview.lines.count == 2); #expect(preview.lines.allSatisfy { $0.beforeMinor == 4628 && $0.afterMinor == 4936 })
        let id = UUID(), p: [String: MadarCore.JSONValue] = ["id": .string(s.tripID.uuidString), "rate": .string("4"), "signature": .string(preview.signature)]
        #expect(try await s.run("money.repriceTrip", p, id: id).status == .applied)
        let after = MoneyRepository(context: ModelContext(s.container))
        #expect(try after.allocationRows().filter { $0.target == .envelope(s.tripID.uuidString) }.reduce(0) { $0 + $1.amountMinor } == 0)
        #expect(try after.confirmedTransactions().allSatisfy { $0.homeAmountMinor == 4936 && $0.amountMinor == 1234 })
        #expect(try await s.run("money.repriceTrip", p).status == .rejected, "A changed graph invalidates the old preview")
        #expect(try await s.run("system.undo", ["undoToken": .string(id.uuidString)]).status == .applied)
        #expect(try MoneyRepository(context: ModelContext(s.container)).confirmedTransactions().allSatisfy { $0.homeAmountMinor == 4628 && $0.rateAtTime == "3.75" })
    }
    @Test func repricingKeepsClosedCyclesAndBankPricesAndRejectsAChangedRefundGraph() async throws {
        let s = try Store(), original = UUID(); #expect(try await s.expense(1234, id: original).status == .applied)
        #expect(try await s.run("money.configureTrip", s.ratePayload).status == .applied)
        let old = try MoneyRepository(context: ModelContext(s.container)).previewTripReprice(id: s.tripID, rate: "4", at: s.now)
        let c = ModelContext(s.container), tx = try #require(try c.fetch(FetchDescriptor<MoneyTransaction>()).first)
        tx.rateSource = "message"; try c.save()
        let protected = try MoneyRepository(context: ModelContext(s.container)).previewTripReprice(id: s.tripID, rate: "4", at: s.now)
        #expect(protected.lines.isEmpty); #expect(protected.excludedCount == 1)
        #expect(try await s.run("money.repriceTrip", ["id": .string(s.tripID.uuidString), "rate": .string("4"), "signature": .string(old.signature)]).status == .rejected)
        tx.rateSource = "trip"; let cycle = try #require(try c.fetch(FetchDescriptor<Cycle>()).first); cycle.closedAt = s.now; try c.save()
        #expect(try MoneyRepository(context: ModelContext(s.container)).previewTripReprice(id: s.tripID, rate: "4", at: s.now).lines.isEmpty)
    }
    @Test func bankStatedHomeAmountWinsOverTripPriceAndDraftKeepsItsPrice() async throws {
        let s = try Store()
        let message = "شراء\nمن حساب *5512\nمبلغ 12.34 USD\nبما يعادل 46.30 SAR\nلدى: متجر الاختبار"
        #expect(try await s.run("money.ingestBankMessage", ["text": .string(message), "sender": .string("Bank")]).status == .applied)
        let repo = MoneyRepository(context: ModelContext(s.container)), row = try #require(try repo.pendingTransactions().first)
        #expect(row.homeAmountMinor == 4630); #expect(row.rateSource == "message"); #expect(row.tripID == s.tripID)
        #expect(try await s.run("money.configureTrip", s.ratePayload).status == .applied)
        #expect(try await s.run("money.confirmTransaction", ["id": .string(row.id.uuidString)]).status == .applied)
        #expect(try MoneyRepository(context: ModelContext(s.container)).confirmedTransactions().first?.homeAmountMinor == 4630)
    }
    @Test func manualExpenseKeepsTheActiveTripMethodAtItsEventTime() async throws {
        let s = try Store(), context = ModelContext(s.container)
        _ = try SettingsStore(context: context).stage([
            "core.dayStart": .string("fajr"),
            "salah.method": .string("mwl"),
            "salah.tripMethod": .string("egyptian"),
            "salah.highLatitudeRule": .string("twilightAngle")
        ])
        let trip = try #require(context.fetch(FetchDescriptor<Trip>()).first)
        trip.city = "لندن"; trip.lat = 51.5074; trip.lon = -0.1278; trip.tzID = "Europe/London"
        trip.start = ISO8601DateFormatter().date(from: "2026-03-20T04:00:00Z")
        trip.end = ISO8601DateFormatter().date(from: "2026-03-21T00:00:00Z")
        try context.save()

        let eventAt = "2026-03-20T04:08:00Z", id = UUID()
        #expect(try await s.run("money.logExpense", [
            "amountMinor": .string("100"), "currency": .string("SAR"), "method": .string("transfer"),
            "fromAccountID": .string(s.bankID.uuidString), "eventAt": .string(eventAt)
        ], id: id).status == .applied)
        let row = try #require(MoneyRepository(context: ModelContext(s.container)).confirmedTransactions().first { $0.id == id })
        // The approved London MWL fixture puts Fajr at 04:10 ±3 minutes; Egypt's earlier Fajr
        // makes 04:08 part of 20 March while the home method would still stamp 19 March.
        #expect(row.dayKey == "2026-03-20")
        #expect(row.tzID == "Europe/London")
        #expect(row.dayPolicy == "fajr@1")
    }
    @Test func aTripEnvelopeTombstoneIsRevivedOnceAfterUndo() async throws {
        let s = try Store(), first = UUID()
        #expect(try await s.expense(1234, id: first).status == .applied)
        #expect(try await s.run("system.undo", ["undoToken": .string(first.uuidString)]).status == .applied)
        #expect(try await s.expense(2000, id: UUID()).status == .applied)
        let rows = try ModelContext(s.container).fetch(FetchDescriptor<Envelope>()).filter { $0.id == s.tripID }
        #expect(rows.count == 1); #expect(rows.first?.deletedAt == nil); #expect(rows.first?.balanceMinor == -7500)
    }
    @Test func fundingMovesExistingMoneyWithOneUndoAndRejectsStaleOrOverspend() async throws {
        let s = try Store(), id = UUID()
        var p: [String: MadarCore.JSONValue] = ["id": .string(s.tripID.uuidString), "amountMinor": .string("300000"), "source": .string("reserve"), "due": .string(ISO8601DateFormatter().string(from: s.now.addingTimeInterval(3*86400))), "expectedBalanceMinor": .string("0")]
        let before = try MoneyRepository(context: ModelContext(s.container)).basis(at: s.now)
        #expect(try await s.run("money.fundTrip", p, id: id).status == .applied)
        let after = try MoneyRepository(context: ModelContext(s.container)).basis(at: s.now)
        #expect(before == after)
        #expect(try await s.run("money.fundTrip", p).status == .rejected)
        p["expectedBalanceMinor"] = .string("300000"); p["amountMinor"] = .string("300001")
        #expect(try await s.run("money.fundTrip", p).status == .rejected)
        #expect(try await s.run("system.undo", ["undoToken": .string(id.uuidString)]).status == .applied)
        #expect(try MoneyRepository(context: ModelContext(s.container)).basis(at: s.now) == before)
    }
    @Test func manualPriceConnectsForeignAccountsAndStaleOrInvalidPricesAreRefused() async throws {
        let s = try Store(), c = ModelContext(s.container), a = Account(); a.currency = "USD"; a.balanceMinor = 1234; a.balanceAt = s.now; c.insert(a); try c.save()
        #expect(try MoneyRepository(context: c).basis(at: s.now).inAccountMinor == 2_004_628)
        var p = s.ratePayload; p["rate"] = .string("0")
        #expect(try await s.run("money.configureTrip", p).status == .rejected)
        p = s.ratePayload; p["expectedRate"] = .null
        #expect(try await s.run("money.configureTrip", p).status == .rejected)
        #expect(try await s.run("money.configureTrip", s.ratePayload).status == .applied)
        #expect(try MoneyRepository(context: ModelContext(s.container)).basis(at: s.now).inAccountMinor == 2_004_936)
    }
}
