import Foundation
import Testing
@testable import MadarCore

@Suite struct DiaryQuestionBankTests {
    @Test func bankHasFortyQuestionsWithoutBlameOrTranslationMarks() {
        let all = DiaryQuestionGroup.allCases.flatMap { DiaryQuestionBank.questions($0) }
        #expect(all.count == 40)
        #expect(Set(all.map(\.arabic)).count == 40)
        for q in all {
            #expect(!q.arabic.contains("لماذا"))
            #expect(q.arabic.hasSuffix("؟"))
            #expect(!q.topic.isEmpty)
            #expect(q.arabic.range(of: "[A-Za-z]", options: .regularExpression) == nil)
        }
    }

    @Test func modelChoicesComeFirstInItsOrderAndAreValidated() {
        let picked = DiaryQuestionBank.selection(group: .aboutDiary, modelIndices: [7, 2, 11], seed: 5)
        #expect(picked == [7, 2, 11])
    }

    @Test func invalidDuplicateOrShortModelAnswersAreFilledWithDistinctValidIndices() {
        for bad in [[99, 99, -1], [4, 4, 4], [3], []] as [[Int]] {
            let picked = DiaryQuestionBank.selection(group: .reflective, modelIndices: bad, seed: 9)
            #expect(picked.count == 3)
            #expect(Set(picked).count == 3)
            #expect(picked.allSatisfy { (0..<20).contains($0) })
        }
        #expect(DiaryQuestionBank.selection(group: .reflective, modelIndices: [4, 4, 4], seed: 9).first == 4)
    }

    @Test func withoutTheModelTheRotationIsDeterministicAndMovesWithTheDay() {
        let a = DiaryQuestionBank.selection(group: .aboutDiary, modelIndices: nil, seed: 100)
        #expect(a == DiaryQuestionBank.selection(group: .aboutDiary, modelIndices: nil, seed: 100))
        #expect(a != DiaryQuestionBank.selection(group: .aboutDiary, modelIndices: nil, seed: 101))
        #expect(Set(a).count == 3)
        #expect(DiaryQuestionBank.selection(group: .aboutDiary, modelIndices: nil, seed: -7).count == 3)
    }
}
