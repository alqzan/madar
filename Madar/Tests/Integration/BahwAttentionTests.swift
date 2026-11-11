import XCTest
import SwiftData
import MadarCore
import MadarData
@testable import Madar

/// Unperformed prayers never become lobby tasks or persisted prayer records; money attention remains signature-based.
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

    func testUnperformedPrayerWindowsDoNotCreateLobbyAttention() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-15T14:00:00+03:00"))
        let app = try session(trackingStart: "2026-10-14")
        // The lobby may ask about an unlogged prayer (owner, 4 Nov); asking never writes a record (RP1).
        let attention = AppBahwService(session: app, evaluationDate: now).attention()
        XCTAssertEqual(attention.moneyCount, 0)
        XCTAssertTrue(try ModelContext(app.container).fetch(FetchDescriptor<PrayerLog>()).isEmpty)
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
