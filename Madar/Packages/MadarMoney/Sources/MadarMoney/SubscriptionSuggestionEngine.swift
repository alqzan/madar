import Foundation

/// Conservatively spots fixed monthly subscriptions among confirmed bank expenses. It only proposes a draft; it never
/// creates an obligation or changes a transaction.
public enum SubscriptionSuggestionEngine {
    public struct Charge: Equatable, Sendable {
        public var id: String
        public var kind: String
        public var reviewState: String
        public var source: String
        public var merchant: String?
        public var counterparty: String?
        public var currency: String
        public var amountMinor: Int
        public var cardID: String?
        public var accountID: String?
        public var obligationID: String?
        public var at: Date

        public init(id: String, kind: String = "expense", reviewState: String = "ok", source: String = "bank",
                    merchant: String?, counterparty: String? = nil, currency: String, amountMinor: Int,
                    cardID: String? = nil, accountID: String? = nil, obligationID: String? = nil, at: Date) {
            self.id = id; self.kind = kind; self.reviewState = reviewState; self.source = source
            self.merchant = merchant; self.counterparty = counterparty; self.currency = currency
            self.amountMinor = amountMinor; self.cardID = cardID; self.accountID = accountID
            self.obligationID = obligationID; self.at = at
        }
    }

    public struct Suggestion: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var amountMinor: Int
        public var currency: String
        /// Three newest qualifying bank-confirmed charges, oldest first, for the user to verify.
        public var evidenceDates: [Date]
        /// The upcoming monthly date, anchored to the stable billing day.
        public var nextDue: Date
        public var count: Int { evidenceDates.count }
    }

    private struct MonthKey: Hashable {
        var ordinal: Int
        var year: Int
        var month: Int
    }

    private struct GroupKey: Hashable {
        var merchant: String
        var currency: String
        var payment: String
    }

    /// A suggestion requires one same-amount expense in each of three consecutive months, a stable payment source,
    /// and a billing day no later than the 28th. The 1–28 day range avoids guessing an end-of-month rule that the
    /// existing schedule model cannot represent. A latest charge older than 40 days is treated as stale.
    public static func suggestions(charges: [Charge], existingObligationNames: [String], now: Date,
                                    timeZone: TimeZone) -> [Suggestion] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let existing = Set(existingObligationNames.map(BankDedupe.normalize).filter { !$0.isEmpty })
        var groups: [GroupKey: [Charge]] = [:]

        for charge in charges {
            guard charge.kind == "expense", charge.reviewState == "ok", charge.source == "bank", charge.obligationID == nil,
                  charge.amountMinor > 0, !charge.currency.isEmpty,
                  let merchant = [charge.merchant, charge.counterparty].compactMap({ $0 })
                    .first(where: { !BankDedupe.normalize($0).isEmpty }) else { continue }
            let normalized = BankDedupe.normalize(merchant)
            guard !normalized.isEmpty, !existing.contains(normalized),
                  let payment = charge.cardID.map({ "card:" + $0 }) ?? charge.accountID.map({ "account:" + $0 }) else { continue }
            groups[.init(merchant: normalized, currency: charge.currency.uppercased(), payment: payment), default: []].append(charge)
        }

        let today = calendar.startOfDay(for: now)
        var result: [Suggestion] = []
        for (key, rows) in groups {
            var byMonth: [MonthKey: [Charge]] = [:]
            for row in rows {
                let parts = calendar.dateComponents([.year, .month, .day], from: row.at)
                guard let year = parts.year, let month = parts.month else { continue }
                let monthKey = MonthKey(ordinal: year * 12 + month - 1, year: year, month: month)
                byMonth[monthKey, default: []].append(row)
            }

            // A second same-merchant payment in a month is ambiguous (for example, two separate visits), so it
            // disqualifies that month instead of making the repeated pattern look stronger.
            let singleChargeMonths = byMonth.filter { $0.value.count == 1 }.map { ($0.key, $0.value[0]) }.sorted { $0.0.ordinal < $1.0.ordinal }
            guard singleChargeMonths.count >= 3 else { continue }
            let lastThree = Array(singleChargeMonths.suffix(3))
            // Do not revive an older pattern when the newest observed month is itself ambiguous.
            guard let newestObservedMonth = byMonth.keys.max(by: { $0.ordinal < $1.ordinal }),
                  newestObservedMonth.ordinal == lastThree[2].0.ordinal else { continue }
            guard lastThree[1].0.ordinal == lastThree[0].0.ordinal + 1,
                  lastThree[2].0.ordinal == lastThree[1].0.ordinal + 1 else { continue }
            let evidence = lastThree.map(\.1)
            guard Set(evidence.map(\.amountMinor)).count == 1,
                  evidence.allSatisfy({ $0.currency.uppercased() == key.currency }) else { continue }
            let days = evidence.compactMap { calendar.dateComponents([.day], from: $0.at).day }.sorted()
            guard days.count == 3, days.first ?? 0 >= 1, days.last ?? 99 <= 28,
                  (days.last ?? 99) - (days.first ?? 0) <= 2 else { continue }

            guard let latest = evidence.last,
                  let age = calendar.dateComponents([.day], from: calendar.startOfDay(for: latest.at), to: today).day,
                  (0...40).contains(age) else { continue }
            let parts = calendar.dateComponents([.year, .month], from: latest.at)
            guard let year = parts.year, let month = parts.month,
                  let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let nextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfMonth) else { continue }
            let nextParts = calendar.dateComponents([.year, .month], from: nextMonth)
            guard
                  let nextYear = nextParts.year, let nextMonthNumber = nextParts.month,
                  let nextDue = calendar.date(from: DateComponents(year: nextYear, month: nextMonthNumber, day: days[1])),
                  calendar.startOfDay(for: nextDue) >= today else { continue }

            let minor = evidence[0].amountMinor
            let identity = BankDedupe.fingerprint(sender: key.merchant + key.currency, text: key.payment + ":" + String(minor))
            let displayName = [latest.merchant, latest.counterparty].compactMap({ $0 })
                .first(where: { !BankDedupe.normalize($0).isEmpty }) ?? key.merchant
            result.append(.init(id: identity, name: displayName, amountMinor: minor,
                                currency: key.currency, evidenceDates: evidence.map(\.at), nextDue: nextDue))
        }

        return result.sorted {
            if $0.nextDue != $1.nextDue { return $0.nextDue < $1.nextDue }
            return BankDedupe.normalize($0.name) < BankDedupe.normalize($1.name)
        }
    }
}
