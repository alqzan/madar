import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

@MainActor struct HabitPersistenceTests {
    let now = ISO8601DateFormatter().date(from:"2026-10-15T20:00:00+03:00")!
    func payload(_ id: UUID, _ rule: HabitRule, source: String? = nil) throws -> [String:MadarCore.JSONValue] {
        var result: [String:MadarCore.JSONValue] = ["id":.string(id.uuidString),"name":.string("ماء"),"rule":try JSONDecoder().decode(MadarCore.JSONValue.self,from:JSONEncoder().encode(rule))]
        if let source { result["source"] = .string(source) }; return result
    }
    @Test func countEventsReplayUndoAndArchivePreserveHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HabitFlow-\(UUID())"); defer { try? FileManager.default.removeItem(at:root) }
        let container = try MadarContainerFactory.makeLocal(at:root), bus = CommandBus(adapter:DurableCommandAdapter(container:container,lockDirectory:root,transactionClock:{$0}))
        func run(_ name:String,_ p:[String:MadarCore.JSONValue],_ id:UUID = UUID()) async throws -> CommandOutcome { try await bus.execute(.init(commandID:id,name:name,payload:.object(p),issuedAt:now),now:now) }
        let habit = UUID(); var rule = HabitRule(effectiveFrom:try GregorianDay("2026-10-15")); rule.measure = .count; rule.target = 2
        let creation=UUID()
        #expect(try await run("habit.save",payload(habit,rule),creation).status == .applied)
        let a = UUID(), b = UUID(), p: [String:MadarCore.JSONValue] = ["habitID":.string(habit.uuidString),"delta":.number(1)]
        #expect(try await run("habit.complete",p,a).status == .applied)
        #expect(try await run("habit.complete",p,b).status == .applied)
        _ = try await run("habit.complete",p,a)
        #expect(try HabitRepository(context:ModelContext(container)).readings(at:now).first?.summary.current?.value == 2)
        #expect(try ModelContext(container).fetch(FetchDescriptor<HabitEvent>()).filter{$0.delta != 0}.count == 2)
        await #expect(throws:(any Error).self){try await run("system.undo",["undoToken":.string(creation.uuidString)])}
        _ = try await run("system.undo",["undoToken":.string(b.uuidString)])
        #expect(try HabitRepository(context:ModelContext(container)).readings(at:now).first?.summary.current?.value == 1)
        #expect(try ModelContext(container).fetch(FetchDescriptor<HabitEvent>()).filter{$0.delta != 0}.count == 3)
        _ = try await run("habit.archive",["id":.string(habit.uuidString),"archived":.bool(true)])
        #expect(try HabitRepository(context:ModelContext(container)).readings(at:now).isEmpty)
        _ = try await run("habit.archive",["id":.string(habit.uuidString),"archived":.bool(false)])
        #expect(try HabitRepository(context:ModelContext(container)).readings(at:now).first?.summary.current?.value == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<HabitLog>()) == 0)
        // A closed period is a final refusal (not a throw), so a queued completion cannot block the inbox.
        let stale = try await run("habit.complete",p.merging(["periodKey":.string("2026-10-14")]){$1})
        #expect(stale.status == .rejected); #expect(stale.reason == "انتهت هذه الفترة؛ افتح العادات للتسجيل")

    }
    @Test func openDetailCanReplaceItsHabitSnapshotAfterReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HabitDetailRefresh-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root)
        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        let id = UUID()
        var rule = HabitRule(effectiveFrom: try GregorianDay("2026-10-15"))
        rule.measure = .count; rule.target = 2
        let save = try await bus.execute(.init(name: "habit.save", payload: .object(payload(id, rule)), issuedAt: now), now: now)
        #expect(save.status == .applied)
        let selected = try #require(HabitRepository(context: ModelContext(container)).readings(at: now).first)
        #expect(selected.summary.current?.value == 0)

        let completion = try await bus.execute(.init(name: "habit.complete", payload: .object(["id": .string(id.uuidString), "delta": .number(1)]), issuedAt: now), now: now)
        #expect(completion.status == .applied)
        let fresh = try #require(HabitRepository(context: ModelContext(container)).readings(at: now).first)
        let refreshed = try #require(selected.refreshed(in: [fresh]))
        #expect(refreshed.id == selected.id)
        #expect(selected.summary.current?.value == 0)
        #expect(refreshed.summary.current?.value == 1)
        #expect(selected.refreshed(in: []).map(\.id) == nil)
    }
    /// Item 26 «فعلتها في يوم سابق»: a past day lands in the period that held it with its diary line; a day to come or
    /// before the habit began is refused, and a day plus a period key is not a valid payload.
    @Test func pastDayIsLoggedInItsOwnPeriodWithItsDiaryLine() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HabitPast-\(UUID())"); defer { try? FileManager.default.removeItem(at:root) }
        let container = try MadarContainerFactory.makeLocal(at:root), bus = CommandBus(adapter:DurableCommandAdapter(container:container,lockDirectory:root,transactionClock:{$0}))
        let later = now.addingTimeInterval(2 * 86400)
        func run(_ name:String,_ p:[String:MadarCore.JSONValue],at date:Date) async throws -> CommandOutcome { try await bus.execute(.init(name:name,payload:.object(p),issuedAt:date),now:date) }
        let habit = UUID(), entry = UUID()
        _ = try await run("habit.save",payload(habit,HabitRule(effectiveFrom:try GregorianDay("2026-10-15"))),at:now)
        let id: MadarCore.JSONValue = .string(habit.uuidString)
        #expect(try await run("habit.complete",["id":id,"day":.string("2026-10-16"),"entryID":.string(entry.uuidString)],at:later).status == .applied)
        let event = try #require(try ModelContext(container).fetch(FetchDescriptor<HabitEvent>()).first { $0.delta != 0 })
        #expect(event.dayKey == "2026-10-16"); #expect(event.periodKey == "2026-10-16"); #expect(event.entryID == entry)
        let reading = try #require(try HabitRepository(context:ModelContext(container)).readings(at:later).first)
        #expect(reading.summary.periods.first { $0.key == "2026-10-16" }?.met == true)
        #expect(reading.summary.current?.met == false)
        #expect(reading.lastTime == HabitTime(day: try GregorianDay("2026-10-16"), entryID: entry))
        #expect(try await run("habit.complete",["id":id],at:later).status == .applied)
        let both = try #require(try HabitRepository(context:ModelContext(container)).readings(at:later).first)
        #expect(both.times.map(\.day.description) == ["2026-10-17","2026-10-16"]); #expect(both.lastTime?.entryID == nil)
        #expect(try await run("habit.complete",["id":id,"day":.string("2026-10-18")],at:later).status == .rejected)
        #expect(try await run("habit.complete",["id":id,"day":.string("2026-10-14")],at:later).status == .rejected)
        #expect(HabitCommand.parse("habit.complete",["id":id,"day":.string("2026-10-16"),"periodKey":.string("2026-10-16")]) == nil)
        #expect(HabitCommand.parse("habit.complete",["id":id,"day":.string("yesterday")]) == nil)
        // A yearly habit already done this year still keeps an earlier remembered day, once.
        let gift = UUID(); var yearly = HabitRule(effectiveFrom:try GregorianDay("2026-10-15")); yearly.frequency = .yearly; yearly.yearMonth = 12; yearly.yearDay = 15
        _ = try await run("habit.save",payload(gift,yearly),at:now)
        let g: MadarCore.JSONValue = .string(gift.uuidString)
        #expect(try await run("habit.complete",["id":g],at:later).status == .applied)
        #expect(try await run("habit.complete",["id":g,"day":.string("2026-10-15")],at:later).status == .applied)
        _ = try await run("habit.complete",["id":g,"day":.string("2026-10-15")],at:later)
        let kept = try #require(try HabitRepository(context:ModelContext(container)).readings(at:later).first { $0.id == gift })
        #expect(kept.times.map(\.day.description) == ["2026-10-17","2026-10-15"]); #expect(kept.summary.current?.met == true)
    }
    @Test func pauseResumeAndPolicyEditsAreDatedAndUndoable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HabitPause-\(UUID())"); defer { try? FileManager.default.removeItem(at:root) }
        let container = try MadarContainerFactory.makeLocal(at:root), bus = CommandBus(adapter:DurableCommandAdapter(container:container,lockDirectory:root,transactionClock:{$0}))
        func run(_ name:String,_ p:[String:MadarCore.JSONValue],at date:Date? = nil) async throws -> CommandOutcome { let date = date ?? now; return try await bus.execute(.init(name:name,payload:.object(p),issuedAt:date),now:date) }
        let id = UUID(); var r = HabitRule(effectiveFrom:try GregorianDay("2026-10-15")); r.measure = .count; r.target = 2
        _ = try await run("habit.save",payload(id,r))
        _ = try await run("habit.pause",["id":.string(id.uuidString),"from":.string("2026-10-14")])
        #expect(try HabitRepository(context:ModelContext(container)).readings(at:now).first?.paused == true)
        let before = try ModelContext(container).fetch(FetchDescriptor<HabitPause>()).first?.fromDayKey
        _ = try await run("habit.resume",["id":.string(id.uuidString)],at:now.addingTimeInterval(86400))
        #expect(try ModelContext(container).fetch(FetchDescriptor<HabitPause>()).first?.fromDayKey == before)
        #expect(try ModelContext(container).fetch(FetchDescriptor<HabitPause>()).first?.toDayKey == "2026-10-16")
        r.effectiveFrom = try GregorianDay("2026-10-16"); r.target = 4
        _ = try await run("habit.save",payload(id,r),at:now.addingTimeInterval(86400))
        let policies = try ModelContext(container).fetch(FetchDescriptor<HabitPolicy>()).sorted { $0.effectiveFrom < $1.effectiveFrom }
        #expect(policies.map(\.target) == [2,4])
        #expect(HabitCommand.parse("habit.pause",["id":.string(id.uuidString),"from":.string("invalid")]) == nil)
    }
    @Test func homeOnlyHabitIsFrozenForSameDayTravel() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HabitSameDayTrip-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root)
        let context = ModelContext(container)
        _ = try SettingsStore(context: context).stage([
            "core.dayStart": .string("midnight"),
            "bahw.travelFreezesHome": .bool(true)
        ], now: now)

        let habit = Habit(); habit.id = UUID(); habit.name = "عادة البيت"; habit.homeOnly = true
        habit.startDate = now; habit.createdAt = now; habit.updatedAt = now
        context.insert(habit)
        let policy = HabitPolicy(); policy.id = UUID(); policy.habitID = habit.id
        policy.effectiveFrom = "2026-10-15"; policy.createdAt = now; policy.updatedAt = now
        context.insert(policy)

        let trip = Trip(); trip.id = UUID(); trip.city = "اختبار"; trip.tzID = "Asia/Riyadh"
        trip.start = now.addingTimeInterval(-6 * 3600); trip.end = now.addingTimeInterval(-4 * 3600)
        trip.createdAt = now; trip.updatedAt = now
        context.insert(trip)
        try context.save()

        let today = try #require(HabitRepository(context: ModelContext(container)).readings(at: now).first)
        #expect(today.paused)
        #expect(today.summary.current?.outcome == .excluded)

        let tomorrow = try #require(HabitRepository(context: ModelContext(container)).readings(at: now.addingTimeInterval(86_400)).first)
        #expect(!tomorrow.paused)
        #expect(tomorrow.summary.current?.outcome == .waiting)
    }
    @Test func homeOnlyTripFreezeUsesMadarDayAndIgnoresDismissedTrips() throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-15T02:30:00+03:00")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HabitTripMadarDay-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root)
        let context = ModelContext(container)
        _ = try SettingsStore(context: context).stage([
            "core.dayStart": .string("fajr"),
            "bahw.travelFreezesHome": .bool(true)
        ], now: now)

        let habit = Habit(); habit.id = UUID(); habit.name = "عادة البيت"; habit.homeOnly = true
        habit.startDate = now; habit.createdAt = now; habit.updatedAt = now
        context.insert(habit)
        let policy = HabitPolicy(); policy.id = UUID(); policy.habitID = habit.id
        policy.effectiveFrom = "2026-10-14"; policy.createdAt = now; policy.updatedAt = now
        context.insert(policy)

        let trip = Trip(); trip.id = UUID(); trip.city = "اختبار"; trip.tzID = "Asia/Riyadh"
        trip.start = now.addingTimeInterval(-30 * 60); trip.end = now.addingTimeInterval(30 * 60)
        trip.createdAt = now; trip.updatedAt = now
        context.insert(trip)
        try context.save()

        let beforeFajr = try #require(HabitRepository(context: ModelContext(container)).readings(at: now).first)
        #expect(beforeFajr.paused)
        #expect(beforeFajr.summary.current?.outcome == .excluded)

        let afterFajr = try #require(HabitRepository(context: ModelContext(container)).readings(at: now.addingTimeInterval(3 * 3600)).first)
        #expect(!afterFajr.paused)

        trip.dismissed = true
        try context.save()
        let dismissed = try #require(HabitRepository(context: ModelContext(container)).readings(at: now).first)
        #expect(!dismissed.paused)
    }
    @Test func hijriPeriodKeysAndCalendarContextSurviveSettingsAndPortableRebuild() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("HabitCalendar-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root),bus=CommandBus(adapter:DurableCommandAdapter(container:container,lockDirectory:root,transactionClock:{$0}))
        let start=ISO8601DateFormatter().date(from:"2027-03-08T12:00:00+03:00")!,id=UUID()
        var rule=HabitRule(effectiveFrom:try GregorianDay("2027-03-08"));rule.frequency = .monthly;rule.hijri=true;rule.monthDays=[30]
        _ = try await bus.execute(.init(name:"habit.save",payload:.object(payload(id,rule)),issuedAt:start),now:start)
        _ = try await bus.execute(.init(name:"habit.complete",payload:.object(["id":.string(id.uuidString)]),issuedAt:start.addingTimeInterval(1)),now:start.addingTimeInterval(1))
        let original=try #require(try ModelContext(container).fetch(FetchDescriptor<HabitEvent>()).first{$0.delta==1})
        let saved=try original.record();#expect(original.periodKey=="h:1448-09")
        // Same-day correction must not move the already recorded last day of Ramadan.
        let changed=start.addingTimeInterval(2)
        _ = try await bus.execute(.init(name:"settings.set",payload:.object(["settings":.object(["core.hijriSource":.string("sighting"),"core.hijriOffset":.number(1)])]),issuedAt:changed),now:changed)
        let snapshot=try #require(try HabitRepository(context:ModelContext(container)).readings(at:start.addingTimeInterval(86400)).first)
        #expect(snapshot.summary.periods.first?.key=="h:1448-09" && snapshot.summary.periods.first?.met==true)
        #expect(try ModelContext(container).fetch(FetchDescriptor<HabitEvent>()).first{$0.delta==1}?.record()==saved)
        let records=try RecordBridge.all(ModelContext(container))
        let rebuilt=try MadarContainerFactory.makeInMemory(),context=ModelContext(rebuilt)
        for record in records{try RecordBridge.insert(record,in:context)};try context.save()
        let restored=try #require(try HabitRepository(context:ModelContext(rebuilt)).readings(at:start.addingTimeInterval(86400)).first)
        #expect(restored.summary.periods.map(\.key)==snapshot.summary.periods.map(\.key))
        #expect(restored.summary.streak==snapshot.summary.streak && restored.summary.periods.first?.met==true)
        #expect(try ModelContext(rebuilt).fetchCount(FetchDescriptor<DeviceSetting>())==0)
    }
    @Test func weeklyContextSurvivesPortableRebuildWithoutDeviceCache() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("HabitWeekRestore-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root),bus=CommandBus(adapter:DurableCommandAdapter(container:container,lockDirectory:root,transactionClock:{$0}))
        let id=UUID();var rule=HabitRule(effectiveFrom:try GregorianDay("2026-10-15"));rule.frequency = .weekly
        _ = try await bus.execute(.init(name:"habit.save",payload:.object(payload(id,rule)),issuedAt:now),now:now)
        _ = try await bus.execute(.init(name:"habit.complete",payload:.object(["id":.string(id.uuidString)]),issuedAt:now),now:now)
        _ = try await bus.execute(.init(name:"settings.set",payload:.object(["settings":.object(["core.weekStart":.string("sunday")])]),issuedAt:now.addingTimeInterval(1)),now:now.addingTimeInterval(1))
        let rows=try RecordBridge.all(ModelContext(container)),rebuilt=try MadarContainerFactory.makeInMemory(),context=ModelContext(rebuilt)
        for row in rows{try RecordBridge.insert(row,in:context)};try context.save()
        let later=now.addingTimeInterval(17*86400)
        let reading=try #require(try HabitRepository(context:ModelContext(rebuilt)).readings(at:later).first)
        #expect(reading.summary.periods.map(\.key)==["2026-10-10","2026-10-17","2026-10-25","2026-11-01"])
        #expect(reading.summary.periods.first?.value==1 && reading.summary.periods.first?.met==true)
        #expect(try ModelContext(rebuilt).fetchCount(FetchDescriptor<DeviceSetting>())==0)
    }
    @Test func finalDeleteTombstonesOnlyArchivedHabitChildrenAndUndoRestoresThem() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("HabitDelete-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root),bus=CommandBus(adapter:DurableCommandAdapter(container:container,lockDirectory:root,transactionClock:{$0}))
        let identity=UUID();let rule=HabitRule(effectiveFrom:try GregorianDay("2026-10-15"))
        func run(_ name:String,_ p:[String:MadarCore.JSONValue],id:UUID=UUID()) async throws->CommandOutcome {try await bus.execute(.init(commandID:id,name:name,payload:.object(p),issuedAt:now),now:now)}
        _ = try await run("habit.save",payload(identity,rule));_ = try await run("habit.complete",["id":.string(identity.uuidString)])
        let context=ModelContext(container),entry=Entry();entry.text="untouched";context.insert(entry);try context.save();let original=try entry.record()
        await #expect(throws:(any Error).self){try await run("habit.deleteArchived",["id":.string(identity.uuidString)])}
        _ = try await run("habit.archive",["id":.string(identity.uuidString),"archived":.bool(true)])
        let deletion=UUID();_ = try await run("habit.deleteArchived",["id":.string(identity.uuidString)],id:deletion)
        let deleted=try ModelContext(container).fetch(FetchDescriptor<HabitEvent>()).first{$0.delta != 0}!.record()
        #expect(!deleted.isLive)
        #expect(try ModelContext(container).fetch(FetchDescriptor<HabitPolicy>()).allSatisfy{$0.deletedAt != nil})
        #expect(try ModelContext(container).fetch(FetchDescriptor<Entry>()).first?.record()==original)
        _ = try await run("system.undo",["undoToken":.string(deletion.uuidString)])
        let restored=try ModelContext(container).fetch(FetchDescriptor<HabitEvent>()).first{$0.delta != 0}!.record()
        #expect(restored.isLive)
        #expect(try RowMerger.mergeVersions(restored,deleted).isLive)
        #expect(try HabitRepository(context:ModelContext(container)).readings(at:now,includeArchived:true).first?.summary.current?.value==1)
    }
    @Test func closedHealthTotalsKeepUnitsAndRejectCurrentOrOldDays() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("HabitHealth-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root),bus=CommandBus(adapter:DurableCommandAdapter(container:container,lockDirectory:root,transactionClock:{$0}))
        let context=ModelContext(container),habit=Habit();habit.linkedSource="walking";habit.kind="linked";context.insert(habit)
        let policy=HabitPolicy();policy.habitID=habit.id;policy.effectiveFrom="2026-10-01";policy.measure="health";policy.unit="steps";policy.target=6000;context.insert(policy);try context.save()
        func run(_ values:[String:MadarCore.JSONValue],unit:String="steps") async throws -> CommandOutcome {try await bus.execute(.init(name:"habit.refreshHealth",payload:.object(["id":.string(habit.id.uuidString),"unit":.string(unit),"values":.object(values)]),issuedAt:now),now:now)}
        _ = try await run(["2026-10-14":.number(6000)])
        _ = try await run(["2026-10-14":.number(5500)])
        let saved=try ModelContext(container).fetch(FetchDescriptor<HabitLog>())
        #expect(saved.count==1 && saved.first?.value==5500)
        await #expect(throws: (any Error).self) {try await run(["2026-10-15":.number(6000)])}
        await #expect(throws: (any Error).self) {try await run(["2026-10-01":.number(6000)])}
        await #expect(throws: (any Error).self) {try await run(["2026-10-14":.number(30)],unit:"exerciseMinutes")}
        #expect(try ModelContext(container).fetch(FetchDescriptor<HabitEvent>()).filter{$0.delta != 0}.count==0)
    }
    @Test func weekSettingAndUndoPreserveWeekEpochs() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("HabitWeeks-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root),bus=CommandBus(adapter:DurableCommandAdapter(container:container,lockDirectory:root,transactionClock:{$0}))
        let identity=UUID(),envelope=CommandEnvelope(commandID:identity,name:"settings.set",payload:.object(["settings":.object(["core.weekStart":.string("sunday")])]),issuedAt:now)
        #expect(try await bus.execute(envelope,now:now).status == .applied)
        let first=try #require(try HabitWeekHistory.load(ModelContext(container)))
        #expect(first.initial=="saturday" && first.changes.last?.start=="sunday")
        _ = try await bus.execute(.init(name:"system.undo",payload:.object(["undoToken":.string(identity.uuidString)]),issuedAt:now),now:now)
        let undo=try #require(try HabitWeekHistory.load(ModelContext(container)))
        #expect(undo.initial=="saturday" && undo.changes.last?.start=="saturday")
    }
    @Test func linkedHabitsReadOwnerFactsWithoutWritingEvents() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HabitLinked-\(UUID())"); defer { try? FileManager.default.removeItem(at:root) }
        let container = try MadarContainerFactory.makeLocal(at:root), bus = CommandBus(adapter:DurableCommandAdapter(container:container,lockDirectory:root,transactionClock:{$0}))
        let context = ModelContext(container), entry = Entry(); entry.dayKey = "2026-10-15"; entry.text = "سطر"; context.insert(entry); try context.save()
        let id = UUID(); var r = HabitRule(effectiveFrom:try GregorianDay("2026-10-15")); r.measure = .count; r.unit = "سطر"
        _ = try await bus.execute(.init(name:"habit.save",payload:.object(payload(id,r,source:"diaryLine")),issuedAt:now),now:now)
        let reading = try #require(HabitRepository(context:ModelContext(container)).readings(at:now).first)
        #expect(reading.summary.current?.value == 1 && reading.summary.current?.met == true)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<HabitEvent>()) == 0)
        #expect(HabitCommand.parse("habit.complete",["id":.string(id.uuidString),"delta":.number(-1)]) == nil)
    }
    /// §7.1 unit table + §7.6: «القراءة» reads active minutes (default 15) or pages from saved sessions; a session
    /// under 60 active seconds and a deleted session never count, and the habit writes no event of its own.
    @Test func readingHabitCountsSessionMinutesOrPages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HabitReading-\(UUID())"); defer { try? FileManager.default.removeItem(at:root) }
        let container = try MadarContainerFactory.makeLocal(at:root), bus = CommandBus(adapter:DurableCommandAdapter(container:container,lockDirectory:root,transactionClock:{$0}))
        let context = ModelContext(container)
        for (seconds, pages, deleted) in [(600, 4, false), (330, 2, false), (45, 9, false), (900, 30, true)] {
            let row = ReadingSession(); row.dayKey = "2026-10-15"; row.activeSeconds = seconds; row.pagesCounted = pages
            if deleted { row.deletedAt = now }; context.insert(row)
        }
        let yesterday = ReadingSession(); yesterday.dayKey = "2026-10-14"; yesterday.activeSeconds = 1200; yesterday.pagesCounted = 12; context.insert(yesterday)
        try context.save()
        let minutes = UUID(); var m = HabitRule(effectiveFrom:try GregorianDay("2026-10-15")); m.measure = .duration; m.unit = "minutes"; m.target = 15
        let pages = UUID(); var p = HabitRule(effectiveFrom:try GregorianDay("2026-10-15")); p.measure = .count; p.unit = "pages"; p.target = 10
        #expect(try await bus.execute(.init(name:"habit.save",payload:.object(payload(minutes,m,source:"reading")),issuedAt:now),now:now).status == .applied)
        #expect(try await bus.execute(.init(name:"habit.save",payload:.object(payload(pages,p,source:"reading")),issuedAt:now),now:now).status == .applied)
        let readings = try HabitRepository(context:ModelContext(container)).readings(at:now)
        let byMinutes = try #require(readings.first { $0.id == minutes }), byPages = try #require(readings.first { $0.id == pages })
        #expect(byMinutes.summary.current?.value == 15 && byMinutes.summary.current?.met == true)
        #expect(byPages.summary.current?.value == 6 && byPages.summary.current?.met == false)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<HabitEvent>()) == 0)
        var wrong = m; wrong.measure = .count; wrong.unit = "سطر"
        #expect(HabitCommand.parse("habit.save", try payload(UUID(), wrong, source:"reading")) == nil)
    }
}
