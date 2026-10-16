/// A reserve square is one actual daily amount. Duration also pays the cycle's obligations
/// (RM9), so "250 dailies" and "196 days of coverage" are distinct, explicitly labelled values.
public struct ReserveReading: Equatable, Sendable {
    public var balanceMinor: Int
    public var dailyMinor: Int?
    public var wholeDailies: Int?
    public var partialDailyMinor: Int?
    public var runway: Runway?
}
public struct ReservePreview: Equatable, Sendable {
    public var before: ReserveReading
    public var after: ReserveReading
    public var spentMinor: Int
}
public enum ReserveEngine {
    public enum Error: Swift.Error, Equatable { case invalidSpend }
    public static func read(balanceMinor: Int, dailyMinor: Int?, cycleLengthDays: Int, obligationsPerCycleMinor: Int) -> ReserveReading {
        let whole = dailyMinor.flatMap { $0 > 0 ? max(0, balanceMinor) / $0 : nil }
        let partial = dailyMinor.flatMap { $0 > 0 ? max(0, balanceMinor) % $0 : nil }
        let runway = dailyMinor.flatMap { RunwayEngine.runway(balanceMinor: balanceMinor, dailyMinor: $0, cycleLengthDays: cycleLengthDays, obligationsPerCycleMinor: obligationsPerCycleMinor) }
        return .init(balanceMinor: balanceMinor, dailyMinor: dailyMinor, wholeDailies: whole, partialDailyMinor: partial, runway: runway)
    }
    /// Read-only: preview never creates a movement or takes money from a reserve.
    public static func preview(balanceMinor: Int, spendMinor: Int, dailyMinor: Int?, cycleLengthDays: Int, obligationsPerCycleMinor: Int) throws -> ReservePreview {
        guard spendMinor >= 0 && spendMinor <= max(0, balanceMinor) else { throw Error.invalidSpend }
        return .init(before: read(balanceMinor: balanceMinor, dailyMinor: dailyMinor, cycleLengthDays: cycleLengthDays, obligationsPerCycleMinor: obligationsPerCycleMinor),
            after: read(balanceMinor: balanceMinor - spendMinor, dailyMinor: dailyMinor, cycleLengthDays: cycleLengthDays, obligationsPerCycleMinor: obligationsPerCycleMinor), spentMinor: spendMinor)
    }
}
