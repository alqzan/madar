import SwiftUI
import SwiftData
import MadarData
import MadarCore
import MadarDesign
import CoreSpotlight

@main
struct MadarApp: App {
    @UIApplicationDelegateAdaptor(MadarApplicationDelegate.self) private var appDelegate
    var body: some Scene { WindowGroup { MadarSceneContent(prayerNotifications: appDelegate.prayerNotifications) } }
}

private struct MadarSceneContent: View {
    let prayerNotifications: PrayerNotificationCoordinator
    @State private var session: AppSession?
    @State private var startupError: String?
    @State private var pendingURL: URL?
    @State private var pendingSpotlightBookID: UUID?
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
            .task { if session == nil && startupError == nil && ProcessInfo.processInfo.environment["MADAR_UI_GALLERY"] != "1" { await load() } }
            .onChange(of: scenePhase) { _, phase in
                guard let session else { return }
                session.privacyPresenter?.transition(phase)
                guard phase == .active else { return }
                Task {
                    do { try await session.drainInbox() }
                    catch BackupOperationError.busy { }
                    catch { session.errorMessage = "لم يكتمل تحديث البيانات. \(error.localizedDescription)" }
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
                Task { do { try await session.drainInbox() } catch { } }
            }
            .onOpenURL { url in
                if let session { session.open(url) }
                else { pendingURL = url }
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                      let bookID = UUID(uuidString: identifier) else { return }
                if let session { session.openSpotlightBook(bookID) }
                else { pendingSpotlightBookID = bookID }
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
                        MadarRootView(session: session).modelContainer(session.container)
                    }.background(ScenePrivacyBridge(session: session).frame(width: 0, height: 0))
                }
                else if let startupError {
                    ContentUnavailableView {
                        Label("تعذّر فتح مدار", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("لم يُفتح مخزن البيانات. بياناتك محفوظة، ويمكنك إعادة المحاولة.\n\(startupError)")
                    } actions: { Button("أعِد المحاولة") { Task { await load() } } }
                } else { ProgressView("يفتح مدار…") }
        }
    }
    @MainActor private func load() async {
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
            if isolatedUITestID != nil,
               ProcessInfo.processInfo.environment["MADAR_UI_PRESERVE_FACE_ID_DEFAULT"] != "1" {
                // UI stores are isolated from owner data. Ordinary screen tests need
                // an unlocked session; the dedicated Face ID test opts into the real
                // fresh-install default with MADAR_UI_PRESERVE_FACE_ID_DEFAULT.
                try await opened.applySettingsAndWait(["core.faceIDLock": .string("none")])
            }
#endif
            opened.lockController = MadarLockController(scope: MadarLockScope(rawValue: opened.string("core.faceIDLock")) ?? .app, service: AppPrivacyService(session: opened))
            await opened.attachPrayerNotifications(prayerNotifications)
            let backup = AppBackupService(session: opened, store: managed, backupDirectory: group.appending(path: "Backups", directoryHint: .isDirectory), keyStore: KeychainBackupKeyStore(service: backupKeyService))
            opened.backupService = backup
            opened.syncService = AppSyncService(session: opened, store: managed, backup: backup)
            if managed.recoveryRequiresRefresh {
                let warnings = try await backup.coordinator.recoverPendingLifecycle()
                guard warnings.isEmpty else { throw DataError.invalidValue(warnings.joined(separator: "\n")) }
            }
#if DEBUG
            await opened.runLegacyMoneyTrialIfRequested()
#endif
            session = opened; startupError = nil
            await opened.reconcileSpotlightIndex()
            do { try await opened.drainInbox() }
            catch BackupOperationError.busy { }
            catch { opened.errorMessage = "لم يكتمل تحديث البيانات. \(error.localizedDescription)" }
            if let pendingURL { opened.open(pendingURL); self.pendingURL = nil }
            if let pendingSpotlightBookID { opened.openSpotlightBook(pendingSpotlightBookID); self.pendingSpotlightBookID = nil }
            await MadarIntentHandoff.shared.attach { [weak opened] request in await opened?.handleIntentRequest(request) ?? false }
        } catch { startupError = error.localizedDescription }
    }
    @Environment(\.scenePhase) private var scenePhase
}
