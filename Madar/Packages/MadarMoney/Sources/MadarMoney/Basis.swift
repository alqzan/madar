/// «على أي أساس» (§7.5 numbers table, F06, RM1, RM2, RM9). Each number has one definition, built from source rows.
public struct AccountState: Equatable, Sendable {
    public enum Ownership: String, Sendable { case mine, notMine }
    public var balanceMinor: Int
    public var ownership: Ownership
    public init(balanceMinor: Int, ownership: Ownership = .mine) { self.balanceMinor = balanceMinor; self.ownership = ownership }
}

/// A credit card's open debt. Debit (mada) and prepaid purchases leave the account at once and never appear here (RM1).
public struct CreditCardState: Equatable, Sendable {
    public var statementMinor: Int
    /// Card payments since the statement closed.
    public var paidSinceCloseMinor: Int
    /// Credit purchases since the statement closed (fees and refunds already netted by the movement rules).
    public var unbilledMinor: Int
    public init(statementMinor: Int, paidSinceCloseMinor: Int = 0, unbilledMinor: Int) {
        self.statementMinor = statementMinor; self.paidSinceCloseMinor = paidSinceCloseMinor; self.unbilledMinor = unbilledMinor
    }
    /// F07: the statement left = statement − payments since close (never below 0); an overpayment lowers the unbilled.
    public var statementLeftMinor: Int { max(0, statementMinor - paidSinceCloseMinor) }
    public var unbilledLeftMinor: Int { max(0, unbilledMinor - max(0, paidSinceCloseMinor - statementMinor)) }
    /// F01: a payment beyond the whole debt stays on the card as credit you hold, so «لك فعلًا» does not move.
    public var creditMinor: Int { max(0, paidSinceCloseMinor - statementMinor - unbilledMinor) }
}

/// One InstallmentItem of a BNPL purchase (Tamara, Tabby); the rest is derived from paidMinor (F03).
public struct InstallmentState: Equatable, Sendable {
    public var amountMinor: Int
    public var paidMinor: Int
    public init(amountMinor: Int, paidMinor: Int = 0) { self.amountMinor = amountMinor; self.paidMinor = paidMinor }
    public var leftMinor: Int { max(0, amountMinor - paidMinor) }
}

public struct BasisInput: Equatable, Sendable {
    public var accounts: [AccountState]
    public var creditCards: [CreditCardState]
    public var installments: [InstallmentState]
    /// The loan instalment now due. RM9 (as C0 shows): the loan is not part of «عليك»; only what is due is reserved,
    /// and paying it lowers «لك فعلًا» and «المحجوز» together (F01).
    public var loanDueMinor: Int
    public var billsDueMinor: Int
    /// Signed allocations on envelope targets (general, goal, trip, reserve, surplus); a balance is their sum (F02).
    public var envelopeAllocationsMinor: [Int]
    public init(accounts: [AccountState], creditCards: [CreditCardState] = [], installments: [InstallmentState] = [],
                loanDueMinor: Int = 0, billsDueMinor: Int = 0, envelopeAllocationsMinor: [Int] = []) {
        self.accounts = accounts; self.creditCards = creditCards; self.installments = installments
        self.loanDueMinor = loanDueMinor; self.billsDueMinor = billsDueMinor; self.envelopeAllocationsMinor = envelopeAllocationsMinor
    }
}

public struct Basis: Equatable, Sendable {
    /// «في حسابك»: owned balances now (cash). An account that is not mine stays out (F06).
    public var inAccountMinor: Int
    /// «عليك»: statements + unbilled + BNPL instalments left, each once.
    public var owedMinor: Int
    /// «لك فعلًا» = في حسابك − عليك.
    public var netMinor: Int
    /// «المحجوز» = loan due + bills + envelope and reserve balances (a negative envelope counts as negative).
    public var reservedMinor: Int
    /// «غير مخصّص» (RM2; was «المتاح») = لك فعلًا − المحجوز. Shown on the basis screen only.
    public var unallocatedMinor: Int
}

public enum BasisEngine {
    public static func basis(_ input: BasisInput) -> Basis {
        // A card's credit balance is your money held at the bank: it sits with the cash, and «عليك» never goes below 0.
        let cash = input.accounts.filter { $0.ownership == .mine }.reduce(0) { $0 + $1.balanceMinor }
            + input.creditCards.reduce(0) { $0 + $1.creditMinor }
        let owed = input.creditCards.reduce(0) { $0 + $1.statementLeftMinor + $1.unbilledLeftMinor }
            + input.installments.reduce(0) { $0 + $1.leftMinor }
        let reserved = input.loanDueMinor + input.billsDueMinor + input.envelopeAllocationsMinor.reduce(0, +)
        return Basis(inAccountMinor: cash, owedMinor: owed, netMinor: cash - owed, reservedMinor: reserved, unallocatedMinor: cash - owed - reserved)
    }
}

/// How long a balance lasts in dailies (§7.5 «الاحتياطي»). RM9: each cycle's obligations are paid from it too.
public struct Runway: Equatable, Sendable {
    public var days: Int
    /// Whole cycles and the days left over («٨ أشهر و١٠ أيام» when the cycle is 30 days).
    public var cycles: Int
    public var extraDays: Int
}

public enum RunwayEngine {
    /// days = ⌊balance × L ÷ (يومك × L + obligations per cycle)⌋; nil when nothing is spent (no runway to show).
    public static func runway(balanceMinor: Int, dailyMinor: Int, cycleLengthDays: Int, obligationsPerCycleMinor: Int = 0) -> Runway? {
        let perCycle = dailyMinor * cycleLengthDays + obligationsPerCycleMinor
        guard perCycle > 0, cycleLengthDays > 0 else { return nil }
        let days = max(0, balanceMinor) * cycleLengthDays / perCycle
        return Runway(days: days, cycles: days / cycleLengthDays, extraDays: days % cycleLengthDays)
    }
}
