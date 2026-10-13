import Foundation

/// Outside the app only the next prayer and its time are shown (RP9, RU2): no qada counts, no streaks.
public struct PrayerNextSnapshot: Codable, Sendable, Equatable {
    public struct Item: Codable, Sendable, Equatable {
        public var prayer: String
        public var name: String
        public var at: Date
        public init(prayer: String, name: String, at: Date) { self.prayer = prayer; self.name = name; self.at = at }
    }
    /// Chronological prayer times covering today and the next day.
    public var items: [Item]
    /// `core.numerals`: "hindi" or "western".
    public var numerals: String
    public init(items: [Item], numerals: String) { self.items = items.sorted { $0.at < $1.at }; self.numerals = numerals }

    /// Retains today's and tomorrow's prayer times, including prayers that have
    /// already occurred today. Controls need today's Fajr to resolve the prayer
    /// day, and earlier times to validate a selected prayer.
    public static func itemsForTodayAndTomorrow(_ items: [Item], at instant: Date, timeZone: TimeZone) -> [Item] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: instant)
        guard let end = calendar.date(byAdding: .day, value: 2, to: today) else { return [] }
        return items.filter { $0.at >= today && $0.at < end }
    }

    public struct State: Sendable, Equatable {
        public var item: Item
        /// Whole minutes until the prayer, never negative.
        public var minutes: Int
    }
    /// The first prayer after `date`, or nil when the snapshot has run out.
    public func state(at date: Date) -> State? {
        guard let next = items.first(where: { $0.at > date }) else { return nil }
        return State(item: next, minutes: max(0, Int(next.at.timeIntervalSince(date) / 60)))
    }
    /// RL7: two fields, «١:١٤» (hours, minutes). The home screen has its own wording; widgets stay compact.
    public func countdown(minutes: Int) -> String {
        digits(minutes / 60) + ":" + digits(minutes % 60 / 10) + digits(minutes % 10)
    }
    public func digits(_ value: Int) -> String {
        guard numerals != "western" else { return String(value) }
        let map: [Character: Character] = ["0": "٠", "1": "١", "2": "٢", "3": "٣", "4": "٤", "5": "٥", "6": "٦", "7": "٧", "8": "٨", "9": "٩"]
        return String(String(value).map { map[$0] ?? $0 })
    }
    /// One entry per minute from `date`, so the countdown is exact without any refresh budget.
    public func timelineDates(from date: Date, horizonMinutes: Int = 480) -> [Date] {
        let start = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
        let end = items.last?.at ?? start
        return (0...horizonMinutes).map { start.addingTimeInterval(Double($0) * 60) }.filter { $0 <= end }
    }
}
