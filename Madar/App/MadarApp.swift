import SwiftUI
import SwiftData
import MadarData
import MadarCore
import MadarDesign
import CoreSpotlight
import Observation

@main
struct MadarApp: App {
    @UIApplicationDelegateAdaptor(MadarApplicationDelegate.self) private var appDelegate
    var body: some Scene { WindowGroup { MadarSceneContent(runtime: appDelegate.runtime) } }
}

private struct MadarSceneContent: View {
    let runtime: MadarRuntime
    private var session: AppSession? { runtime.session }
    private var startupError: String? { runtime.startupError }
    var body: some View {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.environment["MADAR_UI_GALLERY"] == "1" { MadarComponentGallery() }
                else { mainContent }
                #else
                mainContent
                #endif
            }
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar_SA"))
            .task { if session == nil && startupError == nil && ProcessInfo.processInfo.environment["MADAR_UI_GALLERY"] != "1" { await runtime.load() } }
            .onChange(of: scenePhase) { _, phase in
                guard let session else { return }
                session.privacyPresenter?.transition(phase)
                guard phase == .active else { return }
                Task {
                    do { try await session.drainInbox() }
                    catch BackupOperationError.busy { }
                    catch { session.errorMessage = "لم يكتمل تحديث البيانات. \(madarUserMessage(error))" }
                    await session.reconcileSpotlightIndex()
                    await session.refreshEligibleDiaryLettersForNotificationLifecycle()
                    await MadarIntentHandoff.shared.flush()
                    await session.refreshPrayerNotifications()
                }
            }
            // A diary line from Siri waits behind the diary lock and lands once it opens.
            .onChange(of: session?.lockController?.unlocked) { _, _ in
                Task {
                    guard let session else { await MadarIntentHandoff.shared.flush(); return }
                    if session.lockController?.canPresent(.app) == true {
                        session.recordBahwReturnVisit()
                    }
                    if session.lockController?.canPresent(.notes) ?? session.protectedDataAuthorized {
                        await session.refreshEligibleDiaryLettersForNotificationLifecycle()
                        await session.refreshPrayerNotifications()
                    }
                    await MadarIntentHandoff.shared.flush()
                }
            }
            // A Shortcut ran in this process and queued a blind write: apply it now, not at the next launch.
            .onReceive(NotificationCenter.default.publisher(for: .madarInboxChanged)) { _ in
                guard let session else { return }
                Task {
                    do { try await session.drainInbox() }
                    catch BackupOperationError.busy { }
                    catch { session.errorMessage = "لم يكتمل تحديث البيانات. \(madarUserMessage(error))" }
                }
            }
            .onOpenURL { url in
                if let session { session.open(url) }
                else { runtime.pendingURL = url }
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                      let bookID = UUID(uuidString: identifier) else { return }
                if let session { session.openSpotlightBook(bookID) }
                else { runtime.pendingSpotlightBookID = bookID }
            }
    }
    private var mainContent: some View {
        Group {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MADAR_NOTIFICATION_TEST_FLOW"] == "1", let session {
            PrayerNotificationAcceptanceHarness(session: session)
        } else {
            roomContent
        }
        #else
        roomContent
        #endif
        }
    }
    private var roomContent: some View {
        Group {
                if let session, let lock = session.lockController {
                    MadarLockGate(controller: lock, feature: .app) {
                        MadarRootView(session: session).modelContainer(session.container).environment(session)
                    }.background(ScenePrivacyBridge(session: session).frame(width: 0, height: 0))
                }
                else if let startupError {
                    ContentUnavailableView {
                        Label("تعذّر فتح مدار", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("لم يُفتح مخزن البيانات. بياناتك محفوظة، ويمكنك إعادة المحاولة.\n\(startupError)")
                    } actions: { Button("أعِد المحاولة") { Task { await runtime.load() } } }
                } else { ProgressView("يفتح مدار…") }
        }
    }
    @Environment(\.scenePhase) private var scenePhase
}

/// The scene and a cold background launch share one in-flight store opening.
@Observable @MainActor final class MadarRuntime {
    let prayerNotifications = PrayerNotificationCoordinator()
    private(set) var session: AppSession?
    private(set) var startupError: String?
    var pendingURL: URL?
    var pendingSpotlightBookID: UUID?
    @ObservationIgnored weak var backgroundBackups: AppBackupBackgroundTasks?
    @ObservationIgnored private var loading: Task<Void, Never>?

    func load() async {
        if session != nil { return }
        if let loading { await loading.value; return }
        let task = Task { await openSession() }
        loading = task
        await task.value
        loading = nil
    }
    private func openSession() async {
        do {
            guard var group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.alqzan.madar2") else { throw DataError.missingAppGroup }
            var backupKeyService = "com.alqzan.madar2.backup"
            #if DEBUG
            let rawUITestID = ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"]
            let isolatedUITestID: String?
            if let rawUITestID {
                guard !rawUITestID.isEmpty, rawUITestID.count <= 100,
                      rawUITestID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
                    throw DataError.invalidValue("MADAR_UI_STORE_ID must be a non-empty ASCII identifier of at most 100 characters.")
                }
                isolatedUITestID = rawUITestID
            } else {
                isolatedUITestID = nil
            }
            if let fixture = isolatedUITestID {
                group = group.appending(path: "UITestStores/\(fixture)", directoryHint: .isDirectory)
                // The fixture's first export must never read or replace the real backup key.
                backupKeyService += ".uitest.\(fixture)"
            }
            #endif
            let root = group.appending(path: "ManagedData", directoryHint: .isDirectory)
            let lockURL = group.appending(path: "CommandBus.lock")
            // Nil unless this build is signed for iCloud: then no store ever opens a CloudKit mirror.
            MadarCloudMirror.provisionedContainerIdentifier = AppSyncService.provisionedContainer
            let managed: ManagedDataStore
            if !FileManager.default.fileExists(atPath: root.appending(path: "ActiveGeneration.json").path), FileManager.default.fileExists(atPath: group.appending(path: "Madar.store").path) {
                let version = try MadarContainerFactory.storeVersionForAdoption(at:group)
                if version == 1 { managed = try ManagedDataStore.adoptLegacy(from:group,at:root,commandLockURL:lockURL) }
                else {
                    let legacy = try MadarContainerFactory.makeLocal(at:group)
                    managed = try ManagedDataStore.adopt(from:legacy,at:root,commandLockURL:lockURL)
                }
            } else { managed = try ManagedDataStore(root: root, commandLockURL: lockURL) }
            let opened = try AppSession(container: managed.container, managedStore: managed, groupDirectory: group)
#if DEBUG
            if isolatedUITestID != nil {
                // UI stores are isolated from owner data. Lock-flow UI tests opt in
                // explicitly; all other UI tests launch without an app lock.
                let requestedScope = ProcessInfo.processInfo.environment["MADAR_UI_FACE_ID_LOCK"]
                let scope = requestedScope == "app" ? "app" : "none"
                try await opened.applySettingsAndWait(["core.faceIDLock": .string(scope)])
            }
#endif
#if !DEBUG
            // Owner, 3 Nov 2026: the app lock is removed from Madar. A device that had it on is returned to "none" on open.
            if opened.string("core.faceIDLock") != "none" { try await opened.applySettingsAndWait(["core.faceIDLock": .string("none")]) }
#endif
            opened.lockController = MadarLockController(scope: MadarLockScope(rawValue: opened.string("core.faceIDLock")) ?? .app, service: AppPrivacyService(session: opened))
            await opened.attachPrayerNotifications(prayerNotifications)
            let backup = AppBackupService(session: opened, store: managed, backupDirectory: group.appending(path: "Backups", directoryHint: .isDirectory), keyStore: KeychainBackupKeyStore(service: backupKeyService))
            backup.backgroundTasks = backgroundBackups
            opened.backupService = backup
            opened.syncService = AppSyncService(session: opened, store: managed, backup: backup)
            if managed.recoveryRequiresRefresh {
                let warnings = try await backup.coordinator.recoverPendingLifecycle()
                guard warnings.isEmpty else { throw DataError.invalidValue(warnings.joined(separator: "\n")) }
            }
#if DEBUG
            await opened.runLegacyMoneyTrialIfRequested()
            await opened.runLegacyQuranTrialIfRequested()
            await opened.runLegacyPrayerTrialIfRequested()
            await opened.runLegacyHabitTrialIfRequested()
            await opened.runLegacyPersonalTrialIfRequested()
#endif
            session = opened; startupError = nil
            await backgroundBackups?.reschedule(using: backup)
            await opened.reconcileSpotlightIndex()
            do { try await opened.drainInbox() }
            catch BackupOperationError.busy { }
            catch { opened.errorMessage = "لم يكتمل تحديث البيانات. \(madarUserMessage(error))" }
            if let pendingURL { opened.open(pendingURL); self.pendingURL = nil }
            if let pendingSpotlightBookID { opened.openSpotlightBook(pendingSpotlightBookID); self.pendingSpotlightBookID = nil }
            await MadarIntentHandoff.shared.attach { [weak opened] request in await opened?.handleIntentRequest(request) ?? false }
        } catch { startupError = madarUserMessage(error) }
    }

}
