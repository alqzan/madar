/// Owner-approved editable suggestions (17 October 2026). All amounts are minor units.
public enum GoalPreparation {
    public struct Suggestion: Equatable, Sendable {
        public var upfrontMinor: Int
        public var dailyMinor: Int
        public var days: Int?
    }
    public static func days(remainingMinor: Int, dailyMinor: Int) -> Int? {
        guard remainingMinor > 0 else { return 0 }
        guard dailyMinor > 0 else { return nil }
        return remainingMinor / dailyMinor + (remainingMinor % dailyMinor == 0 ? 0 : 1)
    }
    public static func suggestions(targetMinor: Int, availableDailyMinor: Int, surplusMinor: Int) -> [Suggestion] {
        let target = max(0, targetMinor), daily = max(0, availableDailyMinor)
        return [8, 4, 3].map { divisor in
            let upfront = min(target, max(0, surplusMinor))
            let share = target > upfront ? min(target - upfront, daily / divisor) : 0
            return Suggestion(upfrontMinor: upfront, dailyMinor: share, days: days(remainingMinor: target - upfront, dailyMinor: share))
        }
    }
    public static func yearReserve(targetMinor: Int, balancedDailyMinor: Int, daysInYear: Int, reserveMinor: Int) -> Int {
        let (covered, overflow) = max(0, balancedDailyMinor).multipliedReportingOverflow(by: max(0, daysInYear))
        return min(max(0, reserveMinor), overflow ? 0 : max(0, targetMinor - covered))
    }
}
