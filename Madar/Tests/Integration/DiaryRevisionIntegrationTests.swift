import XCTest
import SwiftData
import MadarCore
import MadarData
@testable import Madar
@MainActor final class DiaryRevisionIntegrationTests:XCTestCase {
    // RD1 [DEFAULT]: an edit of a frozen day shows one line everywhere, keeps the original readable, and undo restores it.
    func testFrozenEditShowsOnceEverywhereAndUndoRestores() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"DiaryRevision-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),app=try AppSession(container:container,groupDirectory:root)
        app.authorizeProtectedData();let service=AppDiaryService(app:app,clock:{Date()}),context=ModelContext(container)
        let day=try service.currentDay().adding(days:-10),row=Entry();row.dayKey=day.description;row.text="جلسنا عند البحر";row.tzID="Asia/Riyadh";row.dayPolicy="midnight@1";row.eventAt=day.date(in:TimeZone(identifier:"Asia/Riyadh")!).addingTimeInterval(18*3600)
        let margin=MarginNote();margin.targetDayKey=day.description;margin.targetEntryID=row.id;margin.text="ما زلت أذكره";margin.writtenDayKey=try service.currentDay().description;margin.writtenAt=Date()
        context.insert(row);context.insert(margin);try context.save()
        try await service.edit(row.id.uuidString,text:"جلسنا عند البحر حتى المغرب")
        let page=try service.day(day),written=page.lines.filter{$0.kind=="normal"}
        XCTAssertEqual(written.map(\.text),["جلسنا عند البحر حتى المغرب"])
        XCTAssertEqual(page.originals[written[0].id],"جلسنا عند البحر");XCTAssertTrue(page.editable.contains(written[0].id))
        XCTAssertTrue(page.lines.contains{$0.kind=="margin" && $0.text=="ما زلت أذكره"})
        XCTAssertEqual(try service.archive().days.first{$0.day==day}.map{_ in 1},1)
        let docs=try service.searchIndex().documents.filter{$0.day==day && $0.kind != "margin"}
        XCTAssertEqual(docs.map(\.text),["جلسنا عند البحر حتى المغرب"])
        let exported=try service.exportPages(.init(format:"json",year:day.year,month:day.month,margins:false,sources:false)).first{$0.day==day}
        XCTAssertEqual(exported?.lines.map(\.text),["جلسنا عند البحر حتى المغرب"])
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Entry>()).first{$0.id==row.id}?.text,"جلسنا عند البحر")
        app.undo();for _ in 0..<50 where app.undoToken != nil {try await Task.sleep(for:.milliseconds(50))}
        XCTAssertEqual(try service.day(day).lines.filter{$0.kind=="normal"}.map(\.text),["جلسنا عند البحر"])
        XCTAssertTrue(try service.day(day).originals.isEmpty)
    }
}
