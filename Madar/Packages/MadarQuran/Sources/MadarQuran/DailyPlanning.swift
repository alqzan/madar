import Foundation
import MadarCore

public enum QuranDayLevel: String, Codable, CaseIterable, Sendable {
    case simple, medium, deep, max
    public var hifzFactor: Double {
        switch self { case .simple: 0.5; case .medium: 1; case .deep: 1.5; case .max: 2 }
    }
    public var reviewMinimum: Int {
        switch self { case .simple: 4; case .medium: 8; case .deep: 12; case .max: 22 }
    }
}

public enum QuranRestDay: String, Codable, Sendable {
    // Owner, 24 Oct 2026: any day of the week can be the rest day.
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday, none
    /// Calendar weekday, 1 = Sunday … 7 = Saturday; nil for «بلا».
    public var weekday: Int? {
        switch self { case .sunday: 1; case .monday: 2; case .tuesday: 3; case .wednesday: 4; case .thursday: 5; case .friday: 6; case .saturday: 7; case .none: nil }
    }
    public func contains(_ day: GregorianDay) -> Bool {
        guard let weekday else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        return calendar.component(.weekday, from: day.date(in: .gmt)) == weekday
    }
}

public enum QuranPlanError: Error, Equatable {
    case invalidAmount, invalidPages, invalidRecoveryDays, invalidSession, invalidRakats
}

public struct QuranPlan: Sendable {
    public let id: UUID
    public let startAyah: Int
    public let unit: QuranHifzUnit
    public let amount: Double
    public let intensity: QuranReviewIntensity
    public init(id: UUID, startAyah: Int = 1, unit: QuranHifzUnit = .page,
                amount: Double = 1, intensity: QuranReviewIntensity = .balanced) throws {
        guard (1...6236).contains(startAyah) else { throw QuranReviewError.invalidAyahRange }
        guard amount.isFinite, amount > 0 else { throw QuranPlanError.invalidAmount }
        self.id = id; self.startAyah = startAyah; self.unit = unit
        self.amount = amount; self.intensity = intensity
    }
}

/// Values mirror QuranAllotment. The adapter upserts by naturalKey, never by amount.
public struct QuranDailyAllotment: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case hifzExtra, reviewExtra }
    public enum Origin: String, Codable, Sendable { case missPolicy, raise }
    public let dayKey: GregorianDay
    public let kind: Kind
    public let amount: Double
    public let pages: [Int]
    public let origin: Origin
    public let originDayKey: GregorianDay
    public var naturalKey: String { "\(origin.rawValue)/\(originDayKey)/\(dayKey)/\(kind.rawValue)" }
    public init(dayKey: GregorianDay, kind: Kind, amount: Double = 0, pages: [Int] = [],
                origin: Origin, originDayKey: GregorianDay) throws {
        guard amount.isFinite, amount >= 0 else { throw QuranPlanError.invalidAmount }
        guard pages.allSatisfy({ (1...604).contains($0) }) else { throw QuranPlanError.invalidPages }
        self.dayKey = dayKey; self.kind = kind; self.amount = amount
        self.pages = pages.uniqued(); self.origin = origin; self.originDayKey = originDayKey
    }
}

public enum QuranMissedDayChoice: String, Codable, Sendable { case spread, double, skip, postpone }
public enum QuranWirdBalance: String, Sendable { case full, half, consolidation, rest, complete }
public struct QuranDailyHifz: Sendable {
    /// Quantity remains in the plan's unit, including allotments.
    public let amount: Double
    public let balance: QuranWirdBalance
    public let portion: QuranAyahRange?
    public let bridge: QuranAyahRange?
}

public enum QuranDailyPlanEngine {
    public static func missedDayAllotments(
        originDay: GregorianDay, resolvingOn day: GregorianDay, choice: QuranMissedDayChoice,
        missedAmount: Double, restDay: QuranRestDay
    ) throws -> [QuranDailyAllotment] {
        guard originDay < day, missedAmount.isFinite, missedAmount > 0 else {
            throw QuranPlanError.invalidAmount
        }
        // Both leave the coverage frontier unchanged; postpone shifts the calendar forecast from today.
        guard choice != .skip && choice != .postpone else { return [] }
        let count = choice == .spread ? 3 : 1
        var cursor = day, result: [QuranDailyAllotment] = []
        while result.count < count {
            if !restDay.contains(cursor) {
                result.append(try QuranDailyAllotment(dayKey: cursor, kind: .hifzExtra,
                    amount: missedAmount / Double(count), origin: .missPolicy, originDayKey: originDay))
            }
            cursor = cursor.adding(days: 1)
        }
        return result
    }

    public static func hifz(
        plan: QuranPlan, day: GregorianDay, restDay: QuranRestDay = .friday,
        level: QuranDayLevel = .medium, forceNewHifz: Bool = false, balanceDecides: Bool = true,
        consolidation: QuranAyahRange? = nil, savedHifzToday: Bool = false,
        need: QuranReviewNeed, allotments: [QuranDailyAllotment] = [],
        coverage: QuranCoverage, catalog: QuranResourceCatalog
    ) throws -> QuranDailyHifz {
        if restDay.contains(day) && !forceNewHifz {
            return QuranDailyHifz(amount: 0, balance: .rest, portion: nil, bridge: nil)
        }
        if let consolidation, balanceDecides && !forceNewHifz {
            return QuranDailyHifz(amount: 0, balance: .consolidation, portion: consolidation, bridge: nil)
        }
        guard let start = try coverage.frontier(from: plan.startAyah) else {
            return QuranDailyHifz(amount: 0, balance: .complete, portion: nil, bridge: nil)
        }
        let extras = uniqueAllotments(allotments).filter { $0.dayKey == day && $0.kind == .hifzExtra }
            .reduce(0) { $0 + $1.amount }
        let half = QuranReviewEngine.shouldHalfWird(need: need, balanceDecides: balanceDecides,
            forcedFullWird: forceNewHifz, savedHifzToday: savedHifzToday, consolidationRequired: false)
        let amount = (plan.amount * level.hifzFactor + extras) * (half ? 0.5 : 1)
        guard amount.isFinite else { throw QuranPlanError.invalidAmount }
        // Stop at the first already-covered ayah so filling a deleted gap cannot overwrite later hifz.
        let limit = (start...6236).first(where: { coverage.coveredAyahs.contains($0) }).map { $0 - 1 } ?? 6236
        let portion = try QuranPortionEngine.portion(from: start, through: limit,
            unit: plan.unit, amount: amount, catalog: catalog)
        var bridgeStart = start
        while bridgeStart > plan.startAyah && start - bridgeStart < 3 && coverage.coveredAyahs.contains(bridgeStart - 1) {
            bridgeStart -= 1
        }
        let bridge = bridgeStart < start ? try QuranAyahRange(first: bridgeStart, last: start - 1) : nil
        return QuranDailyHifz(amount: amount, balance: half ? .half : .full, portion: portion, bridge: bridge)
    }

    /// RQ1/RQ6: recent first, ALL due by strength, then fill the level minimum.
    /// Recovery/raise are extra targets; test pages are always the final segment, once only.
    public static func review(
        pages: [QuranPlanningPage], recent: [Int], level: QuranDayLevel = .medium,
        recovery: [Int] = [], raised: [Int] = [], test: [Int] = [], completedToday: Set<Int> = [], serveDue: Bool = true
    ) -> QuranDailyReview {
        let indexed = Dictionary(pages.map { ($0.page, $0) }, uniquingKeysWith: { first, _ in first })
        let eligible = Set(indexed.keys).subtracting(completedToday)
        let recent = recent.uniqued().filter { eligible.contains($0) }.sorted()
        let due = pages.filter { serveDue && $0.isDue && eligible.contains($0.page) }.sorted(by: QuranPlanningPage.weakestFirst)
        var regular = (recent + due.map(\.page)).uniqued()
        let fillers = pages.filter { eligible.contains($0.page) }.sorted(by: QuranPlanningPage.weakestFirst)
        let remainingMinimum = Swift.max(0, level.reviewMinimum - completedToday.intersection(Set(indexed.keys)).count)
        for page in fillers where regular.count < remainingMinimum && !regular.contains(page.page) {
            regular.append(page.page)
        }
        regular = (regular + recovery + raised).uniqued().filter { eligible.contains($0) }
        let tests = test.uniqued().filter { eligible.contains($0) }
        // A page selected for the test is moved out of the regular segment.
        regular.removeAll { tests.contains($0) }
        let remainingRecent = recent.filter { !tests.contains($0) }
        let older = regular.filter { !remainingRecent.contains($0) }.sorted()
        // Merge before sorting: the weakest face determines a run's priority (Q03/RQ6).
        var groups: [[Int]] = []
        for page in older {
            if groups.last?.last == page - 1 { groups[groups.count - 1].append(page) }
            else { groups.append([page]) }
        }
        groups.sort {
            let left = $0.compactMap { indexed[$0]?.strength }.min() ?? 100
            let right = $1.compactMap { indexed[$0]?.strength }.min() ?? 100
            return left == right ? $0[0] < $1[0] : left < right
        }
        regular = remainingRecent + groups.flatMap { $0 }
        return QuranDailyReview(regularPages: regular, testPages: tests)
    }

    static func uniqueAllotments(_ allotments: [QuranDailyAllotment]) -> [QuranDailyAllotment] {
        var seen = Set<String>()
        return allotments.filter { seen.insert($0.naturalKey).inserted }
    }
}

public struct QuranDailyReview: Equatable, Sendable {
    public let regularPages: [Int]
    public let testPages: [Int]
    public var allPages: [Int] { regularPages + testPages }
    /// Merge adjacent faces without changing the prescribed order.
    public var runs: [QuranPageRange] {
        var result: [QuranPageRange] = []
        for segment in [regularPages, testPages] {
            var start: Int?, last: Int?
            for page in segment {
                if let previous = last, page == previous + 1 { last = page }
                else {
                    if let start, let last { result.append(try! QuranPageRange(first: start, last: last)) }
                    start = page; last = page
                }
            }
            if let start, let last { result.append(try! QuranPageRange(first: start, last: last)) }
        }
        return result
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>(); return filter { seen.insert($0).inserted }
    }
}
