import XCTest
import MadarCore
@testable import Madar

/// Owner, 30 Oct: «تقرأ غالبًا …» names the stretch between two prayers that holds most reading time,
/// only from three sessions up and only when that stretch holds at least 40٪ of the time.
@MainActor final class MihbaraReadingGoalTests: XCTestCase {
    func testUsualStretchFollowsPrayers() throws {
        let day = try GregorianDay("2026-10-15")
        let p = try XCTUnwrap(PrayerTimesEngine.calculate(day: day, place: .riyadh))
        let prayers: (Date) -> PrayerDay? = { _ in p }
        let afterIsha = p.isha.addingTimeInterval(1800), afterAsr = p.asr.addingTimeInterval(600), beforeFajr = p.fajr.addingTimeInterval(-1200)
        XCTAssertEqual(MihbaraReadingGoal.usualStretch([(afterIsha, 900), (beforeFajr, 600), (afterAsr, 600)], prayers: prayers), "بعد العشاء")
        XCTAssertEqual(MihbaraReadingGoal.usualStretch([(afterAsr, 1200), (afterIsha, 300), (p.sunrise.addingTimeInterval(3600), 300)], prayers: prayers), "بعد العصر")
        // Two sessions are not «غالبًا».
        XCTAssertNil(MihbaraReadingGoal.usualStretch([(afterIsha, 900), (afterIsha, 900)], prayers: prayers))
        // Four stretches at 25٪ each: none holds 40٪.
        let spread = [(p.fajr.addingTimeInterval(600), 600), (p.dhuhr.addingTimeInterval(600), 600), (afterAsr, 600), (p.maghrib.addingTimeInterval(600), 600)]
        XCTAssertNil(MihbaraReadingGoal.usualStretch(spread.map { (start: $0.0, seconds: $0.1) }, prayers: prayers))
    }
}
