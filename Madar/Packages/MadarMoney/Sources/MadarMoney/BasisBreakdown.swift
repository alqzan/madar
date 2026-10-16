/// The basis column explains the existing numbers, without creating a new balance.
/// Reserved + future dailies + current entitlement + cycle remainder = net cash less debt.
public struct BasisBreakdown: Equatable, Sendable {
    public var netMinor: Int
    public var reservedMinor: Int
    public var unallocatedMinor: Int
    public var futureDailyMinor: Int?
    public var availableNowMinor: Int?
    public var cycleRemainderMinor: Int?
}

public enum BasisBreakdownEngine {
    public static func explain(_ basis: Basis, futureDailyMinor: Int?, availableNowMinor: Int?) -> BasisBreakdown {
        let remainder: Int?
        if let futureDailyMinor, let availableNowMinor { remainder = basis.unallocatedMinor - futureDailyMinor - availableNowMinor }
        else { remainder = nil }
        return .init(netMinor: basis.netMinor, reservedMinor: basis.reservedMinor, unallocatedMinor: basis.unallocatedMinor,
            futureDailyMinor: futureDailyMinor, availableNowMinor: availableNowMinor, cycleRemainderMinor: remainder)
    }
}
