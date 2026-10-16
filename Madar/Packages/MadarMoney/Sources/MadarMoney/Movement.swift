/// F01 «حركة المال»: each movement's single effect on cash («في حسابك»), debt («عليك»), «لك فعلًا» and the budget,
/// as amended by RM1 (debit and prepaid cards), RM4 (obligation-linked rows are budget-neutral) and RM5 (own transfers, wallets).
public enum Movement: Equatable, Sendable {
    public enum PayFrom: Equatable, Sendable {
        /// The account itself (bank transfer, SADAD, online banking).
        case account
        /// mada / Apple Pay on mada / prepaid: posts to the linked account at once (RM1).
        case debitCard, prepaidCard
        /// A credit card: debt now, cash on the payment day.
        case creditCard
        /// Cash spent from the cash wallet.
        case cashWallet
    }
    public enum RefundTo: Equatable, Sendable { case account, creditCard }

    case purchase(PayFrom)
    /// A BNPL purchase (Tamara, Tabby): the whole amount is owed and charged to the budget once, on its envelope.
    case bnplPurchase
    /// An instalment of BNPL; budget-neutral, cash and debt fall together.
    case bnplInstalment
    /// A loan instalment: cash −, «لك فعلًا» −, the reserved due falls by the same amount; budget-neutral.
    case loanInstalment
    /// RM4: a bill paid (SADAD) linked to its obligation: reserved already, so budget-neutral.
    case billPayment(linkedToObligation: Bool)
    case cardPayment
    /// Both sides owned (RM5 pairing, or a tracked wallet top-up).
    case ownTransfer
    /// Bank → the cash wallet.
    case withdrawal
    /// To someone else (or an account that is not mine, or an untracked wallet).
    case externalTransfer(notSpend: Bool)
    case income(isSalary: Bool)
    case refund(RefundTo)
    case cashbackEarned
    case cashbackRedeemed(RefundTo)
    /// A reconciliation adjustment of `deltaMinor` (observed − expected).
    case adjustment(unrecordedSpend: Bool)
}

public struct MovementEffect: Equatable, Sendable {
    public var cashMinor: Int
    public var debtMinor: Int
    /// What the budget is charged (+) or given back (−); 0 = neutral. Charged amounts become allocations (F02).
    public var budgetChargeMinor: Int
    /// «لك فعلًا» = cash − debt, always from the same row.
    public var netMinor: Int { cashMinor - debtMinor }
}

public struct MovementSettings: Equatable, Sendable {
    /// `mal.cashWithdrawalAsSpend` (default true): the withdrawal is charged, and cash spent from the wallet is not charged again.
    public var cashWithdrawalAsSpend: Bool
    public init(cashWithdrawalAsSpend: Bool = true) { self.cashWithdrawalAsSpend = cashWithdrawalAsSpend }
}

public enum MovementEngine {
    /// `amountMinor` is the positive home amount, except an adjustment where it is the signed delta.
    /// `ignoredFromBudget` removes the budget charge only; cash and debt stay right (F06).
    public static func effect(_ movement: Movement, amountMinor a: Int, ignoredFromBudget: Bool = false, settings: MovementSettings = .init()) -> MovementEffect {
        var effect: MovementEffect
        switch movement {
        case .purchase(.account), .purchase(.debitCard), .purchase(.prepaidCard):
            effect = .init(cashMinor: -a, debtMinor: 0, budgetChargeMinor: a)
        case .purchase(.creditCard):
            effect = .init(cashMinor: 0, debtMinor: a, budgetChargeMinor: a)
        case .purchase(.cashWallet):
            effect = .init(cashMinor: -a, debtMinor: 0, budgetChargeMinor: settings.cashWithdrawalAsSpend ? 0 : a)
        case .bnplPurchase:
            effect = .init(cashMinor: 0, debtMinor: a, budgetChargeMinor: a)
        case .bnplInstalment, .cardPayment:
            effect = .init(cashMinor: -a, debtMinor: -a, budgetChargeMinor: 0)
        case .loanInstalment:
            effect = .init(cashMinor: -a, debtMinor: 0, budgetChargeMinor: 0)
        case .billPayment(let linked):
            effect = .init(cashMinor: -a, debtMinor: 0, budgetChargeMinor: linked ? 0 : a)
        case .ownTransfer:
            effect = .init(cashMinor: 0, debtMinor: 0, budgetChargeMinor: 0)
        case .withdrawal:
            effect = .init(cashMinor: 0, debtMinor: 0, budgetChargeMinor: settings.cashWithdrawalAsSpend ? a : 0)
        case .externalTransfer(let notSpend):
            effect = .init(cashMinor: -a, debtMinor: 0, budgetChargeMinor: notSpend ? 0 : a)
        case .income:
            effect = .init(cashMinor: a, debtMinor: 0, budgetChargeMinor: 0)
        case .refund(.account):
            effect = .init(cashMinor: a, debtMinor: 0, budgetChargeMinor: -a)
        case .refund(.creditCard):
            effect = .init(cashMinor: 0, debtMinor: -a, budgetChargeMinor: -a)
        case .cashbackEarned:
            effect = .init(cashMinor: 0, debtMinor: 0, budgetChargeMinor: 0)
        case .cashbackRedeemed(.account):
            effect = .init(cashMinor: a, debtMinor: 0, budgetChargeMinor: 0)
        case .cashbackRedeemed(.creditCard):
            effect = .init(cashMinor: 0, debtMinor: -a, budgetChargeMinor: 0)
        case .adjustment(let unrecordedSpend):
            // ± the delta on cash; neutral unless the user chose «مصروف لم يُسجَّل» for a shortfall.
            effect = .init(cashMinor: a, debtMinor: 0, budgetChargeMinor: unrecordedSpend && a < 0 ? -a : 0)
        }
        if ignoredFromBudget { effect.budgetChargeMinor = 0 }
        return effect
    }
}
