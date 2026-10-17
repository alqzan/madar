import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
import MadarMoney
@testable import MadarCommands

@MainActor struct MoneyZakatTests {
    @MainActor private final class Store {
        let root=FileManager.default.temporaryDirectory.appending(path:"MoneyZakat-\(UUID())")
        let container:ModelContainer
        let bus:CommandBus
        let now=ISO8601DateFormatter().date(from:"2026-10-17T12:00:00+03:00")!
        init() throws {
            container=try MadarContainerFactory.makeLocal(at:root)
            bus=CommandBus(adapter:DurableCommandAdapter(container:container,lockDirectory:root,transactionClock:{$0}))
            let c=ModelContext(container)
            let a=Account();a.balanceMinor=12_850_000;a.balanceAt=now;c.insert(a)
            let excluded=Account();excluded.balanceMinor=500_000;excluded.zakatInclude=false;excluded.balanceAt=now;c.insert(excluded)
            let other=Account();other.balanceMinor=999_999;other.ownership="notMine";other.balanceAt=now;c.insert(other)
            let card=Card();card.kind="credit";card.accountID=a.id;c.insert(card)
            let statement=Statement();statement.cardID=card.id;statement.statementMinor=680_000;statement.closeDate=now.addingTimeInterval(-10*86400);statement.dueDate=now.addingTimeInterval(-86400);c.insert(statement)
            let purchase=MoneyTransaction();purchase.amountMinor=180_000;purchase.homeAmountMinor=180_000;purchase.reviewState="ok";purchase.cardID=card.id;purchase.method="card";purchase.eventAt=now.addingTimeInterval(-86400);purchase.dayKey="2026-10-16";c.insert(purchase)
            let bnpl=Obligation();bnpl.kind="installment";c.insert(bnpl)
            for (amount,offset) in [(40000,-1),(80000,30)] {let item=InstallmentItem();item.obligationID=bnpl.id;item.amountMinor=amount;item.dueDate=now.addingTimeInterval(Double(offset*86400));c.insert(item)}
            let loan=Obligation();loan.kind="loan";c.insert(loan)
            for (amount,offset) in [(285000,-1),(2565000,30)] {let item=InstallmentItem();item.obligationID=loan.id;item.amountMinor=amount;item.dueDate=now.addingTimeInterval(Double(offset*86400));c.insert(item)}
            let reserve=Envelope();reserve.role="reserve";reserve.balanceMinor=10_000_000;c.insert(reserve)
            let fund=Allocation();fund.target="reserve";fund.amountMinor=10_000_000;fund.kind="fund";fund.idempotencyKey="test";c.insert(fund);try c.save()
        }
        deinit{try? FileManager.default.removeItem(at:root)}
        func reading(at:Date?=nil)throws->MoneyZakatReading{try MoneyRepository(context:ModelContext(container)).zakat(at:at ?? now)}
        func payload(_ r:MoneyZakatReading,debts:String="none")->[String:MadarCore.JSONValue]{["signature":.string(r.signature),"basis":.string("gold"),"debts":.string(debts),"goldPriceMinor":.string("40000"),"silverPriceMinor":.null,"goldMg":.string("85000"),"silverMg":.string("595000"),"otherMinor":.string("0"),"hawl":.string("h:1447-09-01")]}
        func run(_ p:[String:MadarCore.JSONValue],id:UUID=UUID(),at:Date?=nil)async throws->CommandOutcome{let t=at ?? now;return try await bus.execute(.init(commandID:id,name:"money.saveZakat",payload:.object(p),issuedAt:t),now:t)}
        func undo(_ id:UUID)async throws->CommandOutcome{try await bus.execute(.init(name:"system.undo",payload:.object(["undoToken":.string(id.uuidString)]),issuedAt:now),now:now)}
    }
    @Test func sameSourcesAsBasisAndNoEnvelopeDoubleCount() throws {
        let s=try Store(),r=try s.reading()
        #expect(!r.hasProfile);#expect(r.input.debtsPolicy == .unset)
        #expect(r.input.owedAllMinor == 980000);#expect(r.input.loanRemainingMinor == 2850000);#expect(r.input.dueNowMinor == 1005000)
        var input=r.input;input.goldPricePerGramMinor=40000;input.debtsPolicy = .none
        #expect(ZakatEngine.assess(input,now:s.now).outcome == .due(amountMinor:321250))
        input.debtsPolicy = .allOwed;#expect(ZakatEngine.assess(input,now:s.now).outcome == .due(amountMinor:296750))
        input.debtsPolicy = .allOwedAndLoan;#expect(ZakatEngine.assess(input,now:s.now).outcome == .due(amountMinor:225500))
        #expect(r.accounts.count == 2);#expect(r.accounts.filter(\.included).count == 1)
    }
    @Test func saveUndoAndResaveKeepOneSingletonAndStaleSheetsAreRejected()async throws{
        let s=try Store(),r=try s.reading(),id=UUID(),p=s.payload(r)
        #expect(try await s.run(p,id:id).status == .applied)
        #expect(try s.reading().input.goldPriceSetAt == s.now)
        #expect(try await s.run(p).status == .rejected)
        #expect(try await s.undo(id).status == .applied)
        #expect(try !s.reading().hasProfile)
        #expect(try await s.run(s.payload(s.reading())).status == .applied)
        #expect(try ModelContext(s.container).fetch(FetchDescriptor<ZakatProfile>()).count == 1)
    }
    @Test func editingDebtDoesNotRefreshAnOldPriceAndInvalidDatesDoNotWrite()async throws{
        let s=try Store();#expect(try await s.run(s.payload(s.reading())).status == .applied)
        let later=s.now.addingTimeInterval(40*86400),current=try s.reading(at:later)
        #expect(try await s.run(s.payload(current,debts:"allOwed"),at:later).status == .applied)
        let after=try s.reading(at:later);#expect(after.input.goldPriceSetAt == s.now);#expect(ZakatEngine.assess(after.input,now:later).goldPriceStale)
        var bad=s.payload(after);bad["hawl"] = .string("h:1448-13-01")
        #expect(try await s.run(bad,at:later).status == .rejected)
        #expect(try s.reading(at:later).input.hawlStartHijri == "h:1447-09-01")
    }
}
