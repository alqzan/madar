import Foundation

/// Phase 3: a refund or reversal message nets the purchase it undoes instead of standing alone. Pure; the room links the draft with
/// `relatedTransactionID`, which the existing confirm path then validates (confirmed expense, same currency, same card).
public enum RefundMatching {
    public struct Refund: Equatable, Sendable {
        public var merchant: String?
        public var cardKey: String?
        public var accountKey: String?
        public var currency: String
        public var amountMinor: Int
        public var at: Date
        public init(merchant: String?, cardKey: String?, accountKey: String?, currency: String, amountMinor: Int, at: Date) {
            self.merchant = merchant; self.cardKey = cardKey; self.accountKey = accountKey
            self.currency = currency; self.amountMinor = amountMinor; self.at = at
        }
    }
    public struct Original: Equatable, Sendable {
        public var id: String
        public var merchant: String?
        public var cardKey: String?
        public var accountKey: String?
        public var currency: String
        public var amountMinor: Int
        /// Refunds already linked to this purchase.
        public var refundedMinor: Int
        public var at: Date
        public init(id: String, merchant: String?, cardKey: String?, accountKey: String?, currency: String, amountMinor: Int, refundedMinor: Int, at: Date) {
            self.id = id; self.merchant = merchant; self.cardKey = cardKey; self.accountKey = accountKey
            self.currency = currency; self.amountMinor = amountMinor; self.refundedMinor = refundedMinor; self.at = at
        }
    }

    /// Stores refund within this many days of the purchase (a long return window).
    public static let windowDays = 90

    /// Purchases the refund could undo, best first: an exact remaining amount before a larger one, then the closest in time.
    public static func candidates(for refund: Refund, among originals: [Original]) -> [Original] {
        let window = TimeInterval(windowDays) * 86_400
        let eligible = originals.filter { original in
            guard MerchantKey.matches(original.merchant, refund.merchant),
                  original.currency.uppercased() == refund.currency.uppercased(),
                  original.cardKey == refund.cardKey,
                  original.at <= refund.at, refund.at.timeIntervalSince(original.at) <= window,
                  original.amountMinor - original.refundedMinor >= refund.amountMinor, refund.amountMinor > 0 else { return false }
            if let a = original.accountKey, let b = refund.accountKey, a != b { return false }
            return true
        }
        return eligible.sorted { l, r in
            let le = l.amountMinor - l.refundedMinor == refund.amountMinor, re = r.amountMinor - r.refundedMinor == refund.amountMinor
            if le != re { return le }
            if l.at != r.at { return l.at > r.at }
            return l.id < r.id
        }
    }

    /// The one purchase to link automatically, or nil when it is ambiguous: a single exact-amount candidate, else a single candidate.
    public static func match(_ refund: Refund, among originals: [Original]) -> String? {
        let list = candidates(for: refund, among: originals)
        let exact = list.filter { $0.amountMinor - $0.refundedMinor == refund.amountMinor }
        if exact.count == 1 { return exact[0].id }
        if exact.isEmpty, list.count == 1 { return list[0].id }
        return nil
    }
}

/// Fees, VAT and the foreign-currency fee a bank message printed beside a movement. Never part of the movement amount.
public struct ChargeBreakdown: Equatable, Sendable {
    public var feeMinor: Int
    public var vatMinor: Int
    public var foreignFeeMinor: Int
    public init(feeMinor: Int = 0, vatMinor: Int = 0, foreignFeeMinor: Int = 0) {
        self.feeMinor = max(0, feeMinor); self.vatMinor = max(0, vatMinor); self.foreignFeeMinor = max(0, foreignFeeMinor)
    }
    public var totalMinor: Int {
        let sum = feeMinor.addingReportingOverflow(vatMinor)
        let all = sum.partialValue.addingReportingOverflow(foreignFeeMinor)
        return sum.overflow || all.overflow ? Int.max : all.partialValue
    }
    public var isEmpty: Bool { feeMinor == 0 && vatMinor == 0 && foreignFeeMinor == 0 }
    public static func + (l: ChargeBreakdown, r: ChargeBreakdown) -> ChargeBreakdown {
        func add(_ a: Int, _ b: Int) -> Int { let s = a.addingReportingOverflow(b); return s.overflow ? Int.max : s.partialValue }
        return .init(feeMinor: add(l.feeMinor, r.feeMinor), vatMinor: add(l.vatMinor, r.vatMinor), foreignFeeMinor: add(l.foreignFeeMinor, r.foreignFeeMinor))
    }
}
