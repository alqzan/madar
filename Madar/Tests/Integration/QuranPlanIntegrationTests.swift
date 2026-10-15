import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarCommands
@testable import Madar

@MainActor final class QuranPlanIntegrationTests: XCTestCase {
    func testUnitQuantityUsesArabicPluralCatalog() {
        var p=QuranUIPlanInput(startAyah:1,unit:.quarter,amount:1,rhythm:.balanced,restDay:"friday",missPolicy:"ask")
        XCTAssertEqual(QuranPlanCopy.amount(p,digits:.init()),"ربع وجه")
        p.amount=2;XCTAssertEqual(QuranPlanCopy.amount(p,digits:.init()),"ربعان من وجه")
        p.unit = .ayah;XCTAssertEqual(QuranPlanCopy.amount(p,digits:.init()),"آيتان")
        p.unit = .page;p.amount=11;XCTAssertEqual(String(QuranPlanCopy.amount(p,digits:.init()).unicodeScalars.filter { !(0x2066...0x2069).contains($0.value) }),"١١ وجهًا")
    }
    func testForecastCountsTodayUntilWholeWirdIsComplete() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"QuranPlan-\(UUID())")
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),context=ModelContext(container)
        _ = try SettingsStore(context:context).stage(["core.dayStart":.string("midnight"),"quran.restDay":.string("none")])
        let now=ISO8601DateFormatter().date(from:"2026-10-15T15:00:00+03:00")!
        let plan=HifzPlan();plan.activeFrom=now.addingTimeInterval(-86400);context.insert(plan)
        let row=HifzSession();row.planID=plan.id;row.fromAyah=1;row.toAyah=3;row.pages=[1];row.dayKey="2026-10-15";row.endedAt=now.addingTimeInterval(-3600);context.insert(row);try context.save()
        let app=try AppSession(container:container,groupDirectory:root),service=AppQuranService(session:app,clock:{now})
        let input=QuranUIPlanInput(startAyah:1,unit:.page,amount:1,rhythm:.balanced,restDay:"none",missPolicy:"ask")
        // 604 faces, one per day, no rest: today plus 603 days; three ayahs do not complete the first face.
        let expected=service.displayDate(try GregorianDay("2028-06-09"),hijriOnly:true)
        let partial = try await service.previewPlan(input); XCTAssertEqual(partial.title,expected)
        row.toAyah=7;try context.save() // Whole first face: 603 remain, starting tomorrow gives the same date.
        let complete = try await service.previewPlan(input); XCTAssertEqual(complete.title,expected)
        let overview=try service.planOverview()
        XCTAssertEqual(overview.forecasts.count,4)
        XCTAssertNotEqual(overview.forecasts["simple"]?.title,overview.forecasts["deep"]?.title)
    }
}
