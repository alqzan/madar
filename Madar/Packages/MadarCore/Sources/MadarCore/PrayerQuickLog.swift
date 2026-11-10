import Foundation

/// When the prayer room may offer «في جماعة / وحدي» directly on the open prayer's card (B2-4).
/// Pure so the sanctity rule (RP3) can be tested: nothing is offered from the adhan until the window ends.
public enum PrayerQuickLog {
    public static func isOffered(prayer: Prayer, adhan: Date, nextAdhan: Date?, isPending: Bool, canLog: Bool, isFridayNoon: Bool, now: Date) -> Bool {
        guard isPending, canLog, !isFridayNoon, now >= adhan else { return false }
        if let nextAdhan, now >= nextAdhan { return false }
        return !SanctityWindow(prayer: prayer, adhan: adhan).contains(now)
    }
}
