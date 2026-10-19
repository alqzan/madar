/// M5-V16 «الاسترداد النقدي · الجرّة» (§7.5, F07): one definition per number, all read-only.
///
/// - Purchase base of a card in a month = its confirmed purchases that month − the refunds linked to them (a refund
///   lands on its original's month), never below zero. Fees, card payments and cashback rows earn nothing; a purchase
///   ignored from the budgets still earns.
/// - Earned of a card in a month = the recorded `CashbackEntry` earned rows of that month when there are any, otherwise
///   `CardPlanning.cashbackEstimate(base, rate)` rounded once on the month's base. Never both. Unknown rate and no
///   recorded row → unknown (nil), never zero.
/// - Landed (نزل) = the cashback that reached an account or a card: confirmed cashback movements plus redeemed rows that
///   carry no movement. A redeemed row linked to its movement is that movement, counted once.
/// - Accumulating (يتجمّع) = max(0, earned − landed); headline = landed + accumulating.
/// - Year end (المنقّط) = the complete months so far + their average × the months left (the current one included),
///   averaged over the complete months since the first month with card data; only after three such months, and never
///   below what is already earned.
public enum CashbackJar {
    public struct Card: Equatable, Sendable {
        public var id: String
        public var rateBp: Int?
        public init(id: String, rateBp: Int?) { self.id = id; self.rateBp = rateBp }
    }
    /// A purchase (positive) or a refund linked to one (negative), already placed on its month (0-based in the year).
    public struct Purchase: Equatable, Sendable {
        public var cardID: String
        public var month: Int
        public var amountMinor: Int
        public var category: String?
        public var categoryID: String?
        public init(cardID: String, month: Int, amountMinor: Int, category: String? = nil, categoryID: String? = nil) {
            self.cardID = cardID; self.month = month; self.amountMinor = amountMinor; self.category = category; self.categoryID = categoryID
        }
    }
    public struct Recorded: Equatable, Sendable {
        public var cardID: String
        public var month: Int
        public var amountMinor: Int
        public init(cardID: String, month: Int, amountMinor: Int) { self.cardID = cardID; self.month = month; self.amountMinor = amountMinor }
    }
    public struct Landed: Equatable, Sendable {
        public var cardID: String?
        public var amountMinor: Int
        public init(cardID: String?, amountMinor: Int) { self.cardID = cardID; self.amountMinor = amountMinor }
    }
    public struct Input: Sendable {
        public var cards: [Card]
        public var months: Int
        public var current: Int
        public var purchases: [Purchase]
        public var earned: [Recorded]
        public var landed: [Landed]
        public init(cards: [Card], months: Int = 12, current: Int, purchases: [Purchase], earned: [Recorded] = [], landed: [Landed] = []) {
            self.cards = cards; self.months = months; self.current = current; self.purchases = purchases; self.earned = earned; self.landed = landed
        }
    }
    public struct CardTotal: Equatable, Sendable {
        public var id: String
        /// Month by month up to the current one; nil where the rate is unknown and nothing was recorded.
        public var monthly: [Int?]
        public var landedMinor: Int
        /// Some purchase this year could not be valued (unknown rate, nothing recorded).
        public var unknown: Bool
        public var earnedMinor: Int? { unknown && monthly.allSatisfy { $0 == nil || $0 == 0 } ? nil : monthly.reduce(0) { $0 + ($1 ?? 0) } }
    }
    public struct Reading: Equatable, Sendable {
        public var cards: [CardTotal]
        public var monthTotals: [Int]
        public var earnedMinor: Int
        public var landedMinor: Int
        public var accumulatingMinor: Int { max(0, earnedMinor - landedMinor) }
        public var headlineMinor: Int { landedMinor + accumulatingMinor }
        public var yearEndMinor: Int?
        /// Cards with purchases this year that could not be valued.
        public var unknownCards: [String] { cards.filter(\.unknown).map(\.id) }
    }

    /// Overflow-checked sums and products; an impossible amount gives no reading rather than a wrong one.
    static func total(_ values: [Int]) -> Int? {
        var result = 0
        for value in values { let next = result.addingReportingOverflow(value); guard !next.overflow else { return nil }; result = next.partialValue }
        return result
    }
    static func product(_ a: Int, _ b: Int) -> Int? { let r = a.multipliedReportingOverflow(by: b); return r.overflow ? nil : r.partialValue }

    public static func read(_ input: Input) -> Reading? {
        guard input.months > 0, (0..<input.months).contains(input.current) else { return nil }
        let span = input.current + 1
        var totals: [CardTotal] = []
        for card in input.cards {
            var monthly: [Int?] = Array(repeating: 0, count: span), unknown = false
            for month in 0..<span {
                let recorded = input.earned.filter { $0.cardID == card.id && $0.month == month }
                if !recorded.isEmpty {
                    guard let sum = total(recorded.map { max(0, $0.amountMinor) }) else { return nil }
                    monthly[month] = sum; continue
                }
                guard let net = total(input.purchases.filter { $0.cardID == card.id && $0.month == month }.map(\.amountMinor)) else { return nil }
                let base = max(0, net)
                if base == 0 { monthly[month] = 0; continue }
                if let value = CardPlanning.cashbackEstimate(purchaseMinor: base, rateBp: card.rateBp) { monthly[month] = value }
                else if card.rateBp == nil { monthly[month] = nil; unknown = true }
                else { return nil }
            }
            guard let landed = total(input.landed.filter { $0.cardID == card.id }.map { max(0, $0.amountMinor) }) else { return nil }
            totals.append(.init(id: card.id, monthly: monthly, landedMinor: landed, unknown: unknown))
        }
        var monthTotals: [Int] = []
        for month in 0..<span {
            guard let sum = total(totals.map { $0.monthly[month] ?? 0 }) else { return nil }
            monthTotals.append(sum)
        }
        guard let earned = total(monthTotals), let landed = total(input.landed.map { max(0, $0.amountMinor) }) else { return nil }
        // The year end: complete months since the first month that has any card data.
        let hasData = (0..<span).map { month in
            input.purchases.contains { $0.month == month && $0.amountMinor != 0 } || input.earned.contains { $0.month == month }
        }
        var yearEnd: Int?
        if let first = hasData.firstIndex(of: true), input.current - first >= 3 {
            let complete = Array(monthTotals[first..<input.current])
            if let sum = total(complete), let average = CardPlanning.rateAmount(sum, numerator: 1, denominator: complete.count),
               let before = total(Array(monthTotals[0..<input.current])),
               let rest = product(average, input.months - input.current), let projected = total([before, rest]) {
                yearEnd = max(projected, earned)
            }
        }
        return .init(cards: totals, monthTotals: monthTotals, earnedMinor: earned, landedMinor: landed, yearEndMinor: yearEnd)
    }

    /// «أي بطاقة أستخدم؟ أعلى استرداد» (§7.5): what the purchases already made on lower-rate cards would have earned
    /// more on the highest-rate card, by category, this year. Only cards with a known rate take part; nothing is assumed
    /// about a bank's category exclusions or caps.
    public struct Switch: Equatable, Sendable {
        public var category: String?
        public var categoryID: String?
        public var baseMinor: Int
        public var gainMinor: Int
    }
    public struct SwitchReading: Equatable, Sendable {
        public var toCardID: String
        public var rows: [Switch]
        public var totalGainMinor: Int
    }
    public static func switchToBest(cards: [Card], purchases: [Purchase]) -> SwitchReading? {
        let known = cards.filter { $0.rateBp != nil }
        guard let best = known.max(by: { ($0.rateBp ?? 0, $1.id) < ($1.rateBp ?? 0, $0.id) }), let top = best.rateBp else { return nil }
        // Grouped by (category, card), rounded once per group, then summed per category.
        var groups: [String: (categoryID: String?, category: String?, card: Card, base: Int)] = [:]
        for purchase in purchases {
            guard let card = known.first(where: { $0.id == purchase.cardID }), let rate = card.rateBp, rate < top else { continue }
            let categoryKey = purchase.categoryID.map { "id:" + $0 } ?? purchase.category.map { "name:" + $0 } ?? "uncategorised"
            let key = categoryKey + "|" + card.id
            let previous = groups[key]?.base ?? 0
            guard let next = total([previous, purchase.amountMinor]) else { return nil }
            groups[key] = (purchase.categoryID, purchase.category, card, next)
        }
        var byCategory: [String: Switch] = [:]
        for group in groups.values {
            let base = max(0, group.base)
            guard base > 0, let gain = CardPlanning.rateAmount(base, numerator: top - (group.card.rateBp ?? 0), denominator: 10_000) else { continue }
            let key = group.categoryID.map { "id:" + $0 } ?? group.category.map { "name:" + $0 } ?? "uncategorised"
            var row = byCategory[key] ?? .init(category: group.category, categoryID: group.categoryID, baseMinor: 0, gainMinor: 0)
            guard let b = total([row.baseMinor, base]), let g = total([row.gainMinor, gain]) else { return nil }
            row.baseMinor = b; row.gainMinor = g; byCategory[key] = row
        }
        let rows = byCategory.values.filter { $0.gainMinor > 0 }.sorted {
            $0.gainMinor != $1.gainMinor ? $0.gainMinor > $1.gainMinor
                : ($0.category ?? "") != ($1.category ?? "") ? ($0.category ?? "") < ($1.category ?? "")
                : ($0.categoryID ?? "") < ($1.categoryID ?? "")
        }
        guard !rows.isEmpty, let sum = total(rows.map(\.gainMinor)) else { return nil }
        return .init(toCardID: best.id, rows: rows, totalGainMinor: sum)
    }
}
