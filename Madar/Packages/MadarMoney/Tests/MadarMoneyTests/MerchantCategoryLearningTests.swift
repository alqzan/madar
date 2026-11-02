import Foundation
import Testing
@testable import MadarMoney

struct MerchantCategoryLearningTests {
    private let cafe = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let child = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!

    private func sample(_ id: Int, merchant: String = "مقهى النخيل", category: UUID?, source: String? = "manual",
                        kind: String = "expense", state: String = "ok", deleted: Bool = false,
                        merged: Bool = false) -> MerchantCategoryLearning.Sample {
        .init(transactionID: UUID(uuidString: String(format: "20000000-0000-0000-0000-%012d", id))!,
              merchant: merchant, categoryID: category, categorySource: source, kind: kind,
              reviewState: state, isDeleted: deleted, isMerged: merged)
    }

    @Test func oneCategoryIsSuggestedOnlyAfterTheConfiguredConfirmedChoices() {
        let rows = [sample(1, category: cafe), sample(2, merchant: "  مقهى النخيل ", category: cafe)]
        let below = MerchantCategoryLearning.evaluate(merchant: "مقهى النخيل", samples: rows.prefix(1).map { $0 }, threshold: 2,
                                                       liveCategoryIDs: [cafe, child])
        #expect(below.suggestedCategoryID == nil)

        let reached = MerchantCategoryLearning.evaluate(merchant: "مقهى النخيل", samples: rows, threshold: 2,
                                                         liveCategoryIDs: [cafe, child])
        #expect(reached.suggestedCategoryID == cafe)
        #expect(reached.counts == [.init(categoryID: cafe, count: 2)])
    }

    @Test func differentPurchaseCategoriesRemainValidAndTwoMatureChoicesStayUnresolved() {
        let rows = [sample(1, category: cafe), sample(2, category: cafe),
                    sample(3, category: child), sample(4, category: child)]
        let result = MerchantCategoryLearning.evaluate(merchant: "مقهى النخيل", samples: rows, threshold: 2,
                                                        liveCategoryIDs: [cafe, child])
        #expect(result.suggestedCategoryID == nil)
        #expect(result.hasMultipleQualifiedCategories)
        #expect(result.counts.map(\.count) == [2, 2])
    }

    @Test func learnedRuleImportedPendingRefundDeletedAndMergedRowsNeverTeach() {
        let rows = [
            sample(1, category: cafe, source: "learned"),
            sample(2, category: cafe, source: "rule"),
            sample(3, category: cafe, state: "needsLook"),
            sample(4, category: cafe, kind: "refund"),
            sample(5, category: cafe, deleted: true),
            sample(6, category: cafe, merged: true),
            sample(7, category: nil),
            sample(8, merchant: "متجر آخر", category: cafe),
            sample(9, category: cafe, source: nil)
        ]
        let result = MerchantCategoryLearning.evaluate(merchant: "مقهى النخيل", samples: rows, threshold: 1,
                                                        liveCategoryIDs: [cafe, child])
        #expect(result.counts.isEmpty)
        #expect(result.suggestedCategoryID == nil)
    }

    @Test func removedCategoryAndLegacyMigrationChoiceNeverBecomeSuggestions() {
        let removedCategory = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
        let rows = [sample(1, category: cafe), sample(2, category: cafe),
                    sample(3, category: removedCategory), sample(4, category: removedCategory, source: "rule")]
        let index = MerchantCategoryLearning.makeIndex(samples: rows, liveCategoryIDs: [cafe, child])
        let result = index.result(for: "مقهى النخيل", threshold: 2)
        #expect(result.counts == [.init(categoryID: cafe, count: 2)])
        #expect(result.suggestedCategoryID == cafe)
    }

    @Test func precomputedIndexAnswersTypedMerchantWithoutRecentChipMembership() {
        let row = sample(20, merchant: "متجر خارج الشرائح", category: child)
        let index = MerchantCategoryLearning.makeIndex(samples: [row], liveCategoryIDs: [cafe, child])
        #expect(index.result(for: "  متجر خارج الشرائح  ", threshold: 1).suggestedCategoryID == child)
    }

    @Test func thresholdZeroTurnsLearningOffAndDuplicateRecordCannotReachThreshold() {
        let duplicate = sample(10, category: cafe)
        let disabled = MerchantCategoryLearning.evaluate(merchant: "مقهى النخيل", samples: [duplicate], threshold: 0,
                                                          liveCategoryIDs: [cafe, child])
        #expect(disabled.suggestedCategoryID == nil)

        let repeated = MerchantCategoryLearning.evaluate(merchant: "مقهى النخيل", samples: [duplicate, duplicate], threshold: 2,
                                                          liveCategoryIDs: [cafe, child])
        #expect(repeated.counts == [.init(categoryID: cafe, count: 1)])
        #expect(repeated.suggestedCategoryID == nil)
    }
}
