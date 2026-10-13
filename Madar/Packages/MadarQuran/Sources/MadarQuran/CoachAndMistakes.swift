import Foundation
import MadarCore

public enum HifzCoachStage: String, Codable, Sendable {
    case repetition
    case lineStarts
    case promptedRecall
    case blindRecitation
    case rating

    fileprivate var isBlindRecitation: Bool { self == .blindRecitation }
}

public enum HifzCoachReveal: Equatable, Sendable {
    case learningHint
    case blindSlip
}

public struct HifzCoachTally: Equatable, Sendable {
    public private(set) var learningHints = 0
    public private(set) var blindSlips = 0

    public init() {}

    @discardableResult
    public mutating func recordReveal(at stage: HifzCoachStage) -> HifzCoachReveal {
        if stage.isBlindRecitation {
            blindSlips += 1
            return .blindSlip
        }
        learningHints += 1
        return .learningHint
    }

    public mutating func recordSlip(at stage: HifzCoachStage) {
        guard stage.isBlindRecitation else { return }
        blindSlips += 1
    }

    public func grade(ayatCount: Int) -> QuranReviewRating {
        QuranMistakeEngine.gradeFromBlindSlips(blindSlips, ayatCount: ayatCount)
    }
}

public struct QuranMistakeKey: Codable, Hashable, Sendable {
    public let ayahID: Int
    /// `nil` identifies the whole ayah, never its first word.
    public let wordIndex: Int?

    public init(ayahID: Int, wordIndex: Int?) {
        self.ayahID = ayahID
        self.wordIndex = wordIndex
    }
}

public enum QuranMistakeEventKind: String, Codable, Sendable {
    case mistake
    case drillPass
    case drillFail
}

public struct QuranMistakeSession: Equatable, Sendable {
    public let id: UUID
    public let dayKey: GregorianDay
    public let isDeleted: Bool

    public init(id: UUID, dayKey: GregorianDay, isDeleted: Bool = false) {
        self.id = id
        self.dayKey = dayKey
        self.isDeleted = isDeleted
    }
}

public struct QuranMistakeEvent: Equatable, Sendable {
    public let key: QuranMistakeKey
    public let sessionID: UUID?
    public let at: Date
    public let kind: QuranMistakeEventKind
    public let inputOrder: Int

    public init(key: QuranMistakeKey, sessionID: UUID?, at: Date, kind: QuranMistakeEventKind, inputOrder: Int = 0) {
        self.key = key
        self.sessionID = sessionID
        self.at = at
        self.kind = kind
        self.inputOrder = inputOrder
    }
}

public struct QuranMistakeSpotSeed: Equatable, Sendable {
    public let key: QuranMistakeKey
    public let legacyHits: Int
    public let legacyLastDrillAt: Date?
    public let legacyStreak: Int

    public init(key: QuranMistakeKey, legacyHits: Int = 0, legacyLastDrillAt: Date? = nil, legacyStreak: Int = 0) {
        self.key = key
        self.legacyHits = legacyHits
        self.legacyLastDrillAt = legacyLastDrillAt
        self.legacyStreak = legacyStreak
    }
}

public struct QuranMistakeSpotSummary: Equatable, Sendable {
    public let key: QuranMistakeKey
    public let hits: Int
    public let successStreak: Int
    public let isOpen: Bool
    public let closedAt: Date?
    public let lastSeenAt: Date?
    public let lastDrillAt: Date?
    public let reopenedAt: Date?

    public var returnedAfterClosure: Bool { isOpen && reopenedAt != nil }
}

public enum QuranMistakeEngine {
    public static let masteryThreshold = 2

    public static func mistakeTolerance(ayatCount: Int) -> Int {
        max(2, (Double(max(1, ayatCount)) / 5).roundedInt)
    }

    /// `blindSlips` is collected only during blind recitation; learning hints are not passed here.
    public static func gradeFromBlindSlips(_ blindSlips: Int, ayatCount: Int) -> QuranReviewRating {
        let marks = max(0, blindSlips)
        guard marks > 0 else { return .mastered }
        return marks <= mistakeTolerance(ayatCount: ayatCount) ? .good : .needsMastery
    }

    public static func summaries(
        seeds: [QuranMistakeSpotSeed],
        events: [QuranMistakeEvent],
        sessions: [QuranMistakeSession]
    ) -> [QuranMistakeSpotSummary] {
        let liveSessionIDs = Set(sessions.filter { !$0.isDeleted }.map(\.id))
        let liveEvents = events.filter { event in
            guard let sessionID = event.sessionID else { return false }
            return liveSessionIDs.contains(sessionID)
        }
        let seedsByKey = Dictionary(seeds.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let eventsByKey = Dictionary(grouping: liveEvents, by: \.key)
        let allKeys = Set(seedsByKey.keys).union(eventsByKey.keys)

        return allKeys.map { key in
            let seed = seedsByKey[key] ?? QuranMistakeSpotSeed(key: key)
            let orderedEvents = (eventsByKey[key] ?? []).sorted(by: eventOrder)
            var hits = max(0, seed.legacyHits)
            var successStreak = min(masteryThreshold, max(0, seed.legacyStreak))
            var closedAt = successStreak == masteryThreshold ? seed.legacyLastDrillAt : nil
            var wasClosedBefore = successStreak == masteryThreshold
            var reopenedAt: Date?
            var lastSeenAt = seed.legacyLastDrillAt
            var lastDrillAt = seed.legacyLastDrillAt

            for event in orderedEvents {
                lastSeenAt = event.at
                switch event.kind {
                case .mistake:
                    hits += 1
                    if successStreak == masteryThreshold, wasClosedBefore { reopenedAt = event.at }
                    successStreak = 0
                    closedAt = nil
                case .drillFail:
                    if successStreak == masteryThreshold, wasClosedBefore { reopenedAt = event.at }
                    successStreak = 0
                    closedAt = nil
                    lastDrillAt = event.at
                case .drillPass:
                    lastDrillAt = event.at
                    if successStreak < masteryThreshold {
                        successStreak += 1
                        if successStreak == masteryThreshold {
                            closedAt = event.at
                            wasClosedBefore = true
                        }
                    }
                }
            }

            return QuranMistakeSpotSummary(
                key: key,
                hits: hits,
                successStreak: successStreak,
                isOpen: successStreak < masteryThreshold,
                closedAt: closedAt,
                lastSeenAt: lastSeenAt,
                lastDrillAt: lastDrillAt,
                reopenedAt: reopenedAt
            )
        }
        .sorted(by: keyOrder)
    }

    public static func openSpots(
        seeds: [QuranMistakeSpotSeed],
        events: [QuranMistakeEvent],
        sessions: [QuranMistakeSession]
    ) -> [QuranMistakeSpotSummary] {
        summaries(seeds: seeds, events: events, sessions: sessions)
            .filter { $0.isOpen && $0.hits > 0 }
            .sorted {
                if $0.returnedAfterClosure != $1.returnedAfterClosure { return $0.returnedAfterClosure }
                if $0.hits != $1.hits { return $0.hits > $1.hits }
                if $0.lastSeenAt != $1.lastSeenAt { return ($0.lastSeenAt ?? .distantPast) > ($1.lastSeenAt ?? .distantPast) }
                return keyOrder($0, $1)
            }
    }

    public static func drillsForToday(
        openSpots: [QuranMistakeSpotSummary],
        alreadyDrilledToday: Set<QuranMistakeKey>,
        intensity: QuranReviewIntensity
    ) -> [QuranMistakeSpotSummary] {
        let remaining = max(0, intensity.preset.drillsPerDay - alreadyDrilledToday.count)
        guard remaining > 0 else { return [] }
        let eligible = openSpots
            .filter { $0.isOpen && $0.hits > 0 && !alreadyDrilledToday.contains($0.key) }
            .sorted {
                if $0.returnedAfterClosure != $1.returnedAfterClosure { return $0.returnedAfterClosure }
                if $0.hits != $1.hits { return $0.hits > $1.hits }
                if $0.lastSeenAt != $1.lastSeenAt { return ($0.lastSeenAt ?? .distantPast) > ($1.lastSeenAt ?? .distantPast) }
                return keyOrder($0, $1)
            }
        return Array(eligible.prefix(remaining))
    }

    /// The stored session dayKey decides which mistakes belong to today.
    public static func mistakesToday(
        events: [QuranMistakeEvent],
        sessions: [QuranMistakeSession],
        dayKey: GregorianDay
    ) -> Int {
        let todaysSessionIDs = Set(sessions.filter { !$0.isDeleted && $0.dayKey == dayKey }.map(\.id))
        return events.reduce(into: 0) { count, event in
            if event.kind == .mistake, let sessionID = event.sessionID, todaysSessionIDs.contains(sessionID) {
                count += 1
            }
        }
    }

    private static func eventOrder(_ lhs: QuranMistakeEvent, _ rhs: QuranMistakeEvent) -> Bool {
        if lhs.at != rhs.at { return lhs.at < rhs.at }
        if lhs.inputOrder != rhs.inputOrder { return lhs.inputOrder < rhs.inputOrder }
        let leftSession = lhs.sessionID?.uuidString ?? ""
        let rightSession = rhs.sessionID?.uuidString ?? ""
        if leftSession != rightSession { return leftSession < rightSession }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }

    private static func keyOrder(_ lhs: QuranMistakeSpotSummary, _ rhs: QuranMistakeSpotSummary) -> Bool {
        if lhs.key.ayahID != rhs.key.ayahID { return lhs.key.ayahID < rhs.key.ayahID }
        return (lhs.key.wordIndex ?? -1) < (rhs.key.wordIndex ?? -1)
    }
}

private extension Double {
    var roundedInt: Int { Int(rounded(.toNearestOrAwayFromZero)) }
}
