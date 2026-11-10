import Foundation

/// Which part of the day the lobby is in. Pure: it reads only prayer times and the clock, never a room's records.
public enum LobbyMoment: Equatable, Sendable {
    /// Inside a sanctity window (adhan + 30 min, Maghrib + 20): the lobby shows no step at all.
    case quiet
    /// The next adhan is less than 30 minutes away.
    case beforeAdhan(Prayer, minutes: Int)
    /// After Fajr's window, until 15 minutes past sunrise.
    case morning
    /// From 15 minutes past sunrise until Dhuhr's approach.
    case duha
    /// After Isha's window until the next Fajr.
    case evening
    case general
}

public enum LobbyMomentPlan {
    /// How far ahead of an adhan the next prayer takes the lead.
    public static let beforeAdhanLead: TimeInterval = 30 * 60
    private static let duhaDelay: TimeInterval = 15 * 60

    /// `days` should hold yesterday, today and tomorrow in order (a night spans two civil days).
    public static func moment(at now: Date, days: [PrayerDay]) -> LobbyMoment {
        let sorted = days.sorted { $0.fajr < $1.fajr }
        if sorted.contains(where: { $0.sanctityWindows.contains { $0.contains(now) } }) { return .quiet }
        let upcoming = sorted.flatMap { day in Prayer.allCases.map { (prayer: $0, adhan: day.time(for: $0)) } }
            .filter { $0.adhan > now }.min { $0.adhan < $1.adhan }
        if let upcoming, upcoming.adhan.timeIntervalSince(now) < beforeAdhanLead {
            return .beforeAdhan(upcoming.prayer, minutes: Int((upcoming.adhan.timeIntervalSince(now) / 60).rounded(.up)))
        }
        for (index, day) in sorted.enumerated() {
            let fajrEnd = day.fajr.addingTimeInterval(30 * 60)
            let duhaStart = day.sunrise.addingTimeInterval(duhaDelay)
            if now >= fajrEnd && now < duhaStart { return .morning }
            if now >= duhaStart && now < day.dhuhr { return .duha }
            let ishaEnd = day.isha.addingTimeInterval(30 * 60)
            let nextFajr = index + 1 < sorted.count ? sorted[index + 1].fajr : nil
            if now >= ishaEnd, nextFajr.map({ now < $0 }) ?? true { return .evening }
        }
        return .general
    }

    /// Moves the step that fits the moment to the front and keeps the others' order. `kahf` (Friday) follows the lead.
    /// Step ids: `nextPrayer`, `quran`, `habit`, `notes`, `kahf`, plus the rest the lobby already builds.
    public static func order(_ ids: [String], moment: LobbyMoment) -> [String] {
        let lead: String? = switch moment {
        case .quiet: nil
        case .beforeAdhan: "nextPrayer"
        case .morning: "quran"
        case .duha: "habit"
        case .evening: "notes"
        case .general: nil
        }
        if moment == .quiet { return [] }
        var rest = ids
        var result: [String] = []
        if let lead, let index = rest.firstIndex(of: lead) { result.append(rest.remove(at: index)) }
        if let index = rest.firstIndex(of: "kahf") { result.append(rest.remove(at: index)) }
        return result + rest
    }
}
