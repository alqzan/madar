/// «التحليل» (§7.5 «التقرير المخطوط»، M5-V14): comparisons derived from readings that already exist. Nothing here is stored.
public enum AnalysisEngine {
    /// Signed whole-percent change from `previousMinor` to `currentMinor`, rounded half away from zero.
    /// nil when there is nothing honest to compare against (no spending in the earlier period): never «٠٪».
    public static func percentChange(currentMinor: Int, previousMinor: Int) -> Int? {
        guard previousMinor > 0 else { return nil }
        return roundedDivision((currentMinor - previousMinor) * 100, by: previousMinor)
    }

    /// The part of a per-cycle category limit that falls on cycle days `fromDay...throughDay` (1-based, inclusive).
    /// The limit is spread evenly over the expected cycle length, by the same rule as «المفروض حتى اليوم»
    /// (limit × elapsed ÷ length, truncated): the shares of all days add up to the limit exactly. Days past the
    /// expected length carry no share.
    public static func limitShare(limitMinor: Int, cycleLengthDays: Int, fromDay: Int, throughDay: Int) -> Int {
        let length = max(1, cycleLengthDays)
        let first = min(max(1, fromDay), length + 1), last = min(max(0, throughDay), length)
        guard last >= first else { return 0 }
        return limitMinor * last / length - limitMinor * (first - 1) / length
    }

    public struct Pace: Equatable, Sendable {
        /// Average daily spending over the days with a known result.
        public var averageSpentMinor: Int
        /// Average «يومك» over the same days.
        public var averageDailyMinor: Int
        /// What would be left of the period's dailies at its end if the average held; nil when the period is over.
        public var projectedLeftMinor: Int?
        public init(averageSpentMinor: Int, averageDailyMinor: Int, projectedLeftMinor: Int?) {
            self.averageSpentMinor = averageSpentMinor; self.averageDailyMinor = averageDailyMinor; self.projectedLeftMinor = projectedLeftMinor
        }
    }

    /// «وتيرتك»: needs at least `minimumDays` known days, so two days never pretend to be a trend.
    /// projectedLeft = (allowance − spent) × (known + remaining) ÷ known, rounded half away from zero.
    public static let minimumPaceDays = 3
    public static func pace(spentMinor: Int, allowanceMinor: Int, knownDays: Int, remainingDays: Int) -> Pace? {
        guard knownDays >= minimumPaceDays else { return nil }
        let left = allowanceMinor - spentMinor
        return Pace(averageSpentMinor: roundedDivision(spentMinor, by: knownDays), averageDailyMinor: roundedDivision(allowanceMinor, by: knownDays),
                    projectedLeftMinor: remainingDays > 0 ? roundedDivision(left * (knownDays + remainingDays), by: knownDays) : nil)
    }

    /// Integer division rounded half away from zero (Swift `/` truncates toward zero).
    public static func roundedDivision(_ value: Int, by divisor: Int) -> Int {
        precondition(divisor > 0)
        let quotient = value / divisor, remainder = value % divisor
        guard abs(remainder) * 2 >= divisor else { return quotient }
        return quotient + (value < 0 ? -1 : 1)
    }
}
