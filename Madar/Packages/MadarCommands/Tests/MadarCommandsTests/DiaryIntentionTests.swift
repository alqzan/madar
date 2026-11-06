import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands
@MainActor struct DiaryIntentionTests {
    private func now()->Date {ISO8601DateFormatter().date(from:"2026-10-15T12:00:00+03:00")!}
    @Test func intentionReplayResultUndoAndImmutableStoredDay() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"Intention-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),bus=CommandBus(adapter:DurableCommandAdapter(container:container,lockDirectory:root,transactionClock:{$0})),context=ModelContext(container),id=UUID(),time=now()
        let command=CommandEnvelope(name:"diary.setIntention",payload:.object(["id":.string(id.uuidString),"dayKey":.string("2026-10-15"),"text":.string("أُنهي ما بدأت")]),issuedAt:time)
        #expect(try await bus.execute(command,now:time).status == .applied);#expect(try await bus.execute(command,now:time).status == .applied)
        var rows=try context.fetch(FetchDescriptor<Niyya>());#expect(rows.count==1);#expect(rows[0].result==nil);#expect(rows[0].dayKey=="2026-10-15")
        let outcome=try await bus.execute(.init(name:"diary.setIntentionResult",payload:.object(["id":.string(id.uuidString),"result":.string("partial")]),issuedAt:time),now:time.addingTimeInterval(1));let token=try #require(outcome.undoToken)
        _ = try await bus.execute(.init(name:"settings.set",payload:.object(["settings":.object(["core.dayStart":.string("midnight")])]),issuedAt:time),now:time.addingTimeInterval(2))
        #expect(try await bus.execute(.init(name:"system.undo",payload:.object(["undoToken":.string(token.uuidString)]),issuedAt:time),now:time.addingTimeInterval(3)).status == .applied)
        rows=try ModelContext(container).fetch(FetchDescriptor<Niyya>());#expect(rows[0].result==nil);#expect(rows[0].dayKey=="2026-10-15")
        await #expect(throws:DataError.self) { try await bus.execute(.init(name:"diary.setIntention",payload:.object(["id":.string(id.uuidString),"dayKey":.string("2026-10-14"),"text":.string("لا تغيّر اليوم")]),issuedAt:time),now:time.addingTimeInterval(4)) }
        #expect(try ModelContext(container).fetch(FetchDescriptor<Niyya>()).first?.dayKey=="2026-10-15")
    }
    @Test func boundedOrderAndSupersededUndoDoNotOverwriteOutcome() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"IntentionCap-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),bus=CommandBus(adapter:DurableCommandAdapter(container:container,lockDirectory:root,transactionClock:{$0})),time=now();var ids:[UUID]=[]
        for n in 0...10 {
            let id=UUID();ids.append(id)
            let command=CommandEnvelope(name:"diary.setIntention",payload:.object(["id":.string(id.uuidString),"dayKey":.string("2026-10-15"),"text":.string("نيّة \(n)")]),issuedAt:time)
            if n<10 {#expect(try await bus.execute(command,now:time.addingTimeInterval(Double(n))).status == .applied)}
            else {await #expect(throws:DataError.self){try await bus.execute(command,now:time.addingTimeInterval(Double(n)))}}
        }
        #expect(try ModelContext(container).fetch(FetchDescriptor<Niyya>()).map(\.order).sorted()==Array(0...9))
        let first=try await bus.execute(.init(name:"diary.setIntentionResult",payload:.object(["id":.string(ids[0].uuidString),"result":.string("notEasy")]),issuedAt:time),now:time.addingTimeInterval(15));let token=try #require(first.undoToken)
        _ = try await bus.execute(.init(name:"diary.setIntentionResult",payload:.object(["id":.string(ids[0].uuidString),"result":.string("done")]),issuedAt:time),now:time.addingTimeInterval(16))
        await #expect(throws:DataError.self) { try await bus.execute(.init(name:"system.undo",payload:.object(["undoToken":.string(token.uuidString)]),issuedAt:time),now:time.addingTimeInterval(17)) }
        #expect(try ModelContext(container).fetch(FetchDescriptor<Niyya>()).first{$0.id==ids[0]}?.result=="done")
    }
    /// FB-45: «احذف النيّة» tombstones the row (never a hard delete) and undo restores its text and result.
    @Test func deleteIntentionTombstonesAndUndoRestores() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"IntentionDelete-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),bus=CommandBus(adapter:DurableCommandAdapter(container:container,lockDirectory:root,transactionClock:{$0})),id=UUID(),time=now()
        _ = try await bus.execute(.init(name:"diary.setIntention",payload:.object(["id":.string(id.uuidString),"dayKey":.string("2026-10-15"),"text":.string("أصل رحمي")]),issuedAt:time),now:time)
        _ = try await bus.execute(.init(name:"diary.setIntentionResult",payload:.object(["id":.string(id.uuidString),"result":.string("done")]),issuedAt:time),now:time.addingTimeInterval(1))
        let outcome=try await bus.execute(.init(name:"diary.deleteIntention",payload:.object(["id":.string(id.uuidString)]),issuedAt:time),now:time.addingTimeInterval(2));let token=try #require(outcome.undoToken)
        var rows=try ModelContext(container).fetch(FetchDescriptor<Niyya>());#expect(rows.count==1);#expect(rows[0].deletedAt != nil)
        await #expect(throws:DataError.self){try await bus.execute(.init(name:"diary.setIntentionResult",payload:.object(["id":.string(id.uuidString),"result":.string("partial")]),issuedAt:time),now:time.addingTimeInterval(3))}
        #expect(try await bus.execute(.init(name:"system.undo",payload:.object(["undoToken":.string(token.uuidString)]),issuedAt:time),now:time.addingTimeInterval(4)).status == .applied)
        rows=try ModelContext(container).fetch(FetchDescriptor<Niyya>());#expect(rows.count==1);#expect(rows[0].deletedAt==nil);#expect(rows[0].text=="أصل رحمي");#expect(rows[0].result=="done")
    }
}
