import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney

/// M5-V19 / RM5: the account rules the intake, `money.saveAccount`, `money.removeAccount` and «الحسابات» share.
@MainActor public enum MoneyAccountRules {
    /// RM5: a message belongs to an account when its sender is the account's bank (or one of its sender names) and the
    /// message names the account's last 4 digits.
    /// `extraTails`: the account's additional tails (`AccountTail`, owner 11 Nov 2026) — an Apple Pay device tail, a replacement card.
    nonisolated public static func matches(_ account: Account, sender: String, last4: String?, extraTails: Set<String> = []) -> Bool {
        guard let last4, account.last4 == last4 || extraTails.contains(last4) else { return false }
        return BankMessageIdentity.matches(account.bank, sender) || account.senderIDs.contains { BankMessageIdentity.matches($0, sender) }
    }

    /// A movement, including an undoable tombstone, refers to the account, directly or through a card linked to it. Its opening balance, currency,
    /// ownership, tracking and kind are then fixed: changing them would rewrite numbers already shown; reconciliation
    /// owns later corrections.
    public static func hasMovements(_ id: UUID, in context: ModelContext) throws -> Bool {
        if try context.fetch(FetchDescriptor<Reconciliation>()).contains(where: { $0.accountID == id }) { return true }
        let cards = Set(try context.fetch(FetchDescriptor<Card>()).filter { $0.accountID == id }.map(\.id))
        return try context.fetch(FetchDescriptor<MoneyTransaction>()).contains { row in
            row.fromAccountID == id || row.toAccountID == id || row.cardID.map(cards.contains) == true
        }
    }

    /// An account can be removed only when nothing ever referred to it: no movement (live or undoable), no
    /// reconciliation, no card (a linked card's debt would drop out of «عليك») and no sub-account.
    public static func removable(_ id: UUID, in context: ModelContext) throws -> Bool {
        if try hasMovements(id, in: context) { return false }
        if try context.fetch(FetchDescriptor<Card>()).contains(where: { $0.accountID == id }) { return false }
        return try !context.fetch(FetchDescriptor<Account>()).contains { $0.parentID == id && live($0) }
    }

    /// Live additional tails by owner: accounts and cards.
    nonisolated public static func liveTails(in context: ModelContext) throws -> [AccountTail] {
        try context.fetch(FetchDescriptor<AccountTail>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && !$0.tail.isEmpty }
    }
    nonisolated public static func tails(ofAccount id: UUID, among tails: [AccountTail]) -> Set<String> {
        Set(tails.filter { $0.accountID == id && $0.cardID == nil }.map(\.tail))
    }
    nonisolated public static func tails(ofCard id: UUID, among tails: [AccountTail]) -> Set<String> {
        Set(tails.filter { $0.cardID == id }.map(\.tail))
    }

    /// Two live accounts at one bank with the same last 4 would both stop matching their messages (intake needs one match).
    public static func duplicateLast4(_ last4: String?, bank: String, excluding id: UUID, in context: ModelContext) throws -> Bool {
        guard let last4, !last4.isEmpty else { return false }
        let extra = try liveTails(in: context)
        return try context.fetch(FetchDescriptor<Account>()).contains { other in
            other.id != id && live(other) && (other.last4 == last4 || tails(ofAccount: other.id, among: extra).contains(last4)) && BankMessageIdentity.matches(other.bank, bank)
        }
    }

    private static func live<T: MadarRecordModel>(_ row: T) -> Bool { (try? row.record().isLive) == true }
}
