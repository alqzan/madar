import Foundation
import MadarCore

/// The three nested home streaks (owner decision, 13 October 2026): congregation days are on time, on-time days are complete.
public enum PrayerStreakLevel: String, CaseIterable, Sendable {
    /// All five in congregation.
    case congregation
    /// All five on time, no qada.
    case onTime
    /// All five prayed, a qada included once it is made up.
    case completion
}

/// How one prayer day stands for one streak level.
public enum PrayerStreakMark: Equatable, Sendable {
    /// The day adds one to the streak.
    case counted
    /// Not all five are settled yet (pending, unconfirmed, excused…): the day neither counts nor breaks.
    case open
    /// Broken by a prayer prayed alone (congregation only).
    case brokeAlone
    /// Broken by a made-up prayer (congregation and on time).
    case brokeQada
    /// Broken by a missed prayer that is not made up yet.
    case brokeMissed
    /// Older than the break: outside the current streak.
    case outside

    public var breaks: Bool { [.brokeAlone, .brokeQada, .brokeMissed].contains(self) }
}

public enum PrayerStreaks {
    /// The single definition every streak number and mark comes from.
    public static func classify(_ day: PrayerDaySummary, level: PrayerStreakLevel, madeUp: Set<String>) -> PrayerStreakMark {
        func paid(_ cell: PrayerCell) -> Bool { madeUp.contains(cell.reference.naturalKey) }
        if day.cells.contains(where: { $0.status == .missed || ($0.status == .qada && !paid($0)) }) { return .brokeMissed }
        let hasQada = day.cells.contains { $0.status == .qada }
        if hasQada && level != .completion { return .brokeQada }
        let settled = day.cells.filter { [.jamaah, .alone, .qada].contains($0.status) }
        if settled.count != 5 { return .open }
        if level == .congregation && settled.contains(where: { $0.status != .jamaah }) { return .brokeAlone }
        return .counted
    }

    /// Marks for the days before `currentDay`, newest first; every day after the first break is `.outside`.
    public static func marks(_ days: [PrayerDaySummary], level: PrayerStreakLevel, qada: [PrayerQada], before currentDay: GregorianDay) -> [(day: GregorianDay, mark: PrayerStreakMark)] {
        let madeUp = Set(qada.filter { $0.madeUpAt != nil }.map { $0.reference.naturalKey })
        var broken = false
        return days.filter { $0.day < currentDay }.sorted { $0.day > $1.day }.map { day in
            if broken { return (day.day, .outside) }
            let mark = classify(day, level: level, madeUp: madeUp)
            if mark.breaks { broken = true }
            return (day.day, mark)
        }
    }

    public static func length(_ days: [PrayerDaySummary], level: PrayerStreakLevel, qada: [PrayerQada], before currentDay: GregorianDay) -> Int {
        marks(days, level: level, qada: qada, before: currentDay).filter { $0.mark == .counted }.count
    }
}
