import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarPrayer

/// §7.3 N04. Letters move only forward (sealed → eligible/orphaned → opened); projects link by Entry.projectID.
@MainActor enum DiaryLetterHandler {
    private static func touch<T: MadarRecordModel>(_ row: T, _ now: Date, _ writer: String, set: (T) -> Void) throws {
        set(row); var record = try row.record(); try record.set(StableIdentity.monotonic(now: now, previous: record.date("updatedAt") ?? now), for: "updatedAt"); try record.set(writer, for: "writerID"); try row.apply(record)
    }
    private static func hijriToday(context: ModelContext, now: Date) throws -> (GregorianDay, HijriDate) {
        let today = try DiaryLineRenderer.today(context: context, now: now), settings = try SettingsStore(context: context)
        let zone = try PrayerRepository(context: context).place(at: now).timeZone
        let hijri = HijriCalendar.date(for: today.date(in: zone).addingTimeInterval(12 * 3600), timeZone: zone,
            source: HijriSource(rawValue: try settings.value(for: "core.hijriSource").string ?? "") ?? .ummAlQura, sightingOffset: Int(try settings.value(for: "core.hijriOffset").number ?? 0))
        return (today, hijri)
    }
    static func seal(id: UUID, text: String, trigger: DiaryLetterTrigger, value: String?, target: UUID?, context: ModelContext, now: Date, writer: String) throws -> Data? {
        if let existing = try context.fetch(FetchDescriptor<Letter>()).first(where: { $0.id == id }) {
            guard existing.text == text, existing.triggerKind == trigger.rawValue else { throw DataError.invalidValue("letter identity") }
            return nil
        }
        let (today, hijri) = try hijriToday(context: context, now: now)
        if trigger == .date, let value, try GregorianDay(value) <= today { throw DataError.invalidValue("اختر يومًا بعد اليوم") }
        if trigger == .hijriDate, let value, value <= DiaryLetters.hijriKey(hijri) { throw DataError.invalidValue("اختر يومًا بعد اليوم") }
        if trigger == .projectFinished, !(try context.fetch(FetchDescriptor<Project>()).contains { $0.id == target && $0.deletedAt == nil && $0.mergedInto == nil && $0.finishedAt == nil }) { throw DataError.invalidValue("المشروع غير متاح") }
        if [.tripStart, .tripEnd].contains(trigger), let target, !(try context.fetch(FetchDescriptor<Trip>()).contains { $0.id == target && $0.deletedAt == nil && $0.mergedInto == nil && !$0.dismissed }) { throw DataError.invalidValue("الرحلة غير متاحة") }
        let row = Letter(); row.id = id; row.text = text; row.triggerKind = trigger.rawValue; row.triggerTargetID = target; row.state = DiaryLetterState.sealed.rawValue
        switch trigger {
        case .date: row.triggerValue = value; row.openAt = try value.map { try GregorianDay($0).date(in: PrayerRepository(context: context).home.timeZone) }
        case .hijriDate: row.triggerValue = value
        case .ramadanStart: row.triggerValue = DiaryLetters.nextRamadan(after: hijri)
        default: break
        }
        row.createdAt = now; row.updatedAt = now; row.writerID = writer; context.insert(row)
        return try JSONEncoder().encode(DiaryInverse(model: "Letter", after: row.record(), dayKey: today.description, previousOrigin: nil))
    }
    static func world(context: ModelContext, now: Date) throws -> DiaryLetterWorld {
        let (today, hijri) = try hijriToday(context: context, now: now)
        let trips = try context.fetch(FetchDescriptor<Trip>()).filter { $0.mergedInto == nil && $0.start != nil }.map { DiaryLetterWorld.Trip(id: $0.id, start: $0.start!, end: $0.end, live: $0.deletedAt == nil && !$0.dismissed) }
        let projects = try context.fetch(FetchDescriptor<Project>()).filter { $0.mergedInto == nil }.map { DiaryLetterWorld.Project(id: $0.id, finishedAt: $0.finishedAt, live: $0.deletedAt == nil) }
        return .init(now: now, today: today, hijriToday: hijri, trips: trips, projects: projects)
    }
    static func facts(_ row: Letter) -> DiaryLetterFacts? {
        guard let trigger = DiaryLetterTrigger(rawValue: row.triggerKind), let state = DiaryLetterState(rawValue: row.state) else { return nil }
        return .init(writtenAt: row.createdAt, trigger: trigger, openDay: trigger == .date ? row.triggerValue.flatMap { try? GregorianDay($0) } : nil,
                     hijriValue: [.hijriDate, .ramadanStart].contains(trigger) ? row.triggerValue : nil, target: row.triggerTargetID, state: state)
    }
    /// Run when the diary opens and the app returns to the foreground. No undo: states only move forward.
    static func refresh(context: ModelContext, now: Date, writer: String) throws {
        let world = try world(context: context, now: now)
        for row in try context.fetch(FetchDescriptor<Letter>()) where row.deletedAt == nil && row.mergedInto == nil && row.state == DiaryLetterState.sealed.rawValue {
            guard let facts = facts(row) else { continue }
            let next = DiaryLetters.evaluate(facts, in: world)
            guard next != .sealed else { continue }
            try touch(row, now, writer) { $0.state = next.rawValue; if next == .eligible { $0.eligibleAt = now } }
        }
    }
    /// The first opening sets openedAt once; reading again later changes nothing.
    static func open(_ id: UUID, context: ModelContext, now: Date, writer: String) throws {
        guard let row = try context.fetch(FetchDescriptor<Letter>()).first(where: { $0.id == id && $0.deletedAt == nil && $0.mergedInto == nil }) else { throw DataError.invalidValue("missing letter") }
        if row.state == DiaryLetterState.opened.rawValue { return }
        guard [DiaryLetterState.eligible.rawValue, DiaryLetterState.orphaned.rawValue].contains(row.state) else { throw DataError.invalidValue("الرسالة لم يحن وقتها") }
        try touch(row, now, writer) { $0.state = DiaryLetterState.opened.rawValue; if $0.openedAt == nil { $0.openedAt = now } }
    }
    /// «اختر موعدًا» for an orphaned letter: it waits for a date instead.
    static func reschedule(_ id: UUID, day: String, context: ModelContext, now: Date, writer: String) throws -> Data {
        guard let row = try context.fetch(FetchDescriptor<Letter>()).first(where: { $0.id == id && $0.deletedAt == nil && $0.mergedInto == nil }), row.state == DiaryLetterState.orphaned.rawValue else { throw DataError.invalidValue("orphaned letter required") }
        let key = try GregorianDay(day); guard key > (try DiaryLineRenderer.today(context: context, now: now)) else { throw DataError.invalidValue("اختر يومًا بعد اليوم") }
        let before = try row.record(), zone = try PrayerRepository(context: context).home.timeZone
        try touch(row, now, writer) { $0.triggerKind = DiaryLetterTrigger.date.rawValue; $0.triggerValue = day; $0.triggerTargetID = nil; $0.openAt = key.date(in: zone); $0.state = DiaryLetterState.sealed.rawValue }
        return try JSONEncoder().encode(DiaryInverse(model: "Letter", after: row.record(), dayKey: day, previousOrigin: nil, before: before))
    }
}

/// Read-only: whether `diary.refreshLetters` would move any letter. Callers skip the write otherwise.
@MainActor public enum DiaryLetterCheck {
    public static func pending(context: ModelContext, now: Date) throws -> Bool {
        let world = try DiaryLetterHandler.world(context: context, now: now)
        return try context.fetch(FetchDescriptor<Letter>()).contains { row in
            row.deletedAt == nil && row.mergedInto == nil && row.state == DiaryLetterState.sealed.rawValue && DiaryLetterHandler.facts(row).map { DiaryLetters.evaluate($0, in: world) != .sealed } == true
        }
    }
}
