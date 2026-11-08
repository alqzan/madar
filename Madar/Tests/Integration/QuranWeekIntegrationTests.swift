import XCTest
import SwiftData
import MadarData
import MadarCore
import MadarCommands
@testable import Madar

@MainActor final class QuranWeekIntegrationTests: XCTestCase {
    func testRollingWeekRestDayDedupedReviewsAndWidgetHaveOneDefinition() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarWeek-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let context = ModelContext(container), settings = try SettingsStore(context: context)
        _ = try settings.stage(["core.dayStart": .string("midnight"), "core.firstCalendar": .string("gregorian"), "quran.restDay": .string("friday")])
        let now = ISO8601DateFormatter().date(from: "2026-10-15T15:00:00+03:00")!, catalog = try QuranResources.catalog()
        func append(_ kind: String, page: Int, day: String, graded: Bool = true) {
            let row = HifzSession(); row.kind = kind; row.pages = [page]; row.dayKey = day
            row.fromAyah = catalog.ayahs(on: page).first!.id; row.toAyah = catalog.ayahs(on: page).last!.id
            row.endedAt = try! GregorianDay(day).date(in: TimeZone(identifier: "Asia/Riyadh")!).addingTimeInterval(12 * 3600); context.insert(row)
            if graded { let grade = PageGrade(); grade.sessionID = row.id; grade.page = page; grade.grade = "mastered"; context.insert(grade) }
        }
        append("hifz", page: 1, day: "2026-10-09") // Friday, actual work counted as coverage, outside the eligible denominator.
        append("hifz", page: 2, day: "2026-10-10")
        append("review", page: 1, day: "2026-10-14")
        append("free", page: 1, day: "2026-10-14") // Same face twice on one day counts once.
        append("drill", page: 1, day: "2026-10-15", graded: false) // Never a study day.
        try context.save()
        let app = try AppSession(container: container, groupDirectory: root), service = AppQuranService(session: app, clock: { now })
        let week = try service.weeklyLog(), widget = try service.widgetSnapshot().payload
        XCTAssertEqual(week.days.map(\.id), (9...15).map { "2026-10-\(String(format: "%02d", $0))" })
        XCTAssertEqual(week.hifz, 2); XCTAssertEqual(week.review, 1)
        XCTAssertEqual(week.eligibleDays, 6); XCTAssertEqual(week.activeDays, 2); XCTAssertEqual(week.closedDays, 0)
        XCTAssertTrue(week.days[0].rest); XCTAssertFalse(week.days[0].eligible)
        XCTAssertEqual(week.days[5].review, 1)
        XCTAssertTrue(week.days.last?.date.contains("١٥ أكتوبر") == true, week.days.last?.date ?? "")
        XCTAssertTrue(week.days.last?.date.contains("هـ") == true, week.days.last?.date ?? "")
        let sessionLog = try service.sessionLog()
        let sessionLogOffMain = try await service.sessionLogOffMain(at: now)
        XCTAssertEqual(sessionLogOffMain.records.map(\.day), sessionLog.records.map(\.day))
        XCTAssertTrue(sessionLog.records.allSatisfy { $0.day.contains(" م") && $0.day.contains(" هـ") })
        let projectedWeek = try await service.weeklyLogOffMain(at: now)
        XCTAssertEqual(projectedWeek.days.map(\.id), week.days.map(\.id))
        XCTAssertEqual(projectedWeek.days.map(\.date), week.days.map(\.date))
        XCTAssertEqual(projectedWeek.days.map(\.hifz), week.days.map(\.hifz))
        XCTAssertEqual(projectedWeek.days.map(\.review), week.days.map(\.review))
        XCTAssertEqual(projectedWeek.days.map(\.partialAyahs), week.days.map(\.partialAyahs))
        XCTAssertEqual(projectedWeek.days.map(\.eligible), week.days.map(\.eligible))
        XCTAssertEqual(projectedWeek.days.map(\.active), week.days.map(\.active))
        XCTAssertEqual(projectedWeek.days.map(\.rest), week.days.map(\.rest))
        XCTAssertEqual(projectedWeek.days.map(\.today), week.days.map(\.today))
        XCTAssertEqual(projectedWeek.hifzChange, week.hifzChange)
        XCTAssertEqual(projectedWeek.reviewChange, week.reviewChange)
        XCTAssertEqual(projectedWeek.activeChange, week.activeChange)
        XCTAssertEqual(widget.hifzWeek, QuranDayCloseCopy.faces(week.hifz, digits: service.numerals))
        XCTAssertEqual(widget.reviewWeek, QuranDayCloseCopy.faces(week.review, digits: service.numerals))
        XCTAssertEqual(widget.days.map(\.review), week.days.map { Double($0.review) / 8 })
        let year = try service.yearLog()
        XCTAssertEqual(year.days.count, 371); XCTAssertEqual(year.months.count, 12)
        XCTAssertEqual(year.days.reduce(0) { $0 + $1.hifz }, 2)
        XCTAssertEqual(year.days.reduce(0) { $0 + $1.review }, 1)
        XCTAssertEqual(year.activeDays, 3) // Actual rest-day work is activity; drill is not.
        XCTAssertEqual(year.days.last?.id, "2026-10-15")
        XCTAssertTrue(year.days.last?.date.contains("١٥ أكتوبر") == true, year.days.last?.date ?? "")
        XCTAssertTrue(year.days.last?.date.contains("هـ") == true, year.days.last?.date ?? "")
        XCTAssertTrue(year.title.contains("١٥ أكتوبر"), year.title)
        XCTAssertTrue(year.months.allSatisfy { $0.title.contains(" م") && $0.secondary.contains(" هـ") })
        let projectedYear = try await service.yearLogOffMain(at: now)
        XCTAssertEqual(projectedYear.days.map(\.id), year.days.map(\.id))
        XCTAssertEqual(projectedYear.days.map(\.date), year.days.map(\.date))
        XCTAssertEqual(projectedYear.days.map(\.monthID), year.days.map(\.monthID))
        XCTAssertEqual(projectedYear.days.map(\.hifz), year.days.map(\.hifz))
        XCTAssertEqual(projectedYear.days.map(\.review), year.days.map(\.review))
        XCTAssertEqual(projectedYear.months.map(\.secondary), year.months.map(\.secondary))
        XCTAssertEqual(projectedYear.activeDays, year.activeDays)
        let recentYearDays = try await service.yearDaysOffMain(from: service.snapshot(), count: 28)
        XCTAssertEqual(recentYearDays.map(\.id), Array(year.days.suffix(28)).map(\.id))
        XCTAssertEqual(recentYearDays.map(\.date), Array(year.days.suffix(28)).map(\.date))
        let journey = try await service.journeyLog()
        XCTAssertEqual(journey.remaining, 602)
        XCTAssertEqual(journey.pageDates.count, 2)
        XCTAssertEqual(journey.pages.count, 604)
        XCTAssertNil(journey.forecastDay) // Fewer than five hifz days.
        XCTAssertEqual(journey.shades[1], 1)
        XCTAssertLessThan(journey.shades[2]!, journey.shades[1]!)
        XCTAssertEqual(journey.mapRows.count, 30)
        let mappedPages = journey.mapRows.flatMap(\.pages).map(\.firstPage)
        XCTAssertEqual(mappedPages.count, 604)
        XCTAssertEqual(Set(mappedPages), Set(1...604))
        XCTAssertEqual(journey.stats.first { $0.id == "work" }?.value, service.dayCount(2))
        XCTAssertEqual(journey.stats.first { $0.id == "work" }?.detail, service.numerals.percent(33) + " من أيام الحفظ المتاحة")
        XCTAssertEqual(journey.stats.first { $0.id == "recited" }?.value, service.faceCount(4))
        _ = root // An isolated temporary store, never the owner's data.
    }
}
