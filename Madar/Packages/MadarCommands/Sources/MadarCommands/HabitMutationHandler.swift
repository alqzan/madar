import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarPrayer

private struct HabitUndo: Codable {
    struct Change: Codable { let before: DataRecord?; let after: DataRecord }
    var changes: [Change] = []
    var event: DataRecord? = nil
}
@MainActor enum HabitMutationHandler {
    static func stage(_ command: HabitCommand, id: UUID, context: ModelContext, now: Date, writer: String) throws -> Data? {
        let today = try DiaryLineRenderer.today(context: context, now: now)
        func habit(_ id: UUID) throws -> Habit { guard let row = try context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id && $0.deletedAt == nil && $0.mergedInto == nil })).first else { throw DataError.invalidValue("العادة غير موجودة") }; return row }
        func touch(_ row: any MadarRecordModel) throws {
            var record = try row.record(); try record.set(StableIdentity.monotonic(now: now, previous: record.date("updatedAt") ?? .distantPast), for:"updatedAt"); try record.set(writer, for:"writerID"); try row.apply(record)
        }
        var inverse = HabitUndo()
        switch command {
        case .save(let identity, let name, let source, let rule, let homeOnly, let reminder):
            let existing = try context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == identity })).first
            // FB-39 (owner, 6 Nov): a new habit may start on a free first date, back up to ten years (then its past days can be
            // logged) or ahead up to a year; an edit of an existing habit still starts today and never rewrites closed periods.
            if existing == nil {
                guard rule.effectiveFrom >= today.adding(days: -3660), rule.effectiveFrom <= today.adding(days: 366) else { throw DataError.invalidValue("تاريخ البداية بعيد جدًا") }
            } else {
                guard rule.effectiveFrom == today else { throw DataError.invalidValue("التعديل يبدأ من اليوم") }
            }
            let start = rule.effectiveFrom
            guard existing?.deletedAt == nil, existing?.mergedInto == nil else { throw DataError.invalidValue("استعادة صريحة مطلوبة") }
            if let existing, existing.linkedSource != source { throw DataError.invalidValue("مصدر العادة ثابت؛ أضف عادة جديدة") }
            let row = existing ?? Habit(), before = try existing?.record()
            row.id = identity; row.name = name; row.linkedSource = source; row.kind = source == nil ? "custom" : "linked"; row.homeOnly = homeOnly; row.reminder = reminder
            if existing == nil { row.startDate = now; row.createdAt = now; row.order = try context.fetchCount(FetchDescriptor<Habit>()); context.insert(row) }
            try touch(row); inverse.changes.append(.init(before: before, after: try row.record()))
            let effectiveFrom = start.description
            let oldPolicy = try context.fetch(FetchDescriptor<HabitPolicy>(predicate: #Predicate { $0.habitID == identity && $0.effectiveFrom == effectiveFrom && $0.deletedAt == nil && $0.mergedInto == nil })).first
            let policy = oldPolicy ?? HabitPolicy(), old = try oldPolicy?.record()
            if oldPolicy == nil { policy.id = StableIdentity.uuid(for: "habit-policy:\(identity):\(start)"); policy.habitID = identity; policy.createdAt = now; context.insert(policy) }
            HabitRepository.apply(rule, to: policy); try touch(policy)
            inverse.changes.append(.init(before: old, after: try policy.record()))
            if let origin=try HabitContextProvenance.ensureOrigin(habit:row,context:context,now:now,writer:writer),existing==nil {
                inverse.changes.append(.init(before:nil,after:try origin.record()))
            }
        case .complete(let identity, let delta, let periodKey, let day, let entryID):
            let row = try habit(identity); guard row.archivedAt == nil, row.kind == "custom" else { throw DataError.invalidValue("العادة المربوطة تُسجّل في غرفتها") }
            let reading = try HabitRepository(context: context).reading(id: identity, at: now)
            let prayers = try PrayerRepository(context: context), event = HabitEvent()
            let target: HabitPeriodResult, logDay: GregorianDay
            if let day, day != today {
                // A past day is logged in the period that held it; a day after today or before the habit began is refused.
                guard day < today else { throw DataError.invalidValue("لا يُسجّل يوم لم يأتِ بعد") }
                guard let reading, day >= reading.firstEffectiveFrom,
                      let period = reading.summary.periods.last(where: { $0.start <= day && day < $0.end }), period.target > 0 else { throw DataError.invalidValue("هذا اليوم قبل بداية العادة") }
                target = period; logDay = day
                event.eventAt = day.date(in: prayers.place(at: now).timeZone).addingTimeInterval(43200)
            } else {
                guard let reading, !reading.paused, let current = reading.summary.current, current.target > 0 else { throw DataError.invalidValue("العادة مستثناة اليوم") }
                guard periodKey == nil || periodKey == current.key else {throw DataError.invalidValue("انتهت هذه الفترة؛ افتح العادات للتسجيل") }
                target = current; logDay = today; event.eventAt = now
            }
            // A finished once-habit takes no second tap in its period, but a remembered earlier day is still a time of
            // its own («آخر مرة»): it is kept unless that day already holds one.
            if target.rule.measure == .once && target.met {
                guard logDay != today, reading?.times.contains(where: { $0.day == logDay }) == false else { return nil }
            }
            let current = target
            event.id = id; event.habitID = identity; event.dayKey = logDay.description; event.periodKey = current.key; event.entryID = entryID
            event.tzID = prayers.place(at: now).timeZoneID
            let settings = try SettingsStore(context: context); event.dayPolicy = ((try settings.value(for:"core.dayStart")).string ?? "fajr") + "@1"
            event.unit = current.rule.unit
            event.delta = current.rule.measure == .once ? 1 : delta; event.createdAt = now; event.updatedAt = now; event.writerID = writer
            context.insert(event); inverse.event = try event.record()
        case .pause(let identity, let from, let until, let trip):
            _ = try habit(identity); try HabitBreak.validateStart(from, today: today)
            let old = try context.fetch(FetchDescriptor<HabitPause>()).filter { $0.habitID == identity && $0.deletedAt == nil && $0.mergedInto == nil && ($0.toDayKey == nil || $0.toDayKey! > today.description) }
            guard old.isEmpty else { throw DataError.invalidValue("العادة مجمدة بالفعل") }
            let row = HabitPause(); row.id = id; row.habitID = identity; row.fromDayKey = from.description; row.toDayKey = until?.description
            if trip {
                guard let active = try PrayerRepository(context: context).activeTrip(at: now) else { throw DataError.invalidValue("لا رحلة جارية") }
                row.reason = "trip"; row.tripID = active.id
            }
            row.createdAt = now; row.updatedAt = now; row.writerID = writer; context.insert(row)
            inverse.changes.append(.init(before:nil,after:try row.record()))
        case .health(let identity, let unit, let values):
            let row = try habit(identity)
            guard row.linkedSource == "walking", row.archivedAt == nil else {throw DataError.invalidValue("مصدر الصحة مطلوب")}
            let policies = try context.fetch(FetchDescriptor<HabitPolicy>()).filter{$0.habitID==identity && $0.deletedAt==nil && $0.mergedInto==nil}.sorted{$0.effectiveFrom<$1.effectiveFrom}
            let logs = try context.fetch(FetchDescriptor<HabitLog>()).filter{$0.habitID==identity && $0.mergedInto==nil}
            let prayers = try PrayerRepository(context:context)
            for (key,value) in values {
                let day=try GregorianDay(key)
                guard day>=today.adding(days:-7),day<today,let policy=policies.last(where:{$0.effectiveFrom<=key}),policy.unit==unit else{throw DataError.invalidValue("نافذة تحديث الصحة سبعة أيام مغلقة وبالوحدة الأصلية")}
                let existing=logs.first{$0.periodKey==key}
                guard existing?.deletedAt==nil else{throw DataError.invalidValue("سجل صحة محذوف")}
                let log=existing ?? HabitLog();log.id=existing?.id ?? StableIdentity.uuid(for:"habit-health:\(identity):\(key)");log.habitID=identity;log.periodKey=key;log.value=value
                if existing==nil{log.eventAt=day.date(in:prayers.home.timeZone).addingTimeInterval(43200);log.tzID=prayers.home.timeZoneID;log.dayPolicy="midnight@1";log.createdAt=now;context.insert(log)}
                try touch(log)
            }
            return nil // Derived HealthKit totals, not a user completion or an undoable health write.
        case .resume(let identity):
            _ = try habit(identity)
            let pauses = try context.fetch(FetchDescriptor<HabitPause>()).filter { $0.habitID == identity && $0.deletedAt == nil && $0.mergedInto == nil && $0.fromDayKey <= today.description && ($0.toDayKey == nil || $0.toDayKey! > today.description) }
            for row in pauses { let before = try row.record(); row.toDayKey = today.description; try touch(row); inverse.changes.append(.init(before:before,after:try row.record())) }
        case .deleteArchived(let identity):
            let row=try habit(identity)
            guard row.archivedAt != nil else{throw DataError.invalidValue("أرشف العادة أولًا")}
            let instances=try habitFamily(context)
            for instance in instances {
                let before=try instance.record()
                let isChild=["HabitPolicy","HabitPause","HabitLog","HabitEvent"].contains(before.model) && before.fields["habitID"]?.string == identity.uuidString
                guard before.isLive,(before.model == "Habit" && before.id == identity) || isChild else{continue}
                var after=before
                let stamp=StableIdentity.monotonic(now:now,previous:before.date("updatedAt") ?? .distantPast)
                try after.set(stamp,for:"deletedAt");try after.set(stamp,for:"deletionBarrierAt");try after.set(stamp,for:"updatedAt");try after.set(writer,for:"writerID")
                try instance.apply(after);inverse.changes.append(.init(before:before,after:after))
            }
        case .archive(let identity, let archived):
            let row = try habit(identity), before = try row.record(); row.archivedAt = archived ? now : nil; try touch(row)
            inverse.changes.append(.init(before:before,after:try row.record()))
        }
        return try JSONEncoder().encode(inverse)
    }
    static func habitFamily(_ context: ModelContext) throws -> [any MadarRecordModel] {
        var rows: [any MadarRecordModel] = []
        rows += try context.fetch(FetchDescriptor<Habit>()); rows += try context.fetch(FetchDescriptor<HabitPolicy>())
        rows += try context.fetch(FetchDescriptor<HabitPause>()); rows += try context.fetch(FetchDescriptor<HabitLog>())
        rows += try context.fetch(FetchDescriptor<HabitEvent>())
        return rows
    }
    static func undo(_ data: Data, context: ModelContext, now: Date, writer: String) throws {
        let inverse = try JSONDecoder().decode(HabitUndo.self, from: data)
        if let original = inverse.event {
            let originalID = original.id
            guard let event = try context.fetch(FetchDescriptor<HabitEvent>(predicate: #Predicate { $0.id == originalID && $0.deletedAt == nil && $0.mergedInto == nil })).first, try event.record() == original else { throw DataError.invalidValue("تعذر التراجع عن التسجيل") }
            let reverse = HabitEvent(); try reverse.apply(original); reverse.id = StableIdentity.uuid(for: "habit-undo:\(original.id)")
            let reverseID = reverse.id
            guard try context.fetchCount(FetchDescriptor<HabitEvent>(predicate: #Predicate { $0.id == reverseID })) == 0 else { return }
            reverse.delta = -event.delta; reverse.createdAt = now; reverse.updatedAt = now; reverse.writerID = writer; context.insert(reverse)
        }
        guard !inverse.changes.isEmpty else { return }
        // Every change is a habit-family row, so only those tables are read (the whole store was read before, on each undo).
        let records = try habitFamily(context).map { try $0.record() }
        for change in inverse.changes {
            if change.before == nil, change.after.model == "Habit" {
                let included = Set(inverse.changes.map { $0.after.id })
                guard !records.contains(where: { $0.isLive && ["HabitEvent","HabitLog","HabitPause"].contains($0.model) && $0.fields["habitID"]?.string == change.after.id.uuidString && !included.contains($0.id) }) else {throw DataError.invalidValue("تحتوي العادة تسجيلات أحدث؛ لا يُلغى إنشاؤها")}
            }
            guard records.contains(change.after) else { throw DataError.invalidValue("تغيّرت العادة بعد هذا الإجراء") }
        }
        for change in inverse.changes.reversed() {
            var record = change.before ?? change.after
            if change.before == nil { try record.set(now, for:"deletedAt"); try record.set(now, for:"deletionBarrierAt") }
            let stamp=StableIdentity.monotonic(now:now,previous:change.after.date("updatedAt") ?? .distantPast)
            if change.before != nil,change.after.deletedAt != nil,record.deletedAt == nil {
                try record.set(change.after.date("deletionBarrierAt"),for:"deletionBarrierAt");try record.set(stamp,for:"restoredAt")
            }
            try record.set(stamp,for:"updatedAt"); try record.set(writer,for:"writerID")
            try RecordBridge.upsert(record,in:context)
        }
    }
}
