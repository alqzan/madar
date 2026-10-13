import Foundation
import MadarCore

public enum QuranReviewError: Error, Equatable {
    case invalidPageRange
}

public struct QuranPageRange: Codable, Hashable, Sendable {
    public let first: Int
    public let last: Int

    public init(first: Int, last: Int) throws {
        guard (1...604).contains(first), (1...604).contains(last), first <= last else {
            throw QuranReviewError.invalidPageRange
        }
        self.first = first
        self.last = last
    }

    public func contains(_ page: Int) -> Bool { (first...last).contains(page) }
}

public enum QuranReviewRating: Int, Codable, CaseIterable, Sendable {
    case needsMastery = 1
    case good = 2
    case mastered = 3
}

public enum QuranReviewIntensity: String, Codable, CaseIterable, Sendable {
    case light
    case balanced
    case intense

    public var preset: QuranReviewPreset {
        switch self {
        case .light:
            QuranReviewPreset(
                dailyReviewPages: 4,
                ladder: [10, 21, 45, 90],
                goodDays: 5,
                needsDays: 2
            )
        case .balanced:
            QuranReviewPreset(
                dailyReviewPages: 7,
                ladder: [7, 14, 30, 60],
                goodDays: 3,
                needsDays: 1
            )
        case .intense:
            QuranReviewPreset(
                dailyReviewPages: 12,
                ladder: [5, 10, 21, 45],
                goodDays: 2,
                needsDays: 1
            )
        }
    }
}

public struct QuranReviewPreset: Hashable, Sendable {
    public let dailyReviewPages: Int
    public let ladder: [Int]
    public let goodDays: Int
    public let needsDays: Int

    public init(dailyReviewPages: Int, ladder: [Int], goodDays: Int, needsDays: Int) {
        self.dailyReviewPages = dailyReviewPages
        self.ladder = ladder
        self.goodDays = goodDays
        self.needsDays = needsDays
    }

    public static let balanced = QuranReviewIntensity.balanced.preset
}

public struct QuranReviewEvent: Hashable, Sendable {
    public let pages: QuranPageRange
    public let day: GregorianDay
    public let rating: QuranReviewRating
    /// Unix milliseconds; used only to choose the latest duplicate review that day.
    public let occurredAt: Int64?
    /// Stable source order resolves events with equal or missing timestamps.
    public let inputOrder: Int

    public init(
        pages: QuranPageRange,
        day: GregorianDay,
        rating: QuranReviewRating,
        occurredAt: Int64? = nil,
        inputOrder: Int = 0
    ) {
        self.pages = pages
        self.day = day
        self.rating = rating
        self.occurredAt = occurredAt
        self.inputOrder = inputOrder
    }
}

public struct QuranPageMemory: Equatable, Sendable {
    public let intervalDays: Int
    public let ease: Double
    public let lapses: Int
    public let lastReviewed: GregorianDay?

    public init(intervalDays: Int, ease: Double, lapses: Int, lastReviewed: GregorianDay?) {
        self.intervalDays = intervalDays
        self.ease = ease
        self.lapses = lapses
        self.lastReviewed = lastReviewed
    }
}

public struct QuranPageSchedule: Equatable, Sendable {
    public let page: Int
    public let intervalDays: Int
    public let ease: Double
    public let lastReviewed: GregorianDay?
    public let dueDate: GregorianDay?
    public let overdueDays: Int
    public let lapses: Int
    public let openMistakes: Int
    public let risk: Double
    public let isDue: Bool
}

public struct QuranDueQueue: Equatable, Sendable {
    public let pages: [QuranPageSchedule]
    public let total: Int
    public let hidden: Int
    public let cap: Int
}

public struct QuranMemoryCursor: Equatable, Sendable {
    public let intervalDays: Int
    public let ease: Double
    public let lastReviewed: GregorianDay?

    public init(intervalDays: Int, ease: Double = 1, lastReviewed: GregorianDay? = nil) {
        self.intervalDays = intervalDays
        self.ease = ease
        self.lastReviewed = lastReviewed
    }
}

public struct QuranReviewUpdate: Equatable, Sendable {
    public let intervalDays: Int
    public let ease: Double
    public let wasEarlyMastery: Bool
}

public struct QuranReviewNeed: Equatable, Sendable {
    public let steadyNeed: Double
    public let todayNeed: Double

    public init(steadyNeed: Double, todayNeed: Double) {
        self.steadyNeed = steadyNeed
        self.todayNeed = todayNeed
    }
}

public enum QuranReviewEngine {
    public static let easeStart = 1.0
    public static let minimumEase = 0.6
    public static let maximumEase = 1.4
    public static let earlyMasteryFraction = 0.8
    public static let neverReviewedRisk = 2.5
    public static let consistencyWindowDays = 14
    public static let halfWirdFactor = 2.0

    private static let easeMultipliers: [QuranReviewRating: Double] = [
        .needsMastery: 0.82,
        .good: 0.95,
        .mastered: 1.06,
    ]

    public static func normalizedEase(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return easeStart }
        return min(maximumEase, max(minimumEase, (value * 100).rounded() / 100))
    }

    public static func nextEase(_ previous: Double, rating: QuranReviewRating) -> Double {
        let normalizedPrevious = previous.isFinite && previous > 0 ? previous : easeStart
        return normalizedEase(normalizedPrevious * easeMultipliers[rating, default: 1])
    }

    public static func nextInterval(
        previousDays: Int,
        rating: QuranReviewRating,
        preset: QuranReviewPreset = .balanced,
        ease rawEase: Double = easeStart,
        elapsedDays: Int = 0
    ) -> Int {
        let ease = normalizedEase(rawEase)
        switch rating {
        case .needsMastery:
            return max(1, preset.needsDays)
        case .good:
            return max(1, (Double(preset.goodDays) * ease).roundedInt)
        case .mastered:
            let baseline = previousDays > 0 ? Double(previousDays) / ease : 0
            if previousDays <= 0 || baseline < Double(preset.goodDays) * 0.75 {
                return max(1, (Double(preset.goodDays) * ease).roundedInt)
            }

            let firstRung = preset.ladder.first ?? 1
            let selectedRung: Int
            if baseline < Double(firstRung) * 0.75 {
                selectedRung = firstRung
            } else {
                let closest = closestRungIndex(to: baseline, ladder: preset.ladder)
                selectedRung = preset.ladder[min(closest + 1, preset.ladder.count - 1)]
            }

            let elapsed = max(0, elapsedDays)
            let base = elapsed > selectedRung ? min(elapsed, selectedRung * 2) : selectedRung
            let ceiling = ((Double(preset.ladder.last ?? selectedRung) * maximumEase).roundedInt)
            return max(1, min((Double(base) * ease).roundedInt, ceiling))
        }
    }

    public static func apply(
        _ rating: QuranReviewRating,
        to cursor: QuranMemoryCursor,
        on day: GregorianDay,
        preset: QuranReviewPreset = .balanced
    ) -> QuranReviewUpdate {
        let elapsed = cursor.lastReviewed.map { max(0, $0.days(to: day)) } ?? 0
        let early = rating == .mastered
            && cursor.intervalDays > 0
            && Double(elapsed) < Double(cursor.intervalDays) * earlyMasteryFraction
        guard !early else {
            return QuranReviewUpdate(
                intervalDays: cursor.intervalDays,
                ease: normalizedEase(cursor.ease),
                wasEarlyMastery: true
            )
        }
        let ease = nextEase(cursor.ease, rating: rating)
        return QuranReviewUpdate(
            intervalDays: nextInterval(
                previousDays: cursor.intervalDays,
                rating: rating,
                preset: preset,
                ease: ease,
                elapsedDays: elapsed
            ),
            ease: ease,
            wasEarlyMastery: false
        )
    }

    public static func memory(
        forPage page: Int,
        events: [QuranReviewEvent],
        through today: GregorianDay,
        preset: QuranReviewPreset = .balanced
    ) -> QuranPageMemory {
        let pageEvents = deduplicated(events)
            .filter { $0.day <= today && $0.pages.contains(page) }
        return foldedMemory(pageEvents, preset: preset)
    }

    private static func foldedMemory(
        _ pageEvents: [QuranReviewEvent],
        preset: QuranReviewPreset
    ) -> QuranPageMemory {
        var cursor = QuranMemoryCursor(intervalDays: 0)
        var lapses = 0
        for event in pageEvents.sorted(by: eventOrder) {
            let update = apply(event.rating, to: cursor, on: event.day, preset: preset)
            cursor = QuranMemoryCursor(
                intervalDays: update.intervalDays,
                ease: update.ease,
                lastReviewed: event.day
            )
            if event.rating == .needsMastery { lapses += 1 }
        }
        return QuranPageMemory(
            intervalDays: cursor.intervalDays,
            ease: cursor.ease,
            lapses: lapses,
            lastReviewed: cursor.lastReviewed
        )
    }

    public static func schedules(
        pages: QuranPageRange,
        events: [QuranReviewEvent],
        openMistakesByPage: [Int: Int] = [:],
        today: GregorianDay,
        preset: QuranReviewPreset = .balanced
    ) -> [QuranPageSchedule] {
        let firstPage = pages.first
        let lastPage = pages.last
        let eventsInWindow = deduplicated(events).filter {
            $0.day <= today && $0.pages.last >= firstPage && $0.pages.first <= lastPage
        }
        var eventsByPage = Array(repeating: [QuranReviewEvent](), count: lastPage - firstPage + 1)
        for event in eventsInWindow {
            let firstCoveredPage = max(firstPage, event.pages.first)
            let lastCoveredPage = min(lastPage, event.pages.last)
            for page in firstCoveredPage...lastCoveredPage {
                eventsByPage[page - firstPage].append(event)
            }
        }

        return (pages.first...pages.last).map { page in
            let memory = foldedMemory(eventsByPage[page - firstPage], preset: preset)
            let mistakes = max(0, openMistakesByPage[page, default: 0])
            guard let lastReviewed = memory.lastReviewed else {
                return QuranPageSchedule(
                    page: page,
                    intervalDays: 0,
                    ease: easeStart,
                    lastReviewed: nil,
                    dueDate: nil,
                    overdueDays: 0,
                    lapses: 0,
                    openMistakes: mistakes,
                    risk: pageRisk(intervalDays: 0, overdueDays: 0, lapses: 0, openMistakes: mistakes, lastReviewed: nil),
                    isDue: true
                )
            }
            let dueDate = lastReviewed.adding(days: memory.intervalDays)
            let overdue = max(0, dueDate.days(to: today))
            return QuranPageSchedule(
                page: page,
                intervalDays: memory.intervalDays,
                ease: memory.ease,
                lastReviewed: lastReviewed,
                dueDate: dueDate,
                overdueDays: overdue,
                lapses: memory.lapses,
                openMistakes: mistakes,
                risk: pageRisk(
                    intervalDays: memory.intervalDays,
                    overdueDays: overdue,
                    lapses: memory.lapses,
                    openMistakes: mistakes,
                    lastReviewed: lastReviewed
                ),
                isDue: dueDate <= today
            )
        }
    }

    public static func pageRisk(
        intervalDays: Int,
        overdueDays: Int,
        lapses: Int,
        openMistakes: Int,
        lastReviewed: GregorianDay?
    ) -> Double {
        let mistakes = Double(max(0, openMistakes)) * 0.5
        let risk: Double
        if lastReviewed == nil {
            risk = neverReviewedRisk + mistakes
        } else {
            let ratio = intervalDays > 0 ? Double(max(0, overdueDays)) / Double(intervalDays) : Double(max(0, overdueDays))
            risk = ratio * 2 + Double(max(0, lapses)) * 0.6 + mistakes
        }
        return (risk * 100).rounded() / 100
    }

    public static func duePages(
        _ schedules: [QuranPageSchedule],
        excluding recentPages: Set<Int> = []
    ) -> [QuranPageSchedule] {
        schedules
            .filter { $0.isDue && !recentPages.contains($0.page) }
            .sorted {
                if $0.risk != $1.risk { return $0.risk > $1.risk }
                if $0.overdueDays != $1.overdueDays { return $0.overdueDays > $1.overdueDays }
                return $0.page < $1.page
            }
    }

    public static func reviewConsistency(
        hifzActivityDays: [GregorianDay],
        reviewActivityDays: [GregorianDay],
        through today: GregorianDay
    ) -> Double {
        let firstDay = today.adding(days: -(consistencyWindowDays - 1))
        let active = Set((hifzActivityDays + reviewActivityDays).filter { $0 >= firstDay && $0 <= today })
        return min(1, Double(active.count) / Double(consistencyWindowDays))
    }

    public static func adaptiveReviewCap(
        dailyReviewPages: Int,
        hifzActivityDays: [GregorianDay],
        reviewActivityDays: [GregorianDay],
        through today: GregorianDay
    ) -> Int {
        let consistency = reviewConsistency(
            hifzActivityDays: hifzActivityDays,
            reviewActivityDays: reviewActivityDays,
            through: today
        )
        let factor = 0.7 + 0.8 * consistency
        return max(2, (Double(dailyReviewPages) * factor).roundedInt)
    }

    public static func dueQueue(
        _ schedules: [QuranPageSchedule],
        dailyReviewPages: Int,
        hifzActivityDays: [GregorianDay],
        reviewActivityDays: [GregorianDay],
        through today: GregorianDay,
        excluding recentPages: Set<Int> = [],
        explicitLimit: Int? = nil
    ) -> QuranDueQueue {
        let due = duePages(schedules, excluding: recentPages)
        let adaptiveCap = adaptiveReviewCap(
            dailyReviewPages: dailyReviewPages,
            hifzActivityDays: hifzActivityDays,
            reviewActivityDays: reviewActivityDays,
            through: today
        )
        let cap = max(1, explicitLimit ?? adaptiveCap)
        return QuranDueQueue(
            pages: Array(due.prefix(cap)),
            total: due.count,
            hidden: max(0, due.count - cap),
            cap: cap
        )
    }

    /// The zero-interval pages are counted in today's due count, not as 1 / 0.
    public static func need(
        recentCount: Int,
        memorizedIntervals: [Int],
        dueCount: Int,
        recoveryShare: Double
    ) -> QuranReviewNeed {
        let recent = Double(max(0, recentCount))
        let expectedDaily = memorizedIntervals.reduce(into: 0.0) { total, interval in
            if interval > 0 { total += 1 / Double(interval) }
        }
        return QuranReviewNeed(
            steadyNeed: recent + expectedDaily,
            todayNeed: recent + Double(max(0, dueCount)) + max(0, recoveryShare.isFinite ? recoveryShare : 0)
        )
    }

    public static func shouldHalfWird(
        need: QuranReviewNeed,
        balanceDecides: Bool,
        forcedFullWird: Bool,
        savedHifzToday: Bool,
        consolidationRequired: Bool,
        factor: Double = halfWirdFactor
    ) -> Bool {
        guard balanceDecides,
              !forcedFullWird,
              !savedHifzToday,
              !consolidationRequired,
              factor.isFinite,
              factor > 0 else { return false }
        return need.todayNeed > factor * need.steadyNeed
    }

    private static func closestRungIndex(to value: Double, ladder: [Int]) -> Int {
        guard !ladder.isEmpty else { return 0 }
        return ladder.indices.min {
            abs(Double(ladder[$0]) - value) < abs(Double(ladder[$1]) - value)
        } ?? 0
    }

    private struct EventKey: Hashable {
        let day: GregorianDay
        let firstPage: Int
        let lastPage: Int
    }

    private static func deduplicated(_ events: [QuranReviewEvent]) -> [QuranReviewEvent] {
        var latestByKey: [EventKey: QuranReviewEvent] = [:]
        for event in events {
            let key = EventKey(day: event.day, firstPage: event.pages.first, lastPage: event.pages.last)
            if let current = latestByKey[key], !isLater(event, than: current) { continue }
            latestByKey[key] = event
        }
        return latestByKey.values.sorted(by: eventOrder)
    }

    private static func isLater(_ lhs: QuranReviewEvent, than rhs: QuranReviewEvent) -> Bool {
        switch (lhs.occurredAt, rhs.occurredAt) {
        case let (left?, right?):
            if left != right { return left > right }
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): break
        }
        return lhs.inputOrder > rhs.inputOrder
    }

    private static func eventOrder(_ lhs: QuranReviewEvent, _ rhs: QuranReviewEvent) -> Bool {
        if lhs.day != rhs.day { return lhs.day < rhs.day }
        switch (lhs.occurredAt, rhs.occurredAt) {
        case let (left?, right?):
            if left != right { return left < right }
        case (nil, _?): return true
        case (_?, nil): return false
        case (nil, nil): break
        }
        return lhs.inputOrder < rhs.inputOrder
    }
}

private extension Double {
    var roundedInt: Int { Int(rounded(.toNearestOrAwayFromZero)) }
}

private extension GregorianDay {
    func days(to later: GregorianDay) -> Int {
        Int((later.date(in: .gmt).timeIntervalSince1970 - date(in: .gmt).timeIntervalSince1970) / 86_400)
    }
}
