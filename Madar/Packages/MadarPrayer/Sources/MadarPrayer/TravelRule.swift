import Foundation
import MadarCore

/// RP7: travel is detected, never assumed. The owner asks once; until then the pill says «خارج مدينتك».
public enum TravelRule {
    /// Owner decision, 13 Oct 2026: the distance is counted from the city's edge, not its centre.
    /// The edge is approximated as a circle of this radius around the home point.
    public static let homeRadiusKm = 25.0

    public static func distanceKm(from a: ActivePlace, to b: ActivePlace) -> Double {
        let r = 6371.0, p1 = a.latitude * .pi / 180, p2 = b.latitude * .pi / 180
        let dp = p2 - p1, dl = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    /// `thresholdKm` is `core.travelKm` (default 80), measured beyond the home city's edge.
    public static func isAway(home: ActivePlace, current: ActivePlace, thresholdKm: Double) -> Bool {
        distanceKm(from: home, to: current) - homeRadiusKm > thresholdKm
    }

    /// RP4: the local method suggested when the trip starts. The owner can change it in the question.
    public static func suggestedMethod(country: String) -> PrayerCalculationMethod {
        switch country.uppercased() {
        case "SA": .ummAlQura
        case "TR": .turkey
        case "US", "CA": .isna
        case "AE": .dubai
        case "KW": .kuwait
        case "QA": .qatar
        case "EG": .egyptian
        default: .mwl
        }
    }
}
