import Foundation
import Testing
@testable import MadarCore

@Suite struct MihbaraReadingTests {
    @Test func threeReadingSlotsRequireAnExplicitReplacement() {
        let ids = (0..<4).map { _ in UUID() }, reading = Set([UUID(),UUID(),UUID()])
        #expect(!MihbaraReading.canRead(id: ids[0], reading: reading, replacing: nil))
        #expect(!MihbaraReading.canRead(id: ids[0], reading: reading, replacing: ids[1]))
        #expect(MihbaraReading.canRead(id: ids[0], reading: reading, replacing: reading.first))
        #expect(MihbaraReading.canRead(id: reading.first!, reading: reading, replacing: nil))
        #expect(MihbaraReading.canRead(id: ids[0], reading: Set(reading.prefix(2)), replacing: nil))
    }
    @Test func hadithIdentitiesSurviveReorderingAndTodaysCompletedWirdDoesNotAdvanceAgain() {
        let numbers = Array((1...42).reversed())
        #expect(MihbaraReading.nextHadith(numbers: numbers, read: Set(1...12), readToday: [], count: 1) == [13])
        #expect(MihbaraReading.nextHadith(numbers: numbers, read: Set(1...13), readToday: [13], count: 1).isEmpty)
        #expect(MihbaraReading.nextHadith(numbers: numbers, read: Set(1...13), readToday: [13], count: 3) == [14,15])
        #expect(MihbaraReading.nextHadith(numbers: numbers, read: Set(1...42), readToday: [], count: 1).isEmpty)
    }
    @Test func aPaperPositionIsAnHonestRatioAndUnknownLengthStaysUnknown() {
        #expect(MihbaraReading.progress(page: 147, pages: 250) == 0.588)
        #expect(MihbaraReading.progress(page: 147, pages: nil) == nil)
        #expect(MihbaraReading.progress(page: nil, pages: 250) == nil)
        #expect(MihbaraReading.progress(page: 300, pages: 250) == 1)
    }
}
