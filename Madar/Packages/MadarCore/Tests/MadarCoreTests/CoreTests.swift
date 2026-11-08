import Foundation
import Testing
@testable import MadarCore

private let zone = TimeZone(identifier: "Asia/Riyadh")!
private func instant(_ day: String = "2026-10-09", hour: Int, minute: Int = 0) throws -> Date { try GregorianDay(day).date(in: zone).addingTimeInterval(Double(hour * 3600 + minute * 60)) }
private struct FixtureFile: Decodable { var fixtures: [Fixture] }
private struct Fixture: Decodable { var date: String; var lat: Double; var lon: Double; var timezone: String; var expected: [String] }

@Test("Pinned handoff golden times, independent expected clocks")
func prayerGoldenTimes() throws {
    let url = try #require(Bundle.module.url(forResource: "prayer-times-reference", withExtension: "json", subdirectory: "Fixtures"))
    let fixtures = try JSONDecoder().decode(FixtureFile.self, from: Data(contentsOf: url)).fixtures
    for fixture in fixtures {
        let place = try ActivePlace(latitude: fixture.lat, longitude: fixture.lon, timeZoneID: fixture.timezone)
        let day = try #require(PrayerTimesEngine.calculate(day: GregorianDay(fixture.date), place: place))
        var cal = Calendar(identifier: .gregorian); cal.timeZone = place.timeZone
        for (prayer, clock) in zip(Prayer.allCases, fixture.expected) {
            let pieces = clock.split(separator: ":").map { Int($0)! }
            let c = cal.dateComponents([.hour, .minute], from: day.time(for: prayer))
            #expect(abs((c.hour! * 60 + c.minute!) - (pieces[0] * 60 + pieces[1])) <= 1)
        }
        #expect(day.isha.timeIntervalSince(day.maghrib) == 90 * 60)
    }
}
@Test("Ramadan interval comes from Madar, not Adhan Isha")
func ramadanInterval() throws {
    let prayers = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2027-02-10"), place: .riyadh))
    #expect(prayers.isha.timeIntervalSince(prayers.maghrib) == 120 * 60)
}
@Test("Hijri reference and sighting-only correction")
func hijriReference() throws {
    let date = try instant(hour: 12)
    #expect(HijriCalendar.date(for: date, timeZone: zone) == HijriDate(year: 1448, month: 4, day: 28))
    #expect(HijriCalendar.date(for: date, timeZone: zone, source: .ummAlQura, sightingOffset: 2).day == 28)
    #expect(HijriCalendar.date(for: date, timeZone: zone, source: .sighting, sightingOffset: 1).day == 29)
}
@Test("Stored day survives boundary change and respects active timezone")
func dayBoundary() throws {
    let prayers = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
    let stored = try MadarDay.resolve(instant: instant(hour: 2), place: .riyadh, prayerDays: [prayers])
    #expect(stored.dayKey == "2026-10-08"); #expect(stored.timeZoneID == "Asia/Riyadh")
    let midnight = try MadarDay.resolve(instant: instant(hour: 2), place: .riyadh, boundary: .midnight, prayerDays: [])
    #expect(midnight.dayKey == "2026-10-09"); #expect(stored.dayKey == "2026-10-08")
    let atFajr = try MadarDay.resolve(instant: prayers.fajr, place: .riyadh, prayerDays: [prayers]); #expect(atFajr.dayKey == "2026-10-09")
    let maghrib = try MadarDay.resolve(instant: prayers.maghrib.addingTimeInterval(-1), place: .riyadh, boundary: .maghrib, prayerDays: [prayers]); #expect(maghrib.dayKey == "2026-10-08")
    let roundTrip = try JSONDecoder().decode(StoredDayKey.self, from: JSONEncoder().encode(stored)); #expect(roundTrip == stored)
}
@Test("True dates and unavailable polar prayer times")
func invalidDatesAndPolar() throws {
    #expect(throws: CoreError.invalidDate) { try GregorianDay("2026-02-30") }
    #expect(throws: CoreError.invalidDate) { try GregorianDay("٢٠٢٦-10-09") }
    let polar = try ActivePlace(latitude: 89, longitude: 0, timeZoneID: "UTC")
    #expect(PrayerTimesEngine.calculate(day: try GregorianDay("2026-06-21"), place: polar) == nil)
}
@Test("Hindi signed money uses Arabic punctuation and FSI/PDI")
func numbers() {
    let f = MadarNumberFormatter()
    #expect(f.string(12345) == "١٢٣٤٥")
    #expect(f.amount(minorUnits: -123456) == "\u{2068}−١٬٢٣٤٫٥٦\u{2069}")
    #expect(f.percent(80) == "٨٠٪")
    #expect(MadarNumberFormatter(style: .western).amount(minorUnits: 123, signed: false) == "\u{2068}1٫23\u{2069}")
    #expect(f.amount(minorUnits: .min).hasPrefix("\u{2068}−"))
}
@Test("Arbiter leaves every scheduled request outside immutable prayer windows")
func sanctity() throws {
    let day = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
    let inputs = Prayer.allCases.map { NotificationCandidate(id: $0.rawValue, room: .quran, dueAt: day.time(for: $0).addingTimeInterval(1), dayKey: day.day.description) }
    let plan = NotificationArbiter.plan(candidates: inputs, prayerDays: [day], now: try instant(hour: 0), timeZone: zone, policy: .init(dailyBudget: 10))
    #expect(plan.scheduled.count == 6)
    for request in plan.scheduled { #expect(!day.sanctityWindows.contains { $0.contains(request.dueAt) }) }
    #expect(day.sanctityWindows.first(where: { $0.prayer == .maghrib })!.end.timeIntervalSince(day.maghrib) == 1200)
    #expect(NotificationArbiter.prayerAsk(day: day, prayer: .fajr, askAfterAdhanMinutes: 1)?.dueAt == day.fajr.addingTimeInterval(1800))
    #expect(NotificationArbiter.prayerAsk(day: day, prayer: .fajr, recorded: true) == nil)
}
@Test("Sanctity windows last 30 minutes after adhan and 20 after Maghrib")
func sanctityWindowDurations() throws {
    let friday = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
    let ramadan = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2027-02-10"), place: .riyadh))
    #expect(ramadan.hijriDate?.month == 9)
    for day in [friday, ramadan] {
        for prayer in Prayer.allCases {
            let minutes = prayer == .maghrib ? 20 : 30
            #expect(day.sanctityWindows.first { $0.prayer == prayer }?.end == day.time(for: prayer).addingTimeInterval(Double(minutes * 60)))
        }
    }
}
@Test("RP3 guard repeats across a following window and clamps exact starts")
func sanctityGuardCascades() throws {
    let first = SanctityWindow(prayer: .dhuhr, adhan: try instant(hour: 10), durationMinutes: 30)
    let following = SanctityWindow(prayer: .asr, adhan: try instant(hour: 10, minute: 25), durationMinutes: 30)
    let guarder = SanctityGuard(windows: [following, first])
    let requested = try instant(hour: 10, minute: 10)
    let clear = try instant(hour: 10, minute: 55)
    #expect(guarder.clamp(requested) == clear)
    #expect(guarder.clamp(following.start) == following.end)
    #expect(guarder.clamp(following.end) == following.end)
}
@Test("RP3 planning clamps prayer asks, snoozes, room requests, digest and nudge")
func sanctityRequestPaths() throws {
    let friday = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
    let dhuhrWindow = try #require(friday.sanctityWindows.first { $0.prayer == .dhuhr })
    let ask = try #require(NotificationArbiter.prayerAsk(day: friday, prayer: .dhuhr, askAfterAdhanMinutes: 25))
    #expect(ask.dueAt == dhuhrWindow.end)
    let snooze = NotificationCandidate(id: "salah.\(friday.day).dhuhr.snooze", room: .salah, kind: .prayerAsk, dueAt: friday.dhuhr.addingTimeInterval(25 * 60), dayKey: friday.day.description)
    let roomRequest = NotificationCandidate(id: "quran.friday", room: .quran, dueAt: friday.dhuhr.addingTimeInterval(25 * 60), dayKey: friday.day.description)
    let fridayPlan = NotificationArbiter.plan(candidates: [snooze, roomRequest], prayerDays: [friday], now: friday.dhuhr.addingTimeInterval(-60 * 60), timeZone: friday.place.timeZone, policy: .init(dailyBudget: 10, staleNudgeEnabled: false))
    #expect(fridayPlan.scheduled.count == 2)
    #expect(fridayPlan.scheduled.allSatisfy { $0.dueAt == dhuhrWindow.end })

    let ramadan = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2027-02-10"), place: .riyadh))
    let reminders = (0..<5).map { offset in
        NotificationCandidate(id: "notes.\(offset)", room: .notes, dueAt: ramadan.isha.addingTimeInterval(-25 * 60 + Double(offset) * 60), dayKey: ramadan.day.description)
    }
    let digestPlan = NotificationArbiter.plan(candidates: reminders, prayerDays: [ramadan], now: ramadan.isha.addingTimeInterval(-60 * 60), timeZone: ramadan.place.timeZone, policy: .init(dailyBudget: 1, staleNudgeEnabled: false))
    let digest = try #require(digestPlan.scheduled.first { $0.kind == .digest })
    #expect(digest.dueAt == ramadan.isha.addingTimeInterval(60 * 60))

    let nudgeNow = friday.dhuhr.addingTimeInterval(-48 * 60 * 60)
    let nudgePlan = NotificationArbiter.plan(candidates: [], prayerDays: [friday], now: nudgeNow, timeZone: friday.place.timeZone, policy: .init(staleNudgeEnabled: true))
    let nudge = try #require(nudgePlan.scheduled.first { $0.kind == .openApp })
    #expect(nudge.dueAt == dhuhrWindow.end)
}
@Test("RP3 full-year property: all requested instants clamp clear in Riyadh, Jeddah and Tromsø")
func sanctityGuardFullYearProperty() throws {
    let places = [
        ActivePlace.riyadh,
        try ActivePlace(latitude: 21.4858, longitude: 39.1925, timeZoneID: "Asia/Riyadh"),
        try ActivePlace(latitude: 69.6492, longitude: 18.9553, timeZoneID: "Europe/Oslo")
    ]
    let first = try GregorianDay("2025-12-25")
    let yearStart = try GregorianDay("2026-01-01")
    let yearEnd = try GregorianDay("2027-01-01")
    for place in places {
        var prayerDays: [PrayerDay] = []
        for offset in 0..<380 {
            let day = first.adding(days: offset)
            if let prayers = PrayerTimesEngine.calculate(day: day, place: place) { prayerDays.append(prayers) }
        }
        let windows = prayerDays.flatMap(\.sanctityWindows)
        let yearWindows = windows.filter { $0.start >= yearStart.date(in: place.timeZone) && $0.start < yearEnd.date(in: place.timeZone) }
        #expect(!yearWindows.isEmpty)
        let guarder = SanctityGuard(windows: windows)
        var violations = 0
        for window in yearWindows {
            let duration = window.end.timeIntervalSince(window.start)
            let requested = [
                window.start.addingTimeInterval(-1), window.start,
                window.start.addingTimeInterval(duration / 2),
                window.end.addingTimeInterval(-1), window.end
            ]
            for instant in requested {
                let clamped = guarder.clamp(instant)
                if clamped < instant || windows.contains(where: { $0.contains(clamped) }) { violations += 1 }
            }
        }
        #expect(violations == 0)
    }
}
@Test("Budget, note ceiling, cycle dedupe, digest and pending reserved slots")
func notificationBudget() throws {
    let day = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
    let now = try instant(hour: 0); let due = try instant(hour: 10)
    let inputs = (0..<10).map { NotificationCandidate(id: "r\($0)", room: .notes, dueAt: due, dayKey: "2026-10-09") }
    let plan = NotificationArbiter.plan(candidates: inputs, prayerDays: [day], now: now, timeZone: zone)
    #expect(plan.scheduled.filter { $0.kind == .reminder }.count == 2)
    let many = (0..<10).map { NotificationCandidate(id: "q\($0)", room: .quran, dueAt: due, dayKey: "2026-10-09") }
    let limited = NotificationArbiter.plan(candidates: many, prayerDays: [day], now: now, timeZone: zone)
    #expect(limited.scheduled.filter { $0.kind == .reminder }.count == 3)
    #expect(limited.digestedIDs.count == 7); #expect(limited.scheduled.filter { $0.kind == .digest }.count == 1)
    let capped = NotificationArbiter.plan(candidates: many, prayerDays: [day], now: now, timeZone: zone, existingPendingCount: 59)
    #expect(capped.scheduled.count == 1); #expect(capped.scheduled.first?.kind == .reminder)
    let cycle = NotificationCandidate(id: "80", room: .mal, dueAt: due, dayKey: day.day.description, categoryCycleKey: "food.2026-10")
    #expect(NotificationArbiter.plan(candidates: [cycle], prayerDays: [day], now: now, timeZone: zone, deliveredCategoryCycles: ["food.2026-10"]).droppedIDs == ["80"])
}
@Test("Quiet cutoff, horizon and asks exempt from budget")
func quietAndHorizon() throws {
    let day = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
    let now = try instant(hour: 0)
    let late = NotificationCandidate(id: "late", room: .notes, dueAt: try instant(hour: 22), dayKey: day.day.description)
    let plan = NotificationArbiter.plan(candidates: [late], prayerDays: [day], now: now, timeZone: zone, policy: .init(quietFromMinutes: 21 * 60 + 30))
    #expect(plan.droppedIDs.contains("late"))
    let asks = Prayer.allCases.compactMap { NotificationArbiter.prayerAsk(day: day, prayer: $0) }
    #expect(NotificationArbiter.plan(candidates: asks, prayerDays: [day], now: now, timeZone: zone, policy: .init(dailyBudget: 1)).scheduled.filter { $0.kind == .prayerAsk }.count == 5)
}
@Test("Routes are read/prefill, future features hidden, invalid inputs rejected")
func routes() throws {
    let context = RouteContext(trackingStart: try GregorianDay("2026-01-01"), today: try GregorianDay("2026-10-09"), settingsKeys: ["core.dayStart"], availability: .init(builtRooms: Set(Room.allCases)))
    let route = try RouteRegistry.parse(URL(string: "madar://mal/add?amount=1234&merchant=test")!, context: context)
    #expect(route.mode == .prefill)
    for path in ["categories", "reconcile", "zakat"] {
        let destination = try RouteRegistry.parse(URL(string: "madar://mal/\(path)")!, context: context)
        #expect(destination.room == .mal)
        #expect(destination.path == [path])
    }
    #expect(try !RouteRegistry.parse(URL(string: "madar://notes/write?day=yesterday")!, context: context).requiresUnlock)
    // «أكمل القراءة» (Siri): the Mihbara room picks the book, so the route carries none and takes no parameters.
    let resume = try RouteRegistry.parse(URL(string: "madar://mihbara/continue")!, context: context)
    #expect(resume.room == .mihbara && resume.path == ["continue"])
    for input in ["madar://mihbara/continue?id=1", "madar://mihbara/continue/extra"] {
        #expect(throws: (any Error).self) { try RouteRegistry.parse(URL(string: input)!, context: context) }
    }
    let locked = RouteContext(trackingStart: context.trackingStart, today: context.today, settingsKeys: context.settingsKeys, unavailableSettings: context.unavailableSettings, lock: .app, availability: context.availability)
    #expect(try RouteRegistry.parse(URL(string: "madar://notes/write")!, context: locked).requiresUnlock)
    for input in ["madar://mal/add?amount=1.5", "madar://mal/add?amount=1&amount=2", "madar://notes/day/2026-02-30", "madar://quran/page/605", "madar://salah/log?prayer=sunrise", "madar://notes/write?save=true", "madar://capture?text=hello", "madar://settings/core/not-a-key"] {
        #expect(throws: (any Error).self) { try RouteRegistry.parse(URL(string: input)!, context: context) }
    }
    let missingSetting = try RouteRegistry.parse(URL(string: "madar://settings/core/no.such.key")!, context: context)
    #expect(missingSetting.room == .core)
    #expect(missingSetting.path == ["core", "no.such.key"])
    let m0 = RouteContext(trackingStart: context.trackingStart, today: context.today, settingsKeys: context.settingsKeys)
    #expect(throws: CoreError.unavailableFeature) { try RouteRegistry.parse(URL(string: "madar://salah")!, context: m0) }
    #expect(FeatureAvailability.m0.builtRooms == [.core])
    #expect(DayEventBus().publish(.init(kind: "PrayerLogged", eventID: UUID(), dayKey: "2026-10-09")).isEmpty)
}
private actor TestAdapter: CommandStoreAdapter {
    var requests: [CommandTransactionRequest] = []
    func transact(_ request: CommandTransactionRequest, now: Date) -> CommandOutcome { requests.append(request); return .init(status: .applied, undoToken: request.envelope.commandID) }
    func count() -> Int { requests.count }
    func first() -> CommandTransactionRequest? { requests.first }
}
@Test("Command parser rejects unknown fields and never accepts room writes in M0")
func commands() async throws {
    let adapter = TestAdapter(); let bus = CommandBus(adapter: adapter); let now = try instant(hour: 12)
    let preset = CommandEnvelope(name: "settings.applyPreset", payload: .object(["settings": .object(["core.dayStart": .string("midnight")])]), issuedAt: now)
    let result = try await bus.execute(preset, now: now); #expect(result.status == .applied)
    let request = try #require(await adapter.first())
    let receipt = CoreCommandReceipt(request: request, now: now, undoJSON: Data([1]), outcome: result)
    #expect(receipt.canUndo(at: now.addingTimeInterval(59))); #expect(!receipt.canUndo(at: now.addingTimeInterval(60)))
    #expect(receipt.expiresAt == now.addingTimeInterval(7 * 86400))
    #expect(request.decision(receipts: [receipt], existingNaturalPayloadHash: nil, now: now.addingTimeInterval(2)) == .replay(result))
    let rejected = try await bus.execute(.init(name: "quran.commitSession", payload: .object([:]), issuedAt: now), now: now)
    #expect(rejected.status == .rejected)
    let malformed = try await bus.execute(.init(name: "settings.set", payload: .object(["settings": .object([:]), "write": .bool(true)]), issuedAt: now), now: now)
    #expect(malformed.status == .rejected); #expect(await adapter.count() == 1)
}
@Test("Canonical hashes cross surfaces and equal natural values never refresh update time")
func canonicalAndDedupe() throws {
    let a: JSONValue = .object(["a": .number(1), "b": .string("text")]); let b: JSONValue = .object(["b": .string("text"), "a": .number(1)])
    #expect(try a.sha256() == b.sha256())
    let now = try instant(hour: 12)
    let request = CommandTransactionRequest(envelope: .init(name: "append", payload: a, source: .widget, issuedAt: now), operation: .replaceSettings([:]), semantics: .append, payloadHash: try a.sha256(), naturalKey: nil)
    let receipt = CoreCommandReceipt(request: request, now: now, undoJSON: Data([1]), outcome: .init(status: .applied))
    let other = CommandTransactionRequest(envelope: .init(name: "append", payload: b, source: .app, issuedAt: now), operation: .replaceSettings([:]), semantics: .append, payloadHash: try b.sha256(), naturalKey: nil)
    #expect(other.decision(receipts: [receipt], existingNaturalPayloadHash: nil, now: now.addingTimeInterval(10)) == .duplicate)
    #expect(other.decision(receipts: [receipt], existingNaturalPayloadHash: nil, now: now.addingTimeInterval(11)) == .apply)
    #expect(receipt.canUndo(at: now.addingTimeInterval(599))); #expect(!receipt.canUndo(at: now.addingTimeInterval(600)))
    let upsert = CommandTransactionRequest(envelope: other.envelope, operation: other.operation, semantics: .upsert, payloadHash: other.payloadHash, naturalKey: "unique")
    #expect(upsert.decision(receipts: [], existingNaturalPayloadHash: other.payloadHash, now: now) == .duplicate)
}
@Test("Preset save and onboarding use durable command operations")
func presetAndOnboarding() async throws {
    let adapter = TestAdapter(); let bus = CommandBus(adapter: adapter); let now = try instant(hour: 12)
    #expect(try await bus.execute(.init(name: "preset.save", payload: .object(["name": .string("صباح"), "settings": .object([:]), "layouts": .object([:])]), issuedAt: now), now: now).status == .applied)
    let save = try #require(await adapter.first()); #expect(save.semantics == .append)
    #expect(try await bus.execute(.init(name: "core.completeOnboarding", payload: .object([:]), issuedAt: now), now: now).status == .applied)
    #expect(try await bus.execute(.init(name: "core.completeOnboarding", payload: .object(["unknown": .bool(true)]), issuedAt: now), now: now).status == .rejected)
}
private struct J10File: Decodable { let version: Int; let scenarios: [J10Scenario] }
private struct J10Scenario: Decodable { let day: String; let isha: String; let quiet: Int?; let device: Bool; let disabled: [String]; let room: String; let expected: [String]; let digestClock: String?; let travel: Bool? }
@Test("J10 v1 week: digest shares budget, quiet timing, travel, per-device switch, type off")
func J10_weekGolden() throws {
    let url = try #require(Bundle.module.url(forResource: "notification-j10-v1", withExtension: "json", subdirectory: "Fixtures"))
    let fixture = try JSONDecoder().decode(J10File.self, from: Data(contentsOf: url)); #expect(fixture.version == 1)
    for scenario in fixture.scenarios {
        let day = try GregorianDay(scenario.day)
        let place = scenario.travel == true ? try ActivePlace(latitude: 21.4858, longitude: 39.1925, timeZoneID: "Asia/Riyadh") : .riyadh
        func clock(_ value: String) throws -> Date { let p = value.split(separator: ":").map { Int($0)! }; return try instant(scenario.day, hour: p[0], minute: p[1]) }
        // Inject written clock inputs to isolate scheduling rules from astronomy calculation.
        let prayers = PrayerDay(day: day, place: place, fajr: try clock("04:30"), sunrise: try clock("05:50"), dhuhr: try clock("11:41"), asr: try clock("15:03"), maghrib: try clock("17:34"), isha: try clock(scenario.isha))
        let candidates = try (0..<6).map { NotificationCandidate(id: "q\($0)", room: Room(rawValue: scenario.room)!, dueAt: try clock("10:00").addingTimeInterval(Double($0 * 60)), dayKey: scenario.day) }
        let result = NotificationArbiter.plan(candidates: candidates, prayerDays: [prayers], now: try clock("00:00"), timeZone: zone, policy: .init(quietFromMinutes: scenario.quiet, thisDeviceRemindersEnabled: scenario.device, staleNudgeEnabled: false), disabledIDs: Set(scenario.disabled))
        #expect(Set(result.scheduled.map(\.id)) == Set(scenario.expected))
        #expect(result.scheduled.filter { $0.kind != .prayerAsk }.count <= 4)
        if let expected = scenario.digestClock { #expect(result.scheduled.first { $0.kind == .digest }?.dueAt == (try clock(expected))) }
        for request in result.scheduled { #expect(!prayers.sanctityWindows.contains { $0.contains(request.dueAt) }) }
    }
}
@Test("J10 cap trims farthest prayers before room requests; nudge stable and in day budget")
func J10_capAndNudge() throws {
    let now = try instant(hour: 0)
    let room = NotificationCandidate(id: "room", room: .quran, dueAt: try instant(hour: 10), dayKey: "2026-10-09")
    let near = NotificationCandidate(id: "near", room: .salah, kind: .prayerAsk, dueAt: now.addingTimeInterval(60), dayKey: "2026-10-09")
    let far = NotificationCandidate(id: "far", room: .salah, kind: .prayerAsk, dueAt: now.addingTimeInterval(80 * 3600), dayKey: "2026-10-12")
    let capped = NotificationArbiter.plan(candidates: [far, near, room], prayerDays: [], now: now, timeZone: zone, policy: .init(staleNudgeEnabled: false), existingPendingCount: 58)
    #expect(Set(capped.scheduled.map(\.id)) == ["near", "room"]); #expect(capped.droppedIDs == ["far"])
    let next = NotificationArbiter.plan(candidates: [], prayerDays: [], now: now, timeZone: zone)
    #expect(next.scheduled.count == 1); #expect(next.scheduled.first?.id == "nudge.2026-10-11")
    let again = NotificationArbiter.plan(candidates: [], prayerDays: [], now: now, timeZone: zone)
    #expect(next == again)
}
@Test("RU1 dual dates separate numeric parts with an Arabic comma")
func test_RU1_dualDatesSeparateDigitsWithArabicComma() throws {
    let dual = DualDate(instant: try instant(hour: 12), timeZone: zone)
    // Hand-written Hijri reference from the handoff, with RU1's punctuation.
    let fixtures: [(FirstCalendar, NumeralStyle, String)] = [
        (.hijri, .hindi, "٢٨ ربيع الآخر ١٤٤٨، ٢٠٢٦-١٠-٠٩"),
        (.gregorian, .hindi, "٢٠٢٦-١٠-٠٩، ٢٨ ربيع الآخر ١٤٤٨"),
        (.hijri, .western, "28 ربيع الآخر 1448، 2026-10-09"),
        (.gregorian, .western, "2026-10-09، 28 ربيع الآخر 1448")
    ]
    for (calendar, numerals, expected) in fixtures {
        #expect(dual.text(firstCalendar: calendar, numerals: numerals) == expected)
    }
}
@Test("J01 dual calendar order and diary night presentation leave stored key alone")
func dualDateAndTravel() throws {
    let date = try instant(hour: 12)
    let dual = DualDate(instant: date, timeZone: zone)
    #expect(dual.text().hasPrefix("٢٨ ربيع الآخر ١٤٤٨"))
    #expect(dual.text(firstCalendar: .gregorian).hasPrefix("٢٠٢٦-١٠-٠٩"))
    let day = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
    #expect(DualDate.diaryNightHijri(instant: day.maghrib, prayers: day).day == 29)
    let riyadhDay = try MadarDay.resolve(instant: instant(hour: 2), place: .riyadh, boundary: .midnight, prayerDays: [])
    let la = try ActivePlace(latitude: 34.0522, longitude: -118.2437, timeZoneID: "America/Los_Angeles")
    let laDay = try MadarDay.resolve(instant: instant(hour: 2), place: la, boundary: .midnight, prayerDays: [])
    #expect(riyadhDay.dayKey == "2026-10-09"); #expect(laDay.dayKey == "2026-10-08")
    #expect(throws: (any Error).self) { try JSONDecoder().decode(ActivePlace.self, from: Data(#"{"latitude":34,"longitude":0,"timeZoneID":"NoSuchZone"}"#.utf8)) }
}
private struct J10Rollover: Decodable {
    let version: Int; let start: String; let boundary: String; let isha: String; let digest: String
    let dayOneCandidates: [String]; let dayTwoCandidates: [String]; let expectedScheduled: [String]; let expectedDropped: [String]
}
@Test("J10 rollover v1: late Isha digest cannot overrun next midnight-day budget")
func J10_finalDeliveryDayBudget() throws {
    let url = try #require(Bundle.module.url(forResource: "notification-j10-rollover-v1", withExtension: "json", subdirectory: "Fixtures"))
    let f = try JSONDecoder().decode(J10Rollover.self, from: Data(contentsOf: url)); #expect(f.version == 1)
    let day = try GregorianDay(f.start), second = day.adding(days: 1)
    let firstPrayers = PrayerDay(day: day, place: .riyadh, fajr: try instant(f.start, hour: 4), sunrise: try instant(f.start, hour: 5), dhuhr: try instant(f.start, hour: 12), asr: try instant(f.start, hour: 15), maghrib: try instant(f.start, hour: 22), isha: try instant(f.start, hour: 23, minute: 30))
    let nextPrayers = PrayerDay(day: second, place: .riyadh, fajr: try instant(second.description, hour: 4), sunrise: try instant(second.description, hour: 5), dhuhr: try instant(second.description, hour: 12), asr: try instant(second.description, hour: 15), maghrib: try instant(second.description, hour: 22), isha: try instant(second.description, hour: 23, minute: 30))
    let one = try f.dayOneCandidates.enumerated().map { i, id in NotificationCandidate(id: id, room: .quran, dueAt: try instant(f.start, hour: 10, minute: i), dayKey: f.start) }
    let two = try f.dayTwoCandidates.enumerated().map { i, id in NotificationCandidate(id: id, room: .quran, dueAt: try instant(second.description, hour: 10, minute: i), dayKey: second.description) }
    let plan = NotificationArbiter.plan(candidates: one + two, prayerDays: [firstPrayers, nextPrayers], now: try instant(f.start, hour: 0), timeZone: zone, policy: .init(staleNudgeEnabled: false, dayBoundary: .midnight))
    #expect(Set(plan.scheduled.map(\.id)) == Set(f.expectedScheduled))
    #expect(Set(plan.droppedIDs) == Set(f.expectedDropped)); #expect(plan.digestedIDs.isEmpty)
    let groups = Dictionary(grouping: plan.scheduled.filter { $0.kind != .prayerAsk }) { GregorianDay.containing($0.dueAt, in: zone) }
    #expect(groups.values.allSatisfy { $0.count <= 4 })
}
@Test("J10 returning later uses durable submitted budget and notes cap, including nudge")
func J10_rescheduleConsumedBudget() throws {
    let now = try instant(hour: 12)
    let day = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
    let candidates = try (0..<4).map { NotificationCandidate(id: "new\($0)", room: .quran, dueAt: try instant(hour: 14, minute: $0), dayKey: "2026-10-09") }
    let result = NotificationArbiter.plan(candidates: candidates, prayerDays: [day], now: now, timeZone: zone, policy: .init(staleNudgeEnabled: false), submittedBudgetByDay: ["2026-10-09": 3])
    #expect(result.scheduled.count == 1); #expect(result.scheduled.first?.kind == .digest)
    let spent = NotificationArbiter.plan(candidates: candidates, prayerDays: [day], now: now, timeZone: zone, policy: .init(staleNudgeEnabled: false), submittedBudgetByDay: ["2026-10-09": 4])
    #expect(spent.scheduled.isEmpty); #expect(spent.droppedIDs.count == 4)
    let note = NotificationCandidate(id: "note", room: .notes, dueAt: try instant(hour: 14), dayKey: "2026-10-09")
    #expect(NotificationArbiter.plan(candidates: [note], prayerDays: [day], now: now, timeZone: zone, policy: .init(staleNudgeEnabled: false), submittedNotesByDay: ["2026-10-09": 2]).scheduled.isEmpty)
}
@Test("M0 internal prayer upsert has strict owner payload and no visible room")
func foundationPrayerCommand() async throws {
    let adapter = TestAdapter(); let bus = CommandBus(adapter: adapter); let now = try instant(hour: 12)
    let payload: JSONValue = .object(["dayKey": .string("2026-10-09"), "prayer": .string("fajr"), "status": .string("jamaah"), "heart": .string("khashi"), "shortened": .bool(false)])
    #expect(try await bus.execute(.init(name: "prayer.log", payload: payload, source: .notification, issuedAt: now), now: now).status == .applied)
    let request = try #require(await adapter.first())
    #expect(request.operation == .logPrayer(dayKey: "2026-10-09", prayer: .fajr, status: "jamaah", heart: "khashi", shortened: false, fridayKind: nil))
    #expect(request.naturalKey == "prayer.2026-10-09.fajr")
    #expect(request.decision(receipts: [], existingNaturalPayloadHash: request.payloadHash, now: now) == .duplicate)
    #expect(!FeatureAvailability.m0.isAvailable(.salah))
    for invalid in [
        JSONValue.object(["dayKey": .string("2026-02-30"), "prayer": .string("fajr"), "status": .string("alone")]),
        .object(["dayKey": .string("2026-10-09"), "prayer": .string("fajr"), "status": .string("pending")]),
        .object(["dayKey": .string("2026-10-09"), "prayer": .string("fajr"), "status": .string("alone"), "heart": .number(1)])
    ] { #expect(try await bus.execute(.init(name: "prayer.log", payload: invalid, source: .widget, issuedAt: now), now: now).status == .rejected) }
    #expect(try await bus.execute(.init(name: "settings.set", payload: .object(["settings": .object(["core.theme": .string("dark")])]), source: .notification, issuedAt: now), now: now).status == .needsApp)
    #expect(await adapter.count() == 1)
}
@Test("Retired prayer-backlog commands cannot create unperformed prayer records")
func prayerBacklogCommandsAreRejected() throws {
    let payload: [String: JSONValue] = [:]
    for name in ["prayer.addOldMissed", "prayer.makeUp", "prayer.markUnrecorded", "prayer.addOldMissedRun", "prayer.makeUpOldest", "prayer.resolveGap"] {
        #expect(throws: CoreError.invalidCommand) { try PrayerMutation.parse(name: name, payload: payload) }
    }
}
@Test("Civil day arithmetic is UTC and never repeats/skips a day across device DST")
func GregorianDay_DSTIndependentArithmetic() throws {
    #expect(try GregorianDay("2026-03-08").adding(days: 1).description == "2026-03-09")
    #expect(try GregorianDay("2026-11-01").adding(days: 1).description == "2026-11-02")
    #expect(try GregorianDay("2026-03-09").adding(days: -1).description == "2026-03-08")
    #expect(try GregorianDay("2028-02-28").adding(days: 1).description == "2028-02-29")
    #expect(try GregorianDay("2026-12-31").adding(days: 1).description == "2027-01-01")
}

@Test("RL5 prayer activities start immediately only outside sanctity and consume the actual Madar day budget")
func liveActivityBudgetAndSanctity() throws {
    let day = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
    // Fajr is 04:31; an immediate start during its fixed 30-minute sanctity window is rejected, not queued.
    let insideSanctity = try instant(hour: 4, minute: 40)
    #expect(NotificationArbiter.liveActivityStart(id: "activity.sanctity", proposedAt: insideSanctity, prayerDays: [day],
        timeZone: zone, policy: .init(dailyBudget: 4), submittedBudgetByDay: [:]) == nil)
    // 06:00 is outside sanctity, before Dhuhr, and more than 12 hours before Isha.
    let proposed = try instant(hour: 6)
    let allowed = NotificationArbiter.liveActivityStart(id: "activity.one", proposedAt: proposed, prayerDays: [day],
        timeZone: zone, policy: .init(dailyBudget: 4), submittedBudgetByDay: ["2026-10-09": 3])
    #expect(allowed?.dueAt == proposed)
    #expect(allowed?.dayKey == "2026-10-09")
    #expect(NotificationArbiter.liveActivityStart(id: "activity.full", proposedAt: proposed, prayerDays: [day],
        timeZone: zone, policy: .init(dailyBudget: 4), submittedBudgetByDay: ["2026-10-09": 4]) == nil)
    // At 06:00, the configured Maghrib boundary still counts yesterday while the Fajr boundary counts today.
    let afterFajr = try instant(hour: 6)
    #expect(NotificationArbiter.liveActivityStart(id: "maghrib-boundary-full", proposedAt: afterFajr, prayerDays: [day],
        timeZone: zone, policy: .init(dayBoundary: .maghrib), submittedBudgetByDay: ["2026-10-08": 4]) == nil)
    #expect(NotificationArbiter.liveActivityStart(id: "fajr-boundary-available", proposedAt: afterFajr, prayerDays: [day],
        timeZone: zone, policy: .init(dayBoundary: .fajr), submittedBudgetByDay: ["2026-10-08": 4])?.dayKey == "2026-10-09")
}

@Test("RL5 immediate activity starts respect quiet hours and device reminders")
func liveActivityQuietAndOff() throws {
    let day = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
    #expect(NotificationArbiter.liveActivityStart(id: "quiet", proposedAt: try instant(hour: 7), prayerDays: [day],
        timeZone: zone, policy: .init(quietFromMinutes: 6 * 60 + 30), submittedBudgetByDay: [:]) == nil)
    #expect(NotificationArbiter.liveActivityStart(id: "off", proposedAt: try instant(hour: 10), prayerDays: [day],
        timeZone: zone, policy: .init(thisDeviceRemindersEnabled: false), submittedBudgetByDay: [:]) == nil)
}

@Test("RL5 contextual activities start only inside the shared budget and allowed prayer window")
func contextActivityStartPolicy() throws {
    let previous = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-08"), place: .riyadh))
    let day = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
    let next = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-10"), place: .riyadh))
    let allowedAt = try instant(hour: 6)
    let allowed = NotificationArbiter.contextActivityStart(id: "context.one", proposedAt: allowedAt,
        prayerDays: [previous, day, next], timeZone: zone, policy: .init(dailyBudget: 4),
        submittedBudgetByDay: ["2026-10-09": 3])
    #expect(allowed?.dueAt == allowedAt)
    #expect(allowed?.dayKey == "2026-10-09")
    #expect(NotificationArbiter.contextActivityStart(id: "context.full", proposedAt: allowedAt,
        prayerDays: [previous, day, next], timeZone: zone, policy: .init(dailyBudget: 4),
        submittedBudgetByDay: ["2026-10-09": 4]) == nil)
    #expect(NotificationArbiter.contextActivityStart(id: "context.quiet", proposedAt: try instant(hour: 22),
        prayerDays: [previous, day, next], timeZone: zone,
        policy: .init(quietFromMinutes: 21 * 60 + 30), submittedBudgetByDay: [:]) == nil)
    #expect(NotificationArbiter.contextActivityStart(id: "context.sanctity", proposedAt: try instant(hour: 4, minute: 40),
        prayerDays: [previous, day, next], timeZone: zone, policy: .init(), submittedBudgetByDay: [:]) == nil)
    #expect(NotificationArbiter.contextActivityStart(id: "context.night", proposedAt: try instant(hour: 2),
        prayerDays: [previous, day, next], timeZone: zone, policy: .init(), submittedBudgetByDay: [:]) == nil)
    #expect(NotificationArbiter.contextActivityStart(id: "context.beforeIsha", proposedAt: try instant(hour: 10),
        prayerDays: [previous, day, next], timeZone: zone, policy: .init(), submittedBudgetByDay: [:]) == nil)
}

/// RP4. Expected clocks come from an independent implementation, not from this engine:
/// Aladhan API (api.aladhan.com/v1/timings), fetched 13 Oct 2026. London = method 3 (Muslim World League, Fajr 18°, Isha 17°);
/// Istanbul = method 13 (Diyanet, Turkey). The source applies the angle-based high-latitude rule, so the test pins `.twilightAngle` (Madar's own default above 48° is the seventh of the night, per the spec). Owner decision 13 Oct 2026: a few minutes of difference is acceptable.
@Test("Trip methods: London with MWL and Istanbul with Turkey match an independent source", arguments: [
    ("London", 51.5074, -0.1278, "Europe/London", PrayerCalculationMethod.mwl, "2026-12-21", ["05:59", "11:59", "13:38", "15:53", "17:51"]),
    ("London", 51.5074, -0.1278, "Europe/London", PrayerCalculationMethod.mwl, "2026-03-20", ["04:10", "12:08", "15:24", "18:14", "20:00"]),
    ("Istanbul", 41.0082, 28.9784, "Europe/Istanbul", PrayerCalculationMethod.turkey, "2026-12-21", ["06:46", "13:07", "15:25", "17:46", "19:13"]),
    ("Istanbul", 41.0082, 28.9784, "Europe/Istanbul", PrayerCalculationMethod.turkey, "2026-03-20", ["05:36", "13:17", "16:39", "19:23", "20:43"]),
    ("Istanbul", 41.0082, 28.9784, "Europe/Istanbul", PrayerCalculationMethod.turkey, "2026-06-21", ["03:24", "13:11", "17:11", "20:47", "22:38"]),
])
func tripMethodTimes(_ city: String, _ lat: Double, _ lon: Double, _ zoneID: String, _ method: PrayerCalculationMethod, _ date: String, _ expected: [String]) throws {
    let place = try ActivePlace(latitude: lat, longitude: lon, timeZoneID: zoneID)
    let day = try #require(PrayerTimesEngine.calculate(day: GregorianDay(date), place: place, options: .init(method: method, highLatitudeRule: .twilightAngle)))
    var cal = Calendar(identifier: .gregorian); cal.timeZone = place.timeZone
    for (prayer, clock) in zip(Prayer.allCases, expected) {
        let pieces = clock.split(separator: ":").map { Int($0)! }
        let c = cal.dateComponents([.hour, .minute], from: day.time(for: prayer))
        let difference = abs((c.hour! * 60 + c.minute!) - (pieces[0] * 60 + pieces[1]))
        #expect(difference <= 3, "\(city) \(date) \(prayer): got \(c.hour!):\(c.minute!), expected \(clock)")
    }
}

@Test("Owner 29 Oct: quiet after Isha ends at midnight, Fajr or sunrise as the owner chooses")
func quietEndChoice() throws {
    let day = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
    let from = 21 * 60 + 30
    func quiet(_ at: Date, _ end: QuietEnd) -> Bool {
        NotificationArbiter.quietWindowContains(at, timeZone: zone, fromMinutes: from, until: end, prayerDays: [day])
    }
    // Evening: quiet from 21:30 whatever the end.
    for end in [QuietEnd.midnight, .fajr, .sunrise] {
        #expect(quiet(try instant(hour: 22), end)); #expect(!quiet(try instant(hour: 20), end))
    }
    // Small hours: only the Fajr and sunrise ends keep the night quiet.
    #expect(!quiet(try instant(hour: 1, minute: 30), .midnight))
    #expect(quiet(try instant(hour: 1, minute: 30), .fajr))
    #expect(quiet(try instant(hour: 1, minute: 30), .sunrise))
    // Between Fajr and sunrise: quiet only until sunrise.
    let between = day.fajr.addingTimeInterval(day.sunrise.timeIntervalSince(day.fajr) / 2)
    #expect(!quiet(between, .fajr)); #expect(quiet(between, .sunrise))
    // After sunrise the day is open again.
    #expect(!quiet(day.sunrise.addingTimeInterval(60), .sunrise))
    // The arbiter drops a 01:30 room reminder only when the night stays quiet.
    let night = NotificationCandidate(id: "night", room: .habits, dueAt: try instant(hour: 1, minute: 30), dayKey: day.day.description)
    let early = try instant(hour: 0)
    #expect(NotificationArbiter.plan(candidates: [night], prayerDays: [day], now: early, timeZone: zone,
        policy: .init(quietFromMinutes: from, quietUntil: .fajr)).droppedIDs.contains("night"))
    #expect(!NotificationArbiter.plan(candidates: [night], prayerDays: [day], now: early, timeZone: zone,
        policy: .init(quietFromMinutes: from, quietUntil: .midnight)).droppedIDs.contains("night"))
}

@Test("A daylight-saving day still digests before quiet begins")
func quietCutoffFollowsTheWallClock() throws {
    // London springs forward at 01:00 on 29 March 2026 (after Ramadan): 22:00 on that day is 21 elapsed hours after midnight, not 22.
    let place = try ActivePlace(latitude: 51.51, longitude: -0.13, timeZoneID: "Europe/London")
    var cal = Calendar(identifier: .gregorian); cal.timeZone = place.timeZone
    func at(_ h: Int, _ m: Int = 0) throws -> Date { try #require(cal.date(from: .init(year: 2026, month: 3, day: 29, hour: h, minute: m))) }
    let day = PrayerDay(day: try GregorianDay("2026-03-29"), place: place, fajr: try at(5, 50), sunrise: try at(7, 15), dhuhr: try at(13, 10),
                        asr: try at(16, 25), maghrib: try at(19, 10), isha: try at(21))
    let candidates = (0..<3).map { NotificationCandidate(id: "habits.2026-03-29.\($0)", room: .habits, dueAt: day.dhuhr.addingTimeInterval(3600 + Double($0) * 600), dayKey: "2026-03-29") }
    let plan = NotificationArbiter.plan(candidates: candidates, prayerDays: [day], now: try at(9), timeZone: place.timeZone,
                                        policy: .init(dailyBudget: 2, quietFromMinutes: 22 * 60, staleNudgeEnabled: false))
    // Isha + 60 min is 22:00, the start of quiet; the digest moves to 21:45 wall time instead of being lost.
    let digest = try #require(plan.scheduled.first { $0.kind == .digest })
    #expect(cal.dateComponents([.hour, .minute], from: digest.dueAt) == DateComponents(hour: 21, minute: 45))
}

// Owner, 4 Nov 2026: the prayer-time alert is a reminder BEFORE the adhan (nothing may arrive from adhan to the end of the sanctity window, RP3).
@Test("Before-adhan reminder: adhan minus N for all five, outside the budget and the digest")
func prayerBeforeReminders() throws {
    let day = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
    let adhans: [Prayer: Date] = [.fajr: day.fajr, .dhuhr: day.dhuhr, .asr: day.asr, .maghrib: day.maghrib, .isha: day.isha]
    let before = Prayer.allCases.compactMap { NotificationArbiter.prayerBefore(day: day, prayer: $0, minutesBefore: 10) }
    #expect(before.count == 5)
    for item in before {
        let prayer = try #require(Prayer.allCases.first { item.id == "salah.2026-10-09.\($0.rawValue).before" })
        #expect(item.dueAt == adhans[prayer]!.addingTimeInterval(-600))
        #expect(item.kind == .prayerBefore && item.room == .salah)
    }
    // Four room reminders fill the whole daily budget; five before-adhan reminders are still all scheduled and nothing is digested.
    let now = try instant(hour: 0)
    let rooms = (0..<4).map { NotificationCandidate(id: "quran.r\($0)", room: .quran, dueAt: day.fajr.addingTimeInterval(Double($0 + 1) * 3600), dayKey: day.day.description) }
    let plan = NotificationArbiter.plan(candidates: before + rooms, prayerDays: [day], now: now, timeZone: zone, policy: .init(dailyBudget: 4, staleNudgeEnabled: false))
    #expect(plan.scheduled.filter { $0.kind == .prayerBefore }.count == 5)
    #expect(plan.scheduled.filter { $0.kind == .reminder }.count == 4)
    #expect(plan.digestedIDs.isEmpty)
    // None of the scheduled instants lies inside a sanctity window.
    let guardian = SanctityGuard(prayerDays: [day])
    #expect(plan.scheduled.allSatisfy { guardian.clamp($0.dueAt) == $0.dueAt })
}

@Test("Before-adhan reminder is dropped, never moved later, when the guard would move it")
func prayerBeforeNeverShifts() throws {
    let day = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
    // A window that ends 5 minutes before Dhuhr's adhan covers the instant 10 minutes before it.
    let covering = SanctityWindow(prayer: .asr, adhan: day.dhuhr.addingTimeInterval(-40 * 60), durationMinutes: 35)
    #expect(NotificationArbiter.prayerBefore(day: day, prayer: .dhuhr, minutesBefore: 10, sanctityWindows: day.sanctityWindows + [covering]) == nil)
    let inside = NotificationCandidate(id: "salah.2026-10-09.dhuhr.before", room: .salah, kind: .prayerBefore, dueAt: day.dhuhr.addingTimeInterval(-600), dayKey: "2026-10-09")
    let plan = NotificationArbiter.plan(candidates: [inside], prayerDays: [day], now: try instant(hour: 0), timeZone: zone, policy: .init(staleNudgeEnabled: false),
                                        sanctityWindows: day.sanctityWindows + [covering])
    #expect(plan.scheduled.isEmpty && plan.droppedIDs == ["salah.2026-10-09.dhuhr.before"])
}

@Test("Before-adhan reminder obeys the owner's own quiet hours")
func prayerBeforeQuiet() throws {
    let day = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
    let fajr = try #require(NotificationArbiter.prayerBefore(day: day, prayer: .fajr, minutesBefore: 10))
    let dhuhr = try #require(NotificationArbiter.prayerBefore(day: day, prayer: .dhuhr, minutesBefore: 10))
    let policy = NotificationPolicy(quietFromMinutes: 21 * 60 + 30, quietUntil: .fajr, staleNudgeEnabled: false)
    let plan = NotificationArbiter.plan(candidates: [fajr, dhuhr], prayerDays: [day], now: try instant(hour: 0), timeZone: zone, policy: policy)
    #expect(plan.droppedIDs == [fajr.id], "quiet runs until Fajr, so the reminder before Fajr is silenced")
    #expect(plan.scheduled.map(\.id) == [dhuhr.id])
    let open = NotificationArbiter.plan(candidates: [fajr], prayerDays: [day], now: try instant(hour: 0), timeZone: zone, policy: .init(staleNudgeEnabled: false))
    #expect(open.scheduled.map(\.id) == [fajr.id], "with no quiet hours (the default) the Fajr reminder is scheduled")
}

@Test("Default room priority puts what is lost with time first")
func defaultRoomPriority() {
    #expect(NotificationPolicy().priority == [.quran, .habits, .notes, .salah, .mal, .mihbara])
}
