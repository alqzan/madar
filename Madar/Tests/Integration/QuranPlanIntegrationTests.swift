import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarCommands
@testable import Madar

@MainActor final class QuranPlanIntegrationTests: XCTestCase {
    func testMissedDayExampleUsesPlanAmountAndSkipsRestWithoutWritingAllotments() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "QuranMissPreview-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        let app = try AppSession(container: container, groupDirectory: root), service = AppQuranService(session: app)
        let input = QuranUIPlanInput(startAyah: 1, unit: .page, amount: 1, rhythm: .balanced, restDay: "friday", missPolicy: "ask")
        let preview = try service.missedDayPreviews(input: input, startingOn: GregorianDay("2026-10-15"), level: .medium)
        let spread = try XCTUnwrap(preview["spread"])
        XCTAssertEqual(spread.map(\.id), ["2026-10-15", "2026-10-17", "2026-10-18", "2026-10-19"])
        XCTAssertEqual(spread.map(\.base), [1, 1, 1, 1])
        for day in spread.prefix(3) { XCTAssertEqual(day.extra, 1.0 / 3, accuracy: 0.000001) }
        XCTAssertEqual(spread[3].extra, 0)
        XCTAssertEqual(preview["double"]?.map(\.extra), [1, 0, 0, 0])
        XCTAssertEqual(preview["skip"]?.map(\.extra), [0, 0, 0, 0])
        let deep = try service.missedDayPreviews(input: input, startingOn: GregorianDay("2026-10-16"), level: .deep)
        XCTAssertEqual(deep["spread"]?.first?.id, "2026-10-17")
        XCTAssertEqual(deep["spread"]?.first?.base, 1.5)
        XCTAssertEqual(deep["spread"]?.first?.extra, 0.5)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuranAllotment>()), 0)
    }
    func testUnitQuantityUsesArabicPluralCatalog() {
        var p=QuranUIPlanInput(startAyah:1,unit:.quarter,amount:1,rhythm:.balanced,restDay:"friday",missPolicy:"ask")
        XCTAssertEqual(QuranPlanCopy.amount(p,digits:.init()),"ربع وجه")
        p.amount=2;XCTAssertEqual(QuranPlanCopy.amount(p,digits:.init()),"ربعان من وجه")
        p.unit = .ayah;XCTAssertEqual(QuranPlanCopy.amount(p,digits:.init()),"آيتان")
        p.unit = .page;p.amount=11;XCTAssertEqual(String(QuranPlanCopy.amount(p,digits:.init()).unicodeScalars.filter { !(0x2066...0x2069).contains($0.value) }),"١١ وجهًا")
        p.amount = 0.25; XCTAssertEqual(QuranPlanCopy.amount(p, digits: .init()), "ربع وجه")
        p.amount = 0.5; XCTAssertEqual(QuranPlanCopy.amount(p, digits: .init()), "نصف وجه")
        p.amount = 0.75; XCTAssertEqual(QuranPlanCopy.amount(p, digits: .init()), "ثلاثة أرباع وجه")
        p.amount = 1.5; XCTAssertEqual(QuranPlanCopy.amount(p, digits: .init()), "وجه ونصف")
        p.amount = 2.25; XCTAssertEqual(QuranPlanCopy.amount(p, digits: .init()), "وجهان وربع")
    }
    func testForecastIsOnlyVisibleForItsInputAndMadarDay() throws {
        let original = QuranUIPlanInput(startAyah: 1, unit: .page, amount: 1, rhythm: .balanced, restDay: "friday", missPolicy: "ask")
        let day = try GregorianDay("2026-10-15")
        let forecast = QuranUIForecast(title: "موعد قديم", assumptions: "", warning: nil, portions: [])
        let state = QuranUIForecastState(input: original, day: day, forecast: forecast)
        XCTAssertEqual(state.visible(for: original, on: day)?.title, "موعد قديم")

        var changed = original
        changed.amount = 2
        XCTAssertNil(state.visible(for: changed, on: day), "A prior estimate must disappear while the changed plan is recalculated.")
        XCTAssertNil(state.visible(for: original, on: day.adding(days: 1)), "A prior estimate must disappear when Madar starts a new day.")
    }
    func testPlanForecastRecalculatesAfterMadarDayStarts() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "QuranForecastDay-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let context = ModelContext(container)
        var now = ISO8601DateFormatter().date(from: "2026-10-15T23:59:00+03:00")!
        _ = try SettingsStore(context: context).stage(["core.dayStart": .string("midnight"), "core.firstCalendar": .string("gregorian"), "quran.restDay": .string("none"), "quran.hifzLevel": .string("medium")], now: now)
        let plan = HifzPlan(); plan.startAyah = 1; plan.unit = "page"; plan.amount = 1; plan.rhythm = "balanced"; plan.missPolicy = "ask"; plan.activeFrom = now
        context.insert(plan)
        try context.save()
        let app = try AppSession(container: container, groupDirectory: root)
        let service = AppQuranService(session: app, clock: { now })
        let input = QuranUIPlanInput(startAyah: 1, unit: .page, amount: 1, rhythm: .balanced, restDay: "none", missPolicy: "ask")
        let firstDay = try GregorianDay("2026-10-15"), firstFinish = try GregorianDay("2028-06-09")
        let nextDay = try GregorianDay("2026-10-16"), nextFinish = try GregorianDay("2028-06-10")

        let first = try await service.previewPlan(input, at: now)
        XCTAssertEqual(service.forecastDay(at: now), firstDay)
        let firstBackgroundDay = try await service.forecastDayOffMain(at: now)
        XCTAssertEqual(firstBackgroundDay, firstDay)
        XCTAssertEqual(first.title, app.dateLabels(firstFinish).primary)
        XCTAssertEqual(first.secondaryDate, app.dateLabels(firstFinish).secondary)
        XCTAssertEqual(first.estimatedDays, 604)
        let firstOverview = try await service.planOverview(at: now)
        XCTAssertEqual(firstOverview.day, firstDay)
        XCTAssertEqual(firstOverview.forecasts["medium"]?.title, first.title)

        now = ISO8601DateFormatter().date(from: "2026-10-16T00:01:00+03:00")!
        let next = try await service.previewPlan(input, at: now)
        XCTAssertEqual(service.forecastDay(at: now), nextDay)
        let nextBackgroundDay = try await service.forecastDayOffMain(at: now)
        XCTAssertEqual(nextBackgroundDay, nextDay)
        XCTAssertEqual(next.title, app.dateLabels(nextFinish).primary)
        XCTAssertEqual(next.secondaryDate, app.dateLabels(nextFinish).secondary)
        XCTAssertEqual(next.estimatedDays, 604)
        let nextOverview = try await service.planOverview(at: now)
        XCTAssertEqual(nextOverview.day, nextDay)
        XCTAssertEqual(nextOverview.forecasts["medium"]?.title, next.title)
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
        let expected=app.dateLabels(try GregorianDay("2028-06-09"), first: .hijri).primary
        let partial = try await service.previewPlan(input); XCTAssertEqual(partial.title,expected); XCTAssertEqual(partial.secondaryDate,"٩ يونيو ٢٠٢٨ م")
        row.toAyah=7;try context.save() // Whole first face: 603 remain, starting tomorrow gives the same date.
        let complete = try await service.previewPlan(input); XCTAssertEqual(complete.title,expected)
        let overview=try await service.planOverview()
        XCTAssertEqual(overview.forecasts.count,4)
        XCTAssertNotEqual(overview.forecasts["simple"]?.title,overview.forecasts["deep"]?.title)
    }
}
