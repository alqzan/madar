import Foundation

/// The one line at the top of the lobby (T13): what to do next, from data the app already owns.
/// Pure: the same input always gives the same order. Inside a sanctity window nothing but the prayer itself is suggested.
public enum NextStepBand: Int, Comparable, Sendable {
    case now = 0, today = 1, soon = 2
    public static func < (a: NextStepBand, b: NextStepBand) -> Bool { a.rawValue < b.rawValue }
}
public enum NextStepKind: Int, Sendable { case prayer = 0, obligation, salary, trip, wird, habit, diaryPage }
public struct NextStep: Equatable, Sendable, Identifiable {
    public let id: String, kind: NextStepKind, title: String, band: NextStepBand, at: Date?
}
public struct NextStepInput: Sendable {
    public struct Item: Equatable, Sendable { public let id: String, title: String, at: Date
        public init(id: String, title: String, at: Date) { self.id = id; self.title = title; self.at = at } }
    public var now: Date
    /// The next adhan, and the sanctity window currently open (if `now` is inside one).
    public var nextPrayer: Item?
    public var openWindow: SanctityWindow?
    public var wirdPagesLeft: Int
    public var obligations: [Item], salary: Item?, trips: [Item]
    public var habitsDue: [Item]
    public var dayPageEmpty: Bool
    public init(now: Date, nextPrayer: Item? = nil, openWindow: SanctityWindow? = nil, wirdPagesLeft: Int = 0, obligations: [Item] = [],
                salary: Item? = nil, trips: [Item] = [], habitsDue: [Item] = [], dayPageEmpty: Bool = false) {
        self.now = now; self.nextPrayer = nextPrayer; self.openWindow = openWindow; self.wirdPagesLeft = wirdPagesLeft
        self.obligations = obligations; self.salary = salary; self.trips = trips; self.habitsDue = habitsDue; self.dayPageEmpty = dayPageEmpty
    }
}
public enum NextStepRanker {
    public static let prayerLeadSeconds: TimeInterval = 20 * 60
    public static let horizon: TimeInterval = 48 * 3600
    public static let todaySeconds: TimeInterval = 24 * 3600

    public static func rank(_ input: NextStepInput) -> [NextStep] {
        let now = input.now
        // Sanctity: inside the window the only suggestion is the prayer.
        if let window = input.openWindow, window.contains(now) {
            return [NextStep(id: "prayer.window", kind: .prayer, title: "حان وقت الصلاة", band: .now, at: window.start)]
        }
        var steps: [NextStep] = []
        if let prayer = input.nextPrayer, prayer.at > now {
            let band: NextStepBand = prayer.at.timeIntervalSince(now) <= prayerLeadSeconds ? .now : .today
            steps.append(.init(id: "prayer." + prayer.id, kind: .prayer, title: prayer.title, band: band, at: prayer.at))
        }
        func band(for due: Date) -> NextStepBand? {
            let gap = due.timeIntervalSince(now)
            if gap < 0 { return .now }            // overdue
            if gap <= todaySeconds { return .today }
            if gap <= horizon { return .soon }
            return nil
        }
        for item in input.obligations { if let b = band(for: item.at) { steps.append(.init(id: "obligation." + item.id, kind: .obligation, title: item.title, band: b, at: item.at)) } }
        if let salary = input.salary, let b = band(for: salary.at), salary.at >= now { steps.append(.init(id: "salary." + salary.id, kind: .salary, title: salary.title, band: b == .now ? .today : b, at: salary.at)) }
        for trip in input.trips where trip.at >= now && trip.at.timeIntervalSince(now) <= horizon {
            steps.append(.init(id: "trip." + trip.id, kind: .trip, title: trip.title, band: trip.at.timeIntervalSince(now) <= todaySeconds ? .today : .soon, at: trip.at))
        }
        if input.wirdPagesLeft > 0 { steps.append(.init(id: "wird", kind: .wird, title: "ورد اليوم", band: .today, at: nil)) }
        for habit in input.habitsDue { steps.append(.init(id: "habit." + habit.id, kind: .habit, title: habit.title, band: .today, at: habit.at)) }
        if input.dayPageEmpty { steps.append(.init(id: "diary.page", kind: .diaryPage, title: "صفحة اليوم تنتظرك", band: .today, at: nil)) }
        return steps.sorted { a, b in
            if a.band != b.band { return a.band < b.band }
            switch (a.at, b.at) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.kind.rawValue != b.kind.rawValue ? a.kind.rawValue < b.kind.rawValue : a.id < b.id
            }
        }
    }
}
