import Foundation

/// Phase 3: Tamara/Tabby plans as a sequence of instalments, derived from the dues they announced and the instalments paid.
/// The count and remaining figures are only what the messages printed; nothing is inferred.
public enum InstalmentPlans {
    public struct Event: Equatable, Sendable {
        public var id: String
        public var provider: String
        public var merchant: String?
        public var currency: String
        public var amountMinor: Int
        /// The due date for an open due, the payment time for a paid instalment.
        public var at: Date
        public var isPaid: Bool
        /// «القسط ٢ من ٤» as printed.
        public var number: Int?
        public var count: Int?
        /// «المتبقي» as printed after this instalment.
        public var remainingMinor: Int?
        public init(id: String, provider: String, merchant: String?, currency: String, amountMinor: Int, at: Date, isPaid: Bool,
                    number: Int? = nil, count: Int? = nil, remainingMinor: Int? = nil) {
            self.id = id; self.provider = provider; self.merchant = merchant; self.currency = currency; self.amountMinor = amountMinor
            self.at = at; self.isPaid = isPaid; self.number = number; self.count = count; self.remainingMinor = remainingMinor
        }
    }

    public struct Plan: Equatable, Sendable, Identifiable {
        public var id: String
        public var provider: String
        public var merchant: String?
        public var currency: String
        public var paidCount: Int
        public var paidMinor: Int
        public var openCount: Int
        public var nextDueAt: Date?
        public var nextAmountMinor: Int?
        /// Instalments in the plan, only when a message printed it.
        public var printedCount: Int?
        public var remainingCount: Int?
        /// The remaining balance as the newest message that printed one stated it.
        public var remainingMinor: Int?
    }

    public static func derive(_ events: [Event]) -> [Plan] {
        var base: [String: [Event]] = [:]
        for event in events {
            let key = BankDedupe.normalize(event.provider) + "|" + MerchantKey.key(event.merchant) + "|" + event.currency.uppercased()
            base[key, default: []].append(event)
        }
        var groups: [String: [Event]] = [:]
        for (key, rows) in base {
            let split = splitPlans(rows)
            if split.count == 1 { groups[key] = split[0].rows } else { for plan in split { groups[key + "|" + plan.tag] = plan.rows } }
        }
        return groups.map { id, rows in
            let paid = rows.filter(\.isPaid), open = rows.filter { !$0.isPaid }.sorted { ($0.at, $0.id) < ($1.at, $1.id) }
            let printed = rows.compactMap(\.count).max()
            let paidCount = max(paid.count, paid.compactMap(\.number).max() ?? 0)
            let newestRemaining = rows.filter { $0.remainingMinor != nil }.max { ($0.at, $0.id) < ($1.at, $1.id) }?.remainingMinor
            let next = open.first
            return Plan(id: id, provider: rows[0].provider, merchant: rows.compactMap(\.merchant).first, currency: rows[0].currency.uppercased(),
                        paidCount: paidCount, paidMinor: paid.reduce(0) { $0 &+ $1.amountMinor }, openCount: open.count, nextDueAt: next?.at,
                        nextAmountMinor: next?.amountMinor, printedCount: printed, remainingCount: printed.map { max(0, $0 - paidCount) },
                        remainingMinor: newestRemaining)
        }.sorted { l, r in
            switch (l.nextDueAt, r.nextDueAt) {
            case let (a?, b?) where a != b: return a < b
            case (nil, _?): return false
            case (_?, nil): return true
            default: return l.id < r.id
            }
        }
    }

    /// D4 (owner, 11 Nov 2026): two plans at one merchant and provider are told apart by the printed instalment count and the instalment
    /// amount. Amounts within count − 1 minor units are one plan (a total that does not divide evenly puts the remainder on one instalment).
    /// An instalment with no printed count joins the one plan of its amount; when none or several fit, the uncounted rows stay together.
    private static func splitPlans(_ rows: [Event]) -> [(tag: String, rows: [Event])] {
        var plans: [(count: Int, amount: Int, rows: [Event])] = []
        for event in rows.filter({ $0.count != nil }).sorted(by: { ($0.count!, $0.amountMinor, $0.at, $0.id) < ($1.count!, $1.amountMinor, $1.at, $1.id) }) {
            let count = event.count!
            if let i = plans.firstIndex(where: { $0.count == count && abs($0.amount - event.amountMinor) < max(1, count) }) { plans[i].rows.append(event) }
            else { plans.append((count, event.amountMinor, [event])) }
        }
        var uncounted: [Event] = []
        for event in rows where event.count == nil {
            let fits = plans.indices.filter { abs(plans[$0].amount - event.amountMinor) < max(1, plans[$0].count) }
            if fits.count == 1 { plans[fits[0]].rows.append(event) } else { uncounted.append(event) }
        }
        var result = plans.map { (tag: "n\($0.count)|\($0.amount)", rows: $0.rows) }
        if !uncounted.isEmpty { result.append((tag: "uncounted", rows: uncounted)) }
        return result
    }
}
