import Foundation
import Testing
@testable import MadarCore

/// A ZIP64 header whose sizes do not fit in `Int` must be refused, never crash the importer.
@Suite struct ZIPReaderBoundsTests {
    private func le(_ value: UInt64, bytes: Int) -> [UInt8] { (0..<bytes).map { UInt8((value >> (8 * UInt64($0))) & 0xFF) } }

    @Test func zip64RecordWithOverflowingOffsetIsRejected() {
        var data = [UInt8](repeating: 0, count: 200)
        // ZIP64 end-of-central-directory record at 0, locator at 56, classic EOCD at 76 (22 bytes).
        data.replaceSubrange(0..<4, with: le(0x06064b50, bytes: 4))
        data.replaceSubrange(32..<40, with: le(1, bytes: 8))
        data.replaceSubrange(40..<48, with: le(UInt64.max, bytes: 8)) // central size: does not fit in Int
        data.replaceSubrange(48..<56, with: le(UInt64.max - 3, bytes: 8))
        data.replaceSubrange(56..<60, with: le(0x07064b50, bytes: 4))
        data.replaceSubrange(64..<72, with: le(0, bytes: 8))
        data.replaceSubrange(76..<80, with: le(0x06054b50, bytes: 4))
        data.replaceSubrange(86..<90, with: le(0xFFFF_FFFF, bytes: 4))
        data.replaceSubrange(90..<94, with: le(0xFFFF_FFFF, bytes: 4))
        data.removeLast(200 - 98)
        #expect(throws: ZIPReaderError.self) { _ = try ZIPReader(data: Data(data)) }
    }
}

@Suite struct HabitRampReachTests {
    @Test func capWithinStepsAndHorizonIsReachable() {
        #expect(HabitSchedule.reachableCap(start: 10, step: 1, everyDays: 7, cap: 20) == 20)
    }
    @Test func capBeyondOneHundredStepsIsCut() {
        #expect(HabitSchedule.reachableCap(start: 1, step: 1, everyDays: 1, cap: 500) == 101)
    }
    @Test func capBeyondTheHorizonIsCut() {
        // 3660 / 364 = 10 steps of 1 from 5.
        #expect(HabitSchedule.reachableCap(start: 5, step: 1, everyDays: 364, cap: 50) == 15)
    }
}
