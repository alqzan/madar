import XCTest
import SwiftData
import MadarCore
import MadarData
@testable import Madar

@MainActor final class LegacyPersonalTrialTests: XCTestCase {
    func testSealedSourceStaysOutOfCardsSearchExportAndReplayKeepsNativeEdits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PersonalTrial-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let app = try AppSession(container: store.container, managedStore: store, groupDirectory: root)
        app.authorizeProtectedData()
        let zone = TimeZone(identifier: "Asia/Riyadh")!, observed = try GregorianDay("2026-10-25")
        let raw = #"{"futureLetters":[{"id":"l","content":"SEALED-SOURCE-MUST-STAY-PRIVATE","title":"kept separately","writtenDate":"2026-10-01","deliveryDate":"2027-11-19","opened":false}],"countdownEvents":[{"id":"a","title":"موعد محفوظ","date":"2027-11-19"},{"id":"b","title":"عد صاعد","date":"2027-11-20","countUpAfter":true}]}"#
        let plan = try LegacyPersonalImport.plan(backup: Data(raw.utf8), observedDay: observed, zone: zone, uuid: StableIdentity.uuid(for:))
        let created = try LegacyPersonalTrial.apply(plan, to: store.container, zone: zone, observedDay: observed)
        XCTAssertEqual(created["letters.created"], 1); XCTAssertEqual(created["days.created"], 1)
        XCTAssertEqual(created["archived.countUpAfter"], 1)
        let context = ModelContext(store.container), service = AppDiaryService(app: app)
        let letter = try XCTUnwrap(context.fetch(FetchDescriptor<Letter>()).first)
        XCTAssertEqual(letter.state, "sealed"); XCTAssertNil(letter.openedAt)
        XCTAssertEqual(letter.triggerValue, "2027-11-19")
        XCTAssertNil(try service.letters().first?.text)
        XCTAssertFalse(try service.searchIndex().documents.contains { $0.text.contains("SEALED-SOURCE") })
        XCTAssertFalse(try service.exportPages(.init()).flatMap(\.lines).contains { $0.text.contains("SEALED-SOURCE") })
        let day = try XCTUnwrap(context.fetch(FetchDescriptor<UpcomingDay>()).first)
        XCTAssertEqual(day.calendar, "greg"); XCTAssertEqual(day.year, 2027); XCTAssertEqual(day.month, 11); XCTAssertEqual(day.day, 19)
        XCTAssertEqual(day.repeats, "none"); XCTAssertEqual(day.countFromDayKey, "2026-10-25")
        letter.state = "opened"; letter.openedAt = Date(); day.title = "تعديل محلي"; day.deletedAt = Date()
        try context.save()
        func records() throws -> [DataRecord] { try RecordBridge.all(ModelContext(store.container)).sorted { ($0.model, $0.id.uuidString) < ($1.model, $1.id.uuidString) } }
        let before = try records()
        let replay = try LegacyPersonalTrial.apply(plan, to: store.container, zone: zone, observedDay: observed.adding(days: 1))
        XCTAssertEqual(replay.filter { $0.key.hasSuffix(".created") }.values.reduce(0,+), 0)
        XCTAssertEqual(try records(), before)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ImportLink>()), 3)
    }
    func testOpenedDayAndDeletionEvidenceSurvive() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PersonalDates-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedDataStore(root: root)
        let zone = TimeZone(identifier: "Asia/Riyadh")!, observed = try GregorianDay("2026-10-25")
        let raw = #"{"futureLetters":[{"id":"l","content":"مفتوحة","writtenDate":"2026-10-01","deliveryDate":"2026-10-02","opened":true,"openedDate":"2026-10-03"},{"id":"unknown","content":"مفتوحة بلا يوم مسجل","writtenDate":"2026-10-01","deliveryDate":"2026-10-02","opened":true}],"countdownEvents":[{"id":"d","title":"محذوف","date":"2026-11-19"}],"deleted":{"d":1700000000000}}"#
        let plan = try LegacyPersonalImport.plan(backup: Data(raw.utf8), observedDay: observed, zone: zone, uuid: StableIdentity.uuid(for:))
        _ = try LegacyPersonalTrial.apply(plan, to: store.container, zone: zone, observedDay: observed)
        let context = ModelContext(store.container)
        let letters = try context.fetch(FetchDescriptor<Letter>())
        let letter = try XCTUnwrap(letters.first { $0.id == StableIdentity.uuid(for: "myDream:Letter:l") })
        let unknown = try XCTUnwrap(letters.first { $0.id == StableIdentity.uuid(for: "myDream:Letter:unknown") })
        XCTAssertEqual(unknown.state, "opened"); XCTAssertNil(unknown.openedAt)
        XCTAssertEqual(letter.state, "opened")
        XCTAssertEqual(letter.openedAt.map { GregorianDay.containing($0, in: zone).description }, "2026-10-03")
        let day = try XCTUnwrap(context.fetch(FetchDescriptor<UpcomingDay>()).first)
        XCTAssertEqual(day.deletedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }
}
