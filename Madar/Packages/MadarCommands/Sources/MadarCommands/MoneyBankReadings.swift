import Foundation
import SwiftData
import MadarData
import MadarMoney

/// Owner, 11 Nov 2026: what bank messages teach the money room besides movements — quiet balance mismatches, a new-card question,
/// upcoming dues and paired own-account transfers. All derived on read from stored rows; nothing here writes.
public extension MoneyRepository {
    struct BalanceMismatch: Equatable, Sendable {
        public var accountID: UUID
        public var accountName: String
        public var messageID: UUID?
        public var reading: BalanceMatching.Reading
        /// Settle with `money.reconcile`, `rows: [{accountID, expectedMinor: reading.expectedMinor, observedMinor: reading.observedMinor,
        /// at: <reading.at as ISO 8601>, name?}]` — the same command and rule as «المطابقة مع البنك».
        public var isSettleable: Bool { reading.isSettleable }
    }

    /// One row per tracked account whose latest printed balance differs from the confirmed book at that moment. `.waitingForReview`
    /// readings are returned too (the UI may hide them); only `.open` ones are settleable. Never notifies.
    func balanceMismatches(at now: Date = .now) throws -> [BalanceMismatch] {
        let home = try SettingsStore(context: context).value(for: "core.currency").string ?? "SAR"
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { ($0.deletedAt == nil && $0.mergedInto == nil) && $0.ownership == "mine" && $0.tracked && $0.currency == home }
        let readings = try context.fetch(FetchDescriptor<BankReading>()).filter { ($0.deletedAt == nil && $0.mergedInto == nil) && $0.accountID != nil && $0.balanceMinor != nil && $0.balanceAt != nil }
        let tracked = Set(readings.compactMap(\.accountID)).intersection(accounts.map(\.id))
        guard !tracked.isEmpty else { return [] }
        // Only the movements of the accounts that printed a balance, not the whole ledger.
        let ids: [UUID?] = tracked.map { Optional($0) }
        var touching: [UUID: MoneyTransaction] = [:]
        for row in try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { ids.contains($0.fromAccountID) })) { touching[row.id] = row }
        for row in try context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { ids.contains($0.toAccountID) })) { touching[row.id] = row }
        let live = touching.values.filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let confirmed = live.filter { $0.reviewState == "ok" }, pending = live.filter { $0.reviewState != "ok" }
        let cards = try context.fetch(FetchDescriptor<Card>())
        let settlements = try context.fetch(FetchDescriptor<Reconciliation>()).filter { ($0.deletedAt == nil && $0.mergedInto == nil) && $0.accountID != nil }
        var result: [BalanceMismatch] = []
        for reading in readings {
            guard let account = accounts.first(where: { $0.id == reading.accountID }), let observed = reading.balanceMinor, let at = reading.balanceAt,
                  at <= now, at > (account.balanceAt ?? .distantFuture) else { continue }
            let book = try accountBalance(account, at: at, transactions: confirmed, cards: cards)
            let withPending = try accountBalance(account, at: at, transactions: confirmed + pending, cards: cards)
            let pendingRows = pending.filter { ($0.fromAccountID == account.id || $0.toAccountID == account.id) && $0.eventAt > (account.balanceAt ?? .distantPast) && $0.eventAt <= at }
            let settled = settlements.filter { $0.accountID == account.id }.map(\.at).max()
            guard let found = BalanceMatching.reading(accountKey: account.id.uuidString, messageKey: reading.balanceMessageID?.uuidString ?? "", at: at,
                observedMinor: observed, bookMinor: book, pendingNetMinor: withPending - book, pendingCount: pendingRows.count, lastSettlementAt: settled) else { continue }
            result.append(.init(accountID: account.id, accountName: account.name, messageID: reading.balanceMessageID, reading: found))
        }
        return result.sorted { ($0.reading.at, $0.accountID.uuidString) > ($1.reading.at, $1.accountID.uuidString) }
    }

    struct TailCandidate: Equatable, Sendable {
        public enum Kind: String, Sendable { case account, card }
        public var kind: Kind
        public var id: UUID
        public var name: String
        public var bank: String
    }
    struct UnknownTail: Equatable, Sendable {
        public var tail: String
        public var sender: String
        public var messageIDs: [UUID]
        /// Tracked accounts and cards of the same bank first, then the rest. Answer with
        /// `money.attachTail {tail, accountID | cardID, kind: "card" | "applePay" | "account", label?}`.
        public var candidates: [TailCandidate]
        public var latestAt: Date
    }

    /// «بطاقة جديدة — لأي حساب تتبع؟»: tails of unreviewed messages that match no tracked account or card (own tail, additional tails
    /// and the sender's bank all count). Once per (bank, tail); gone once the tail is attached.
    func unknownTails() throws -> [UnknownTail] {
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { ($0.deletedAt == nil && $0.mergedInto == nil) && $0.ownership == "mine" }
        let allAccounts = try context.fetch(FetchDescriptor<Account>()).filter { ($0.deletedAt == nil && $0.mergedInto == nil) }
        let cards = try context.fetch(FetchDescriptor<Card>()).filter { ($0.deletedAt == nil && $0.mergedInto == nil) }
        let extra = try MoneyAccountRules.liveTails(in: context)
        let candidates = accounts.filter(\.tracked).map { TailCandidate(kind: .account, id: $0.id, name: $0.name, bank: $0.bank) }
            + cards.map { TailCandidate(kind: .card, id: $0.id, name: $0.name, bank: $0.bank) }
        guard !candidates.isEmpty else { return [] }
        let skipped: Set<BankMessageKind> = [.marketing, .otp, .unknown, .declined, .statement]
        var items: [UnknownTailQuestions.Item] = []
        for message in try context.fetch(FetchDescriptor<BankMessage>()) where (message.deletedAt == nil && message.mergedInto == nil) && ["needsLook", "possibleDuplicate"].contains(message.status) {
            guard let bytes = message.parsedJSON, let fields = try? JSONDecoder().decode(MoneyParsedFields.self, from: bytes), !skipped.contains(fields.messageKind) else { continue }
            var checked = Set<String>()
            for tail in [fields.last4, fields.accountLast4].compactMap({ $0 }) where checked.insert(tail).inserted {
                var probe = fields; probe.last4 = tail; probe.accountLast4 = nil
                let known = MoneyMutationHandler.resolve(parsed: probe, sender: message.sender, accounts: allAccounts, cards: cards, extra: extra)
                guard known.card == nil, known.account == nil else { continue }
                let same = candidates.filter { BankMessageIdentity.matches($0.bank, message.sender) }
                let ordered = same + candidates.filter { c in !same.contains(c) }
                items.append(.init(messageKey: message.id.uuidString, sender: message.sender, tail: tail, at: fields.eventAt ?? message.receivedAt,
                                   candidateKeys: ordered.map { $0.kind.rawValue + ":" + $0.id.uuidString }))
            }
        }
        let byKey = Dictionary(candidates.map { ($0.kind.rawValue + ":" + $0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        return UnknownTailQuestions.group(items).map { q in
            .init(tail: q.tail, sender: q.sender, messageIDs: q.messageKeys.compactMap(UUID.init(uuidString:)),
                  candidates: q.candidateKeys.compactMap { byKey[$0] }, latestAt: q.latestAt)
        }
    }

    struct UpcomingDueRow: Equatable, Sendable {
        public var id: UUID
        public var payee: String
        public var kind: String
        public var amountMinor: Int
        public var currency: String
        public var dueAt: Date?
        public var sourceMessageID: UUID?
        /// The live payment that closed it, if any.
        public var closedByTransactionID: UUID?
        /// A credit-card statement (closed by a card payment of at least `amountMinor`); `payee` already carries the card tail.
        public var isStatement: Bool = false
        public var minimumDueMinor: Int?
        public var cardLast4: String?
        /// Tamara/Tabby: the merchant and «القسط ٢ من ٤» when the announcing message printed them.
        public var merchant: String?
        public var instalmentNumber: Int?
        public var instalmentCount: Int?
        public var remainingMinor: Int?
        public var isOpen: Bool { closedByTransactionID == nil }
    }

    /// Announced bills and BNPL reminders sorted by due date (undated last). A due whose closing payment was deleted is open again.
    /// Close one by hand-free means only: a later matching payment closes it at intake; `money.dismissDue {id}` removes one.
    func upcomingDues(includeClosed: Bool = false) throws -> [UpcomingDueRow] {
        let dues = try context.fetch(FetchDescriptor<UpcomingDue>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil }))
        let live = try liveTransactions(dues.compactMap(\.closedByTransactionID))
        let messages = try parsedMessages(dues.compactMap(\.sourceMessageID))
        let rows = dues.map { due -> UpcomingDueRow in
            let source = due.sourceMessageID.flatMap { messages[$0] }
            var row = UpcomingDueRow(id: due.id, payee: due.payee, kind: due.kind, amountMinor: due.amountMinor, currency: due.currency, dueAt: due.dueAt,
                           sourceMessageID: due.sourceMessageID, closedByTransactionID: due.closedByTransactionID.flatMap { live[$0] == nil ? nil : $0 })
            row.isStatement = source?.message.kind == BankMessageKind.statement.rawValue
            row.minimumDueMinor = row.isStatement ? source?.fields?.minimumDueMinor : nil
            row.cardLast4 = row.isStatement ? source?.fields?.last4 : nil
            row.merchant = source?.fields?.merchant
            row.instalmentNumber = source?.fields?.instalmentNumber; row.instalmentCount = source?.fields?.instalmentCount
            row.remainingMinor = source?.fields?.remainingMinor
            return row
        }
        let shown = includeClosed ? rows : rows.filter(\.isOpen)
        let order = UpcomingDues.sorted(shown.map { .init(id: $0.id.uuidString, payee: $0.payee, amountMinor: $0.amountMinor, currency: $0.currency, dueAt: $0.dueAt, announcedAt: .distantPast) }).map(\.id)
        let byID = Dictionary(shown.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        return order.compactMap { byID[$0] }
    }

    struct PairedTransfer: Equatable, Sendable {
        public var outgoingID: UUID
        public var incomingID: UUID
        public var fromAccountID: UUID?
        public var toAccountID: UUID?
        public var amountMinor: Int
        public var currency: String
        public var at: Date
    }

    /// Own-account transfers made of an outgoing message and a deposit message: one neutral movement (the deposit row is folded into the
    /// outgoing one, `mergedInto`). Lets the room say «حوّلتَ ١٠٠ من الراجحي إلى stc pay» once.
    func pairedTransfers() throws -> [PairedTransfer] {
        let all = try context.fetch(FetchDescriptor<MoneyTransaction>())
        let outgoing = Dictionary(all.filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.kind == "transfer" }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return all.compactMap { row in
            guard row.deletedAt == nil, let target = row.mergedInto, ["transfer", "income"].contains(row.kind), let out = outgoing[target],
                  out.fromAccountID != nil, out.toAccountID != nil else { return nil }
            return PairedTransfer(outgoingID: out.id, incomingID: row.id, fromAccountID: out.fromAccountID, toAccountID: out.toAccountID,
                                  amountMinor: out.amountMinor, currency: out.currency, at: out.eventAt)
        }.sorted { ($0.at, $0.outgoingID.uuidString) > ($1.at, $1.outgoingID.uuidString) }
    }
}
