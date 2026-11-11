import Foundation
import Testing
@testable import MadarMoney

private let zone = TimeZone(identifier: "Asia/Riyadh")!
private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var c = Calendar(identifier: .gregorian); c.timeZone = zone
    return c.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
}
private func startOfDay(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var c = Calendar(identifier: .gregorian); c.timeZone = zone
    return c.date(from: DateComponents(year: y, month: m, day: d))!
}

struct MerchantKeyTests {
    @Test func variantsOfOneMerchantShareAKey() {
        let names = ["Starbucks", "ستاربكس", "SQ *STARBUCKS #204 RIYADH SA", "Starbucks 1234", "STARBUCKS COFFEE RIYADH KSA"]
        #expect(Set(names.map(MerchantKey.key)) == ["starbucks"])
        #expect(Set(["PAYPAL *NETFLIX.COM", "نتفلكس", "Netflix"].map(MerchantKey.key)) == ["netflix"])
        #expect(Set(["Tamara - Noon", "noon.com", "نون"].map(MerchantKey.key)) == ["noon"])
        #expect(Set(["الدانوب", "Danube Hypermarket 12"].map(MerchantKey.key)) == ["danube"])
        #expect(Set(["Al Dawaa 12", "دواء"].map(MerchantKey.key)) == ["aldawaa"])
    }
    @Test func arabicLetterVariantsAndArticlesFold() {
        #expect(MerchantKey.key("مطعم الإفطار") == MerchantKey.key("مطعم  الافطار #5"))
        #expect(MerchantKey.key("مقهى النخيل") == MerchantKey.key("مقهي النخيل"))
        #expect(MerchantKey.key("مقهى النخيل") != MerchantKey.key("مقهى الورد"))
    }
    @Test func namesThatMerelyStartWithAnAliasWordAreNotMerged() {
        #expect(!MerchantKey.matches("كريم العتيبي", "Careem"))
        #expect(!MerchantKey.matches("زين العابدين", "Zain"))
        #expect(!MerchantKey.matches("صيدلية دواء الحي", "الدواء"))
        #expect(!MerchantKey.matches("Apple Pharmacy", "Apple"))
        #expect(!MerchantKey.matches("Panda Express", "Panda"))
        #expect(!MerchantKey.matches("Extra Space Storage", "extra"))
        #expect(!MerchantKey.matches("نهدي القحطاني", "Nahdi"))
        #expect(MerchantKey.matches("كريم", "careem") && MerchantKey.matches("Zain", "زين"))
    }
    @Test func differentMerchantsAndEmptyNamesNeverMatch() {
        #expect(!MerchantKey.matches("Starbucks", "Costa"))
        #expect(MerchantKey.key("") == "" && MerchantKey.key("!!! ###") == "" && MerchantKey.key(nil) == "")
        #expect(!MerchantKey.matches("", ""))
    }
}

struct RecurringChargesTests {
    private func occ(_ i: Int, _ y: Int, _ m: Int, _ d: Int, _ amount: Int, key: String = "x") -> RecurringCharges.Occurrence {
        .init(id: "o\(i)", key: key, name: "Name", currency: "SAR", amountMinor: amount, at: day(y, m, d))
    }
    private func detect(_ list: [RecurringCharges.Occurrence], _ profile: RecurringCharges.Profile = .subscription, now: Date) -> [RecurringCharges.Series] {
        RecurringCharges.detect(list, profile: profile, now: now, timeZone: zone)
    }

    @Test func weeklyChargesExpectTheNextWeek() throws {
        let s = try #require(detect([occ(1, 2026, 10, 4, 1000), occ(2, 2026, 10, 11, 1000), occ(3, 2026, 10, 18, 1000), occ(4, 2026, 10, 25, 1000)], now: day(2026, 10, 27)).first)
        #expect(s.cadence == .weekly && s.count == 4 && s.nextExpectedAt == startOfDay(2026, 11, 1) && s.status == .upcoming && s.priceChange == nil)
    }
    @Test func anyIntervalWorksAndTheGracePeriodMakesItLateThenMissed() throws {
        let rows = [occ(1, 2026, 9, 1, 500), occ(2, 2026, 9, 11, 500), occ(3, 2026, 9, 21, 500), occ(4, 2026, 10, 1, 500)]
        let late = try #require(detect(rows, now: day(2026, 10, 12)).first)
        #expect(late.cadence == .days(10) && late.nextExpectedAt == startOfDay(2026, 10, 11) && late.status == .late(days: 1))
        let missed = try #require(detect(rows, now: day(2026, 10, 20)).first)   // 9 days past, grace 3, two intervals 20
        #expect(missed.status == .missed(days: 9))
        #expect(detect(rows, now: day(2026, 11, 20)).first?.status == .ended)   // 40 days past
    }
    @Test func salaryKeepsItsBillingDayThroughWeekendShiftsAndFlagsARaise() throws {
        let s = try #require(detect([occ(1, 2026, 8, 27, 1_000_000), occ(2, 2026, 9, 25, 1_000_000), occ(3, 2026, 10, 27, 1_050_000)], .salary, now: day(2026, 10, 28)).first)
        #expect(s.cadence == .monthly && s.nextExpectedAt == startOfDay(2026, 11, 27) && s.amountMinor == 1_050_000)
        #expect(s.priceChange == .init(fromMinor: 1_000_000, toMinor: 1_050_000, since: day(2026, 10, 27)))
    }
    @Test func aSubscriptionPriceStepIsFlaggedButDriftingAmountsAreNotASubscription() throws {
        let s = try #require(detect([occ(1, 2026, 7, 17, 3900), occ(2, 2026, 8, 17, 3900), occ(3, 2026, 9, 17, 4900)], now: day(2026, 9, 20)).first)
        #expect(s.nextExpectedAt == startOfDay(2026, 10, 17) && s.priceChange?.fromMinor == 3900 && s.priceChange?.toMinor == 4900)
        #expect(detect([occ(1, 2026, 7, 17, 100), occ(2, 2026, 8, 17, 150), occ(3, 2026, 9, 17, 100)], now: day(2026, 9, 20)).isEmpty)
        #expect(detect([occ(1, 2026, 7, 17, 100), occ(2, 2026, 8, 17, 200), occ(3, 2026, 9, 17, 300)], now: day(2026, 9, 20)).isEmpty)
    }
    @Test func tooFewIrregularOrSameDayChargesAreNotRecurring() {
        #expect(detect([occ(1, 2026, 7, 17, 100), occ(2, 2026, 8, 17, 100)], now: day(2026, 8, 20)).isEmpty)
        #expect(detect([occ(1, 2026, 7, 1, 100), occ(2, 2026, 7, 9, 100), occ(3, 2026, 8, 20, 100)], now: day(2026, 8, 21)).isEmpty)
        #expect(detect([occ(1, 2026, 7, 17, 100), occ(2, 2026, 7, 17, 100), occ(3, 2026, 7, 17, 100)], now: day(2026, 7, 18)).isEmpty)
        // Every second day is below the five-day floor.
        #expect(detect([occ(1, 2026, 7, 1, 100), occ(2, 2026, 7, 3, 100), occ(3, 2026, 7, 5, 100)], now: day(2026, 7, 6)).isEmpty)
    }
    @Test func anOldIrregularHistoryDoesNotHideACurrentPattern() throws {
        let rows = [occ(1, 2026, 1, 2, 800), occ(2, 2026, 3, 20, 800), occ(3, 2026, 6, 1, 800), occ(4, 2026, 7, 1, 800), occ(5, 2026, 8, 1, 800)]
        let s = try #require(detect(rows, now: day(2026, 8, 5)).first)
        #expect(s.count == 3 && s.nextExpectedAt == startOfDay(2026, 9, 1))
    }
    @Test func groupsAreByMerchantKeyAndCurrency() {
        let a = [occ(1, 2026, 7, 1, 100, key: "a"), occ(2, 2026, 8, 1, 100, key: "a"), occ(3, 2026, 9, 1, 100, key: "a")]
        var b = [occ(4, 2026, 7, 1, 100, key: "b"), occ(5, 2026, 8, 1, 100, key: "b"), occ(6, 2026, 9, 1, 100, key: "b")]
        b[2].currency = "USD"   // a different currency breaks the run into two groups of two
        #expect(detect(a + b, now: day(2026, 9, 2)).map(\.key) == ["a"])
    }
}

struct RefundMatchingTests {
    private func original(_ id: String, _ amount: Int, _ at: Date, merchant: String = "SQ *STARBUCKS 12", card: String? = "card-1", refunded: Int = 0) -> RefundMatching.Original {
        .init(id: id, merchant: merchant, cardKey: card, accountKey: "acc-1", currency: "SAR", amountMinor: amount, refundedMinor: refunded, at: at)
    }
    private func refund(_ amount: Int, _ at: Date, merchant: String = "ستاربكس", card: String? = "card-1") -> RefundMatching.Refund {
        .init(merchant: merchant, cardKey: card, accountKey: "acc-1", currency: "SAR", amountMinor: amount, at: at)
    }
    @Test func aRefundMatchesTheOnlyPurchaseOfTheSameMerchantAndCard() {
        #expect(RefundMatching.match(refund(5000, day(2026, 10, 10)), among: [original("p", 5000, day(2026, 10, 1)), original("other", 5000, day(2026, 10, 1), merchant: "Costa")]) == "p")
        // A partial refund fits one larger purchase.
        #expect(RefundMatching.match(refund(3000, day(2026, 10, 10)), among: [original("p", 5000, day(2026, 10, 1))]) == "p")
    }
    @Test func ambiguousWrongCardTooLateOrAlreadyRefundedPurchasesAreNotLinked() {
        let two = [original("a", 5000, day(2026, 10, 1)), original("b", 5000, day(2026, 10, 5))]
        #expect(RefundMatching.match(refund(5000, day(2026, 10, 10)), among: two) == nil)
        #expect(RefundMatching.candidates(for: refund(5000, day(2026, 10, 10)), among: two).map(\.id) == ["b", "a"])
        // An exact amount wins over a bigger purchase.
        #expect(RefundMatching.match(refund(5000, day(2026, 10, 10)), among: [original("big", 9000, day(2026, 10, 9)), original("exact", 5000, day(2026, 10, 1))]) == "exact")
        #expect(RefundMatching.match(refund(5000, day(2026, 10, 10), card: "card-2"), among: [original("p", 5000, day(2026, 10, 1))]) == nil)
        #expect(RefundMatching.match(refund(5000, day(2027, 1, 10)), among: [original("p", 5000, day(2026, 10, 1))]) == nil)   // 101 days
        #expect(RefundMatching.match(refund(5000, day(2026, 9, 30)), among: [original("p", 5000, day(2026, 10, 1))]) == nil)   // before the purchase
        #expect(RefundMatching.match(refund(3000, day(2026, 10, 10)), among: [original("p", 5000, day(2026, 10, 1), refunded: 3000)]) == nil)   // 2000 left
    }
    @Test func chargesAddWithoutOverflow() {
        let sum = ChargeBreakdown(feeMinor: 100, vatMinor: 15) + ChargeBreakdown(foreignFeeMinor: 250)
        #expect(sum.totalMinor == 365 && !sum.isEmpty && ChargeBreakdown().isEmpty)
        #expect(ChargeBreakdown(feeMinor: Int.max, vatMinor: 1).totalMinor == Int.max)
    }
}

struct InstalmentPlansTests {
    private func event(_ id: String, merchant: String = "Noon", amount: Int = 2500, at: Date, paid: Bool, number: Int? = nil, count: Int? = nil, remaining: Int? = nil) -> InstalmentPlans.Event {
        .init(id: id, provider: "Tamara", merchant: merchant, currency: "SAR", amountMinor: amount, at: at, isPaid: paid, number: number, count: count, remainingMinor: remaining)
    }
    @Test func printedNumbersGiveTheRemainingCountAndTheNewestPrintedBalance() throws {
        let plans = InstalmentPlans.derive([
            event("p1", at: day(2026, 8, 1), paid: true, number: 1, count: 4, remaining: 7500),
            event("p2", at: day(2026, 9, 1), paid: true, number: 2, count: 4, remaining: 5000),
            event("d3", at: day(2026, 10, 1), paid: false, number: 3, count: 4)
        ])
        let plan = try #require(plans.first)
        #expect(plans.count == 1 && plan.paidCount == 2 && plan.paidMinor == 5000 && plan.openCount == 1)
        #expect(plan.printedCount == 4 && plan.remainingCount == 2 && plan.remainingMinor == 5000)
        #expect(plan.nextDueAt == day(2026, 10, 1) && plan.nextAmountMinor == 2500)
    }
    @Test func nothingIsInferredWhenNoMessagePrintedTheCount() throws {
        let plans = InstalmentPlans.derive([event("p1", at: day(2026, 8, 1), paid: true), event("d2", merchant: "نون", at: day(2026, 9, 1), paid: false),
                                            event("other", merchant: "Jarir", at: day(2026, 9, 5), paid: false)])
        #expect(plans.count == 2)   // Noon and نون are one merchant; Jarir another
        let noon = try #require(plans.first { $0.merchant != "Jarir" })
        #expect(noon.paidCount == 1 && noon.openCount == 1 && noon.printedCount == nil && noon.remainingCount == nil && noon.remainingMinor == nil)
    }
    @Test func tamaraMessagePrintsTheInstalmentNumberAndBalance() {
        let text = "دفعة قادمة بقيمة 125.00 ريال لطلبك من نون مستحقة اليوم\nالقسط 2 من 4\nالمبلغ المتبقي: 250.00 ريال\ntamara"
        let parsed = BankMessageParser.parse(text, timeZone: zone, receivedAt: day(2026, 10, 1), sender: "Tamara")
        #expect(parsed.provider == "Tamara" && parsed.statementDueMinor == 12_500)
        #expect(parsed.instalmentNumber == 2 && parsed.instalmentCount == 4 && parsed.remainingMinor == 25_000)
        let plain = BankMessageParser.parse("دفعة قادمة بقيمة 125.00 ريال لطلبك من نون مستحقة اليوم\ntamara", timeZone: zone, receivedAt: day(2026, 10, 1), sender: "Tamara")
        #expect(plain.instalmentNumber == nil && plain.instalmentCount == nil && plain.remainingMinor == nil)
    }
}

struct StatementDueClosingTests {
    private func statement(amount: Int = 680_000) -> UpcomingDues.Due {
        .init(id: "s", payee: "Bank 3333", amountMinor: amount, currency: "SAR", dueAt: day(2026, 11, 5), announcedAt: day(2026, 10, 20), isStatement: true, tail: "3333")
    }
    private func pay(_ id: String, _ amount: Int, card: Bool = true, tail: String? = "3333", at: Date = day(2026, 10, 25)) -> UpcomingDues.Payment {
        .init(id: id, payees: ["Bank"], amountMinor: amount, currency: "SAR", at: at, isCardPayment: card, tail: tail)
    }
    @Test func aCardPaymentOfAtLeastTheStatementClosesIt() {
        #expect(UpcomingDues.closures(open: [statement()], payments: [pay("p", 680_000)]).first?.payment == "p")
        #expect(UpcomingDues.closures(open: [statement()], payments: [pay("p", 700_000)]).first?.payment == "p")
    }
    @Test func minimumPartialBillWrongCardOrEarlierPaymentsLeaveItOpen() {
        #expect(UpcomingDues.closures(open: [statement()], payments: [pay("min", 340_000)]).isEmpty)
        #expect(UpcomingDues.closures(open: [statement()], payments: [pay("bill", 680_000, card: false)]).isEmpty)
        #expect(UpcomingDues.closures(open: [statement()], payments: [pay("other", 680_000, tail: "4444")]).isEmpty)
        #expect(UpcomingDues.closures(open: [statement()], payments: [pay("early", 680_000, at: day(2026, 10, 19))]).isEmpty)
        // A card payment never closes an ordinary bill of the same amount.
        let bill = UpcomingDues.Due(id: "b", payee: "Bank", amountMinor: 680_000, currency: "SAR", dueAt: day(2026, 11, 5), announcedAt: day(2026, 10, 20))
        #expect(UpcomingDues.closures(open: [bill], payments: [pay("p", 680_000)]).isEmpty)
    }
}

// Owner decisions D2, D4, D5 (11 Nov 2026) and the audit's missing Phase 3 cases. Expected values follow the owner's rules, not the code.
struct PhaseThreeDecisionTests {
    @Test func aBrandFollowedByAServiceWordIsItsOwnMerchant() {
        // D2: «Uber Eats», «Careem Food», «Amazon Web Services» are other businesses than the brand alone.
        #expect(!MerchantKey.matches("Uber Eats", "Uber"))
        #expect(!MerchantKey.matches("Careem Food", "Careem"))
        #expect(!MerchantKey.matches("Amazon Web Services", "Amazon"))
        #expect(!MerchantKey.matches("Uber Eats", "Careem Food"))
        // One service printed two ways is still one merchant.
        #expect(MerchantKey.matches("UBER EATS", "Uber Eats"))
        #expect(MerchantKey.matches("UBEREATS", "Uber Eats"))
        #expect(MerchantKey.matches("AWS", "Amazon Web Services"))
        #expect(MerchantKey.matches("CAREEM FOOD RIYADH SA", "Careem Food"))
        #expect(MerchantKey.matches("أمازون ويب سيرفسز", "AWS"))
    }
    @Test func ordinaryBrandVariantsStayWithTheBrand() {
        // D2: «UBER TRIP», «AMAZON SA» and the like are the brand itself.
        #expect(MerchantKey.matches("UBER TRIP", "Uber"))
        #expect(MerchantKey.matches("AMAZON SA", "Amazon"))
        #expect(MerchantKey.matches("Amazon.sa", "امازون"))
        #expect(MerchantKey.matches("CAREEM RIDE", "كريم"))
        #expect(MerchantKey.matches("PAYPAL *UBER", "Uber"))
    }
    @Test func alBaikIsOneMerchantHoweverTheArticleIsWritten() {
        #expect(Set(["Al Baik", "AlBaik", "ALBAIK 12 RIYADH", "البيك", "بيك"].map(MerchantKey.key)).count == 1)
    }
}

struct InstalmentPlanSplitTests {
    private func event(_ id: String, amount: Int, at: Date, paid: Bool, number: Int? = nil, count: Int? = nil, remaining: Int? = nil) -> InstalmentPlans.Event {
        .init(id: id, provider: "Tamara", merchant: "Noon", currency: "SAR", amountMinor: amount, at: at, isPaid: paid, number: number, count: count, remainingMinor: remaining)
    }
    @Test func twoPlansAtOneMerchantAndProviderStayTwoPlans() throws {
        // D4: told apart by printed instalment count and instalment amount.
        let plans = InstalmentPlans.derive([
            event("a1", amount: 2500, at: day(2026, 8, 1), paid: true, number: 1, count: 4, remaining: 7500),
            event("a2", amount: 2500, at: day(2026, 9, 1), paid: true, number: 2, count: 4, remaining: 5000),
            event("b1", amount: 10_000, at: day(2026, 9, 10), paid: true, number: 1, count: 3, remaining: 20_000),
            event("b2", amount: 10_000, at: day(2026, 10, 10), paid: false, number: 2, count: 3)
        ])
        #expect(plans.count == 2)
        let a = try #require(plans.first { $0.printedCount == 4 }), b = try #require(plans.first { $0.printedCount == 3 })
        #expect(a.paidCount == 2 && a.paidMinor == 5000 && a.remainingCount == 2 && a.remainingMinor == 5000 && a.openCount == 0)
        #expect(b.paidCount == 1 && b.paidMinor == 10_000 && b.remainingCount == 2 && b.remainingMinor == 20_000 && b.openCount == 1)
        #expect(b.nextDueAt == day(2026, 10, 10) && b.nextAmountMinor == 10_000)
    }
    @Test func anUncountedInstalmentJoinsThePlanOfItsAmount() throws {
        let plans = InstalmentPlans.derive([
            event("a1", amount: 2500, at: day(2026, 8, 1), paid: true, number: 1, count: 4),
            event("b1", amount: 10_000, at: day(2026, 9, 10), paid: true, number: 1, count: 3),
            event("a-open", amount: 2500, at: day(2026, 10, 1), paid: false)
        ])
        #expect(plans.count == 2)
        let a = try #require(plans.first { $0.printedCount == 4 })
        #expect(a.openCount == 1 && a.nextDueAt == day(2026, 10, 1))
    }
    @Test func aLastInstalmentRoundedByAFewHalalasStaysInItsPlan() throws {
        // 100.00 in three instalments: 33.33, 33.33, 33.34. One plan, not two.
        let plans = InstalmentPlans.derive([
            event("1", amount: 3333, at: day(2026, 8, 1), paid: true, number: 1, count: 3),
            event("2", amount: 3333, at: day(2026, 9, 1), paid: true, number: 2, count: 3),
            event("3", amount: 3334, at: day(2026, 10, 1), paid: false, number: 3, count: 3)
        ])
        #expect(plans.count == 1)
        #expect(plans.first?.paidCount == 2 && plans.first?.openCount == 1 && plans.first?.remainingCount == 1)
    }
}

struct RelativeDueTests {
    private let reminder = "دفعة قادمة بقيمة 125.00 ريال لطلبك من نون مستحقة غدا\ntamara"
    @Test func aRelativeDueDayIsDatedOnlyWhenTheArrivalTimeIsKnown() {
        // D5: the arrival time is known → receive day + 1.
        let known = BankMessageParser.parse(reminder, timeZone: zone, receivedAt: day(2026, 10, 1), sender: "Tamara")
        #expect(known.dueDate == day(2026, 10, 2))
        // Pasted later with no arrival time: the due stays undated.
        let pasted = BankMessageParser.parse(reminder, timeZone: zone, receivedAt: day(2026, 10, 9), sender: "Tamara", arrivalKnown: false)
        #expect(pasted.dueDate == nil && pasted.statementDueMinor == 12_500)
    }
    @Test func undatedInstalmentDuesOfOneAmountKeepTheirOwnKeys() {
        // The same undated reminder pasted twice is one due; instalments 2 and 3 of the same amount are two.
        let two = UpcomingDues.naturalKey(payee: "Tamara", amountMinor: 12_500, currency: "SAR", dueDayKey: nil, instalmentNumber: 2)
        let three = UpcomingDues.naturalKey(payee: "Tamara", amountMinor: 12_500, currency: "SAR", dueDayKey: nil, instalmentNumber: 3)
        #expect(two != three)
        #expect(two == UpcomingDues.naturalKey(payee: "Tamara", amountMinor: 12_500, currency: "SAR", dueDayKey: nil, instalmentNumber: 2))
        // Dated keys are unchanged by the instalment number, so stored dues keep their identity.
        #expect(UpcomingDues.naturalKey(payee: "Tamara", amountMinor: 12_500, currency: "SAR", dueDayKey: "2026-10-02", instalmentNumber: 2)
                == UpcomingDues.naturalKey(payee: "Tamara", amountMinor: 12_500, currency: "SAR", dueDayKey: "2026-10-02"))
        #expect(UpcomingDues.naturalKey(payee: "Tamara", amountMinor: 12_500, currency: "SAR", dueDayKey: nil)
                == "UpcomingDue:" + BankDedupe.normalize("Tamara") + ":12500:SAR:none")
    }
}

struct RecurringChargeDayTests {
    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = zone
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }
    @Test func aChargeBetweenMidnightAndFajrBelongsToTheStoredAppDay() throws {
        // Paid 1:30 on 1 Sep, but the app day (day starts at Fajr) is 31 Aug, like the earlier charges on the 31st.
        let rows: [RecurringCharges.Occurrence] = [
            .init(id: "1", key: "x", name: "N", currency: "SAR", amountMinor: 900, at: at(2026, 6, 30, 20), dayKey: "2026-06-30"),
            .init(id: "2", key: "x", name: "N", currency: "SAR", amountMinor: 900, at: at(2026, 7, 31, 20), dayKey: "2026-07-31"),
            .init(id: "3", key: "x", name: "N", currency: "SAR", amountMinor: 900, at: at(2026, 9, 1, 1), dayKey: "2026-08-31")
        ]
        let s = try #require(RecurringCharges.detect(rows, profile: .subscription, now: day(2026, 9, 5), timeZone: zone).first)
        // Billing day is the 31st (median of 30, 31, 31), clamped to 30 in September.
        #expect(s.cadence == .monthly && s.nextExpectedAt == startOfDay(2026, 9, 30))
    }
    @Test func lateIsCountedFromTodaysAppDay() throws {
        // 02:00 on 13 Nov is still the app day of 12 Nov (day starts at Fajr): a charge expected on the 12th is not late yet.
        let rows: [RecurringCharges.Occurrence] = (8...10).map { m in
            .init(id: "\(m)", key: "x", name: "N", currency: "SAR", amountMinor: 900, at: at(2026, m, 12, 20), dayKey: String(format: "2026-%02d-12", m))
        }
        let s = try #require(RecurringCharges.detect(rows, profile: .subscription, now: at(2026, 11, 13, 2), timeZone: zone, todayKey: "2026-11-12").first)
        #expect(s.nextExpectedAt == startOfDay(2026, 11, 12) && s.status == .upcoming)
        // An impossible stored day falls back to the civil day of the time instead of rolling into the next month.
        var odd = rows; odd[2].dayKey = "2026-10-41"
        #expect(RecurringCharges.detect(odd, profile: .subscription, now: at(2026, 11, 13, 2), timeZone: zone, todayKey: "2026-11-12").first?.nextExpectedAt == startOfDay(2026, 11, 12))
    }
    @Test func aBillingDayOf29To31ClampsToShortMonthsAndComesBack() throws {
        func occ(_ i: Int, _ y: Int, _ m: Int, _ d: Int) -> RecurringCharges.Occurrence {
            .init(id: "o\(i)", key: "x", name: "N", currency: "SAR", amountMinor: 500, at: day(y, m, d))
        }
        // 31 Oct, 30 Nov, 31 Dec → billing day 31; next is 31 Jan.
        let jan = try #require(RecurringCharges.detect([occ(1, 2026, 10, 31), occ(2, 2026, 11, 30), occ(3, 2026, 12, 31)], profile: .subscription, now: day(2027, 1, 2), timeZone: zone).first)
        #expect(jan.nextExpectedAt == startOfDay(2027, 1, 31))
        // 30 Nov, 31 Dec, 31 Jan → next is 28 Feb 2027 (not a leap year), then 31 Mar.
        let feb = try #require(RecurringCharges.detect([occ(1, 2026, 11, 30), occ(2, 2026, 12, 31), occ(3, 2027, 1, 31)], profile: .subscription, now: day(2027, 2, 2), timeZone: zone).first)
        #expect(feb.nextExpectedAt == startOfDay(2027, 2, 28))
        let mar = try #require(RecurringCharges.detect([occ(1, 2026, 12, 31), occ(2, 2027, 1, 31), occ(3, 2027, 2, 28)], profile: .subscription, now: day(2027, 3, 2), timeZone: zone).first)
        #expect(mar.nextExpectedAt == startOfDay(2027, 3, 31))
        // 29 Jan 2028 → 29 Feb 2028 exists (leap year).
        let leap = try #require(RecurringCharges.detect([occ(1, 2027, 11, 29), occ(2, 2027, 12, 29), occ(3, 2028, 1, 29)], profile: .subscription, now: day(2028, 2, 2), timeZone: zone).first)
        #expect(leap.nextExpectedAt == startOfDay(2028, 2, 29))
    }
}
