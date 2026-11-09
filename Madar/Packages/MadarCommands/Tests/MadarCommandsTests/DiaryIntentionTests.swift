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
    @Test func delayedReviewIsDueAfterSevenDaysAndUndoPreservesOutcome() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"IntentionReview-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),bus=CommandBus(adapter:DurableCommandAdapter(container:container,lockDirectory:root,transactionClock:{$0})),context=ModelContext(container),id=UUID(),time=now()
        let row=Niyya();row.id=id;row.dayKey="2026-10-08";row.text="أمشي كل مساء";row.result="partial";row.createdAt=time.addingTimeInterval(-7*86_400);row.updatedAt=row.createdAt;context.insert(row);try context.save()
        let payload:[String:MadarCore.JSONValue]=["id":.string(id.uuidString),"period":.string("weekly"),"text":.string("مشيت ثلاث مرات، وسأبدأ بعشر دقائق.")]
        let outcome=try await bus.execute(.init(name:"diary.setIntentionReview",payload:.object(payload),issuedAt:time),now:time),token=try #require(outcome.undoToken)
        var loaded=try ModelContext(container).fetch(FetchDescriptor<Niyya>()).first
        #expect(loaded?.weeklyReview=="مشيت ثلاث مرات، وسأبدأ بعشر دقائق.");#expect(loaded?.monthlyReview==nil);#expect(loaded?.result=="partial");#expect(loaded?.dayKey=="2026-10-08")
        #expect(try await bus.execute(.init(name:"system.undo",payload:.object(["undoToken":.string(token.uuidString)]),issuedAt:time),now:time.addingTimeInterval(1)).status == .applied)
        loaded=try ModelContext(container).fetch(FetchDescriptor<Niyya>()).first
        #expect(loaded?.weeklyReview==nil);#expect(loaded?.result=="partial");#expect(loaded?.text=="أمشي كل مساء")
        await #expect(throws:DataError.self){try await bus.execute(.init(name:"diary.setIntentionReview",payload:.object(["id":.string(id.uuidString),"period":.string("monthly"),"text":.string("مراجعة مبكرة")]),issuedAt:time),now:time)}
        let overdueID = UUID(), overdue = Niyya(); overdue.id = overdueID; overdue.dayKey = "2026-10-01"; overdue.text = "أقرأ كل يوم"; overdue.createdAt = time; overdue.updatedAt = time
        context.insert(overdue); try context.save()
        let monthDate = time.addingTimeInterval(31 * 86_400)
        await #expect(throws:DataError.self){try await bus.execute(.init(name:"diary.setIntentionReview",payload:.object(["id":.string(overdueID.uuidString),"period":.string("monthly"),"text":.string("تقييم الشهر")]),issuedAt:monthDate),now:monthDate)}
        _ = try await bus.execute(.init(name:"diary.setIntentionReview",payload:.object(["id":.string(overdueID.uuidString),"period":.string("weekly"),"text":.string("أقرأ بعد الفجر")]),issuedAt:monthDate),now:monthDate)
        _ = try await bus.execute(.init(name:"diary.setIntentionReview",payload:.object(["id":.string(overdueID.uuidString),"period":.string("monthly"),"text":.string("تقييم الشهر")]),issuedAt:monthDate.addingTimeInterval(1)),now:monthDate.addingTimeInterval(1))
        let checked = try ModelContext(container).fetch(FetchDescriptor<Niyya>()).first{$0.id==overdueID}
        #expect(checked?.weeklyReview=="أقرأ بعد الفجر"); #expect(checked?.monthlyReview=="تقييم الشهر")
    }
    @Test func audioInsightUndoReceiptDoesNotCopyOriginalAudio() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"AudioInsights-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),bus=CommandBus(adapter:DurableCommandAdapter(container:container,lockDirectory:root,transactionClock:{$0})),context=ModelContext(container),id=UUID(),time=now(),original=Data(repeating:0xA5,count:128_000)
        let media=Media();media.id=id;media.kind="audio";media.data=original;media.sizeBytes=original.count;media.sha256="synthetic";media.voiceTone="sad";context.insert(media);try context.save()
        let payload:[String:MadarCore.JSONValue]=["mediaID":.string(id.uuidString),"title":.string("مراجعة يوم هادئ"),"voiceTone":.string("calm"),"audioLevels":.array([.number(0.2),.number(0.8)])]
        let outcome=try await bus.execute(.init(name:"diary.setAudioInsights",payload:.object(payload),issuedAt:time),now:time),token=try #require(outcome.undoToken)
        let receipt=try #require(ModelContext(container).fetch(FetchDescriptor<CommandReceipt>()).first{$0.name=="diary.setAudioInsights"}),undoJSON=try #require(receipt.undoJSON)
        let undoText=String(decoding:undoJSON,as:UTF8.self)
        #expect(undoJSON.count < 4_096);#expect(!undoText.contains(original.base64EncodedString()))
        var loaded=try ModelContext(container).fetch(FetchDescriptor<Media>()).first
        #expect(loaded?.data==original);#expect(loaded?.title=="مراجعة يوم هادئ");#expect(loaded?.voiceTone=="sad")
        #expect(try await bus.execute(.init(name:"system.undo",payload:.object(["undoToken":.string(token.uuidString)]),issuedAt:time),now:time.addingTimeInterval(1)).status == .applied)
        loaded=try ModelContext(container).fetch(FetchDescriptor<Media>()).first
        #expect(loaded?.data==original);#expect(loaded?.title==nil);#expect(loaded?.voiceTone=="sad");#expect(loaded?.audioLevelsJSON==nil)
    }
}
