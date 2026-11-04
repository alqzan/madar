import XCTest
import SwiftData
import MadarCore
import MadarData
@testable import Madar

/// The expected sets come from the rules, not from the code: only prayers whose window has ended are listed (RP1),
/// every one of yesterday's five is listed when none was logged, and a shown set is not shown again until it changes.
@MainActor final class BahwAttentionTests: XCTestCase {
    private func session(trackingStart: String) throws -> AppSession {
        let root = FileManager.default.temporaryDirectory.appending(path: "BahwAttention-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let app = try AppSession(container: container, groupDirectory: root)
        app.authorizeProtectedData()
        let context = ModelContext(container)
        _ = try SettingsStore(context: context).stage(["salah.trackingStart": .object(["dayKey": .string(trackingStart), "edits": .number(0)]), "core.dayStart": .string("midnight")])
        // The first run is when the setting was created; pin it to the day tracking began so the test never depends on today's date.
        let created = try XCTUnwrap(ISO8601DateFormatter().date(from: "\(trackingStart)T03:00:00+03:00"))
        for row in try context.fetch(FetchDescriptor<Setting>()) where row.key == "salah.trackingStart" { row.createdAt = created }
        try context.save()
        return app
    }

    func testListsClosedPrayersOnlyAndLeavesTheOpenWindowAlone() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-15T14:00:00+03:00"))
        let app = try session(trackingStart: "2026-10-14")
        let attention = AppBahwService(session: app, evaluationDate: now).attention()
        let ids = Set(attention.prayers.map(\.id))
        for prayer in ["fajr", "dhuhr", "asr", "maghrib", "isha"] { XCTAssertTrue(ids.contains("2026-10-14.\(prayer)"), "yesterday's \(prayer) was never logged") }
        XCTAssertTrue(ids.contains("2026-10-15.fajr"))
        XCTAssertFalse(ids.contains("2026-10-15.dhuhr"), "Dhuhr's window is still open at 14:00")
        XCTAssertFalse(ids.contains("2026-10-15.asr"), "Asr has not come yet")
    }

    func testFajrIsListedOnlyAfterSunriseAndNotBeforeTheNextAdhan() throws {
        let app = try session(trackingStart: "2026-10-14")
        let beforeSunrise = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-15T05:30:00+03:00"))
        let morning = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-15T09:00:00+03:00"))
        let early = Set(AppBahwService(session: app, evaluationDate: beforeSunrise).attention().prayers.map(\.id))
        XCTAssertFalse(early.contains("2026-10-15.fajr"), "Fajr's window runs until sunrise")
        let late = Set(AppBahwService(session: app, evaluationDate: morning).attention().prayers.map(\.id))
        XCTAssertTrue(late.contains("2026-10-15.fajr"), "after sunrise and before Dhuhr, an unlogged Fajr has closed")
        XCTAssertFalse(late.contains("2026-10-15.dhuhr"), "Dhuhr has not come yet")
    }

    func testAShownSetIsNotShownAgainUntilItChanges() throws {
        UserDefaults.standard.removeObject(forKey: BahwAttentionMemory.key)
        defer { UserDefaults.standard.removeObject(forKey: BahwAttentionMemory.key) }
        var attention = BahwAttention(moneyCount: 3)
        XCTAssertTrue(BahwAttentionMemory.isNew(attention))
        UserDefaults.standard.set(attention.signature, forKey: BahwAttentionMemory.key)
        XCTAssertFalse(BahwAttentionMemory.isNew(attention))
        attention.moneyCount = 4
        XCTAssertTrue(BahwAttentionMemory.isNew(attention))
        XCTAssertFalse(BahwAttentionMemory.isNew(BahwAttention()), "nothing waiting, nothing shown")
    }
}
