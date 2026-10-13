import Foundation
import MadarCore
import MadarQuran
import XCTest

@MainActor
final class FixedCycleReviewTests: XCTestCase {
    private func day(_ value: String) throws -> GregorianDay { try GregorianDay(value) }

    // Synthetic contiguous ranges exercise cycle selection only. M2-R01 supplies the licensed Quran boundaries.
    private func syntheticSegments(count: Int) -> [QuranCycleSegment] {
        (1...count).map { number in
            let first = ((number - 1) * 6_236) / count + 1
            let last = (number * 6_236) / count
            return QuranCycleSegment(number: number, ayahs: try! QuranAyahRange(first: first, last: last))
        }
    }

    func testDailyJuzCycleUsesInjectedBoundariesAndRepeatsAfterThirtyDays() throws {
        let start = try day("2026-01-01")
        let juz = syntheticSegments(count: 30)
        let manzils = syntheticSegments(count: 7)

        let first = QuranFixedCycleEngine.target(
            mode: .fixedJuzDaily,
            cycleStartDayKey: start,
            todayDayKey: start,
            juzSegments: juz,
            manzilSegments: manzils
        )
        XCTAssertEqual(first?.unit, .juz)
        XCTAssertEqual(first?.segmentNumber, 1)
        XCTAssertEqual(first?.ayahs, juz[0].ayahs)

        let thirtieth = QuranFixedCycleEngine.target(
            mode: .fixedJuzDaily,
            cycleStartDayKey: start,
            todayDayKey: start.adding(days: 29),
            juzSegments: juz,
            manzilSegments: manzils
        )
        XCTAssertEqual(thirtieth?.segmentNumber, 30)
        XCTAssertEqual(thirtieth?.ayahs, juz[29].ayahs)

        let nextCycle = QuranFixedCycleEngine.target(
            mode: .fixedJuzDaily,
            cycleStartDayKey: start,
            todayDayKey: start.adding(days: 30),
            juzSegments: juz,
            manzilSegments: manzils
        )
        XCTAssertEqual(nextCycle?.segmentNumber, 1)
    }

    func testSevenManzilCycleRepeatsWeekly() throws {
        let start = try day("2026-02-01")
        let juz = syntheticSegments(count: 30)
        let manzils = syntheticSegments(count: 7)

        let seventh = QuranFixedCycleEngine.target(
            mode: .fixedManzilWeekly,
            cycleStartDayKey: start,
            todayDayKey: start.adding(days: 6),
            juzSegments: juz,
            manzilSegments: manzils
        )
        XCTAssertEqual(seventh?.unit, .manzil)
        XCTAssertEqual(seventh?.segmentNumber, 7)
        XCTAssertEqual(seventh?.ayahs, manzils[6].ayahs)

        let nextWeek = QuranFixedCycleEngine.target(
            mode: .fixedManzilWeekly,
            cycleStartDayKey: start,
            todayDayKey: start.adding(days: 7),
            juzSegments: juz,
            manzilSegments: manzils
        )
        XCTAssertEqual(nextWeek?.segmentNumber, 1)
    }

    func testSpacedModeAndDaysBeforeCycleHaveNoFixedTarget() throws {
        let start = try day("2026-03-10")
        let juz = syntheticSegments(count: 30)
        let manzils = syntheticSegments(count: 7)

        XCTAssertNil(QuranFixedCycleEngine.target(
            mode: .spaced,
            cycleStartDayKey: start,
            todayDayKey: start,
            juzSegments: juz,
            manzilSegments: manzils
        ))
        XCTAssertNil(QuranFixedCycleEngine.target(
            mode: .fixedJuzDaily,
            cycleStartDayKey: start,
            todayDayKey: start.adding(days: -1),
            juzSegments: juz,
            manzilSegments: manzils
        ))
    }

    func testIncompleteOrDiscontinuousMapsCannotProduceTargets() throws {
        let start = try day("2026-04-01")
        let juz = syntheticSegments(count: 30)
        let manzils = syntheticSegments(count: 7)

        XCTAssertNil(QuranFixedCycleEngine.target(
            mode: .fixedJuzDaily,
            cycleStartDayKey: start,
            todayDayKey: start,
            juzSegments: Array(juz.dropLast()),
            manzilSegments: manzils
        ))

        let brokenManzils = Array(manzils.dropFirst()) + [
            QuranCycleSegment(number: 1, ayahs: try QuranAyahRange(first: 2, last: 892))
        ]
        XCTAssertNil(QuranFixedCycleEngine.target(
            mode: .fixedManzilWeekly,
            cycleStartDayKey: start,
            todayDayKey: start,
            juzSegments: juz,
            manzilSegments: brokenManzils
        ))
    }

    func testAyahRangesRejectInvalidValuesWhenCreatedOrDecoded() throws {
        XCTAssertThrowsError(try QuranAyahRange(first: 0, last: 1)) { error in
            XCTAssertEqual(error as? QuranReviewError, .invalidAyahRange)
        }

        let invalid = Data(#"{"first":1,"last":7000}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(QuranAyahRange.self, from: invalid))
    }
}
