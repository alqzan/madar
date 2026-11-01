import Foundation
import Testing
@testable import MadarQuran

/// Expected values come from the legacy definitions (types.ts at aba0c1b: rating 1 يحتاج · 2 جيد · 3 متقن;
/// frontierId = last memorised ayah; MISTAKE_MASTERY = 2), §7.4 Q01 and the Madani page facts
/// (al-Fatiha 1–7 is face 1; al-Baqarah 1–5 opens face 2). Never from the planner's own output.
@Suite struct LegacyQuranImportTests {
    let zone = TimeZone(identifier: "Asia/Riyadh")!
    /// Deterministic stand-in for StableIdentity (FNV-1a over two seeds).
    func uuid(_ key: String) -> UUID {
        func fnv(_ seed: UInt64) -> UInt64 { key.utf8.reduce(seed) { ($0 ^ UInt64($1)) &* 0x100000001b3 } }
        let a = fnv(0xcbf29ce484222325), b = fnv(0x84222325cbf29ce4)
        return UUID(uuidString: String(format: "%08X-%04X-%04X-%04X-%012llX", UInt32(a >> 32), UInt16((a >> 16) & 0xFFFF), UInt16(a & 0xFFFF), UInt16(b >> 48), b & 0xFFFFFFFFFFFF))!
    }

    let fixture: [String: Any] = [
        "quranKhatma": ["completed": 0, "juz": 3],
        "quranHifz": [
            "plan": ["intensity": "intense", "unit": "quarter", "createdAt": "2026-07-19", "amount": 1, "reviewWindowPages": 10, "startId": 1],
            "frontierId": 12, "planId": "l:1:2026-07-19", "planUpdatedAt": 1784988142570, "lastTestDate": "2026-10-20",
            "sessions": [
                ["id": "s-new", "date": "2026-07-20", "fromId": 6, "toId": 7, "rating": 1, "at": 1784530800000],
                ["id": "s-old", "date": "2026-07-19", "fromId": 1, "toId": 5, "rating": 3],
                ["id": "s-norating", "date": "2026-07-21", "fromId": 8, "toId": 9],
                ["id": "s-gone", "date": "2026-07-21", "fromId": 8, "toId": 9, "rating": 2],
            ],
            "reviews": [["id": "r-1", "date": "2026-07-19", "fromId": 1, "toId": 12, "rating": 2]],
            "mistakes": [
                ["id": "m-word", "ayahId": 2, "wordIndex": 0, "word": "ٱلۡحَمۡدُ", "hits": ["2026-07-20"], "resolved": false, "okStreak": 1, "updatedAt": "2026-07-20"],
                ["id": "m-wrong", "ayahId": 2, "wordIndex": 0, "word": "رَبِّ", "hits": ["2026-07-20"], "resolved": false, "updatedAt": "2026-07-20"],
                ["id": "m-hand", "ayahId": 3, "wordIndex": NSNull(), "hits": ["2026-07-20", "2026-07-21"], "resolved": true, "okStreak": 1, "updatedAt": "2026-07-22"],
            ],
            "deletedRecords": ["s-gone": 1784600000000],
        ],
    ]

    func run(_ backup: [String: Any]) throws -> LegacyQuranImport.Plan {
        try LegacyQuranImport.plan(backup: JSONSerialization.data(withJSONObject: backup), timeZone: zone, catalog: QuranResourceCatalog.bundled(), uuid: { uuid($0) })
    }
    func run() throws -> LegacyQuranImport.Plan { try run(fixture) }

    @Test func gradesFollowTheLegacyEnum() {
        #expect(LegacyQuranImport.grade(legacy: 1) == "needs")
        #expect(LegacyQuranImport.grade(legacy: 2) == "good")
        #expect(LegacyQuranImport.grade(legacy: 3) == "mastered")
        #expect(LegacyQuranImport.grade(legacy: nil) == nil)
        #expect(LegacyQuranImport.grade(legacy: 4) == nil)
        #expect(LegacyQuranImport.grade(legacy: true) == nil)
    }

    @Test func planSessionsAndPages() throws {
        let plan = try run()
        let p = try #require(plan.plan)
        #expect(p.unit == "quarter" && p.amount == 1 && p.startAyah == 1 && p.rhythm == "intense" && p.frontierAyah == 12)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        #expect(cal.dateComponents([.year, .month, .day], from: p.activeFrom) == DateComponents(year: 2026, month: 7, day: 19))
        let byID = Dictionary(uniqueKeysWithValues: plan.sessions.map { ($0.sourceID, $0) })
        // Missing rating → excluded and counted; a tombstoned id never imports.
        #expect(byID["s-norating"] == nil && plan.counts["skipped.hifz.rating"] == 1)
        #expect(byID["s-gone"] == nil && plan.counts["skipped.hifz.tombstoned"] == 1)
        let old = try #require(byID["s-old"]), new = try #require(byID["s-new"]), review = try #require(byID["r-1"])
        #expect(old.pages == [1] && new.pages == [1] && review.pages == [1, 2])
        #expect(new.endedAt == Date(timeIntervalSince1970: 1_784_530_800) && !new.synthesizedTime)
        // No `at`: inside the stored day, hifz before the same-day review.
        #expect(old.synthesizedTime && old.dayKey == "2026-07-19")
        #expect(cal.component(.hour, from: old.endedAt) == 9 && cal.component(.hour, from: review.endedAt) == 22)
        #expect(old.endedAt < review.endedAt)
        let grades = plan.grades.filter { $0.sessionID == review.id }.map(\.grade)
        #expect(grades == ["good", "good"])
        #expect(plan.grades.first { $0.sessionID == new.id }?.grade == "needs")
        #expect(plan.grades.first { $0.sessionID == old.id }?.grade == "mastered")
    }

    @Test func frontierGapIsOneImportSession() throws {
        let plan = try run()
        // Hifz reaches ayah 7; the legacy frontier is 12 → one session covers 8…12.
        let gap = try #require(plan.sessions.first { $0.sourceModel == "HifzFrontierGap" })
        #expect(gap.fromAyah == 8 && gap.toAyah == 12 && gap.kind == "hifz" && gap.pages == [2])
        #expect(plan.counts["hifz.frontierGap"] == 1 && plan.counts["hifz.frontierGapAyahs"] == 5)
        #expect(plan.grades.contains { $0.sessionID == gap.id } == false)
    }

    @Test func frontierGapsDoNotCoverAyahsAlreadyImported() throws {
        var backup = fixture
        var hifz = backup["quranHifz"] as! [String: Any]
        hifz["frontierId"] = 8
        hifz["sessions"] = [
            ["id": "s-prefix", "date": "2026-07-19", "fromId": 1, "toId": 2, "rating": 3],
            ["id": "s-island", "date": "2026-07-20", "fromId": 5, "toId": 6, "rating": 2],
        ]
        hifz["reviews"] = []
        backup["quranHifz"] = hifz

        let plan = try run(backup)
        let gaps = plan.sessions.filter { $0.sourceModel == "HifzFrontierGap" }
        #expect(gaps.map { "\($0.fromAyah)-\($0.toAyah)" } == ["3-4", "7-8"])
        #expect(Set(gaps.map(\.id)).count == 2)
        #expect(plan.counts["hifz.frontierGap"] == 2 && plan.counts["hifz.frontierGapAyahs"] == 4)
    }

    @Test func invalidGregorianSessionDaysAreSkipped() throws {
        var backup = fixture
        var hifz = backup["quranHifz"] as! [String: Any]
        hifz["frontierId"] = 0
        hifz["sessions"] = [
            ["id": "s-invalid-day", "date": "2026-02-31", "fromId": 1, "toId": 2, "rating": 3],
            ["id": "s-malformed-day", "date": "2026--1-01", "fromId": 1, "toId": 2, "rating": 3],
        ]
        hifz["reviews"] = [["id": "r-invalid-day", "date": "2026-02-31", "fromId": 1, "toId": 2, "rating": 2]]
        backup["quranHifz"] = hifz

        let plan = try run(backup)
        #expect(plan.sessions.isEmpty)
        #expect(plan.counts["skipped.hifz.date"] == 2 && plan.counts["skipped.review.date"] == 1)
    }

    @Test func outOfRangeFrontierIsSkippedWithoutAbortingPlan() throws {
        var backup = fixture
        var hifz = backup["quranHifz"] as! [String: Any]
        hifz["frontierId"] = 6237
        backup["quranHifz"] = hifz

        let plan = try run(backup)
        #expect(plan.plan?.frontierAyah == nil)
        #expect(plan.sessions.contains { $0.sourceModel == "HifzFrontierGap" } == false)
        #expect(plan.counts["skipped.frontier"] == 1)
    }

    @Test func mistakesKeepWordsOnlyWhenTheyMatch() throws {
        let plan = try run()
        let word = try #require(plan.spots.first { $0.sourceID == "m-word" })
        #expect(word.ayahId == 2 && word.wordIndex == 0 && word.legacyHits == 1 && word.legacyStreak == 1)
        #expect(plan.spots.contains { $0.sourceID == "m-wrong" } == false)
        #expect(plan.archives.contains { $0.sourceModel == "HifzMistake" && $0.sourceID == "m-wrong" })
        // Closed by hand in the old app (one pass): owner, 24 Oct 2026 — back to the drills, its one pass kept.
        let hand = try #require(plan.spots.first { $0.sourceID == "m-hand" })
        #expect(hand.wordIndex == nil && hand.legacyHits == 2 && hand.legacyStreak == 1 && hand.legacyLastDrillAt == nil)
        #expect(plan.counts["mistake.reopenedFromHand"] == 1 && plan.counts["mistake.open"] == 2)
    }

    @Test func everythingElseIsArchivedAndTheRunIsDeterministic() throws {
        let plan = try run()
        #expect(plan.counts["excluded.quranKhatma"] == 1 && plan.counts["archived.tombstones"] == 1)
        let planArchive = try #require(plan.archives.first { $0.sourceModel == "HifzPlan" })
        let extra = try #require(JSONSerialization.jsonObject(with: planArchive.json) as? [String: Any])
        #expect(Set(extra.keys) == ["reviewWindowPages", "planId", "planUpdatedAt", "frontierId", "lastTestDate"])
        #expect(try run() == plan)
    }

    /// Owner data, this Mac only: runs when MADAR_TRIAL_QURAN names the old backup. Prints counts, never content.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MADAR_TRIAL_QURAN"] != nil)) func ownerBackupPlansWithoutFailures() throws {
        let path = try #require(ProcessInfo.processInfo.environment["MADAR_TRIAL_QURAN"])
        let plan = try LegacyQuranImport.plan(backup: Data(contentsOf: URL(fileURLWithPath: path)), timeZone: zone, catalog: QuranResourceCatalog.bundled(), uuid: { uuid($0) })
        print("OWNER-QURAN-COUNTS", plan.counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        #expect(plan.plan != nil)
        #expect(plan.counts.keys.contains { $0.hasPrefix("skipped.") } == false)
    }
}
