import Foundation

/// Owner, 17 Nov 2026 (idea 2): the lobby may say, once a week, that a daily habit is struggling. Pure; it only reads
/// evaluated periods and never writes — the user changes the habit in the editor if they want to.
public enum HabitInsights {
    public struct WeekBehaviour: Equatable, Sendable {
        public let met: Int
        public let total: Int
        /// Fewer than three of the seven days met. Needs at least five countable days, so a new or mostly paused habit is left alone.
        public var struggling: Bool { total >= 5 && met < 3 }
    }
    /// The seven closed days before `today` of a daily habit. Excluded days (paused, not yet started) are not counted.
    public static func lastWeek(of summary: HabitSummary, today: GregorianDay) -> WeekBehaviour? {
        let days = summary.periods.filter { $0.rule.frequency == .daily && $0.target > 0 && $0.outcome != .excluded && $0.start >= today.adding(days: -7) && $0.start < today }
        guard !days.isEmpty else { return nil }
        return .init(met: days.filter(\.met).count, total: days.count)
    }
}
