import Foundation

/// When the prayer room may offer «في جماعة / وحدي» directly on the open prayer's card (B2-4).
/// Pure so the sanctity rule (RP3) can be tested: nothing is offered from the adhan until the window ends.
public enum PrayerQuickLog {
    public static func isOffered(prayer: Prayer, adhan: Date, nextAdhan: Date?, isPending: Bool, canLog: Bool, isFridayNoon: Bool, now: Date) -> Bool {
        guard isPending, canLog, !isFridayNoon, now >= adhan else { return false }
        if let nextAdhan, now >= nextAdhan { return false }
        return !SanctityWindow(prayer: prayer, adhan: adhan).contains(now)
    }
    /// Seconds until the open prayer's time ends, only where the next adhan is that end (Dhuhr, Asr, Maghrib).
    /// Fajr ends at sunrise and Isha at midnight, so no remaining time is claimed for them.
    public static func timeLeft(prayer: Prayer, nextAdhan: Date?, now: Date) -> TimeInterval? {
        guard prayer == .dhuhr || prayer == .asr || prayer == .maghrib, let nextAdhan, nextAdhan > now else { return nil }
        return nextAdhan.timeIntervalSince(now)
    }
}

/// Which unlogged prayer the lobby asks about on open (RP3: never inside any sanctity window).
public enum PrayerLobbyAsk {
    public struct Entry: Sendable {
        public let prayer: Prayer
        public let adhan: Date?
        public let isPending: Bool
        public let canLog: Bool
        public let isFridayNoon: Bool
        public init(prayer: Prayer, adhan: Date?, isPending: Bool, canLog: Bool, isFridayNoon: Bool) {
            self.prayer = prayer; self.adhan = adhan; self.isPending = isPending; self.canLog = canLog; self.isFridayNoon = isFridayNoon
        }
    }
    /// The last pending, loggable, already-called prayer of today (not Friday noon); nil while any sanctity window is open.
    public static func choose(_ entries: [Entry], now: Date) -> Prayer? {
        for entry in entries {
            guard let adhan = entry.adhan else { continue }
            if SanctityWindow(prayer: entry.prayer, adhan: adhan).contains(now) { return nil }
        }
        return entries.last { entry in
            guard let adhan = entry.adhan else { return false }
            return entry.isPending && entry.canLog && adhan <= now && !entry.isFridayNoon
        }?.prayer
    }
}

/// The Siri/Shortcuts «سجّل صلاة» rule (T07), pure so it is tested: a prayer whose adhan has not come yet cannot be logged,
/// whichever day is named. A day after today never has; today's has not until its adhan has passed.
public enum PrayerLogTiming {
    public static func hasNotOccurred(dayKey: String, todayKey: String, adhanToday: Date?, now: Date) -> Bool {
        if dayKey > todayKey { return true }
        guard dayKey == todayKey, let adhanToday else { return false }
        return adhanToday > now
    }
}
