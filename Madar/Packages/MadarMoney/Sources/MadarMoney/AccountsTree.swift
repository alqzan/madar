import Foundation

/// M5-V19 «الحسابات» (`mal/28-Z-R19-acc`): one root per account, credit card and instalment purchase. The trunk number
/// is «لك فعلًا» from `BasisEngine` itself (F06, RM5), so the tree can never disagree with the basis.
public struct AccountRoot: Equatable, Sendable {
    public enum Side: String, Sendable { case cash, creditCard, instalment }
    public var id: String
    public var side: Side
    /// Cash: the balance. A debt: what is owed, as a positive amount.
    public var amountMinor: Int
    /// An owned, tracked account, or any debt. A not-mine account or an untracked wallet is drawn but never summed.
    public var counts: Bool
    public init(id: String, side: Side, amountMinor: Int, counts: Bool = true) {
        self.id = id; self.side = side; self.amountMinor = amountMinor; self.counts = counts
    }
}

public struct AccountsTotals: Equatable, Sendable {
    /// «كاش»: owned, tracked balances (the basis «في حسابك»).
    public var cashMinor: Int
    /// «عليك»: cards and instalments left.
    public var owedMinor: Int
    /// «لك فعلًا» = كاش − عليك.
    public var netMinor: Int
    /// Balances drawn with a cut root: outside every number.
    public var leftOutMinor: Int
}

/// How Madar knows a balance: the newest of the opening balance the user entered, the last confirmed reconciliation,
/// or the newest bank message that printed the balance.
public enum AccountBalanceSource: Equatable, Sendable {
    case entered(at: Date)
    case reconciled(at: Date)
    /// The message's printed balance equals Madar's book at that moment.
    case message(at: Date)
    /// The message printed a different balance: printed − book.
    case messageDiffers(at: Date, printedMinor: Int, differenceMinor: Int)

    public var at: Date {
        switch self { case .entered(let at), .reconciled(let at), .message(let at), .messageDiffers(let at, _, _): at }
    }
}

public enum AccountsTree {
    public static func totals(_ roots: [AccountRoot]) -> AccountsTotals {
        let counted = roots.filter(\.counts)
        let basis = BasisEngine.basis(.init(
            accounts: counted.filter { $0.side == .cash }.map { AccountState(balanceMinor: $0.amountMinor) },
            creditCards: counted.filter { $0.side == .creditCard }.map { CreditCardState(statementMinor: max(0, $0.amountMinor), unbilledMinor: 0) },
            installments: counted.filter { $0.side == .instalment }.map { InstallmentState(amountMinor: max(0, $0.amountMinor)) }))
        let leftOut = roots.filter { !$0.counts && $0.side == .cash }.reduce(0) { $0 + $1.amountMinor }
        return .init(cashMinor: basis.inAccountMinor, owedMinor: basis.owedMinor, netMinor: basis.netMinor, leftOutMinor: leftOut)
    }

    /// 0…1: how thick a root is drawn. Area follows the amount (square root), so a large account does not dwarf the rest.
    public static func rootWeight(amountMinor: Int, largestMinor: Int) -> Double {
        guard largestMinor > 0 else { return 0 }
        return min(1, (Double(abs(amountMinor)) / Double(largestMinor)).squareRoot())
    }

    /// The newest evidence wins; on the same instant a reconciliation (the user checked) beats a message, and a message
    /// beats the opening balance.
    public static func source(openingAt: Date?, reconciledAt: Date?, message: (at: Date, printedMinor: Int, bookMinor: Int)?) -> AccountBalanceSource? {
        var candidates: [(AccountBalanceSource, Int)] = []
        if let openingAt { candidates.append((.entered(at: openingAt), 0)) }
        if let message {
            let difference = message.printedMinor - message.bookMinor
            candidates.append((difference == 0 ? .message(at: message.at) : .messageDiffers(at: message.at, printedMinor: message.printedMinor, differenceMinor: difference), 1))
        }
        if let reconciledAt { candidates.append((.reconciled(at: reconciledAt), 2)) }
        return candidates.max { $0.0.at == $1.0.at ? $0.1 < $1.1 : $0.0.at < $1.0.at }?.0
    }
}
