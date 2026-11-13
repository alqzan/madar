import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarQuran

public struct QuranDraftPayload: Codable, Sendable {
    public var draft: QuranSessionDraft
    public var revealedAyahs: Set<Int>?
    public var testPages: [Int]?
    public var drillKey: QuranMistakeKey?
    public var method: String
    public var nightKey: GregorianDay?
    public var rakats: Int?
    public var witr: Bool?
    public var coach: QuranCoachProgress?
    public var reviewSections: [QuranReviewSection]?
    public var qiyamRakahIndex: Int?
    public init(draft: QuranSessionDraft, method: String = "coach", nightKey: GregorianDay? = nil, rakats: Int? = nil, witr: Bool? = nil, drillKey: QuranMistakeKey? = nil, testPages: [Int]? = nil, revealedAyahs: Set<Int>? = nil) {
        self.draft = draft; self.revealedAyahs = revealedAyahs; self.testPages = testPages; self.drillKey = drillKey; self.method = method; self.nightKey = nightKey; self.rakats = rakats; self.witr = witr
    }
}
private struct QuranInverse: Codable {
    let version: Int
    let before: [DataRecord]
    let after: [DataRecord]
}
public struct QuranStagedResult: Sendable {
    public let inverse: Data?
    public let duplicate: Bool
}

/// Stages within DurableCommandAdapter's lease/context. It never saves or suspends.
@MainActor public enum QuranMutationHandler {
    public static func stage(name: String, payload: [String: MadarCore.JSONValue], in context: ModelContext,
                             catalog: QuranResourceCatalog, now: Date, writer: String) throws -> QuranStagedResult {
        guard QuranCommandPayload.validate(name: name, payload: payload) else { throw DataError.invalidValue("Quran payload") }
        let repository = try QuranRepository(context: context, catalog: catalog)
        // Only an undoable command needs the full history to build its inverse; a draft save or discard has none.
        let before = nonUndoableCommands.contains(name) ? [] : try records(context)
        func text(_ key: String) -> String { if case .string(let value) = payload[key] { value } else { "" } }
        func number(_ key: String) -> Double { if case .number(let value) = payload[key] { value } else { 0 } }
        func id(_ key: String) throws -> UUID { guard let id = UUID(uuidString: text(key)) else { throw DataError.invalidValue("Quran id") }; return id }
        func touch<T: MadarRecordModel>(_ row: T, deleting: Bool = false) throws {
            var record = try row.record()
            let stamp = StableIdentity.monotonic(now: now, previous: record.date("updatedAt") ?? now)
            try record.set(stamp, for: "updatedAt"); try record.set(writer, for: "writerID")
            if deleting { try record.set(stamp, for: "deletedAt"); try record.set(stamp, for: "deletionBarrierAt") }
            try row.apply(record)
        }
        // Same restore stamping as undo: keep the barrier, mark restoredAt after it.
        func revive<T: MadarRecordModel>(_ row: T) throws {
            var record = try row.record()
            let stamp = StableIdentity.monotonic(now: now, previous: record.date("updatedAt") ?? now)
            let barrier = record.date("deletionBarrierAt") ?? record.date("deletedAt")
            try record.set(nil as Date?, for: "deletedAt"); try record.set(barrier, for: "deletionBarrierAt")
            try record.set(max(stamp, (barrier ?? .distantPast).addingTimeInterval(0.001)), for: "restoredAt")
            try row.apply(record)
        }
        func dayState(_ day: GregorianDay) throws -> QuranDayState {
            let rows = try context.fetch(FetchDescriptor<QuranDayState>()).filter { $0.dayKey == day.description && $0.mergedInto == nil }
            if let row = rows.max(by: { $0.updatedAt < $1.updatedAt }) {
                // An undone day choice is a tombstone; a new choice revives it from clean defaults.
                if row.deletedAt != nil {
                    row.hifzLevel = nil; row.reviewLevel = nil; row.forceNewHifz = false; row.testPages = []
                    try revive(row)
                }
                return row
            }
            let row = QuranDayState(); row.id = StableIdentity.uuid(for: "QuranDayState:\(day)"); row.dayKey = day.description
            row.createdAt = now; context.insert(row); return row
        }
        func putAllotment(_ value: QuranDailyAllotment) throws {
            let rows = try context.fetch(FetchDescriptor<QuranAllotment>()).filter { $0.mergedInto == nil }
            if let existing = rows.first(where: { $0.origin == value.origin.rawValue && $0.originDayKey == value.originDayKey.description && $0.dayKey == value.dayKey.description && $0.kind == value.kind.rawValue }) {
                if existing.deletedAt != nil {
                    // An undone allotment is revived with the new choice instead of silently swallowing it.
                    existing.amount = value.amount; existing.pages = value.pages
                    try revive(existing); try touch(existing); return
                }
                if value.origin == .raise {
                    var seen = Set<Int>()
                    let union = (existing.pages + value.pages).filter { seen.insert($0).inserted }
                    if union != existing.pages { existing.pages = union; try touch(existing) }
                }
                return
            }
            let row = QuranAllotment(); row.id = StableIdentity.uuid(for: "QuranAllotment:\(value.naturalKey)")
            row.dayKey = value.dayKey.description; row.kind = value.kind.rawValue; row.amount = value.amount; row.pages = value.pages
            row.origin = value.origin.rawValue; row.originDayKey = value.originDayKey.description; row.createdAt = now
            context.insert(row); try touch(row)
        }
        var duplicate = false, needsCache = false, undoable = true
        switch name {
        case "quran.saveDraft":
            undoable = false
            guard let data = Data(base64Encoded: text("draft")) else { throw DataError.invalidValue("Quran draft") }
            let value = try JSONDecoder().decode(QuranDraftPayload.self, from: data), draft = value.draft
            guard draft.startedAt <= now, [.hifz, .review, .free, .qiyam, .drill].contains(draft.kind),
                  ["coach", "completeAyah", "gradual", "next", "link", "continuous"].contains(value.method) else { throw DataError.invalidValue("Quran draft") }
            if draft.kind == .qiyam {
                guard value.nightKey != nil, let rakats = value.rakats, [2, 4, 6, 8].contains(rakats), (0...rakats).contains(value.qiyamRakahIndex ?? draft.grades.count) else { throw DataError.invalidValue("Quran qiyam draft") }
            }
            let snapshot = try repository.snapshot(at: now)
            // Validation is reused even for a learning-only draft that has nothing eligible to commit yet.
            _ = try QuranSessionEngine.prepareCommit(draft: draft, endedAt: now, alreadyCommitted: [], coverage: snapshot.coverage, catalog: catalog)
            let sessions = try context.fetch(FetchDescriptor<HifzSession>()).filter { $0.mergedInto == nil }
            guard !sessions.contains(where: { $0.commitID == draft.id }) else { return QuranStagedResult(inverse: nil, duplicate: true) }
            let existing = try context.fetch(FetchDescriptor<SessionDraft>()).first { $0.id == draft.id && $0.mergedInto == nil }
            if let existing {
                let previous = try JSONDecoder().decode(QuranDraftPayload.self, from: existing.provisionalJSON)
                guard existing.deletedAt == nil, previous.draft.startedAt == draft.startedAt,
                      previous.draft.storedDay == draft.storedDay, previous.draft.portions == draft.portions,
                      previous.draft.planID == draft.planID, previous.draft.kind == draft.kind,
                      previous.nightKey == value.nightKey, previous.rakats == value.rakats, previous.testPages == value.testPages,
                      previous.drillKey == value.drillKey else { throw DataError.invalidValue("Quran draft identity") }
            } else {
                guard !snapshot.drafts.contains(where: { $0.id != draft.id }) else { throw DataError.invalidValue("Quran draft already active") }
            }
            let row = existing ?? SessionDraft(); row.id = draft.id; row.kind = draft.kind.rawValue; row.dayKey = draft.storedDay.dayKey; row.startedAt = draft.startedAt
            row.portionJSON = try JSONEncoder().encode(draft.portions)
            row.cursorJSON = try JSONEncoder().encode(draft)
            row.provisionalJSON = try JSONEncoder().encode(value)
            if existing == nil { row.createdAt = now; context.insert(row) }; try touch(row)
        case "quran.discardDraft":
            undoable = false
            let draftID = try id("draftID")
            if let row = try context.fetch(FetchDescriptor<SessionDraft>()).first(where: { $0.id == draftID && $0.mergedInto == nil && $0.deletedAt == nil }) { try touch(row, deleting: true) }
            else { duplicate = true }
        case "quran.saveBookmark":
            let bookmarkID = try id("id")
            let row = try context.fetch(FetchDescriptor<MushafBookmark>(predicate: #Predicate { $0.id == bookmarkID && $0.mergedInto == nil })).first
            guard row?.deletedAt == nil else { throw DataError.invalidValue("Quran bookmark deleted") }
            let bookmark = row ?? MushafBookmark()
            bookmark.id = bookmarkID; bookmark.page = Int(number("page")); bookmark.name = text("name").trimmingCharacters(in: .whitespacesAndNewlines)
            if row == nil { bookmark.createdAt = now; context.insert(bookmark) }
            try touch(bookmark)
        case "quran.deleteBookmark":
            let bookmarkID = try id("id")
            guard let row = try context.fetch(FetchDescriptor<MushafBookmark>(predicate: #Predicate { $0.id == bookmarkID && $0.mergedInto == nil && $0.deletedAt == nil })).first else { duplicate = true; break }
            try touch(row, deleting: true)
        case "quran.discardUnreadableDrafts":
            undoable = false
            // T02: diary drafts share this table and are never Quran drafts.
            let rows = try context.fetch(FetchDescriptor<SessionDraft>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && !$0.kind.hasPrefix("diary.") }
            var discardedAny = false
            for row in rows {
                let value: QuranSessionDraft
                do {
                    value = try JSONDecoder().decode(QuranDraftPayload.self, from: row.provisionalJSON).draft
                } catch is DecodingError {
                    try touch(row, deleting: true)
                    discardedAny = true
                    continue
                }
                let hasValidIdentity = value.id == row.id && value.storedDay.dayKey == row.dayKey && value.kind.rawValue == row.kind
                if !hasValidIdentity {
                    try touch(row, deleting: true)
                    discardedAny = true
                }
            }
            duplicate = !discardedAny
        case "quran.commitSession":
            let draftID = try id("draftID")
            let existing = try context.fetch(FetchDescriptor<HifzSession>()).filter { $0.mergedInto == nil }
            let row = try context.fetch(FetchDescriptor<SessionDraft>()).first { $0.id == draftID && $0.mergedInto == nil && $0.deletedAt == nil }
            if existing.contains(where: { $0.commitID == draftID }) {
                if let row { try touch(row, deleting: true) }
                return QuranStagedResult(inverse: nil, duplicate: true)
            }
            guard let row else { throw DataError.invalidValue("Quran draft missing") }
            let value = try JSONDecoder().decode(QuranDraftPayload.self, from: row.provisionalJSON)
            let snapshot = try repository.snapshot(at: now)
            guard let commit = try QuranSessionEngine.prepareCommit(draft: value.draft, endedAt: now,
                alreadyCommitted: Set(existing.compactMap(\.commitID)), coverage: snapshot.coverage, catalog: catalog) else {
                throw DataError.invalidValue("Quran session has no completed work")
            }
            let session = HifzSession(); session.id = StableIdentity.uuid(for: "HifzSession:\(commit.commitID)")
            session.commitID = commit.commitID; session.planID = commit.planID; session.dayKey = commit.storedDay.dayKey
            session.tzID = commit.storedDay.timeZoneID; session.dayPolicy = "\(commit.storedDay.boundary.rawValue)@1"
            session.kind = commit.kind.rawValue; session.fromAyah = commit.ayahs.first; session.toAyah = commit.ayahs.last
            session.endedAt = commit.endedAt; session.pages = commit.pages; session.method = value.method
            session.mistakes = commit.mistakes.filter { $0.kind == .mistake }.count; session.createdAt = now
            context.insert(session); try touch(session)
            for grade in commit.grades {
                let row = PageGrade(); row.id = StableIdentity.uuid(for: "PageGrade:\(session.id):\(grade.page)")
                row.sessionID = session.id; row.page = grade.page; row.grade = grade.rating.storedRaw; row.role = grade.isTest ? "test" : "regular"
                row.createdAt = now; context.insert(row); try touch(row)
            }
            for (index, event) in commit.mistakes.enumerated() {
                let row = MistakeEvent(); row.id = StableIdentity.uuid(for: "MistakeEvent:\(session.id):\(index)")
                row.sessionID = session.id; row.ayahId = event.key.ayahID; row.wordIndex = event.key.wordIndex; row.kind = event.kind.rawValue
                row.at = event.at; row.createdAt = now; context.insert(row); try touch(row)
            }
            if commit.kind == .qiyam {
                guard let night = value.nightKey, let target = value.rakats else { throw DataError.invalidValue("Quran qiyam metadata") }
                let completed = value.qiyamRakahIndex ?? value.draft.grades.count
                let partial: Bool = if case .bool(true) = payload["partial"] { true } else { false }
                guard completed > 0, completed <= target, partial || completed == target else { throw DataError.invalidValue("أكمل الركعات أو سجّل ما أتممت صراحة") }
                let rakats = partial ? completed : target
                let existing = try context.fetch(FetchDescriptor<QiyamNight>()).filter { $0.nightKey == night.description && $0.mergedInto == nil }.max { $0.updatedAt < $1.updatedAt }
                guard existing?.deletedAt == nil else { throw DataError.invalidValue("explicitRestoreRequired") }
                guard existing?.quranSessionID == nil else { throw DataError.invalidValue("Qiyam wird already recorded") }
                let row = existing ?? QiyamNight(); row.nightKey = night.description; row.rakaat = Swift.max(row.rakaat, rakats)
                row.witr = row.witr || (value.witr ?? false); row.quranSessionID = session.id
                if existing == nil { row.id = StableIdentity.uuid(for: "QiyamNight:\(night)"); row.createdAt = now; row.tzID = commit.storedDay.timeZoneID; row.dayPolicy = "prayerDay@1"; context.insert(row) }
                session.nightKey = night.description; try touch(row); try touch(session)
            }
            // Draft tombstone, session, children and receipt commit in the caller's single save.
            try touch(row, deleting: true); needsCache = true
        case "quran.savePlan":
            let plans = try context.fetch(FetchDescriptor<HifzPlan>()).filter { $0.mergedInto == nil }
            let previous = plans.filter { $0.deletedAt == nil && $0.supersededAt == nil }.max { $0.version < $1.version }
            for old in plans where old.deletedAt == nil && old.supersededAt == nil { old.supersededAt = now; try touch(old) }
            let row = HifzPlan(); row.version = (plans.map(\.version).max() ?? 0) + 1
            row.startAyah = Int(number("startAyah")); row.unit = text("unit"); row.amount = number("amount"); row.rhythm = text("rhythm"); row.missPolicy = text("missPolicy")
            // B2-7: changing the amount or rhythm of the same plan continues it; only a different starting ayah begins a new one.
            row.activeFrom = previous.flatMap { $0.startAyah == row.startAyah && $0.activeFrom <= now ? $0.activeFrom : nil } ?? now
            row.createdAt = now; context.insert(row); try touch(row)
            try repository.settings.prepare(.string(text("restDay")), for: "quran.restDay", now: now)
            needsCache = true
        case "quran.setTodayLevel", "quran.forceNewHifz", "quran.freezeTest":
            let day = try repository.currentDay(at: now), row = try dayState(day.date)
            if name == "quran.setTodayLevel" {
                if text("kind") == "hifz" { row.hifzLevel = text("level") } else { row.reviewLevel = text("level") }
            } else if name == "quran.forceNewHifz" { row.forceNewHifz = true }
            else if row.testPages.isEmpty { row.testPages = try repository.snapshot(at: now).testPages }
            try touch(row)
        case "quran.resolveMissedDay":
            let origin = try GregorianDay(text("dayKey")), snapshot = try repository.snapshot(at: now)
            guard origin < snapshot.day.date, let plan = snapshot.plan, snapshot.hifz?.balance != .complete,
                  origin >= snapshot.planStartDay ?? origin,
                  !snapshot.restDay.contains(origin), !snapshot.sessions.contains(where: { $0.kind == .hifz && $0.dayKey == origin }) else { throw DataError.invalidValue("Quran missed day") }
            let rows = try context.fetch(FetchDescriptor<QuranAllotment>()).filter { $0.mergedInto == nil }
            if rows.contains(where: { $0.deletedAt == nil && $0.origin == "missPolicy" && $0.originDayKey == origin.description }) { duplicate = true; break }
            let habitual = QuranDayLevel(rawValue: try repository.settings.value(for: "quran.hifzLevel").string ?? "medium") ?? .medium
            let choice = QuranMissedDayChoice(rawValue: text("choice"))!
            // A passed day is judged by the plan version that was active on it (same start ayah and unit; the latest saved on or before that day).
            var dayAmount = plan.plan.amount
            for row in try context.fetch(FetchDescriptor<HifzPlan>()).sorted(by: { $0.version < $1.version })
            where row.deletedAt == nil && row.mergedInto == nil && row.startAyah == plan.plan.startAyah && row.unit == plan.plan.unit.rawValue {
                if try repository.currentDay(at: row.createdAt).date <= origin { dayAmount = row.amount }
            }
            let targets = try QuranDailyPlanEngine.missedDayAllotments(originDay: origin, resolvingOn: snapshot.day.date, choice: choice,
                missedAmount: dayAmount * habitual.hifzFactor, restDay: snapshot.restDay)
            if targets.isEmpty {
                try putAllotment(QuranDailyAllotment(dayKey: snapshot.day.date, kind: .hifzExtra, origin: .missPolicy, originDayKey: origin))
            } else { for target in targets { try putAllotment(target) } }
        case "quran.createRecovery", "quran.cancelRecovery":
            let rows = try context.fetch(FetchDescriptor<RecoveryPlan>()).filter { $0.mergedInto == nil && $0.deletedAt == nil && $0.cancelledAt == nil }
            for row in rows { row.cancelledAt = now; try touch(row) }
            if name == "quran.createRecovery" {
                let snapshot = try repository.snapshot(at: now)
                let value = try QuranRecoveryPlan.starting(on: snapshot.day.date, days: Int(number("days")), candidates: snapshot.pages)
                guard !value.pages.isEmpty else { throw DataError.invalidValue("Quran no far pages") }
                let row = RecoveryPlan(); row.startDayKey = value.startDayKey.description; row.days = value.days; row.pages = value.pages
                row.createdAt = now; context.insert(row); try touch(row)
            }
        case "quran.raisePages":
            let snapshot = try repository.snapshot(at: now), juz = Int(number("juz"))
            let segment = try catalog.juzCycleSegments().first { $0.number == juz }
            guard let segment else { throw DataError.invalidValue("Quran juz") }
            let ayahs = Set(segment.ayahs.first...segment.ayahs.last)
            let candidates = snapshot.pages.filter { catalog.ayahs(on: $0.page).contains { ayahs.contains($0.id) } }
            try putAllotment(QuranRecoveryEngine.raise(on: snapshot.day.date, pages: candidates))
        case "quran.editSessionGrade", "quran.deleteSession":
            let sessionID = try id("sessionID")
            guard let session = try context.fetch(FetchDescriptor<HifzSession>()).first(where: { $0.id == sessionID && $0.mergedInto == nil && $0.deletedAt == nil }) else { throw DataError.invalidValue("Quran session missing") }
            let grades = try context.fetch(FetchDescriptor<PageGrade>()).filter { $0.sessionID == sessionID && $0.mergedInto == nil && $0.deletedAt == nil }
            if name == "quran.editSessionGrade" {
                guard let grade = grades.first(where: { $0.page == Int(number("page")) }) else { throw DataError.invalidValue("Quran grade missing") }
                grade.grade = text("grade"); try touch(grade)
            } else {
                try touch(session, deleting: true)
                for grade in grades { try touch(grade, deleting: true) }
                for event in try context.fetch(FetchDescriptor<MistakeEvent>()) where event.sessionID == sessionID && event.mergedInto == nil && event.deletedAt == nil { try touch(event, deleting: true) }
                for night in try context.fetch(FetchDescriptor<QiyamNight>()) where night.quranSessionID == sessionID && night.mergedInto == nil && night.deletedAt == nil { night.quranSessionID = nil; try touch(night) }
            }
            needsCache = true
        default: throw DataError.invalidValue("Quran command unavailable")
        }
        if needsCache { try rebuildCache(repository, at: now, writer: writer) }
        guard undoable else { return QuranStagedResult(inverse: nil, duplicate: duplicate) }
        let after = try records(context)
        let changed = after.filter { record in before.first(where: { $0.model == record.model && $0.id == record.id }) != record }
        guard !changed.isEmpty else { return QuranStagedResult(inverse: nil, duplicate: true) }
        let original = before.filter { record in changed.contains { $0.model == record.model && $0.id == record.id } }
        return QuranStagedResult(inverse: try JSONEncoder().encode(QuranInverse(version: 1, before: original, after: changed)), duplicate: duplicate)
    }

    public static func undo(_ data: Data, in context: ModelContext, catalog: QuranResourceCatalog, now: Date, writer: String) throws {
        let inverse = try JSONDecoder().decode(QuranInverse.self, from: data)
        guard inverse.version == 1 else { throw DataError.invalidValue("Quran stale undo") }
        let current = try records(context)
        for after in inverse.after {
            guard current.first(where: { $0.model == after.model && $0.id == after.id }) == after else { throw DataError.invalidValue("Quran undo superseded") }
        }
        for after in inverse.after {
            let before = inverse.before.first { $0.model == after.model && $0.id == after.id }
            var restored = before ?? after
            let stamp = StableIdentity.monotonic(now: now, previous: after.date("updatedAt") ?? now)
            try restored.set(stamp, for: "updatedAt"); try restored.set(writer, for: "writerID")
            if before == nil { try restored.set(stamp, for: "deletedAt"); try restored.set(stamp, for: "deletionBarrierAt") }
            else if restored.isLive && after.deletedAt != nil { try restored.set(after.date("deletionBarrierAt"), for: "deletionBarrierAt"); try restored.set(stamp, for: "restoredAt") }
            try RecordBridge.upsert(restored, in: context)
        }
        try rebuildCache(QuranRepository(context: context, catalog: catalog), at: now, writer: writer)
    }

    private static let nonUndoableCommands: Set<String> = ["quran.saveDraft", "quran.discardDraft", "quran.discardUnreadableDrafts"]
    /// Counts full-history reads, so a test can prove that a non-undoable command performs none.
    nonisolated(unsafe) static var historyReads = 0
    private static func records(_ context: ModelContext) throws -> [DataRecord] {
        historyReads += 1
        var rows = try context.fetch(FetchDescriptor<HifzPlan>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<HifzSession>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<PageGrade>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MistakeEvent>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<QuranDayState>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<QuranAllotment>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<RecoveryPlan>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MushafBookmark>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<QiyamNight>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Setting>()).filter { $0.key == "quran.restDay" }.map { try $0.record() }
        return rows.filter { $0.fields["mergedInto"] == .null }
    }

    /// Also used by the DEBUG owner trial after inserting legacy rows directly.
    public static func rebuildCache(_ repository: QuranRepository, at now: Date, writer: String) throws {
        let snapshot = try repository.snapshot(at: now), context = repository.context
        let rows = try context.fetch(FetchDescriptor<PageSchedule>()).filter { $0.mergedInto == nil }
        for old in rows where !snapshot.coverage.completedPages.contains(old.page) && old.deletedAt == nil {
            old.deletedAt = now; old.updatedAt = StableIdentity.monotonic(now: now, previous: old.updatedAt); old.writerID = writer
        }
        for page in snapshot.pages {
            let existing = rows.first { $0.page == page.page }
            let row = existing ?? PageSchedule()
            let at = snapshot.coverage.memorizedAt[page.page]
            let lastAt = snapshot.sessions.last { $0.grades.contains { $0.page == page.page } && [.review, .free, .qiyam].contains($0.kind) && $0.endedAt > (at ?? .distantPast) }?.endedAt ?? at
            guard existing == nil || row.deletedAt != nil || row.memorizedAt != at || row.nextDue != page.nextDue.description || row.lastReviewedAt != lastAt || row.lastGrade != page.grade.storedRaw || row.ease != snapshot.memories[page.page]?.ease || row.scheduleVersion != 1 else { continue }
            row.page = page.page; row.memorizedAt = at; row.nextDue = page.nextDue.description; row.lastReviewedAt = lastAt
            row.ease = snapshot.memories[page.page]?.ease ?? 1
            row.lastGrade = page.grade.storedRaw; row.scheduleVersion = 1; row.deletedAt = nil
            row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt); row.writerID = writer
            // stage is an unused legacy cache field; no stage fact is introduced.
            if existing == nil { row.id = StableIdentity.uuid(for: "PageSchedule:\(page.page)"); row.createdAt = now; context.insert(row) }
        }
    }
}
