import MadarCore
import MadarQuran
import XCTest

/// [FIX] RQ1 and the 13 Oct 2026 delegated targets (docs/DECISIONS.md): a 365-day load simulation at 100, 300 and
/// 604 memorised faces, with 100% «متقن» and with 35% «جيد»: half-wird days ≤ 10% and ≤ 20%, never more than 3 in a row.
/// The faces are first memorised one a day (a warm-up that is not measured), so the year starts from the state a real
/// reciter reaches, not from a ready-made steady state. Hifz continues during the year (a full wird adds one face,
/// a half wird half a face) up to 604. Ratings come from a seeded generator, so 35% is 35% of all reviews.
/// The same simulation under the old fixed-cap rule must fail, which shows the test can fail.
@MainActor
final class ReviewBalanceSimulationTests: XCTestCase {
    private enum Rule { case computedNeed, oldFixedCap }
    private struct Page { var cursor = QuranMemoryCursor(intervalDays: 0); var memorizedOn: GregorianDay }
    private struct Result {
        var halfDays = 0, longestRun = 0, days = 0, goodReviews = 0, reviews = 0
        var halfPercent: Double { Double(halfDays) * 100 / Double(max(1, days)) }
        var goodShare: Double { Double(goodReviews) / Double(max(1, reviews)) }
    }
    /// SplitMix64: deterministic, so a run is reproducible.
    private struct Generator {
        var state: UInt64
        mutating func unit() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
        }
    }

    func testSimulatedReviewBalanceMeetsTheApprovedTargetsAtAllCorpusSizes() throws {
        for pageCount in [100, 300, 604] {
            let mastered = try simulate(pageCount: pageCount, goodShare: 0, rule: .computedNeed)
            let mixed = try simulate(pageCount: pageCount, goodShare: 0.35, rule: .computedNeed)
            print("RQ1 simulation: pages=\(pageCount), mastered=\(mastered.halfPercent)% (run \(mastered.longestRun)), 35%-good=\(mixed.halfPercent)% (run \(mixed.longestRun)), good share=\(mixed.goodShare)")
            XCTAssertEqual(mixed.goodShare, 0.35, accuracy: 0.02, "the mixed profile really is 35% «جيد»")
            XCTAssertLessThanOrEqual(mastered.halfPercent, 10)
            XCTAssertLessThanOrEqual(mixed.halfPercent, 20)
            XCTAssertLessThanOrEqual(mastered.longestRun, 3)
            XCTAssertLessThanOrEqual(mixed.longestRun, 3)
        }
    }

    /// RQ1 "Problem": under the written fixed-N rule the backlog grows and half a wird becomes the norm
    /// (347 of 365 days at 284 faces). If this ever passes the targets, the simulation has stopped measuring load.
    func testTheOldFixedCapRuleFailsTheSameSimulation() throws {
        for pageCount in [300, 604] {
            let old = try simulate(pageCount: pageCount, goodShare: 0.35, rule: .oldFixedCap)
            print("RQ1 old rule: pages=\(pageCount), half=\(old.halfPercent)%")
            XCTAssertGreaterThan(old.halfPercent, 20)
        }
    }

    /// Decision text: the rule "fires only after a real pile-up such as missed days". A missed fortnight must trigger it.
    func testMissedDaysPileUpTriggersHalfWird() throws {
        let result = try simulate(pageCount: 300, goodShare: 0.35, rule: .computedNeed, missedDays: 100..<114)
        print("RQ1 after 14 missed days: half=\(result.halfDays) days, run \(result.longestRun)")
        XCTAssertGreaterThan(result.halfDays, 0)
    }

    private func simulate(pageCount: Int, goodShare: Double, rule: Rule, missedDays: Range<Int> = 0..<0) throws -> Result {
        let preset = QuranReviewPreset.balanced, recentCount = 5, oldCap = 8
        var generator = Generator(state: UInt64(pageCount) &* 7919 &+ UInt64(goodShare * 1000))
        var day = try GregorianDay("2025-01-01")
        var pages: [Page] = [], hifzCarry = 0.0
        var result = Result(), run = 0

        func rate(_ result: inout Result, measured: Bool) -> QuranReviewRating {
            let good = generator.unit() < goodShare
            if measured { result.reviews += 1; if good { result.goodReviews += 1 } }
            return good ? .good : .mastered
        }
        func review(_ index: Int, measured: Bool) {
            let rating = rate(&result, measured: measured)
            let update = QuranReviewEngine.apply(rating, to: pages[index].cursor, on: day, preset: preset)
            pages[index].cursor = QuranMemoryCursor(intervalDays: update.intervalDays, ease: update.ease, lastReviewed: day)
        }
        func memorize(measured: Bool) {
            guard pages.count < 604 else { return }
            pages.append(Page(memorizedOn: day))
            review(pages.count - 1, measured: measured) // the hifz grade is the face's first event
        }

        // Warm-up: one face a day until the corpus size is reached; reviews follow the same rule, nothing is measured.
        // Measured year: 365 days.
        let warmUp = pageCount
        for offset in 0..<(warmUp + 365) {
            let measured = offset >= warmUp
            let recent = Set(pages.indices.suffix(recentCount))
            let due = pages.indices.filter { index in
                !recent.contains(index) && pages[index].cursor.lastReviewed.map { $0.adding(days: pages[index].cursor.intervalDays) <= day } == true
            }
            let half: Bool
            var served: [Int]
            switch rule {
            case .computedNeed:
                let need = QuranReviewEngine.need(recentCount: recent.count, memorizedIntervals: pages.map(\.cursor.intervalDays),
                    dueCount: due.count, recoveryShare: 0)
                half = QuranReviewEngine.shouldHalfWird(need: need, balanceDecides: true, forcedFullWird: false,
                    savedHifzToday: false, consolidationRequired: false)
                served = Array(recent) + due // RQ1: every due face is served
            case .oldFixedCap:
                half = due.count > 2 * oldCap
                let weakest = due.sorted { pages[$0].cursor.intervalDays < pages[$1].cursor.intervalDays }
                served = Array(recent) + weakest.prefix(max(0, oldCap - recent.count))
            }
            served.sort()
            let missed = measured && missedDays.contains(offset - warmUp)
            if !missed { for index in served { review(index, measured: measured) } }

            if missed {
                run = 0; day = day.adding(days: 1); continue
            } else if !measured {
                memorize(measured: false)
            } else {
                result.days += 1
                if half { result.halfDays += 1; run += 1; result.longestRun = max(result.longestRun, run) } else { run = 0 }
                hifzCarry += half ? 0.5 : 1
                while hifzCarry >= 1 { hifzCarry -= 1; memorize(measured: true) }
            }
            day = day.adding(days: 1)
        }
        return result
    }
}
