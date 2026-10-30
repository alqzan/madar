import XCTest
import SwiftData
import MadarData
import MadarCore
@testable import Madar

@MainActor final class AppServiceIntegrationTests: XCTestCase {
    func test_M1T04_ActivityBudgetLedgerCountsSubmittedAndObservedOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarActivityBudget-\(UUID())")
        let managed = try ManagedDataStore(root: root.appending(path: "Data"), commandLockURL: root.appending(path: "CommandBus.lock"))
        // Real synthetic persistence, without attaching to the system notification center.
        let context = ModelContext(managed.container)
        for (id, kind, state, deleted) in [
            ("activity.one", "room", "submitted", false),
            ("activity.one", "room", "submitted", false),
            ("room.observed", "room", "observed", false),
            ("digest.one", "digest", "submitted", false),
            ("nudge.one", "nudge", "submitted", false),
            ("cancelled", "room", "cancelled", false),
            ("prayer.one", "prayer", "submitted", false),
            ("deleted", "room", "submitted", true)
        ] {
            let row = NotificationLedger()
            row.dayKey = "2026-10-09"; row.requestID = id; row.requestClass = kind; row.state = state
            if deleted { row.deletedAt = Date() }
            context.insert(row)
        }
        try context.save()
        XCTAssertEqual(PrayerNotificationCoordinator.activityBudgetCounts(rows: try context.fetch(FetchDescriptor<NotificationLedger>())), ["2026-10-09": 4])
    }

    func test_M0T10_FoundationPrayerClocksUseGoldenDayNumeralsAndZone() throws {
        // Expected clocks are copied from the approved Riyadh 2026-10-09 handoff row.
        // This UTC instant is still October 8 in UTC, but October 9 in the active place.
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-08T22:30:00Z"))
        let arabic = FoundationPrayerTimesPresentation(instant: instant, place: .riyadh)
        XCTAssertEqual(arabic.day.description, "2026-10-09")
        XCTAssertEqual(arabic.rows.map(\.prayer), [.fajr, .dhuhr, .asr, .maghrib, .isha])
        XCTAssertEqual(arabic.rows.map(\.title), ["الفجر", "الظهر", "العصر", "المغرب", "العشاء"])
        XCTAssertEqual(arabic.rows.map(\.clock), ["٠٤:٣١", "١١:٤١", "١٥:٠٢", "١٧:٣٢", "١٩:٠٢"])
        XCTAssertEqual(arabic.rows.first?.accessibilityLabel, "الفجر، ٠٤:٣١")
        let western = FoundationPrayerTimesPresentation(instant: instant, place: .riyadh, numerals: .western)
        XCTAssertEqual(western.rows.map(\.clock), ["04:31", "11:41", "15:02", "17:32", "19:02"])
        let sameDay = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-09T10:00:00Z"))
        let utcPlace = try ActivePlace(latitude: 24.7136, longitude: 46.6753, timeZoneID: "UTC")
        let utc = FoundationPrayerTimesPresentation(instant: sameDay, place: utcPlace, numerals: .western)
        // Same coordinates/date, clocks expressed three hours earlier than Asia/Riyadh.
        XCTAssertEqual(utc.rows.map(\.clock), ["01:31", "08:41", "12:02", "14:32", "16:02"])
        let adjusted = FoundationPrayerTimesPresentation(instant: instant, place: .riyadh, options: .init(offsets: [.fajr: 5]), numerals: .western)
        XCTAssertEqual(adjusted.rows.first?.clock, "04:36")
    }

    func test_M0T10_UnavailablePrayerClocksNeverFabricateRows() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-21T12:00:00Z"))
        let polar = try ActivePlace(latitude: 89, longitude: 0, timeZoneID: "UTC")
        let unavailable = FoundationPrayerTimesPresentation(instant: instant, place: polar)
        XCTAssertNil(unavailable.prayerDay)
        XCTAssertTrue(unavailable.rows.isEmpty)
        XCTAssertEqual(unavailable.day.description, "2026-06-21")
    }

    func test_M0S2_LegacyCutSettingsRemainStoredWithoutAvailableRoutes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarCutSettings-\(UUID())")
        let managed = try ManagedDataStore(root: root.appending(path: "Data"), commandLockURL: root.appending(path: "CommandBus.lock"))
        let schema = try SettingsSchema.bundled()
        let legacy: [String: MadarData.JSONValue] = [
            "core.fontScale": .string("xlarge"), "core.motion": .string("none"), "core.roomIdentity": .string("calmPaper"),
            "tabbar.style": .string("capsule"), "tabbar.labels": .string("selected"), "tabbar.openOn": .string("last"), "tabbar.minimizeOnScroll": .bool(false)
        ]
        for (key, value) in legacy {
            let data = try JSONEncoder().encode(value)
            if try schema.definition(for: key).scope == "device" {
                let row = DeviceSetting(); row.key = key; row.valueJSON = data
                managed.container.mainContext.insert(row)
            } else {
                let row = Setting(); row.key = key; row.valueJSON = data
                managed.container.mainContext.insert(row)
            }
        }
        try managed.container.mainContext.save()
        let session = try AppSession(container: managed.container, managedStore: managed, groupDirectory: root)
        for (key, value) in legacy {
            XCTAssertEqual(session.values[key], value, "Legacy values must be preserved: \(key)")
            session.errorMessage = nil
            session.open(try XCTUnwrap(URL(string: "madar://settings/core/\(key)")))
            XCTAssertNotNil(session.errorMessage, "A cut setting must not expose a route: \(key)")
            XCTAssertEqual(session.selectedTab, "foundation", key)
            XCTAssertEqual(session.settingsQuery, "", key)
        }
        try session.reload()
        for (key, value) in legacy { XCTAssertEqual(session.values[key], value, key) }
        session.errorMessage = nil
        session.open(try XCTUnwrap(URL(string: "madar://settings/core/core.theme")))
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(session.selectedTab, "customize")
        XCTAssertEqual(session.settingsQuery, "الوضع")
        session.settingsRoute = nil
        session.open(try XCTUnwrap(URL(string: "madar://settings/core/no.such.key")))
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(session.selectedTab, "customize")
        XCTAssertEqual(session.settingsQuery, "")
        XCTAssertEqual(session.settingsRoute?.path, ["core", "no.such.key"])
    }
    func testBackupUIAdapterRestoresSyncedDataAndPreservesDevicePreferences() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarService-\(UUID())")
        let managed = try ManagedDataStore(root: root.appending(path: "Data"), commandLockURL: root.appending(path: "CommandBus.lock"))
        let session = try AppSession(container: managed.container, managedStore: managed, groupDirectory: root)
        let backup = AppBackupService(session: session, store: managed, backupDirectory: root.appending(path: "Backups"), keyStore: MemoryBackupKeyStore())
        try await session.applySettingsAndWait(["core.firstCalendar": .string("gregorian"), "core.theme": .string("light")])
        try await backup.setSchedule(.manual)
        ExportPrivacyTestHarness.install(on: session)
        let file = try await backup.export(passphrase: "test-only-passphrase", progress: { _ in })
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let status = try await backup.status()
        XCTAssertEqual(status.manualCount, 1)
        XCTAssertTrue(status.keyConfigured)
        try await session.applySettingsAndWait(["core.firstCalendar": .string("hijri"), "core.theme": .string("dark")])
        let preview = try await backup.previewRestore(file: file, passphrase: "test-only-passphrase", progress: { _ in })
        let originalGeneration = managed.binding.generationID
        let restored = try await backup.restore(previewID: preview.id, mode: .replace, progress: { _ in })
        XCTAssertGreaterThan(restored.restoredCount, 0)
        XCTAssertTrue(restored.warnings.isEmpty, restored.warnings.description)
        XCTAssertNotEqual(originalGeneration, managed.binding.generationID)
        XCTAssertEqual(session.string("core.firstCalendar"), "gregorian")
        XCTAssertEqual(session.string("core.theme"), "dark")
        XCTAssertEqual(session.string("core.backup"), "manual")
        XCTAssertFalse(session.maintenanceInProgress)
        let after = try await backup.status()
        XCTAssertEqual(after.automaticCount, 1)
        // The same session's already-created bus follows the promoted generation.
        try await session.applySettingsAndWait(["core.firstCalendar": .string("hijri")])
        let reopened = try ManagedDataStore(root: managed.root, commandLockURL: managed.commandLockURL)
        let settings = try SettingsStore(context: ModelContext(reopened.container))
        XCTAssertEqual(try settings.value(for: "core.firstCalendar"), .string("hijri"))
    }

    func testPlainExportUIAdapterNeedsNoPasswordAndResumesSession() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarPlainService-\(UUID())")
        let managed = try ManagedDataStore(root: root.appending(path: "Data"), commandLockURL: root.appending(path: "CommandBus.lock"))
        let session = try AppSession(container: managed.container, managedStore: managed, groupDirectory: root)
        let backup = AppBackupService(session: session, store: managed, backupDirectory: root.appending(path: "Backups"), keyStore: MemoryBackupKeyStore())
        try await session.applySettingsAndWait(["core.firstCalendar": .string("hijri"), "core.faceIDLock": .string("app")])
        ExportPrivacyTestHarness.install(on: session)
        let file = try await backup.exportPlain(progress: { _ in })
        let validated = try PortableExportCodec.validate(Data(contentsOf: file))
        XCTAssertEqual(file.pathExtension, "zip")
        XCTAssertFalse(validated.records.contains { $0.model == "DeviceSetting" || $0.model == "CommandReceipt" })
        XCTAssertTrue(validated.records.contains { $0.model == "Setting" && $0.fields["key"] == .string("core.firstCalendar") })
        let status = try await backup.status()
        XCTAssertFalse(status.keyConfigured); XCTAssertEqual(status.manualCount, 0)
        XCTAssertFalse(session.maintenanceInProgress)
        try await session.applySettingsAndWait(["core.firstCalendar": .string("gregorian")])
        XCTAssertEqual(session.string("core.firstCalendar"), "gregorian")
    }

    func testStalePreviewDoesNotChangeGenerationOrCreateSafetyBackup() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarService-\(UUID())")
        let managed = try ManagedDataStore(root: root.appending(path: "Data"), commandLockURL: root.appending(path: "CommandBus.lock"))
        let session = try AppSession(container: managed.container, managedStore: managed, groupDirectory: root)
        let backup = AppBackupService(session: session, store: managed, backupDirectory: root.appending(path: "Backups"), keyStore: MemoryBackupKeyStore())
        ExportPrivacyTestHarness.install(on: session)
        let file = try await backup.export(passphrase: "test-only-passphrase", progress: { _ in })
        let preview = try await backup.previewRestore(file: file, passphrase: "test-only-passphrase", progress: { _ in })
        try await session.applySettingsAndWait(["core.firstCalendar": .string("hijri")])
        let originalGeneration = managed.binding.generationID
        do { _ = try await backup.restore(previewID: preview.id, mode: .replace, progress: { _ in }); XCTFail("stale preview accepted") }
        catch { XCTAssertEqual(error as? BackupOperationError, .stalePreview) }
        XCTAssertEqual(originalGeneration, managed.binding.generationID)
        let status = try await backup.status()
        XCTAssertEqual(status.automaticCount, 0)
        XCTAssertFalse(session.maintenanceInProgress)
        await backup.cancel()
    }
}
