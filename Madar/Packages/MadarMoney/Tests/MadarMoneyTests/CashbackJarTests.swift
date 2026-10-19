import Testing
@testable import MadarMoney

/// M5-V16: expected values computed by hand from the definitions in §7.5 (earned is shown in the jar and never
/// changes cash; redeemed is one cashback movement, counted once) and F07 (rate × purchase, half away from zero).
struct CashbackJarTests {
    private let plat = CashbackJar.Card(id: "P", rateBp: 50), travel = CashbackJar.Card(id: "T", rateBp: 150)

    @Test func roundsOnceOnTheMonthBaseNotPerPurchase() throws {
        // Three purchases of 0.33 at 1.5%: 0.495 halala each would round to 0 three times; the month base 0.99 × 1.5%
        // = 1.485 halala → 1.
        let r = try #require(CashbackJar.read(.init(cards: [travel], current: 0, purchases: Array(repeating: .init(cardID: "T", month: 0, amountMinor: 33), count: 3))))
        #expect(r.earnedMinor == 1)
        // 1.00 SAR × 0.5% = 0.5 halala → 1 (half away from zero).
        #expect(CashbackJar.read(.init(cards: [plat], current: 0, purchases: [.init(cardID: "P", month: 0, amountMinor: 100)]))?.earnedMinor == 1)
    }

    @Test func earnedLandedAndAccumulatingAreOneDefinitionEach() throws {
        // Month 0: 2,000 on 0.5% → 10.00; 1,000 on 1.5% → 15.00. Month 1 (current): 400 → 2.00; 200 → 3.00.
        let input = CashbackJar.Input(cards: [plat, travel], current: 1, purchases: [
            .init(cardID: "P", month: 0, amountMinor: 200_000), .init(cardID: "T", month: 0, amountMinor: 100_000),
            .init(cardID: "P", month: 1, amountMinor: 40_000), .init(cardID: "T", month: 1, amountMinor: 20_000)],
            landed: [.init(cardID: "P", amountMinor: 2_500)])
        let r = try #require(CashbackJar.read(input))
        #expect(r.monthTotals == [2_500, 500])
        #expect(r.earnedMinor == 3_000 && r.landedMinor == 2_500 && r.accumulatingMinor == 500 && r.headlineMinor == 3_000)
        #expect(r.cards.map(\.earnedMinor) == [1_200, 1_800])
        #expect(r.cards.map(\.landedMinor) == [2_500, 0])
        // More landed than estimated (the bank paid more): nothing is negative, the headline is what landed.
        let over = try #require(CashbackJar.read(.init(cards: [plat], current: 0, purchases: [.init(cardID: "P", month: 0, amountMinor: 100_000)], landed: [.init(cardID: nil, amountMinor: 900)])))
        #expect(over.earnedMinor == 500 && over.accumulatingMinor == 0 && over.headlineMinor == 900)
    }

    @Test func refundsReduceTheirOriginalMonthAndNeverGoBelowZero() throws {
        // 1,000 bought, 300 refunded to the same month → 700 × 1.5% = 10.50.
        let r = try #require(CashbackJar.read(.init(cards: [travel], current: 1, purchases: [
            .init(cardID: "T", month: 0, amountMinor: 100_000), .init(cardID: "T", month: 0, amountMinor: -30_000),
            .init(cardID: "T", month: 1, amountMinor: 10_000), .init(cardID: "T", month: 1, amountMinor: -50_000)])))
        #expect(r.monthTotals == [1_050, 0])
    }

    @Test func recordedEarnedReplacesTheEstimateNeverAddsToIt() throws {
        // Estimate for 1,000 at 1.5% would be 15.00; the recorded 12.34 is the month's value, not 27.34.
        let r = try #require(CashbackJar.read(.init(cards: [travel], current: 0, purchases: [.init(cardID: "T", month: 0, amountMinor: 100_000)],
                                                     earned: [.init(cardID: "T", month: 0, amountMinor: 1_234)])))
        #expect(r.earnedMinor == 1_234)
    }

    @Test func unknownRatesStayUnknown() throws {
        let unknown = CashbackJar.Card(id: "U", rateBp: nil), idle = CashbackJar.Card(id: "I", rateBp: nil)
        let r = try #require(CashbackJar.read(.init(cards: [plat, unknown, idle], current: 0, purchases: [
            .init(cardID: "P", month: 0, amountMinor: 100_000), .init(cardID: "U", month: 0, amountMinor: 50_000)])))
        #expect(r.earnedMinor == 500, "The unknown card adds nothing, not an assumed zero rate")
        #expect(r.cards[1].earnedMinor == nil && r.cards[1].monthly == [nil])
        #expect(r.cards[2].earnedMinor == 0 && !r.cards[2].unknown, "No purchases: nothing to value")
        #expect(r.unknownCards == ["U"])
    }

    @Test func yearEndNeedsThreeCompleteMonthsAndAveragesThem() throws {
        // Rate 100% so purchases are the earned values. Months 0–1 empty, 2–4 complete (10, 20, 30), month 5 current (5).
        let full = CashbackJar.Card(id: "F", rateBp: 10_000)
        func input(_ values: [Int], current: Int) -> CashbackJar.Input {
            .init(cards: [full], current: current, purchases: values.enumerated().filter { $0.element != 0 }.map { .init(cardID: "F", month: $0.offset, amountMinor: $0.element) })
        }
        // Average of the three complete months since the first with data = 20; 60 so far + 20 × 7 months left = 200.
        #expect(CashbackJar.read(input([0, 0, 10, 20, 30, 5], current: 5))?.yearEndMinor == 200)
        // Two complete months only → no dotted line.
        #expect(CashbackJar.read(input([0, 0, 10, 20, 5], current: 4))?.yearEndMinor == nil)
        // 61 ÷ 3 = 20.33 → 20: 61 + 20 × 9 = 241.
        #expect(CashbackJar.read(input([10, 20, 31, 5], current: 3))?.yearEndMinor == 241)
        // Never below what is already earned: 3 + 1 × 9 = 12 < 103.
        #expect(CashbackJar.read(input([1, 1, 1, 100], current: 3))?.yearEndMinor == 103)
        #expect(CashbackJar.read(input([1], current: 12)) == nil, "The current month is inside the year")
    }

    @Test func switchingToTheHighestRateByCategory() throws {
        // On 0.5%: groceries 1,200 + 300 − 200 refunded = 1,300; restaurants 500; uncategorised 100. On 1.5% the
        // difference (1%) is 13.00, 5.00 and 1.00. Purchases already on the best card or on an unknown rate are left out.
        let cards = [plat, travel, CashbackJar.Card(id: "U", rateBp: nil)]
        let s = try #require(CashbackJar.switchToBest(cards: cards, purchases: [
            .init(cardID: "P", month: 0, amountMinor: 120_000, category: "بقالة"), .init(cardID: "P", month: 3, amountMinor: 30_000, category: "بقالة"),
            .init(cardID: "P", month: 3, amountMinor: -20_000, category: "بقالة"), .init(cardID: "P", month: 1, amountMinor: 50_000, category: "مطاعم"),
            .init(cardID: "P", month: 2, amountMinor: 10_000), .init(cardID: "T", month: 2, amountMinor: 99_999, category: "بقالة"),
            .init(cardID: "U", month: 2, amountMinor: 500_000, category: "بقالة")]))
        #expect(s.toCardID == "T")
        #expect(s.rows.map(\.gainMinor) == [1_300, 500, 100])
        #expect(s.rows.map(\.category) == ["بقالة", "مطاعم", nil])
        #expect(s.rows[0].baseMinor == 130_000 && s.totalGainMinor == 1_900)
        #expect(CashbackJar.switchToBest(cards: [travel, CashbackJar.Card(id: "U", rateBp: nil)], purchases: [.init(cardID: "U", month: 0, amountMinor: 1_000)]) == nil, "Nothing to compare")
    }

    @Test func duplicateCategoryNamesRemainSeparateByStableCategoryID() throws {
        let first = "category-groceries", second = "category-market"
        let reading = try #require(CashbackJar.switchToBest(cards: [plat, travel], purchases: [
            .init(cardID: "P", month: 0, amountMinor: 100_000, category: "بقالة", categoryID: first),
            .init(cardID: "P", month: 0, amountMinor: 200_000, category: "بقالة", categoryID: second)
        ]))
        #expect(reading.rows.count == 2)
        #expect(Set(reading.rows.compactMap(\.categoryID)) == [first, second])
        #expect(reading.rows.map(\.baseMinor).sorted() == [100_000, 200_000])
        #expect(reading.rows.map(\.gainMinor).sorted() == [1_000, 2_000])
    }
}
