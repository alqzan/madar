import Foundation

/// M5-V17 «سجّل مصروفًا»: what a manual expense will do, read before it is saved. Every number reuses the one
/// definition that already owns it — the budget charge from `MovementEngine`, the split from `AllocationEngine`
/// (L12), «اليوم» and «لك الآن» from `CycleEngine.headline`, the card's use of its limit from `CardPlanning`.
public enum ExpenseEntry {
    /// The four choices under the amount: all from «يومك», a quarter or a half from an envelope, or all of it.
    public enum Share: String, CaseIterable, Sendable {
        case daily, quarter, half, envelope
        /// The envelope's part, in percent.
        public var envelopePercent: Int {
            switch self { case .daily: 0; case .quarter: 25; case .half: 50; case .envelope: 100 }
        }
    }

    public struct Split: Equatable, Sendable {
        public var dailyMinor: Int
        public var envelopeMinor: Int
        public init(dailyMinor: Int, envelopeMinor: Int) { self.dailyMinor = dailyMinor; self.envelopeMinor = envelopeMinor }
    }

    /// The budget charge over «يومك» and one envelope. The envelope takes ⌊charge × percent ÷ 100⌋ and «يومك» the rest,
    /// so the parts always add up to the charge to the halala (L12: the remainder lands on the last part, «يومك»).
    public static func split(chargeMinor: Int, share: Share) -> Split {
        guard chargeMinor > 0 else { return .init(dailyMinor: 0, envelopeMinor: 0) }
        switch share {
        case .daily: return .init(dailyMinor: chargeMinor, envelopeMinor: 0)
        case .envelope: return .init(dailyMinor: 0, envelopeMinor: chargeMinor)
        case .quarter, .half:
            let parts = AllocationEngine.distribute(chargeMinor, weights: [share.envelopePercent, 100 - share.envelopePercent])
            return .init(dailyMinor: parts[1], envelopeMinor: parts[0])
        }
    }

    /// The allocation sources the command receives: none for «كله من يومي» (F02's default), the envelope first
    /// and «يومك» last otherwise. A part of zero is left out.
    public static func sources(_ split: Split, envelopeID: String) -> [(AllocationTarget, Int)] {
        guard split.envelopeMinor > 0 else { return [] }
        var rows: [(AllocationTarget, Int)] = [(.envelope(envelopeID), split.envelopeMinor)]
        if split.dailyMinor > 0 { rows.append((.daily, split.dailyMinor)) }
        return rows
    }

    /// «اليوم» and «لك الآن» after the expense: the same headline, with the daily part added to its day of the cycle.
    /// A day before today lowers «لك الآن» only; a day outside the cycle changes neither.
    public static func headlineAfter(elapsedDays: Int, _ input: CycleInput, dailySpentMinor: [Int: Int],
                                     expenseDay: Int, dailyChargeMinor: Int) -> Headline {
        var spent = dailySpentMinor
        if dailyChargeMinor != 0, expenseDay >= 1, expenseDay <= elapsedDays {
            spent[expenseDay, default: 0] += dailyChargeMinor
        }
        return CycleEngine.headline(elapsedDays: elapsedDays, input, dailySpentMinor: spent)
    }

    /// The amount as a part of «يومك» the user can picture («نحو ربع يومك», «نحو يوميتين»), never a multiplier.
    public enum DailyPart: Equatable, Sendable {
        case lessThanTenth
        case about(Fraction)
        /// About a whole number of dailies (two or more).
        case dailies(Int)
    }
    public enum Fraction: Equatable, Sendable { case tenth, fifth, quarter, third, half, twoThirds, threeQuarters, whole }

    /// Per mille of the daily: under 75 ‰ «أقل من عُشر»; then the nearest of a tenth (≤ 150), a fifth (≤ 225), a quarter
    /// (≤ 290), a third (≤ 415), a half (≤ 580), two thirds (≤ 710), three quarters (≤ 875) and the whole day (< 1500);
    /// from 1.5 dailies, the number of dailies rounded half up. No «يومك» (nil or zero) gives nothing.
    public static func dailyPart(amountMinor: Int, dailyMinor: Int?) -> DailyPart? {
        guard let dailyMinor, dailyMinor > 0, amountMinor > 0 else { return nil }
        let product = amountMinor.multipliedReportingOverflow(by: 1000)
        guard !product.overflow else { return .dailies(amountMinor / dailyMinor) }
        let permille = product.partialValue / dailyMinor
        switch permille {
        case ..<75: return .lessThanTenth
        case ..<151: return .about(.tenth)
        case ..<226: return .about(.fifth)
        case ..<291: return .about(.quarter)
        case ..<416: return .about(.third)
        case ..<581: return .about(.half)
        case ..<711: return .about(.twoThirds)
        case ..<876: return .about(.threeQuarters)
        case ..<1500: return .about(.whole)
        default: return .dailies((permille + 500) / 1000)
        }
    }

    /// §7.5 «المصروف الكبير»: three dailies or more.
    public static func isBig(amountMinor: Int, dailyMinor: Int?) -> Bool {
        guard let dailyMinor, dailyMinor > 0 else { return false }
        let triple = dailyMinor.multipliedReportingOverflow(by: 3)
        return triple.overflow ? false : amountMinor >= triple.partialValue
    }

    /// A credit card after the purchase: what is owed, and the share of the limit it uses (nil without a known limit).
    public struct CardAfter: Equatable, Sendable {
        public var owedMinor: Int
        public var utilisationBp: Int?
        public var overLimit: Bool
        /// §7.5: use of the limit above 30% is worth a word.
        public var aboveThirtyPercent: Bool
    }
    public static func creditCardAfter(owedMinor: Int, purchaseMinor: Int, limitMinor: Int?) -> CardAfter {
        let owed = owedMinor + purchaseMinor
        let use = CardPlanning.utilisationBp(owedMinor: owed, limitMinor: limitMinor)
        return .init(owedMinor: owed, utilisationBp: use, overLimit: limitMinor.map { owed > $0 } ?? false, aboveThirtyPercent: (use ?? 0) > 3_000)
    }

    /// An Arabic count of riyals as the object of «صرفت»: «ريالًا واحدًا», «ريالين», «٥ ريالات», «٤٢ ريالًا», «١٠٠ ريال».
    /// A fractional amount reads «١٨٫٥٠ ريال». `digits` renders the number in the user's numerals.
    public static func riyalsSpent(amountMinor: Int, exponent: Int = 2, digits: (Int) -> String, fractional: (Int) -> String) -> String {
        var scale = 1; for _ in 0..<max(0, exponent) { scale *= 10 }
        guard amountMinor % scale == 0 else { return fractional(amountMinor) + " ريال" }
        let n = amountMinor / scale
        if n == 1 { return "ريالًا واحدًا" }
        if n == 2 { return "ريالين" }
        let tail = n % 100
        switch tail {
        case 3...10: return digits(n) + " ريالات"
        case 11...99: return digits(n) + " ريالًا"
        default: return digits(n) + " ريال"
        }
    }
}
