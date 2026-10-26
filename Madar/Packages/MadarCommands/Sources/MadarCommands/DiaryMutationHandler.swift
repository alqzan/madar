import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarPrayer

struct DiaryInverse: Codable {
    let model: String
    let after: DataRecord
    let dayKey: String
    let previousOrigin: String?
    var before: DataRecord? = nil
    var deletedEntries: [DiaryEntryDeletion]? = nil
}
struct DiaryEntryDeletion: Codable {
    let before: DataRecord
    let after: DataRecord
}
@MainActor enum DiaryMutationHandler {
    static func stage(text: String, day: String, targetDay: String?, id: UUID, context: ModelContext, now: Date, writer: String, mediaIDs: [UUID] = [], audioID: UUID? = nil, storedDay: GregorianDay? = nil) throws -> Data? {
        let settings = try SettingsStore(context: context), prayer = try PrayerRepository(context: context)
        let place = prayer.place(at: now), civil = GregorianDay.containing(now, in: place.timeZone)
        let boundary = DayBoundary(rawValue: try settings.value(for: "core.dayStart").string ?? "") ?? .fajr
        let days = [civil.adding(days: -1), civil].compactMap { PrayerTimesEngine.calculate(day: $0, place: place, options: prayer.options) }
        let stored = try MadarDay.resolve(instant: now, place: place, boundary: boundary, prayerDays: days)
        let key = storedDay ?? (day == "yesterday" ? stored.date.adding(days: -1) : stored.date)
        guard key <= stored.date else { throw DataError.invalidValue("future diary day") }
        if let targetDay {
            guard let target = try? GregorianDay(targetDay), target < stored.date else { throw DataError.invalidValue("margin target") }
            let rows = try context.fetch(FetchDescriptor<MarginNote>())
            if rows.contains(where: { $0.id == id }) { return nil }
            let row = MarginNote(); row.id = id; row.text = text; row.targetDayKey = targetDay
            row.writtenAt = now; row.writtenDayKey = stored.dayKey; row.tzID = place.timeZoneID; row.dayPolicy = boundary.rawValue + "@1"
            row.createdAt = now; row.updatedAt = now; row.writerID = writer; context.insert(row)
            return try JSONEncoder().encode(DiaryInverse(model: "MarginNote", after: row.record(), dayKey: stored.dayKey, previousOrigin: nil))
        }
        let entries = try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id }))
        if !entries.isEmpty { return nil }
        let selectedKey = key.description
        let keyedPages = try context.fetch(FetchDescriptor<DayPage>(predicate: #Predicate { $0.dayKey == selectedKey && $0.mergedInto == nil }))
        guard !keyedPages.contains(where: { $0.deletedAt != nil }) else { throw DataError.invalidValue("explicitRestoreRequired: diary day") }
        let pages = keyedPages.filter { $0.deletedAt == nil }
        let page = pages.max { $0.updatedAt < $1.updatedAt } ?? DayPage()
        let previousOrigin = page.origin
        if pages.isEmpty {
            page.dayKey = key.description; page.createdAt = now; context.insert(page)
        }
        page.origin = "native"; page.updatedAt = StableIdentity.monotonic(now: now, previous: page.updatedAt); page.writerID = writer
        let row = Entry(); row.id = id; row.dayKey = key.description; row.eventAt = now
        row.tzID = place.timeZoneID; row.dayPolicy = boundary.rawValue + "@1"; row.text = text
        row.attachmentMediaIDs = mediaIDs; row.mediaID = audioID
        row.ink = key < stored.date ? "late" : "normal"; row.source = "native"
        row.createdAt = now; row.updatedAt = now; row.writerID = writer; context.insert(row)
        return try JSONEncoder().encode(DiaryInverse(model: "Entry", after: row.record(), dayKey: key.description, previousOrigin: previousOrigin))
    }
    static func setIntention(id:UUID,day:String,text:String,context:ModelContext,now:Date,writer:String) throws -> Data {
        guard try GregorianDay(day) <= DiaryLineRenderer.today(context:context,now:now) else{throw DataError.invalidValue("future intention")}
        let rows=try context.fetch(FetchDescriptor<Niyya>()),existing=rows.first{$0.id==id}
        guard existing?.deletedAt == nil,existing?.mergedInto == nil,existing == nil || existing?.dayKey==day else{throw DataError.invalidValue("intention identity")}
        let live=rows.filter{$0.dayKey==day && $0.deletedAt==nil && $0.mergedInto==nil}
        guard existing != nil || live.count<10 else{throw DataError.invalidValue("تتّسع الصفحة لعشر نيّات؛ يمكنك تعديل نيّة موجودة")}
        let before=try existing?.record(),row=existing ?? Niyya()
        if existing==nil {row.id=id;row.dayKey=day;row.order=(0...9).first{n in !live.contains{$0.order==n}} ?? 0;row.createdAt=now;context.insert(row)}
        row.text=text;row.updatedAt=StableIdentity.monotonic(now:now,previous:row.updatedAt);row.writerID=writer
        return try JSONEncoder().encode(DiaryInverse(model:"Niyya",after:row.record(),dayKey:row.dayKey,previousOrigin:nil,before:before))
    }
    static func setIntentionResult(id:UUID,result:String?,context:ModelContext,now:Date,writer:String) throws -> Data {
        guard let row=try context.fetch(FetchDescriptor<Niyya>()).first(where:{$0.id==id && $0.deletedAt==nil && $0.mergedInto==nil}) else{throw DataError.invalidValue("missing intention")}
        let before=try row.record();row.result=result;row.updatedAt=StableIdentity.monotonic(now:now,previous:row.updatedAt);row.writerID=writer
        return try JSONEncoder().encode(DiaryInverse(model:"Niyya",after:row.record(),dayKey:row.dayKey,previousOrigin:nil,before:before))
    }
    static func setTranscript(entry: UUID, text: String, context: ModelContext, now: Date, writer: String) throws -> Data {
        guard let row = try context.fetch(FetchDescriptor<Entry>()).first(where: { $0.id == entry && $0.deletedAt == nil && $0.mergedInto == nil }), let media = row.mediaID,
            try context.fetch(FetchDescriptor<Media>()).contains(where: { $0.id == media && $0.kind == "audio" && $0.deletedAt == nil && $0.mergedInto == nil }) else { throw DataError.invalidValue("audio entry required") }
        let before = try row.record(); row.text = text; row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt); row.writerID = writer
        return try JSONEncoder().encode(DiaryInverse(model: "Entry", after: row.record(), dayKey: row.dayKey, previousOrigin: nil, before: before))
    }
    /// RD1. Before the freeze the line is corrected in place (undo restores the text). After it, a new row replaces
    /// the head and names it; the original row is never changed, and undo tombstones only the new row.
    static func edit(entry: UUID, revision: UUID, text: String, context: ModelContext, now: Date, writer: String) throws -> Data? {
        let rows = try context.fetch(FetchDescriptor<Entry>())
        if let existing = rows.first(where: { $0.id == revision }) {
            guard existing.source == "revision", existing.sourceID == entry.uuidString, existing.text == text else { throw DataError.invalidValue("revision identity") }
            return nil
        }
        let live = rows.filter { $0.deletedAt == nil && $0.mergedInto == nil }
        guard let row = live.first(where: { $0.id == entry }), row.source != "autoPinned", row.mediaID == nil,
              !live.contains(where: { $0.source == "revision" && $0.sourceID == entry.uuidString }) else { throw DataError.invalidValue("editable diary line required") }
        guard row.text != text else { return nil }
        if now < (try freezesAt(row, context: context)) {
            let before = try row.record(); row.text = text; row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt); row.writerID = writer
            return try JSONEncoder().encode(DiaryInverse(model: "Entry", after: row.record(), dayKey: row.dayKey, previousOrigin: nil, before: before))
        }
        let next = Entry(); next.id = revision; next.dayKey = row.dayKey; next.eventAt = row.eventAt; next.tzID = row.tzID; next.dayPolicy = row.dayPolicy
        next.text = text; next.textFormat = row.textFormat; next.ink = row.ink; next.attachmentMediaIDs = row.attachmentMediaIDs; next.projectID = row.projectID
        next.place = row.place; next.lat = row.lat; next.lon = row.lon; next.source = "revision"; next.sourceID = row.id.uuidString
        next.createdAt = now; next.updatedAt = now; next.writerID = writer; context.insert(next)
        return try JSONEncoder().encode(DiaryInverse(model: "Entry", after: next.record(), dayKey: next.dayKey, previousOrigin: nil))
    }
    static func deleteEntry(_ id: UUID, context: ModelContext, now: Date, writer: String) throws -> Data {
        let rows = try context.fetch(FetchDescriptor<Entry>())
        let live = rows.filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let byID = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard let head = byID[id] else { throw DataError.invalidValue("missing diary entry") }
        let chains = DiaryRevisionChains(live.map {
            .init(id: $0.id, replaces: $0.source == "revision" ? $0.sourceID.flatMap(UUID.init(uuidString:)) : nil)
        })
        guard chains.heads.contains(id) else { throw DataError.invalidValue("diary entry is not the current line") }

        // A revision family is one logical line. Remove every live ancestor and branch so no older text
        // becomes visible when the current line is deleted.
        var familyIDs: Set<UUID> = [id]
        var changed = true
        while changed {
            changed = false
            for row in live {
                let parent = row.source == "revision" ? row.sourceID.flatMap(UUID.init(uuidString:)) : nil
                if familyIDs.contains(row.id) || parent.map(familyIDs.contains) == true {
                    if familyIDs.insert(row.id).inserted { changed = true }
                    if let parent, byID[parent] != nil, familyIDs.insert(parent).inserted { changed = true }
                }
            }
        }
        let family = live.filter { familyIDs.contains($0.id) }.sorted {
            $0.eventAt == $1.eventAt ? $0.id.uuidString < $1.id.uuidString : $0.eventAt < $1.eventAt
        }
        guard !family.isEmpty, family.allSatisfy({ $0.dayKey == head.dayKey }) else {
            throw DataError.invalidValue("invalid diary revision family")
        }
        let before = try family.map { try $0.record() }
        for row in family {
            row.deletedAt = now; row.deletionBarrierAt = now
            row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt); row.writerID = writer
        }
        let after = try family.map { try $0.record() }
        let changes = zip(before, after).map { DiaryEntryDeletion(before: $0.0, after: $0.1) }
        guard let deletedHead = after.first(where: { $0.id == id }) else { throw DataError.invalidValue("missing deleted diary entry") }
        // Media rows and external bytes stay live through the undo window. Receipt records contain Entry
        // references only; the expiry sweep clears unreferenced bytes after undo is no longer possible.
        return try JSONEncoder().encode(DiaryInverse(model: "EntryDeletion", after: deletedHead, dayKey: head.dayKey,
                                                     previousOrigin: nil, deletedEntries: changes))
    }
    static func freezesAt(_ row: Entry, context: ModelContext) throws -> Date {
        let day = try GregorianDay(row.dayKey), boundary = DiaryFreeze.boundary(policy: row.dayPolicy)
        let repository = try PrayerRepository(context: context), active = repository.place(at: row.eventAt)
        let place = (try? ActivePlace(latitude: active.latitude, longitude: active.longitude, timeZoneID: row.tzID)) ?? active
        let next = boundary == .midnight ? nil : PrayerTimesEngine.calculate(day: day.adding(days: 1), place: place, options: repository.options)
        guard let freeze = DiaryFreeze.freezesAt(day: day, boundary: boundary, timeZone: place.timeZone, nextDay: next) else { throw CoreError.missingPrayerTimes }
        return freeze
    }
    static func undo(_ data: Data, context: ModelContext, now: Date, writer: String) throws {
        let inverse = try JSONDecoder().decode(DiaryInverse.self, from: data)
        func tombstone<T: MadarRecordModel>(_ row: T) throws {
            guard try row.record() == inverse.after else { throw DataError.invalidValue("undo superseded: diary") }
            var record = try row.record(); let stamp = StableIdentity.monotonic(now: now, previous: record.date("updatedAt") ?? now)
            try record.set(stamp, for: "deletedAt"); try record.set(stamp, for: "deletionBarrierAt")
            try record.set(stamp, for: "updatedAt"); try record.set(writer, for: "writerID"); try row.apply(record)
        }
        if inverse.model == "EntryDeletion" {
            guard let changes = inverse.deletedEntries, !changes.isEmpty else { throw DataError.invalidValue("invalid diary deletion receipt") }
            let rows = try context.fetch(FetchDescriptor<Entry>())
            for change in changes {
                guard let row = rows.first(where: { $0.id == change.after.id && $0.mergedInto == nil }),
                      try row.record() == change.after else { throw DataError.invalidValue("undo superseded: diary deletion") }
            }
            for change in changes {
                guard let row = rows.first(where: { $0.id == change.after.id && $0.mergedInto == nil }) else { throw DataError.invalidValue("missing diary entry") }
                var restored = change.before
                let barrier = change.after.date("deletionBarrierAt") ?? change.after.date("deletedAt") ?? now
                try restored.set(Optional<Date>.none, for: "deletedAt")
                try restored.set(Optional<Date>.none, for: "deletionBarrierAt")
                try restored.set(max(now, barrier.addingTimeInterval(0.001)), for: "restoredAt")
                try restored.set(StableIdentity.monotonic(now: now, previous: change.after.date("updatedAt") ?? now), for: "updatedAt")
                try restored.set(writer, for: "writerID")
                try row.apply(restored)
            }
        } else if inverse.model == "Niyya" {
            guard let row=try context.fetch(FetchDescriptor<Niyya>()).first(where:{$0.id==inverse.after.id && $0.mergedInto==nil}),try row.record()==inverse.after else{throw DataError.invalidValue("undo superseded: intention")}
            if let before=inverse.before {row.text=try before.decode("text",as:String.self);row.result=try before.decode("result",as:String?.self);row.updatedAt=StableIdentity.monotonic(now:now,previous:row.updatedAt);row.writerID=writer}
            else{try tombstone(row)}
        } else if inverse.model == "Entry" {
            let rows = try context.fetch(FetchDescriptor<Entry>())
            guard let row = rows.first(where: { $0.id == inverse.after.id && $0.mergedInto == nil }) else { throw DataError.invalidValue("missing diary entry") }
            if let before = inverse.before {
                guard try row.record() == inverse.after else { throw DataError.invalidValue("undo superseded: transcript") }
                row.text = try before.decode("text", as: String.self); row.projectID = try before.decode("projectID", as: UUID?.self)
                row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt); row.writerID = writer
            } else {
                // RD1: a revision that a later live revision replaces cannot be undone on its own, or two heads would show.
                guard !rows.contains(where: { $0.source == "revision" && $0.sourceID == row.id.uuidString && $0.deletedAt == nil && $0.mergedInto == nil }) else { throw DataError.invalidValue("undo superseded: revision") }
                try tombstone(row)
            }
            if inverse.previousOrigin == "dayOne", !rows.contains(where: { $0.id != row.id && $0.dayKey == inverse.dayKey && $0.source == "native" && $0.deletedAt == nil && $0.mergedInto == nil }) {
                for page in try context.fetch(FetchDescriptor<DayPage>()) where page.dayKey == inverse.dayKey && page.deletedAt == nil && page.mergedInto == nil {
                    page.origin = "dayOne"; page.updatedAt = StableIdentity.monotonic(now: now, previous: page.updatedAt); page.writerID = writer
                }
            }
        } else if inverse.model == "Letter" {
            guard let row = try context.fetch(FetchDescriptor<Letter>()).first(where: { $0.id == inverse.after.id && $0.mergedInto == nil }) else { throw DataError.invalidValue("missing letter") }
            if let before = inverse.before {
                guard try row.record() == inverse.after else { throw DataError.invalidValue("undo superseded: letter") }
                row.triggerKind = try before.decode("triggerKind", as: String.self); row.triggerValue = try before.decode("triggerValue", as: String?.self)
                row.triggerTargetID = try before.decode("triggerTargetID", as: UUID?.self); row.openAt = try before.decode("openAt", as: Date?.self)
                row.state = try before.decode("state", as: String.self); row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt); row.writerID = writer
            } else { try tombstone(row) }
        } else if inverse.model == "UpcomingDay" {
            guard let row = try context.fetch(FetchDescriptor<UpcomingDay>()).first(where: { $0.id == inverse.after.id && $0.mergedInto == nil }), try row.record() == inverse.after else { throw DataError.invalidValue("undo superseded: upcoming day") }
            if let before = inverse.before {
                row.title = try before.decode("title", as: String.self); row.calendar = try before.decode("calendar", as: String.self); row.year = try before.decode("year", as: Int?.self)
                row.month = try before.decode("month", as: Int.self); row.day = try before.decode("day", as: Int.self); row.repeats = try before.decode("repeats", as: String.self)
                row.countFromDayKey = try before.decode("countFromDayKey", as: String.self)
                // Receipts written before V11 carry no countUpAfter key; that day did not count up.
                row.countUpAfter = (try? before.decode("countUpAfter", as: Bool.self)) ?? false
                row.deletedAt = try before.decode("deletedAt", as: Date?.self); row.deletionBarrierAt = try before.decode("deletionBarrierAt", as: Date?.self)
                if row.deletedAt == nil { row.restoredAt = now }
                row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt); row.writerID = writer
            } else { try tombstone(row) }
        } else if inverse.model == "Project" {
            guard let row = try context.fetch(FetchDescriptor<Project>()).first(where: { $0.id == inverse.after.id && $0.mergedInto == nil }), try row.record() == inverse.after else { throw DataError.invalidValue("undo superseded: project") }
            if let before = inverse.before {
                row.name = try before.decode("name", as: String.self); row.intention = try before.decode("intention", as: String.self); row.keyword = try before.decode("keyword", as: String?.self)
                row.finishedAt = try before.decode("finishedAt", as: Date?.self); row.reflection = try before.decode("reflection", as: String?.self)
                row.deletedAt = try before.decode("deletedAt", as: Date?.self); row.deletionBarrierAt = try before.decode("deletionBarrierAt", as: Date?.self)
                if row.deletedAt == nil { row.restoredAt = now }
                row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt); row.writerID = writer
            } else { try tombstone(row) }
        } else {
            guard let row = try context.fetch(FetchDescriptor<MarginNote>()).first(where: { $0.id == inverse.after.id && $0.mergedInto == nil }) else { throw DataError.invalidValue("missing margin") }
            try tombstone(row)
        }
    }
}
