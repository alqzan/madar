import Foundation

/// Owner Quran trial (item 19, dev-only): plans the old Madar backup's `quranHifz` part as native rows (§7.4 Q01, §17).
/// Pure: the caller supplies the verified catalog, the home time zone and the stable-identity function, and inserts the
/// rows in one transaction. Every row id derives from the legacy id, so a second run finds them and adds nothing.
/// Past sessions cannot go through `quran.commitSession` (it stamps `now`), so the planner keeps the legacy times.
public enum LegacyQuranImport {
    public struct PlanRow: Equatable, Sendable {
        public let id: UUID, sourceID: String, startAyah: Int, unit: String, amount: Double, rhythm: String
        public let frontierAyah: Int?, activeFrom: Date, updatedAt: Date
    }
    public struct SessionRow: Equatable, Sendable {
        public let id: UUID, sourceModel: String, sourceID: String, kind: String, dayKey: String
        public let endedAt: Date, updatedAt: Date, fromAyah: Int, toAyah: Int, pages: [Int]
        /// The legacy row had no `at`; the time is a deterministic stand-in inside its stored day.
        public let synthesizedTime: Bool
        public let raw: Data
    }
    public struct GradeRow: Equatable, Sendable {
        public let id: UUID, sessionID: UUID, page: Int, grade: String
    }
    public struct SpotRow: Equatable, Sendable {
        public let id: UUID, sourceID: String, ayahId: Int, wordIndex: Int?
        public let legacyHits: Int, legacyLastDrillAt: Date?, legacyStreak: Int, updatedAt: Date
        public let raw: Data
    }
    /// A legacy record or field with no native home, kept whole in ImportLink.unmappedJSON.
    public struct Archive: Equatable, Sendable {
        public let id: UUID, sourceModel: String, sourceID: String, json: Data
    }
    public struct Plan: Equatable, Sendable {
        public var plan: PlanRow?
        public var sessions: [SessionRow] = []
        public var grades: [GradeRow] = []
        public var spots: [SpotRow] = []
        public var archives: [Archive] = []
        public var counts: [String: Int] = [:]
    }

    /// Legacy `HifzRating` (types.ts at aba0c1b): 1 يحتاج إتقاناً · 2 جيّد · 3 متقن. Anything else is not a grade.
    public static func grade(legacy: Any?) -> String? {
        guard let value = legacy as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        switch value.doubleValue { case 1: return "needs"; case 2: return "good"; case 3: return "mastered"; default: return nil }
    }

    /// Compares a legacy word with the bundled token: marks, tatweel and the wasla form are not letters.
    public static func sameWord(_ a: String, _ b: String) -> Bool {
        func bare(_ s: String) -> String {
            String(String.UnicodeScalarView(s.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
                if scalar.properties.generalCategory == .nonspacingMark || scalar.properties.generalCategory == .enclosingMark { return nil }
                switch scalar.value {
                case 0x0640: return nil
                case 0x0671: return Unicode.Scalar(0x0627)
                case 0x06E5, 0x06E6: return nil
                default: return scalar
                }
            }))
        }
        return !bare(a).isEmpty && bare(a) == bare(b)
    }

    public static func plan(backup: Data, timeZone: TimeZone, catalog: QuranResourceCatalog, uuid: (String) -> UUID) throws -> Plan {
        var result = Plan()
        func count(_ key: String, _ n: Int = 1) { result.counts[key, default: 0] += n }
        guard let root = try JSONSerialization.jsonObject(with: backup) as? [String: Any] else { return result }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        func day(_ text: Any?) -> DateComponents? {
            guard let text = text as? String else { return nil }
            let bytes = Array(text.utf8)
            guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
                  bytes[0..<4].allSatisfy({ (48...57).contains($0) }),
                  bytes[5..<7].allSatisfy({ (48...57).contains($0) }),
                  bytes[8..<10].allSatisfy({ (48...57).contains($0) }),
                  let year = Int(String(decoding: bytes[0..<4], as: UTF8.self)),
                  let month = Int(String(decoding: bytes[5..<7], as: UTF8.self)),
                  let day = Int(String(decoding: bytes[8..<10], as: UTF8.self)),
                  (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
            let components = DateComponents(year: year, month: month, day: day)
            guard let date = calendar.date(from: components) else { return nil }
            let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
            guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else { return nil }
            return components
        }
        func at(_ text: Any?, hour: Int, seconds: Int = 0) -> Date? {
            guard var parts = day(text) else { return nil }
            parts.hour = hour; parts.second = seconds
            return calendar.date(from: parts)
        }
        func millis(_ value: Any?) -> Date? {
            guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue > 0 else { return nil }
            return Date(timeIntervalSince1970: value.doubleValue / 1000)
        }
        func json(_ value: Any) -> Data { (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])) ?? Data() }
        func archive(_ model: String, _ id: String, _ value: Any) {
            result.archives.append(Archive(id: uuid("myDream:ImportLink:\(model):\(id)"), sourceModel: model, sourceID: id, json: json(value)))
        }
        for key in ["quranKhatma", "quranWird", "quranReflections"] where root[key] != nil {
            // Recitation khatma is out of scope (§3); wird/reflections have no v1 home. Kept whole, listed by name.
            archive(key, key, root[key]!); count("excluded." + key)
        }
        guard let hifz = root["quranHifz"] as? [String: Any] else { return result }

        // Plan v1. Unit raw values copy 1:1; intensity → rhythm; a missing intensity is the legacy default «balanced».
        let rawFrontier = hifz["frontierId"]
        let frontierValue: Int? = {
            guard let number = rawFrontier as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let value = number.doubleValue
            guard value.isFinite, value.rounded(.towardZero) == value, value >= 0, value <= 6236 else { return nil }
            return Int(value)
        }()
        let frontier = frontierValue ?? 0
        if rawFrontier != nil && frontierValue == nil { count("skipped.frontier") }
        if let plan = hifz["plan"] as? [String: Any] {
            let unit = plan["unit"] as? String, intensity = (plan["intensity"] as? String) ?? "balanced"
            let start = (plan["startId"] as? NSNumber)?.intValue, amount = (plan["amount"] as? NSNumber)?.doubleValue
            if let unit, ["ayah", "quarter", "half", "page"].contains(unit), ["light", "balanced", "intense"].contains(intensity),
               let start, (1...6236).contains(start), let amount, amount >= 1, let from = at(plan["createdAt"], hour: 8) {
                let source = (hifz["planId"] as? String) ?? "plan"
                let id = uuid("myDream:HifzPlan:\(source)")
                result.plan = PlanRow(id: id, sourceID: source, startAyah: start, unit: unit, amount: amount, rhythm: intensity,
                    frontierAyah: frontier > 0 ? frontier : nil, activeFrom: from, updatedAt: millis(hifz["planUpdatedAt"]) ?? from)
                count("plan.imported")
            } else { count("skipped.plan") }
            var extra = plan.filter { !["unit", "intensity", "startId", "amount", "createdAt"].contains($0.key) }
            for key in ["planId", "planUpdatedAt", "frontierId", "frontierUpdatedAt", "lastTestDate"] { if let value = hifz[key] { extra[key] = value } }
            archive("HifzPlan", (hifz["planId"] as? String) ?? "plan", extra)
        }
        let known = Set(["plan", "frontierId", "sessions", "reviews", "mistakes", "lastTestDate", "planId", "planUpdatedAt", "frontierUpdatedAt", "deletedRecords"])
        for (key, value) in hifz where !known.contains(key) { archive("quranHifz." + key, key, value); count("archived.field") }
        // Legacy tombstones whose rows are already gone have nothing to tombstone natively; their ids and stamps are kept.
        if let deleted = hifz["deletedRecords"] as? [String: Any], !deleted.isEmpty {
            archive("HifzDeletedRecords", "deletedRecords", deleted); count("archived.tombstones", deleted.count)
        }
        let tombstoned = Set((hifz["deletedRecords"] as? [String: Any])?.keys.map { $0 } ?? [])

        // Sessions (hifz) and reviews. Legacy arrays are newest first; a missing `at` is placed inside its stored day,
        // hifz in the morning and reviews at night, so a same-day review follows the memorisation it reviews.
        var seenIDs = Set<String>()
        for (model, kind, list, hour) in [("HifzSession", "hifz", hifz["sessions"], 9), ("HifzReviewLog", "review", hifz["reviews"], 22)] {
            let rows = (list as? [[String: Any]]) ?? []
            for (index, row) in rows.enumerated() {
                guard let legacyID = row["id"] as? String, !legacyID.isEmpty, seenIDs.insert(legacyID).inserted else { count("skipped.\(kind).id"); continue }
                if tombstoned.contains(legacyID) { count("skipped.\(kind).tombstoned"); continue }
                guard let dayText = row["date"] as? String, day(dayText) != nil else { count("skipped.\(kind).date"); continue }
                guard let from = (row["fromId"] as? NSNumber)?.intValue, let to = (row["toId"] as? NSNumber)?.intValue,
                      let range = try? QuranAyahRange(first: from, last: to) else { count("skipped.\(kind).range"); continue }
                // A missing grade is never «جيد» by default (Q01): the row is excluded and counted.
                guard let grade = grade(legacy: row["rating"]) else { count("skipped.\(kind).rating"); continue }
                let stamped = millis(row["at"])
                guard let ended = stamped ?? at(dayText, hour: hour, seconds: rows.count - index) else { count("skipped.\(kind).time"); continue }
                let portions = try QuranPortionEngine.pages(for: range, catalog: catalog)
                guard !portions.isEmpty else { count("skipped.\(kind).pages"); continue }
                let id = uuid("myDream:\(model):\(legacyID)")
                result.sessions.append(SessionRow(id: id, sourceModel: model, sourceID: legacyID, kind: kind, dayKey: dayText,
                    endedAt: ended, updatedAt: millis(row["updatedAt"]) ?? ended, fromAyah: from, toAyah: to,
                    pages: portions.map(\.page), synthesizedTime: stamped == nil, raw: json(row)))
                for portion in portions {
                    result.grades.append(GradeRow(id: uuid("myDream:PageGrade:\(legacyID):\(portion.page)"), sessionID: id, page: portion.page, grade: grade))
                }
                count("\(kind).imported"); if stamped == nil { count("\(kind).synthesizedTime") }
            }
        }

        // Q01 gap rule: synthesize only ayahs absent from imported hifz, splitting disjoint ranges so no session covers
        // an ayah already represented by an imported session.
        if let plan = result.plan, frontier >= plan.startAyah {
            var covered = Set<Int>()
            for row in result.sessions where row.kind == "hifz" { covered.formUnion(row.fromAyah...row.toAyah) }
            var gaps: [ClosedRange<Int>] = []
            var gapStart: Int?
            for ayah in plan.startAyah...frontier {
                if covered.contains(ayah) {
                    if let start = gapStart { gaps.append(start...(ayah - 1)); gapStart = nil }
                } else if gapStart == nil { gapStart = ayah }
            }
            if let start = gapStart { gaps.append(start...frontier) }
            for gap in gaps {
                let first = gap.lowerBound, last = gap.upperBound
                let range = try QuranAyahRange(first: first, last: last)
                let pages = try QuranPortionEngine.pages(for: range, catalog: catalog).map(\.page)
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone; f.dateFormat = "yyyy-MM-dd"
                let sourceID = gaps.count == 1 ? "frontierGap" : "frontierGap:\(first)-\(last)"
                result.sessions.append(SessionRow(id: uuid("myDream:HifzSession:\(sourceID)"), sourceModel: "HifzFrontierGap", sourceID: sourceID,
                    kind: "hifz", dayKey: f.string(from: plan.activeFrom), endedAt: plan.activeFrom, updatedAt: plan.activeFrom,
                    fromAyah: first, toAyah: last, pages: pages, synthesizedTime: true, raw: json(["frontierId": frontier, "missing": last - first + 1])))
                count("hifz.frontierGap"); count("hifz.frontierGapAyahs", last - first + 1)
            }
        }

        // Mistake spots. Whole-ayah → wordIndex nil. A word position is kept only when the bundled token at that
        // 0-based index is the same word; otherwise the spot is archived, never guessed.
        var seenKeys = Set<String>()
        for row in (hifz["mistakes"] as? [[String: Any]]) ?? [] {
            guard let legacyID = row["id"] as? String, !legacyID.isEmpty else { count("skipped.mistake.id"); continue }
            if tombstoned.contains(legacyID) { count("skipped.mistake.tombstoned"); continue }
            guard let ayahID = (row["ayahId"] as? NSNumber)?.intValue, let ayah = catalog.ayah(id: ayahID) else {
                archive("HifzMistake", legacyID, row); count("archived.mistake.ayah"); continue
            }
            let wordIndex = (row["wordIndex"] as? NSNumber)?.intValue
            if let wordIndex {
                let tokens = ayah.wordTokens
                guard tokens.indices.contains(wordIndex), let word = row["word"] as? String, sameWord(word, tokens[wordIndex].text) else {
                    archive("HifzMistake", legacyID, row); count("archived.mistake.word"); continue
                }
            }
            guard seenKeys.insert("\(ayahID):\(wordIndex.map(String.init) ?? "all")").inserted else {
                archive("HifzMistake", legacyID, row); count("archived.mistake.duplicateKey"); continue
            }
            let hits = (row["hits"] as? [String])?.count ?? 0
            let lastDrill = at(row["lastDrill"], hour: 12)
            let streak = (row["okStreak"] as? NSNumber)?.intValue ?? 0
            // The old app could close a spot by hand (resolved without two passes). Owner, 24 Oct 2026: those return to
            // the drills until two passes close them. A spot closed by two passes stays closed. Raw values archived.
            let resolved = (row["resolved"] as? Bool) == true && streak >= QuranMistakeEngine.masteryThreshold
            if (row["resolved"] as? Bool) == true && !resolved { count("mistake.reopenedFromHand") }
            let seededStreak = resolved ? QuranMistakeEngine.masteryThreshold : min(max(0, streak), QuranMistakeEngine.masteryThreshold - 1)
            let closedAt = resolved ? (lastDrill ?? at(row["updatedAt"], hour: 12)) : lastDrill
            result.spots.append(SpotRow(id: uuid("myDream:MistakeSpot:\(legacyID)"), sourceID: legacyID, ayahId: ayahID, wordIndex: wordIndex,
                legacyHits: hits, legacyLastDrillAt: closedAt, legacyStreak: seededStreak,
                updatedAt: at(row["updatedAt"], hour: 12) ?? closedAt ?? Date(timeIntervalSince1970: 0), raw: json(row)))
            count(resolved ? "mistake.closed" : "mistake.open")
        }
        return result
    }
}
