import Foundation
import Testing
@testable import MadarMoney

struct SubscriptionSuggestionEngineTests {
    private var zone: TimeZone { TimeZone(identifier: "Asia/Riyadh")! }

    private func at(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func charge(_ id: String, _ year: Int, _ month: Int, _ day: Int, amount: Int = 39_900,
                        merchant: String? = "منصة شاهد", currency: String = "SAR", cardID: String? = "credit-1",
                        accountID: String? = nil, kind: String = "expense", reviewState: String = "ok",
                        source: String = "bank", obligationID: String? = nil, counterparty: String? = nil) -> SubscriptionSuggestionEngine.Charge {
        .init(id: id, kind: kind, reviewState: reviewState, source: source, merchant: merchant,
              counterparty: counterparty, currency: currency, amountMinor: amount, cardID: cardID, accountID: accountID,
              obligationID: obligationID, at: at(year, month, day))
    }

    @Test func suggestsThreeStableMonthlyChargesWithTheirEvidenceAndNextDate() throws {
        let result = SubscriptionSuggestionEngine.suggestions(charges: [
            charge("july", 2026, 7, 17), charge("august", 2026, 8, 18), charge("september", 2026, 9, 18)
        ], existingObligationNames: [], now: at(2026, 10, 16), timeZone: zone)

        let suggestion = try #require(result.first)
        #expect(result.count == 1)
        #expect(suggestion.name == "منصة شاهد" && suggestion.amountMinor == 39_900 && suggestion.currency == "SAR")
        #expect(suggestion.count == 3 && suggestion.evidenceDates == [at(2026, 7, 17), at(2026, 8, 18), at(2026, 9, 18)])
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        #expect(calendar.isDate(suggestion.nextDue, inSameDayAs: at(2026, 10, 18)))
    }

    @Test func variableAmountsAndUnstableMerchantNamesDoNotLookRecurring() {
        let variable = [charge("july", 2026, 7, 18), charge("august", 2026, 8, 18, amount: 40_000), charge("september", 2026, 9, 18)]
        let differentNames = [charge("july", 2026, 7, 18), charge("august", 2026, 8, 18, merchant: "شاهد"), charge("september", 2026, 9, 18)]
        #expect(SubscriptionSuggestionEngine.suggestions(charges: variable, existingObligationNames: [], now: at(2026, 10, 16), timeZone: zone).isEmpty)
        #expect(SubscriptionSuggestionEngine.suggestions(charges: differentNames, existingObligationNames: [], now: at(2026, 10, 16), timeZone: zone).isEmpty)

        let counterpartyFallback = [charge("july", 2026, 7, 18, merchant: "", counterparty: "Shahid"),
            charge("august", 2026, 8, 18, merchant: nil, counterparty: "Shahid"),
            charge("september", 2026, 9, 18, merchant: " ", counterparty: "Shahid")]
        #expect(SubscriptionSuggestionEngine.suggestions(charges: counterpartyFallback, existingObligationNames: [], now: at(2026, 10, 16), timeZone: zone).first?.name == "Shahid")
    }

    @Test func needsThreeConsecutiveMonthsAndOneChargePerMonth() {
        let missingMonth = [charge("july", 2026, 7, 18), charge("september", 2026, 9, 18), charge("october", 2026, 10, 18)]
        let repeatedMonth = [charge("july", 2026, 7, 18), charge("august-a", 2026, 8, 18), charge("august-b", 2026, 8, 19), charge("september", 2026, 9, 18)]
        #expect(SubscriptionSuggestionEngine.suggestions(charges: missingMonth, existingObligationNames: [], now: at(2026, 10, 16), timeZone: zone).isEmpty)
        #expect(SubscriptionSuggestionEngine.suggestions(charges: repeatedMonth, existingObligationNames: [], now: at(2026, 10, 16), timeZone: zone).isEmpty)

        // An ambiguous newest month must not make an older three-month pattern look current.
        let olderPatternPlusDuplicate = [charge("july", 2026, 7, 18), charge("august", 2026, 8, 18),
            charge("september", 2026, 9, 18), charge("october-a", 2026, 10, 15), charge("october-b", 2026, 10, 16)]
        #expect(SubscriptionSuggestionEngine.suggestions(charges: olderPatternPlusDuplicate, existingObligationNames: [], now: at(2026, 10, 16), timeZone: zone).isEmpty)
    }

    @Test func onlyConfirmedBankExpensesWithStablePaymentSourceQualify() {
        let invalid = [
            charge("pending", 2026, 7, 18, reviewState: "needsLook"),
            charge("refund", 2026, 8, 18, kind: "refund"),
            charge("manual", 2026, 9, 18, source: "manual"),
            charge("linked", 2026, 10, 18, obligationID: "already-recognized")
        ]
        let noStableSource = [charge("july", 2026, 7, 18, cardID: nil), charge("august", 2026, 8, 18, cardID: nil), charge("september", 2026, 9, 18, cardID: nil)]
        #expect(SubscriptionSuggestionEngine.suggestions(charges: invalid, existingObligationNames: [], now: at(2026, 10, 16), timeZone: zone).isEmpty)
        #expect(SubscriptionSuggestionEngine.suggestions(charges: noStableSource, existingObligationNames: [], now: at(2026, 10, 16), timeZone: zone).isEmpty)
        let alreadyLinked = [charge("july", 2026, 7, 18, obligationID: "recognized"),
            charge("august", 2026, 8, 18, obligationID: "recognized"), charge("september", 2026, 9, 18, obligationID: "recognized")]
        #expect(SubscriptionSuggestionEngine.suggestions(charges: alreadyLinked, existingObligationNames: [], now: at(2026, 10, 16), timeZone: zone).isEmpty)
    }

    @Test func existingObligationAndStalePatternAreSuppressed() {
        let rows = [charge("july", 2026, 7, 18), charge("august", 2026, 8, 18), charge("september", 2026, 9, 18)]
        #expect(SubscriptionSuggestionEngine.suggestions(charges: rows, existingObligationNames: ["منصة شاهد"], now: at(2026, 10, 16), timeZone: zone).isEmpty)
        #expect(SubscriptionSuggestionEngine.suggestions(charges: rows, existingObligationNames: [], now: at(2026, 11, 5), timeZone: zone).isEmpty)
    }

    @Test func endOfMonthDatesAreNotGuessedIntoAStableMonthlyRule() {
        let monthEnd = [charge("january", 2026, 1, 31), charge("february", 2026, 2, 28), charge("march", 2026, 3, 31)]
        #expect(SubscriptionSuggestionEngine.suggestions(charges: monthEnd, existingObligationNames: [], now: at(2026, 4, 15), timeZone: zone).isEmpty)
    }
}
