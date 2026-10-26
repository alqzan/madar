import Foundation

/// A small, device-local welcome plan created after a multi-day absence.
public struct BahwReturnPlanSnapshot: Codable, Equatable, Sendable {
    public enum QuranGoal: String, Codable, Sendable {
        case halfWird
    }

    public let days: [GregorianDay]
    public let quranGoal: QuranGoal
    public let habitsPerDay: Int

    public init(startingOn day: GregorianDay) {
        days = (0..<3).map { day.adding(days: $0) }
        quranGoal = .halfWird
        habitsPerDay = 1
    }

    public func dayNumber(on day: GregorianDay) -> Int? {
        days.firstIndex(of: day).map { $0 + 1 }
    }
}

public struct BahwReturnVisitState: Codable, Equatable, Sendable {
    public var lastVisitedDay: GregorianDay?
    public var plan: BahwReturnPlanSnapshot?

    public init(lastVisitedDay: GregorianDay? = nil, plan: BahwReturnPlanSnapshot? = nil) {
        self.lastVisitedDay = lastVisitedDay
        self.plan = plan
    }
}

public enum BahwReturnPlanEngine {
    public static let absenceDays = 3

    /// Records an app visit using the resolved Madar day, so settings and travel share the same boundary.
    public static func recordVisit(on today: GregorianDay, state previous: BahwReturnVisitState?) -> BahwReturnVisitState {
        var next = previous ?? BahwReturnVisitState()

        // Expire a plan outside its three saved day keys, including after a day-key change.
        if let plan = next.plan, plan.dayNumber(on: today) == nil {
            next.plan = nil
        }

        if let last = next.lastVisitedDay,
           let gap = dayDistance(from: last, to: today),
           gap >= absenceDays {
            next.plan = BahwReturnPlanSnapshot(startingOn: today)
        }

        next.lastVisitedDay = today
        return next
    }

    public static func dayNumber(on today: GregorianDay, state: BahwReturnVisitState) -> Int? {
        state.plan?.dayNumber(on: today)
    }

    private static func dayDistance(from start: GregorianDay, to end: GregorianDay) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.dateComponents([.day], from: start.date(in: .gmt), to: end.date(in: .gmt)).day
    }
}
