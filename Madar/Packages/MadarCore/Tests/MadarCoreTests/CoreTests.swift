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
    #expect(try RouteRegistry.parse(URL(string: "madar://notes/write?day=yesterday")!, context: context).requiresUnlock)
    for input in ["madar://mal/add?amount=1.5", "madar://mal/add?amount=1&amount=2", "madar://notes/day/2026-02-30", "madar://quran/page/605", "madar://salah/log?prayer=sunrise", "madar://notes/write?save=true", "madar://settings/core/no.such.key"] {
        #expect(throws: (any Error).self) { try RouteRegistry.parse(URL(string: input)!, context: context) }
    }
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
@Test("Friday classification travels through old-missed and make-up commands")
func fridayPrayerMutationCommands() throws {
    let day = try GregorianDay("2026-10-09")
    let ref = PrayerReference(day: day, prayer: .dhuhr)
    let base: [String: JSONValue] = ["dayKey": .string(day.description), "prayer": .string("dhuhr")]
    var oldMissed = base; oldMissed["fridayKind"] = .string("jumuah")
    #expect(try PrayerMutation.parse(name: "prayer.addOldMissed", payload: oldMissed).0 == .addOldMissed(ref, fridayKind: .jumuah))
    var makeUp = base; makeUp["fridayKind"] = .string("dhuhr")
    #expect(try PrayerMutation.parse(name: "prayer.makeUp", payload: makeUp).0 == .makeUp(ref, fridayKind: .dhuhr))
    makeUp["fridayKind"] = .string("unknown")
    #expect(throws: CoreError.invalidCommand) { try PrayerMutation.parse(name: "prayer.makeUp", payload: makeUp) }
}
@Test("Civil day arithmetic is UTC and never repeats/skips a day across device DST")
func GregorianDay_DSTIndependentArithmetic() throws {
    #expect(try GregorianDay("2026-03-08").adding(days: 1).description == "2026-03-09")
    #expect(try GregorianDay("2026-11-01").adding(days: 1).description == "2026-11-02")
    #expect(try GregorianDay("2026-03-09").adding(days: -1).description == "2026-03-08")
    #expect(try GregorianDay("2028-02-28").adding(days: 1).description == "2028-02-29")
    #expect(try GregorianDay("2026-12-31").adding(days: 1).description == "2027-01-01")
}
