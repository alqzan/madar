import Foundation

public enum QuranSessionKind: String, Codable, Sendable {
    case hifz, review, free, qiyam, drill
}

public struct QuranCoverageSession: Sendable {
    public let id: String
    public let kind: QuranSessionKind
    public let ayahs: QuranAyahRange
    public let endedAt: Date
    public let isDeleted: Bool

    public init(id: String, kind: QuranSessionKind, ayahs: QuranAyahRange, endedAt: Date, isDeleted: Bool = false) {
        self.id = id; self.kind = kind; self.ayahs = ayahs; self.endedAt = endedAt; self.isDeleted = isDeleted
    }
}

public struct QuranCoveragePage: Sendable {
    public let number: Int
    public let ayahIDs: Set<Int>

    public init(number: Int, ayahIDs: Set<Int>) throws {
        guard (1...604).contains(number), !ayahIDs.isEmpty,
              ayahIDs.allSatisfy({ (1...6236).contains($0) }) else { throw QuranCoverageError.invalidMap }
        self.number = number; self.ayahIDs = ayahIDs
    }
}

public struct QuranPartialPage: Equatable, Sendable {
    public let page: Int
    public let memorizedRanges: [QuranAyahRange]
}

public struct QuranCoverage: Equatable, Sendable {
    public let ranges: [QuranAyahRange]
    public let coveredAyahs: Set<Int>
    public let completedPages: Set<Int>
    public let completedJuz: Set<Int>
    public let pagesOutsideCompletedJuz: Set<Int>
    public let memorizedAt: [Int: Date]
    /// RQ5: these ayahs enter recent review even before their page is complete.
    public let partialRecentPortions: [QuranPartialPage]

    public var percent: Int { completedPages.count * 100 / 604 }
    public var isKhatm: Bool { completedPages == Set(1...604) }

    public func frontier(from startAyah: Int) throws -> Int? {
        guard (1...6236).contains(startAyah) else { throw QuranReviewError.invalidAyahRange }
        for id in startAyah...6236 where !coveredAyahs.contains(id) { return id }
        return nil
    }

    public func planProgress(in range: QuranAyahRange) -> Double {
        Double((range.first...range.last).filter { coveredAyahs.contains($0) }.count) /
            Double(range.last - range.first + 1)
    }
}

public enum QuranCoverageError: Error, Equatable {
    case invalidMap
    case invalidQuantity
    case invalidTimestamp
}

public enum QuranCoverageEngine {
    public static func summarize(sessions: [QuranCoverageSession], catalog: QuranResourceCatalog) throws -> QuranCoverage {
        guard let layout = catalog.layout else { throw QuranCoverageError.invalidMap }
        let pages = try layout.pages.map { page in
            try QuranCoveragePage(number: page.page, ayahIDs: Set(page.lines.flatMap(\.words).map(\.ayahID)))
        }
        return try summarize(sessions: sessions, pages: pages, juzSegments: catalog.juzCycleSegments())
    }

    /// Rebuilds from active facts on every call. Deletion/undo never adjusts a stored counter.
    public static func summarize(
        sessions: [QuranCoverageSession], pages: [QuranCoveragePage], juzSegments: [QuranCycleSegment] = []
    ) throws -> QuranCoverage {
        guard Set(pages.map(\.number)).count == pages.count,
              Set(juzSegments.map(\.number)).count == juzSegments.count,
              juzSegments.allSatisfy({ (1...30).contains($0.number) }) else { throw QuranCoverageError.invalidMap }
        let active = sessions.filter { $0.kind == .hifz && !$0.isDeleted }
        guard active.allSatisfy({ $0.endedAt.timeIntervalSince1970.isFinite }) else {
            throw QuranCoverageError.invalidTimestamp
        }
        let ordered = active.sorted {
            $0.endedAt == $1.endedAt ? $0.id < $1.id : $0.endedAt < $1.endedAt
        }
        var pagesByAyah: [Int: [Int]] = [:]
        var remaining = Dictionary(uniqueKeysWithValues: pages.map { ($0.number, $0.ayahIDs.count) })
        for page in pages {
            for id in page.ayahIDs { pagesByAyah[id, default: []].append(page.number) }
        }
        var covered = Set<Int>()
        var times: [Int: Date] = [:]
        for session in ordered {
            for id in session.ayahs.first...session.ayahs.last where covered.insert(id).inserted {
                for page in pagesByAyah[id, default: []] {
                    remaining[page, default: 0] -= 1
                    if remaining[page] == 0 { times[page] = session.endedAt }
                }
            }
        }
        let complete = Set(pages.filter { $0.ayahIDs.isSubset(of: covered) }.map(\.number))
        let completeJuz = juzSegments.filter { segment in
            (segment.ayahs.first...segment.ayahs.last).allSatisfy { covered.contains($0) }
        }
        let juzAyahs = Set(completeJuz.flatMap { Array($0.ayahs.first...$0.ayahs.last) })
        let extra = Set(pages.filter { complete.contains($0.number) && !$0.ayahIDs.isSubset(of: juzAyahs) }.map(\.number))
        let partial = try pages.sorted { $0.number < $1.number }.compactMap { page -> QuranPartialPage? in
            let ids = page.ayahIDs.intersection(covered)
            guard !ids.isEmpty, !complete.contains(page.number) else { return nil }
            return QuranPartialPage(page: page.number, memorizedRanges: try normalizedIDs(ids))
        }
        return QuranCoverage(ranges: try normalizedIDs(covered), coveredAyahs: covered, completedPages: complete,
                             completedJuz: Set(completeJuz.map(\.number)), pagesOutsideCompletedJuz: extra,
                             memorizedAt: times, partialRecentPortions: partial)
    }

    private static func normalizedIDs(_ ids: Set<Int>) throws -> [QuranAyahRange] {
        let sorted = ids.sorted()
        guard let first = sorted.first else { return [] }
        var start = first, last = first
        var result: [QuranAyahRange] = []
        for id in sorted.dropFirst() {
            if id == last + 1 { last = id }
            else { result.append(try QuranAyahRange(first: start, last: last)); start = id; last = id }
        }
        result.append(try QuranAyahRange(first: start, last: last))
        return result
    }
}

public enum QuranHifzUnit: String, Codable, Sendable { case ayah, quarter, half, page }

public struct QuranPagePortion: Equatable, Sendable {
    public let page: Int
    public let wholePage: Bool
    public let ayahs: QuranAyahRange
}

public enum QuranPortionEngine {
    public static func portion(
        from start: Int, through limit: Int = 6236, unit: QuranHifzUnit,
        amount: Double, multiplier: Double = 1, catalog: QuranResourceCatalog
    ) throws -> QuranAyahRange {
        guard (1...6236).contains(start), (start...6236).contains(limit),
              catalog.ayahs.count == 6236, catalog.ayah(id: start) != nil else {
            throw QuranReviewError.invalidAyahRange
        }
        guard amount.isFinite, multiplier.isFinite, amount > 0, multiplier > 0,
              (amount * multiplier).isFinite else { throw QuranCoverageError.invalidQuantity }
        let scaled = amount * multiplier
        if unit == .ayah {
            let count = max(1, Int(min(6236, scaled).rounded(.toNearestOrAwayFromZero)))
            return try QuranAyahRange(first: start, last: min(limit, start + count - 1))
        }
        let factor: Double = unit == .quarter ? 0.25 : (unit == .half ? 0.5 : 1)
        let quantity = min(604, scaled * factor)
        guard let first = catalog.ayah(id: start) else { throw QuranCoverageError.invalidMap }
        // Preserve portionEnd's page-boundary result for integral face quantities.
        if quantity >= 1, abs(quantity - quantity.rounded()) < 1e-10 {
            let page = min(604, first.page + Int(quantity.rounded()) - 1)
            guard let last = catalog.ayahs(on: page).last?.id else { throw QuranCoverageError.invalidMap }
            return try QuranAyahRange(first: start, last: min(limit, last))
        }
        let target = Double(first.page) + Double(first.lineStart - 1) / 15 + quantity
        var best = start
        var distance = Double.infinity
        for ayah in catalog.ayahs where (start...limit).contains(ayah.id) {
            let end = Double(ayah.page) + Double(ayah.lineEnd) / 15
            let candidate = abs(end - target)
            // Equal distances retain the earlier ayah, independent of float noise.
            if candidate < distance - 1e-10 { best = ayah.id; distance = candidate }
        }
        return try QuranAyahRange(first: start, last: best)
    }

    public static func pages(for range: QuranAyahRange, catalog: QuranResourceCatalog) throws -> [QuranPagePortion] {
        guard let layout = catalog.layout else { throw QuranCoverageError.invalidMap }
        return try layout.pages.compactMap { page in
            let ids = Set(page.lines.flatMap(\.words).map(\.ayahID))
            let included = ids.filter { (range.first...range.last).contains($0) }.sorted()
            guard let first = included.first, let last = included.last else { return nil }
            return QuranPagePortion(page: page.page, wholePage: included.count == ids.count,
                                    ayahs: try QuranAyahRange(first: first, last: last))
        }
    }

    public static func leadOnPage(from ayah: Int, catalog: QuranResourceCatalog) -> Int? {
        guard ayah > 1, let current = catalog.ayah(id: ayah),
              let previous = catalog.ayah(id: ayah - 1), previous.page == current.page else { return nil }
        return ayah - 1
    }
}
