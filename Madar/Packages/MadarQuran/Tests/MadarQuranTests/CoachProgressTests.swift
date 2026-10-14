import XCTest
@testable import MadarQuran

final class CoachProgressTests: XCTestCase {
    func testRepetitionsFollowThreeFiveSevenAndDoNotSkipAnAyah() {
        for (intensity, target) in [(QuranReviewIntensity.light, 3), (.balanced, 5), (.intense, 7)] {
            XCTAssertEqual(QuranCoachProgress.repetitionTarget(intensity), target)
            var progress = QuranCoachProgress(), stage = HifzCoachStage.repetition, ayah = 1
            for _ in 0..<(target - 1) { progress.advanceLearning(stage: &stage, ayahID: &ayah, pageAyahs: [1, 2], intensity: intensity, method: .coach) }
            XCTAssertEqual(stage, .repetition); XCTAssertEqual(ayah, 1)
            progress.advanceLearning(stage: &stage, ayahID: &ayah, pageAyahs: [1, 2], intensity: intensity, method: .coach)
            XCTAssertEqual(stage, .lineStarts)
            progress.advanceLearning(stage: &stage, ayahID: &ayah, pageAyahs: [1, 2], intensity: intensity, method: .coach)
            XCTAssertEqual(stage, .promptedRecall)
            progress.advanceLearning(stage: &stage, ayahID: &ayah, pageAyahs: [1, 2], intensity: intensity, method: .coach)
            XCTAssertEqual(stage, .repetition); XCTAssertEqual(ayah, 2); XCTAssertEqual(progress.repetitions, 0)
        }
    }
    func testFatihaHasSevenAyahsAndFortyNineBalancedLearningActionsBeforeBlindRecitation() {
        var progress = QuranCoachProgress(), stage = HifzCoachStage.repetition, ayah = 1
        for _ in 0..<48 { progress.advanceLearning(stage: &stage, ayahID: &ayah, pageAyahs: Array(1...7), intensity: .balanced, method: .coach) }
        XCTAssertEqual(stage, .promptedRecall); XCTAssertEqual(ayah, 7)
        progress.advanceLearning(stage: &stage, ayahID: &ayah, pageAyahs: Array(1...7), intensity: .balanced, method: .coach)
        XCTAssertEqual(stage, .blindRecitation); XCTAssertEqual(ayah, 1)
    }
    func testAlternativeMethodsStillRequireTheBlindStage() {
        for method in [QuranLearningMethod.completeAyah, .next, .gradual, .link] {
            var progress = QuranCoachProgress(), stage = HifzCoachStage.repetition, ayah = 149
            for _ in 0..<(method == .gradual ? 4 : 1) { progress.advanceLearning(stage: &stage, ayahID: &ayah, pageAyahs: [149], intensity: .balanced, method: method) }
            XCTAssertEqual(stage, .blindRecitation)
        }
    }
    func testCounterAndBridgeSurviveCodableRoundTrip() throws {
        var value = QuranCoachProgress(bridgeAyahs: [2054, 2055, 2056]); value.repetitions = 2
        XCTAssertEqual(try JSONDecoder().decode(QuranCoachProgress.self, from: JSONEncoder().encode(value)), value)
    }
    func testGradualMaskHasExactNestedQuartersAndHandlesShortAyahs() {
        XCTAssertEqual(QuranCoachProgress.hiddenWordIndices(ayahID: 1, wordCount: 4, step: 0), [2])
        XCTAssertEqual(QuranCoachProgress.hiddenWordIndices(ayahID: 1, wordCount: 4, step: 1), [2, 0])
        XCTAssertEqual(QuranCoachProgress.hiddenWordIndices(ayahID: 1, wordCount: 4, step: 2), [2, 0, 3])
        XCTAssertEqual(QuranCoachProgress.hiddenWordIndices(ayahID: 1, wordCount: 4, step: 3), [0, 1, 2, 3])
        XCTAssertEqual(QuranCoachProgress.hiddenWordIndices(ayahID: 1, wordCount: 1, step: 0), [0])
    }
}
