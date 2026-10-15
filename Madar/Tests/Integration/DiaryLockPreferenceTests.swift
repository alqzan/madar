import XCTest
import SwiftData
import MadarData
@testable import Madar

@MainActor final class DiaryLockPreferenceTests: XCTestCase {
    func testLegacyPreferenceReadsUnlockedWithoutChangingStoredBytes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryLockPreference-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        let row = DeviceSetting(); row.key = "core.faceIDLock"; row.valueJSON = Data("\"notesOnly\"".utf8)
        context.insert(row); try context.save()
        let store = try SettingsStore(context: context)
        XCTAssertEqual(try store.value(for: "core.faceIDLock"), .string("none"))
        XCTAssertEqual(row.valueJSON, Data("\"notesOnly\"".utf8))
        XCTAssertEqual(try store.schema.definition(for: "core.faceIDLock").options.map(\.value), [.string("app"), .string("none")])
        let app = try AppSession(container: container, groupDirectory: root)
        let lock = MadarLockController(scope: .notesOnly, service: AppPrivacyService(session: app))
        XCTAssertEqual(lock.scope, .none)
        XCTAssertFalse(lock.requiresProtection(.notes)); XCTAssertFalse(lock.requiresProtection(.export))
        XCTAssertTrue(lock.canPresent(.notes))
        let wholeApp = MadarLockController(scope: .app, service: AppPrivacyService(session: app))
        XCTAssertTrue(wholeApp.requiresProtection(.notes)); XCTAssertFalse(wholeApp.canPresent(.notes))
    }
}
