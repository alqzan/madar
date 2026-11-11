import Foundation

// Owner decisions, 11 Nov 2026: what a bank message teaches Madar beyond the movement itself. Pure; the commands and the
// money room share these rules. Nothing here is recorded automatically — every message still waits in the review queue.

// MARK: - Continuous balance matching

/// A balance printed by a bank message for a tracked account, set against Madar's own book at that moment.
/// Derived on every read and never stored: it disappears when the book catches up, when the owner settles it, or when a
/// later message prints a newer balance.
public enum BalanceMatching {
    public struct Reading: Equatable, Sendable {
        public enum Status: String, Sendable {
            /// The book is final for that moment and differs from the bank: the room shows one quiet row with «سمّ الفرق».
            case open
            /// Unreviewed drafts of this account are still unconfirmed, so the book is not final yet. Not a mismatch.
            case waitingForReview
        }
        public var accountKey: String
        public var messageKey: String
        /// The time the message printed the balance (its printed time, else the time it arrived).
        public var at: Date
        /// Madar's confirmed book at `at` — the same number `money.reconcile` recomputes and compares.
        public var expectedMinor: Int
        public var observedMinor: Int
        /// Net effect and count of unconfirmed drafts of the account up to `at`.
        public var pendingMinor: Int
        public var pendingCount: Int
        public var status: Status
        /// observed − expected, as `Reconciliation.deltaMinor`.
        public var differenceMinor: Int { observedMinor - expectedMinor }
        /// The line the existing reconcile engine names and settles; one definition of the difference.
        public var line: ReconcileLine { .init(side: .account, expectedMinor: expectedMinor, observedMinor: observedMinor) }
        /// `money.reconcile` refuses a negative observed balance, so an overdrawn balance cannot be settled through it.
        public var isSettleable: Bool { status == .open && observedMinor >= 0 && differenceMinor != 0 }
        public var names: [ReconcileName] { status == .open ? ReconcileEngine.names(for: line) : [] }
    }

    /// nil when there is nothing to show: the books agree, the drafts explain the difference, or the owner already settled this
    /// account at or after the printed moment (`lastSettlementAt`: the newest live `Reconciliation.at` of the account).
    public static func reading(accountKey: String, messageKey: String, at: Date, observedMinor: Int, bookMinor: Int,
                               pendingNetMinor: Int, pendingCount: Int, lastSettlementAt: Date?) -> Reading? {
        if let lastSettlementAt, lastSettlementAt >= at { return nil }
        if observedMinor == bookMinor { return nil }
        if pendingCount > 0, observedMinor == bookMinor + pendingNetMinor { return nil }
        return .init(accountKey: accountKey, messageKey: messageKey, at: at, expectedMinor: bookMinor, observedMinor: observedMinor,
                     pendingMinor: pendingNetMinor, pendingCount: pendingCount, status: pendingCount > 0 ? .waitingForReview : .open)
    }

    /// Bulk pastes arrive out of order: a stored balance is replaced only by a message printed later than it.
    public static func replaces(storedAt: Date?, with printedAt: Date) -> Bool {
        guard let storedAt else { return true }
        return printedAt > storedAt
    }
}

// MARK: - Own-account transfer pairing (outgoing leg + incoming deposit)

/// One side of a transfer as a bank message told it. `fromAccountID` / `toAccountID` are the tracked own accounts the message's
/// tails (or a tracked wallet's name) identified; nil when the message did not identify that side.
public struct OwnTransferLeg: Equatable, Sendable {
    public enum Direction: Sendable { case out, `in` }
    public var id: String
    public var direction: Direction
    public var amountMinor: Int
    public var currency: String
    public var at: Date
    public var fromAccountID: String?
    public var toAccountID: String?
    public init(id: String, direction: Direction, amountMinor: Int, currency: String, at: Date, fromAccountID: String?, toAccountID: String?) {
        self.id = id; self.direction = direction; self.amountMinor = amountMinor; self.currency = currency; self.at = at
        self.fromAccountID = fromAccountID; self.toAccountID = toAccountID
    }
}

/// An outgoing transfer or top-up from one tracked account and the deposit message of another tracked account are one own-accounts
/// transfer: neutral, not an expense plus an income. Covers a bank → stc pay top-up and a share trade with a tracked
/// «Alinma Investment» wallet. Subsumes the old `TransferPairing` (both sides still unidentified on the far side).
public enum OwnTransferPairing {
    /// Two bank SMS of one transfer print their own clock times and arrive minutes apart. When a printed tail already names the
    /// other side (the outgoing leg's destination or the deposit's source), tail + amount + currency is strong evidence, so
    /// 30 minutes absorbs a delayed deposit message without ever pairing separate days. When neither tail names the other side the
    /// evidence is only «same amount, opposite sides», so it keeps `TransferPairing`'s 10 minutes (RM8's near-duplicate window).
    public static let strongWindowSeconds: TimeInterval = 30 * 60
    public static let weakWindowSeconds: TimeInterval = TransferPairing.windowSeconds

    public static func pairs(_ legs: [OwnTransferLeg]) -> [(out: String, in: String)] {
        var used = Set<String>(), result: [(out: String, in: String)] = []
        let outs = legs.filter { $0.direction == .out && $0.fromAccountID != nil }.sorted { ($0.at, $0.id) < ($1.at, $1.id) }
        for out in outs {
            let candidates = legs.filter { leg in
                guard leg.direction == .in, let destination = leg.toAccountID, !used.contains(leg.id), !used.contains(out.id),
                      leg.amountMinor == out.amountMinor, leg.currency == out.currency, destination != out.fromAccountID else { return false }
                if let target = out.toAccountID, target != destination { return false }
                if let source = leg.fromAccountID, source != out.fromAccountID { return false }
                let strong = out.toAccountID != nil || leg.fromAccountID != nil
                return abs(leg.at.timeIntervalSince(out.at)) <= (strong ? strongWindowSeconds : weakWindowSeconds)
            }
            if let match = candidates.min(by: { (abs($0.at.timeIntervalSince(out.at)), $0.id) < (abs($1.at.timeIntervalSince(out.at)), $1.id) }) {
                used.insert(match.id); used.insert(out.id); result.append((out.id, match.id))
            }
        }
        return result
    }
}

// MARK: - Unknown card tail

/// «بطاقة جديدة — لأي حساب تتبع؟»: a message names a tail that matches no tracked account or card. Asked once per (bank, tail), however
/// many messages carry it; answering stores the tail on the chosen account or card.
public enum UnknownTailQuestions {
    public struct Item: Equatable, Sendable {
        public var messageKey: String
        public var sender: String
        public var tail: String
        public var at: Date
        /// Ids of the tracked accounts and cards the owner may choose from (same bank first).
        public var candidateKeys: [String]
        public init(messageKey: String, sender: String, tail: String, at: Date, candidateKeys: [String]) {
            self.messageKey = messageKey; self.sender = sender; self.tail = tail; self.at = at; self.candidateKeys = candidateKeys
        }
    }
    public struct Question: Equatable, Sendable {
        public var tail: String
        public var sender: String
        public var messageKeys: [String]
        public var candidateKeys: [String]
        public var latestAt: Date
    }

    public static func group(_ items: [Item]) -> [Question] {
        var order: [String] = [], grouped: [String: [Item]] = [:]
        for item in items.sorted(by: { ($0.at, $0.messageKey) > ($1.at, $1.messageKey) }) {
            let key = BankDedupe.normalize(item.sender) + "|" + item.tail
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(item)
        }
        return order.compactMap { key in
            guard let first = grouped[key]?.first, let all = grouped[key] else { return nil }
            return Question(tail: first.tail, sender: first.sender, messageKeys: all.map(\.messageKey), candidateKeys: first.candidateKeys, latestAt: first.at)
        }
    }
}

// MARK: - Upcoming dues

/// A bill issued or a Tamara/Tabby reminder is an announcement, never an expense. It is listed until a later payment to the same
/// payee for the same amount closes it.
public enum UpcomingDues {
    public struct Due: Equatable, Sendable {
        public var id: String
        public var payee: String
        public var amountMinor: Int
        public var currency: String
        public var dueAt: Date?
        /// When the announcing message arrived (its printed time, else its receive time).
        public var announcedAt: Date
        /// The payment that closed it, only while that payment is still live.
        public var closedBy: String?
        /// A credit-card statement: closed by a card payment of at least its amount, never by a bill payment.
        public var isStatement: Bool
        /// The card tail a statement names; when both sides name one they must agree.
        public var tail: String?
        public init(id: String, payee: String, amountMinor: Int, currency: String, dueAt: Date?, announcedAt: Date, closedBy: String? = nil,
                    isStatement: Bool = false, tail: String? = nil) {
            self.id = id; self.payee = payee; self.amountMinor = amountMinor; self.currency = currency; self.dueAt = dueAt
            self.announcedAt = announcedAt; self.closedBy = closedBy; self.isStatement = isStatement; self.tail = tail
        }
    }
    public struct Payment: Equatable, Sendable {
        public var id: String
        /// Every name the payment message gives the payee: biller, provider, merchant, sender.
        public var payees: [String]
        public var amountMinor: Int
        public var currency: String
        public var at: Date
        public var isCardPayment: Bool
        public var tail: String?
        public init(id: String, payees: [String], amountMinor: Int, currency: String, at: Date, isCardPayment: Bool = false, tail: String? = nil) {
            self.id = id; self.payees = payees; self.amountMinor = amountMinor; self.currency = currency; self.at = at
            self.isCardPayment = isCardPayment; self.tail = tail
        }
    }

    /// A payment after the due date still settles it for a while (a late SADAD payment); long after, it is a different payment.
    public static let lateGraceSeconds: TimeInterval = 14 * 86_400
    /// A notice with no printed due date can be paid for this long after it arrived.
    public static let undatedWindowSeconds: TimeInterval = 45 * 86_400

    /// Natural key text of a due. A repeated reminder of one payment (Tamara: «خلال يومين», then «غدًا», then «اليوم») names one due day.
    public static func naturalKey(payee: String, amountMinor: Int, currency: String, dueDayKey: String?, instalmentNumber: Int? = nil) -> String {
        // An undated due (D5) carries the printed instalment number, so instalments 2 and 3 of one amount pasted together stay two dues.
        // Dated keys are unchanged: stored dues keep their identity.
        "UpcomingDue:" + BankDedupe.normalize(payee) + ":" + String(amountMinor) + ":" + currency + ":" + (dueDayKey ?? "none")
            + (dueDayKey == nil ? instalmentNumber.map { ":n\($0)" } ?? "" : "")
    }

    public static func samePayee(_ lhs: String, _ rhs: String) -> Bool {
        let a = BankDedupe.normalize(lhs), b = BankDedupe.normalize(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        if min(a.count, b.count) >= 3, a.contains(b) || b.contains(a) { return true }
        return BankMessageIdentity.matches(lhs, rhs)
    }

    public static func isOpen(_ due: Due) -> Bool { due.closedBy == nil }

    /// Open dues first by due date (undated last), then by amount, then id — a stable list.
    public static func sorted(_ dues: [Due]) -> [Due] {
        dues.sorted { l, r in
            switch (l.dueAt, r.dueAt) {
            case let (a?, b?) where a != b: return a < b
            case (nil, _?): return false
            case (_?, nil): return true
            default: return (l.amountMinor, l.id) < (r.amountMinor, r.id)
            }
        }
    }

    /// Which open due each payment closes: same payee, same currency and amount, a payment later than the notice and inside the window;
    /// the earliest due date first, each payment and each due once.
    public static func closures(open: [Due], payments: [Payment]) -> [(due: String, payment: String)] {
        var taken = Set<String>(), result: [(due: String, payment: String)] = []
        let ordered = sorted(open.filter(isOpen))
        for payment in payments.sorted(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
            let match = ordered.first { due in
                guard !taken.contains(due.id), due.currency == payment.currency,
                      payment.at >= due.announcedAt, payment.payees.contains(where: { samePayee($0, due.payee) }) else { return false }
                // A statement is paid by a card payment of at least its amount (a minimum or partial payment leaves it open); every other due by
                // an exact bill or instalment payment.
                if due.isStatement {
                    guard payment.isCardPayment, payment.amountMinor >= due.amountMinor else { return false }
                    if let a = due.tail, let b = payment.tail, a != b { return false }
                } else {
                    guard !payment.isCardPayment, due.amountMinor == payment.amountMinor else { return false }
                }
                let deadline = (due.dueAt.map { $0.addingTimeInterval(lateGraceSeconds) }) ?? due.announcedAt.addingTimeInterval(undatedWindowSeconds)
                return payment.at <= deadline
            }
            if let match { taken.insert(match.id); result.append((match.id, payment.id)) }
        }
        return result
    }
}
