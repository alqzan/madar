import XCTest
import MadarCore
@testable import Madar

final class MadarAIMoneySnapshotTests: XCTestCase {
    private let categoryID = "category.food"
    private let merchantID = "merchant.مقهى النخلة"
    private var pairID: String { categoryID + "|" + merchantID }

    private func snapshot(totalMinor: Int = 3_000, previousTotalMinor: Int? = 2_000) -> MadarAIMoneySnapshot {
        let category = MadarAIMoneyMetric(id: categoryID, name: "المطاعم", amountMinor: 2_500, kind: .category)
        let merchant = MadarAIMoneyMetric(id: merchantID, name: "مقهى النخلة", amountMinor: 1_700, kind: .merchant)
        let previousCategory = MadarAIMoneyMetric(id: categoryID, name: "المطاعم", amountMinor: 1_500, kind: .category)
        let previousMerchant = MadarAIMoneyMetric(id: merchantID, name: "مقهى النخلة", amountMinor: 900, kind: .merchant)
        let pair = MadarAIMoneyCategoryMerchant(id: pairID, categoryID: categoryID, categoryName: "المطاعم",
                                                merchantID: merchantID, merchantName: "مقهى النخلة", amountMinor: 1_300)
        let previousPair = MadarAIMoneyCategoryMerchant(id: pairID, categoryID: categoryID, categoryName: "المطاعم",
                                                        merchantID: merchantID, merchantName: "مقهى النخلة", amountMinor: 700)
        return MadarAIMoneySnapshot(
            firstDayKey: "2026-10-01", lastDayKey: "2026-10-31", rangeTitle: "الشهر الحالي",
            confirmedCount: 4, pendingCount: 0, totalMinor: totalMinor,
            categories: [category], merchants: [merchant], previousTotalMinor: previousTotalMinor,
            previousCategories: [previousCategory], previousMerchants: [previousMerchant],
            categoryMerchants: [pair], previousCategoryMerchants: [previousPair]
        )
    }

    private func overlappingMerchantAndCategorySnapshot() -> MadarAIMoneySnapshot {
        let category = MadarAIMoneyMetric(id: "category.food", name: "المطاعم", amountMinor: 2_500, kind: .category)
        let merchant = MadarAIMoneyMetric(id: "merchant.مطاعم الشام", name: "مطاعم الشام", amountMinor: 1_900, kind: .merchant)
        let pair = MadarAIMoneyCategoryMerchant(id: category.id + "|" + merchant.id, categoryID: category.id,
                                                categoryName: category.name, merchantID: merchant.id,
                                                merchantName: merchant.name, amountMinor: 1_200)
        return MadarAIMoneySnapshot(
            firstDayKey: "2026-10-01", lastDayKey: "2026-10-31", rangeTitle: "الشهر الحالي",
            confirmedCount: 4, pendingCount: 0, totalMinor: 3_000,
            categories: [category], merchants: [merchant], previousTotalMinor: nil,
            previousCategories: nil, previousMerchants: nil, categoryMerchants: [pair], previousCategoryMerchants: nil
        )
    }

    private func multiwordCategorySnapshot() -> MadarAIMoneySnapshot {
        let category = MadarAIMoneyMetric(id: "category.healthy-food", name: "الطعام الصحي", amountMinor: 2_500, kind: .category)
        let merchant = MadarAIMoneyMetric(id: "merchant.متجر الحي", name: "متجر الحي", amountMinor: 1_900, kind: .merchant)
        let pair = MadarAIMoneyCategoryMerchant(id: category.id + "|" + merchant.id, categoryID: category.id,
                                                categoryName: category.name, merchantID: merchant.id,
                                                merchantName: merchant.name, amountMinor: 1_200)
        return MadarAIMoneySnapshot(
            firstDayKey: "2026-10-01", lastDayKey: "2026-10-31", rangeTitle: "الشهر الحالي",
            confirmedCount: 4, pendingCount: 0, totalMinor: 3_000,
            categories: [category], merchants: [merchant], previousTotalMinor: nil,
            previousCategories: nil, previousMerchants: nil, categoryMerchants: [pair], previousCategoryMerchants: nil
        )
    }

    func testHighestMerchantUsesMerchantTotalInsteadOfHighestCategory() {
        let facts = snapshot().answerFacts(for: "كم صرفت عند أكثر جهة؟")

        XCTAssertEqual(facts.map(\.amountMinor), [1_700])
        XCTAssertTrue(facts.first?.title.contains("مقهى النخلة") == true)
        XCTAssertFalse(facts.first?.title.contains("تصنيف") == true)
    }

    func testHighestMerchantWithinCategoryUsesTheCategoryMerchantAmount() {
        let facts = snapshot().answerFacts(for: "كم صرفت عند أكثر جهة في المطاعم؟")

        XCTAssertEqual(facts.map(\.amountMinor), [1_300])
        XCTAssertTrue(facts.first?.title.contains("المطاعم") == true)
        XCTAssertTrue(facts.first?.title.contains("مقهى النخلة") == true)
    }

    func testNamedMerchantAndCategoryComparisonKeepsTheSamePair() {
        let facts = snapshot().answerFacts(for: "كم تغير صافي مقهى النخلة في تصنيف المطاعم عن الفترة السابقة؟")

        XCTAssertEqual(facts.map(\.amountMinor), [1_300, 700, 600])
        XCTAssertTrue(facts.last?.title.contains("زاد") == true)
        XCTAssertTrue(facts.allSatisfy { $0.title.contains("المطاعم") && $0.title.contains("مقهى النخلة") })
    }

    func testNarrativeComparisonShowsDeterministicDirectionAndDifference() {
        let current = snapshot()
        let facts = current.answerFacts(for: "كيف تغيّر إنفاقي عن الفترة السابقة؟")

        XCTAssertEqual(facts.map(\.amountMinor), [3_000, 2_000, 1_000])
        XCTAssertTrue(facts.last?.title.contains("زاد صافي المصروف") == true)
        XCTAssertFalse(current.questionNeedsFigure("كيف تغيّر إنفاقي؟"))
        XCTAssertTrue(current.questionNeedsFigure("كم تغيّر إنفاقي؟"))
        XCTAssertTrue(current.modelContextArabic.contains("صافي تصنيف المطاعم أعلى من الفترة المقارنة"))
    }

    func testNarrativeComparisonHandlesDecreaseAndNoChange() {
        let decreased = snapshot(totalMinor: 1_500, previousTotalMinor: 2_500)
            .answerFacts(for: "كيف تغيّر الإنفاق عن الفترة السابقة؟")
        let unchanged = snapshot(totalMinor: 2_000, previousTotalMinor: 2_000)
            .answerFacts(for: "كيف تغيّر الإنفاق عن الفترة السابقة؟")

        XCTAssertEqual(decreased.last?.amountMinor, 1_000)
        XCTAssertTrue(decreased.last?.title.contains("انخفض") == true)
        XCTAssertEqual(unchanged.last?.amountMinor, 0)
        XCTAssertTrue(unchanged.last?.title.contains("لم يتغيّر") == true)
    }

    func testMerchantNameContainingCategoryUsesAllMerchantCategoriesUnlessScoped() {
        let snapshot = overlappingMerchantAndCategorySnapshot()

        let merchantFacts = snapshot.answerFacts(for: "كم صافي مطاعم الشام؟")
        XCTAssertEqual(merchantFacts.map(\.amountMinor), [1_900])
        XCTAssertEqual(merchantFacts.first?.title, "صافي المصروف لدى مطاعم الشام")

        let scopedFacts = snapshot.answerFacts(for: "كم صافي مطاعم الشام في تصنيف المطاعم؟")
        XCTAssertEqual(scopedFacts.map(\.amountMinor), [1_200])
        XCTAssertTrue(scopedFacts.first?.title.contains("في تصنيف المطاعم") == true)
    }

    func testTopMerchantAcceptsDistinctivePartOfMultiwordCategory() {
        let facts = multiwordCategorySnapshot().answerFacts(for: "كم صرفت عند أكثر جهة في الطعام؟")

        XCTAssertEqual(facts.map(\.amountMinor), [1_200])
        XCTAssertTrue(facts.first?.title.contains("متجر الحي") == true)
        XCTAssertTrue(facts.first?.title.contains("الطعام الصحي") == true)
    }

    func testUnknownMerchantWithinCategoryNeverFallsBackToCategoryTotal() {
        let facts = snapshot().answerFacts(for: "كم صرفت عند متجر غير موجود في المطاعم؟")

        XCTAssertTrue(facts.isEmpty)
    }
}

final class MadarAIDiarySourceTests: XCTestCase {
    func testShortDiaryScopeKeepsFullTextForSpecificQuestions() throws {
        let note = MadarAIDiaryRecord(id: "memo.one", dayKey: "2026-11-02", kind: "مذكرة", text: "قابلت نورة في المكتبة واشتريت كتابًا عن التاريخ.")
        let request = try MadarAIAnalysisRequest.diary(
            records: [note], scopeTitle: "مذكرة واحدة", rangeSummary: "اليوم",
            digits: MadarNumberFormatter(style: .hindi)
        )

        XCTAssertFalse(request.diaryUsesThematicSummary)
        XCTAssertTrue(request.sourceSegments.joined().contains("نورة"))
    }

    func testLongDiaryScopeIsMarkedAsThematicSummary() throws {
        let longText = String(repeating: "تفصيل مهم ", count: 500)
        let note = MadarAIDiaryRecord(id: "memo.long", dayKey: "2026-11-02", kind: "مذكرة", text: longText)
        let request = try MadarAIAnalysisRequest.diary(
            records: [note], scopeTitle: "مذكرة واحدة", rangeSummary: "اليوم",
            digits: MadarNumberFormatter(style: .hindi)
        )

        XCTAssertTrue(request.diaryUsesThematicSummary)
        XCTAssertGreaterThan(request.sourceSegments.count, 1)
    }
}
