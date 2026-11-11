import Foundation
import Testing
@testable import MadarMoney

struct BankReadingsTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: balance matching
    @Test func equalBooksShowNothingAndADifferenceIsOneOpenReading() {
        #expect(BalanceMatching.reading(accountKey: "a", messageKey: "m", at: t0, observedMinor: 10_000, bookMinor: 10_000, pendingNetMinor: 0, pendingCount: 0, lastSettlementAt: nil) == nil)
        let r = BalanceMatching.reading(accountKey: "a", messageKey: "m", at: t0, observedMinor: 9_000, bookMinor: 10_000, pendingNetMinor: 0, pendingCount: 0, lastSettlementAt: nil)
        #expect(r?.status == .open); #expect(r?.differenceMinor == -1_000); #expect(r?.isSettleable == true)
        #expect(r?.names == [.missedSpend, .bankFee, .unexplained])
        #expect(r?.line == ReconcileLine(side: .account, expectedMinor: 10_000, observedMinor: 9_000))
    }
    @Test func draftsThatExplainTheDifferenceAreNotAMismatchAndOthersWait() {
        // The message's own pending draft (-1,000) makes 9,000 the expected balance once reviewed.
        #expect(BalanceMatching.reading(accountKey: "a", messageKey: "m", at: t0, observedMinor: 9_000, bookMinor: 10_000, pendingNetMinor: -1_000, pendingCount: 1, lastSettlementAt: nil) == nil)
        let r = BalanceMatching.reading(accountKey: "a", messageKey: "m", at: t0, observedMinor: 8_000, bookMinor: 10_000, pendingNetMinor: -1_000, pendingCount: 1, lastSettlementAt: nil)
        #expect(r?.status == .waitingForReview); #expect(r?.isSettleable == false); #expect(r?.names.isEmpty == true)
    }
    @Test func settlingSilencesTheReadingAndANegativeBalanceCannotBeSettled() {
        #expect(BalanceMatching.reading(accountKey: "a", messageKey: "m", at: t0, observedMinor: 1, bookMinor: 2, pendingNetMinor: 0, pendingCount: 0, lastSettlementAt: t0) == nil)
        #expect(BalanceMatching.reading(accountKey: "a", messageKey: "m", at: t0, observedMinor: 1, bookMinor: 2, pendingNetMinor: 0, pendingCount: 0, lastSettlementAt: t0.addingTimeInterval(-1)) != nil)
        let negative = BalanceMatching.reading(accountKey: "a", messageKey: "m", at: t0, observedMinor: -500, bookMinor: 2_000, pendingNetMinor: 0, pendingCount: 0, lastSettlementAt: nil)
        #expect(negative?.differenceMinor == -2_500); #expect(negative?.isSettleable == false)
    }
    @Test func onlyALaterMessageReplacesAStoredBalance() {
        #expect(BalanceMatching.replaces(storedAt: nil, with: t0))
        #expect(BalanceMatching.replaces(storedAt: t0, with: t0.addingTimeInterval(1)))
        #expect(!BalanceMatching.replaces(storedAt: t0, with: t0)); #expect(!BalanceMatching.replaces(storedAt: t0, with: t0.addingTimeInterval(-60)))
    }

    // MARK: own transfer pairing
    func out(_ id: String, _ at: TimeInterval, from: String? = "A", to: String? = nil, amount: Int = 50_000) -> OwnTransferLeg {
        .init(id: id, direction: .out, amountMinor: amount, currency: "SAR", at: t0.addingTimeInterval(at), fromAccountID: from, toAccountID: to)
    }
    func inn(_ id: String, _ at: TimeInterval, to: String? = "W", from: String? = nil, amount: Int = 50_000, currency: String = "SAR") -> OwnTransferLeg {
        .init(id: id, direction: .in, amountMinor: amount, currency: currency, at: t0.addingTimeInterval(at), fromAccountID: from, toAccountID: to)
    }
    @Test func topUpAndDepositPairWhenTheTailNamesTheOtherSide() {
        let pairs = OwnTransferPairing.pairs([out("o", 0, to: "W"), inn("i", 20 * 60)])
        #expect(pairs.count == 1); #expect(pairs.first?.out == "o"); #expect(pairs.first?.in == "i")
        // Just past the strong window: no pair.
        #expect(OwnTransferPairing.pairs([out("o", 0, to: "W"), inn("i", 31 * 60)]).isEmpty)
    }
    @Test func withoutAnyTailOnlyTheShortWindowPairs() {
        #expect(OwnTransferPairing.pairs([out("o", 0), inn("i", 9 * 60)]).count == 1)
        #expect(OwnTransferPairing.pairs([out("o", 0), inn("i", 11 * 60)]).isEmpty)
    }
    @Test func aWrongTailAmountCurrencyOrSameAccountNeverPairs() {
        #expect(OwnTransferPairing.pairs([out("o", 0, to: "X"), inn("i", 60)]).isEmpty)
        #expect(OwnTransferPairing.pairs([out("o", 0, to: "W"), inn("i", 60, from: "Z")]).isEmpty)
        #expect(OwnTransferPairing.pairs([out("o", 0), inn("i", 60, amount: 50_001)]).isEmpty)
        #expect(OwnTransferPairing.pairs([out("o", 0), inn("i", 60, currency: "USD")]).isEmpty)
        #expect(OwnTransferPairing.pairs([out("o", 0), inn("i", 60, to: "A")]).isEmpty)
        #expect(OwnTransferPairing.pairs([out("o", 0, from: nil), inn("i", 60)]).isEmpty)
    }
    @Test func eachLegPairsOnceNearestFirst() {
        let pairs = OwnTransferPairing.pairs([out("o1", 0), out("o2", 120), inn("i1", 100), inn("i2", 400)])
        #expect(pairs.count == 2)
        #expect(pairs.contains { $0.out == "o1" && $0.in == "i1" } || pairs.contains { $0.out == "o1" && $0.in == "i2" })
        #expect(Set(pairs.map(\.in)).count == 2); #expect(Set(pairs.map(\.out)).count == 2)
        // o2 is nearest to i1 (20 s) but o1 goes first and takes it only if nearest to o1; o1's nearest is i1 (100 s) vs i2 (400 s).
        #expect(pairs.first { $0.out == "o1" }?.in == "i1")
    }
    @Test func bothSidesIdentifiedOnBothLegsStillPairsAShareTrade() {
        let pairs = OwnTransferPairing.pairs([out("buy", 0, to: "W"), inn("dep", 30, to: "W", from: "A")])
        #expect(pairs.count == 1)
    }

    // MARK: unknown tails
    @Test func oneQuestionPerBankAndTailWhateverTheMessageCount() {
        let items: [UnknownTailQuestions.Item] = [
            .init(messageKey: "m1", sender: "Bank", tail: "0000", at: t0, candidateKeys: ["a"]),
            .init(messageKey: "m2", sender: "bank", tail: "0000", at: t0.addingTimeInterval(60), candidateKeys: ["a"]),
            .init(messageKey: "m3", sender: "Bank", tail: "0001", at: t0.addingTimeInterval(30), candidateKeys: ["a", "b"]),
            .init(messageKey: "m4", sender: "Other", tail: "0000", at: t0.addingTimeInterval(10), candidateKeys: ["c"])]
        let questions = UnknownTailQuestions.group(items)
        #expect(questions.count == 3)
        #expect(questions.first?.tail == "0000"); #expect(questions.first?.messageKeys == ["m2", "m1"])
        #expect(questions.map(\.latestAt) == questions.map(\.latestAt).sorted(by: >))
    }

    // MARK: upcoming dues
    func due(_ id: String, payee: String = "Tamara", amount: Int = 12_000, dueIn days: Double? = 2, announced: TimeInterval = 0) -> UpcomingDues.Due {
        .init(id: id, payee: payee, amountMinor: amount, currency: "SAR", dueAt: days.map { t0.addingTimeInterval($0 * 86_400) }, announcedAt: t0.addingTimeInterval(announced))
    }
    func pay(_ id: String, _ payees: [String] = ["Tamara"], amount: Int = 12_000, at: TimeInterval) -> UpcomingDues.Payment {
        .init(id: id, payees: payees, amountMinor: amount, currency: "SAR", at: t0.addingTimeInterval(at))
    }
    @Test func aLaterPaymentOfTheSameAmountToTheSamePayeeClosesTheEarliestDue() {
        let dues = [due("late", dueIn: 30), due("soon", dueIn: 2)]
        let closed = UpcomingDues.closures(open: dues, payments: [pay("p", at: 86_400)])
        #expect(closed.count == 1); #expect(closed.first?.due == "soon"); #expect(closed.first?.payment == "p")
    }
    @Test func wrongAmountPayeeEarlierOrTooLatePaymentsLeaveItOpen() {
        let d = [due("d")]
        #expect(UpcomingDues.closures(open: d, payments: [pay("a", amount: 12_001, at: 100)]).isEmpty)
        #expect(UpcomingDues.closures(open: d, payments: [pay("b", ["Tabby"], at: 100)]).isEmpty)
        #expect(UpcomingDues.closures(open: d, payments: [pay("c", at: -1)]).isEmpty)
        #expect(UpcomingDues.closures(open: d, payments: [pay("e", at: (2 + 15) * 86_400)]).isEmpty)
        #expect(UpcomingDues.closures(open: d, payments: [pay("f", at: (2 + 13) * 86_400)]).count == 1)
        #expect(UpcomingDues.closures(open: [due("u", dueIn: nil)], payments: [pay("g", at: 46 * 86_400)]).isEmpty)
    }
    @Test func twoEqualInstalmentsCloseOneEachAndAClosedDueIsNotOpen() {
        let closed = UpcomingDues.closures(open: [due("d1", dueIn: 2), due("d2", dueIn: 16)], payments: [pay("p1", at: 86_400), pay("p2", at: 15 * 86_400)])
        #expect(closed.map(\.due) == ["d1", "d2"])
        var d = due("x"); #expect(UpcomingDues.isOpen(d)); d.closedBy = "p"; #expect(!UpcomingDues.isOpen(d))
        #expect(UpcomingDues.closures(open: [d], payments: [pay("p2", at: 100)]).isEmpty)
    }
    @Test func payeeNamesMatchByNormalizationContainmentOrBankAlias() {
        #expect(UpcomingDues.samePayee("Tamara", " tamara "))
        #expect(UpcomingDues.samePayee("Saudi Electricity", "electricity"))
        #expect(UpcomingDues.samePayee("الراجحي", "Al Rajhi"))
        #expect(!UpcomingDues.samePayee("Tamara", "Tabby")); #expect(!UpcomingDues.samePayee("", "Tamara"))
    }
    @Test func listIsSortedByDueDateUndatedLast() {
        let list = UpcomingDues.sorted([due("c", dueIn: nil), due("b", dueIn: 5), due("a", dueIn: 1), due("a2", amount: 10_000, dueIn: 1)])
        #expect(list.map(\.id) == ["a2", "a", "b", "c"])
    }
    @Test func repeatedReminderOfOnePaymentSharesANaturalKey() {
        let k1 = UpcomingDues.naturalKey(payee: "Tamara", amountMinor: 12_000, currency: "SAR", dueDayKey: "2026-11-20")
        let k2 = UpcomingDues.naturalKey(payee: " tamara", amountMinor: 12_000, currency: "SAR", dueDayKey: "2026-11-20")
        #expect(k1 == k2); #expect(k1 != UpcomingDues.naturalKey(payee: "Tamara", amountMinor: 12_000, currency: "SAR", dueDayKey: "2026-11-21"))
    }

    @Test func onlyABillIssuedNoticeIsKeptAsADueNotice() {
        #expect(BankMessageParser.isDueNotice("تم إصدار فاتورتك والمبلغ المطلوب 50.00 ريال"))
        #expect(!BankMessageParser.isDueNotice("عرض خاص لك اشترك الآن"))
        #expect(!BankMessageParser.isDueNotice("شراء مدى\nبطاقة: 3333*\nمبلغ: 50.00 SAR"))
    }
}
