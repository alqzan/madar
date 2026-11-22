import SwiftUI
import SwiftData
import MadarData
import MadarCore
import MadarDesign
import MadarCommands

// Shared by the iPhone/iPad app (`MadarApp`) and the Mac app (`MadarMacApp`): one way to open the store and the session.

/// The store has not opened yet, so follow the system appearance until saved preferences are available.
struct MadarLaunchPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: RoomTheme { RoomTheme(room: "bahw", dark: colorScheme == .dark) }
    var body: some View {
        VStack(spacing: 14) {
            MadarGlyph("MadarOrbit", size: 56).foregroundStyle(theme.accent)
            Text("مدار").font(.custom("thmanyahserifdisplay-Bold", size: 34))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .foregroundStyle(theme.ink)
    }
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
        // The verified Quran catalog (about half a second to parse) is needed by the lobby, the widgets and the reminders:
        // read it on a background thread while the store opens instead of on the main thread under the first screen.
        Task.detached(priority: .userInitiated) { _ = try? QuranResources.catalog() }
        Task.detached(priority: .background) { TemporaryFilesCleanup.run() }
        let task = Task { await openSession() }
        loading = task
        await task.value
        loading = nil
    }
    /// T03: the unreadable store is set aside, never deleted; if a clean one cannot open either, it is put back.
    func startWithFreshStore() async {
        guard session == nil, let group = MadarPlatform.dataDirectory else { return }
        do {
            let aside = try StartupRecovery.setAsideStore(groupDirectory: group)
            startupError = nil
            await load()
            if session == nil {
                let failure = startupError
                try StartupRecovery.putBack(aside, groupDirectory: group)
                startupError = failure
            } else {
                session?.errorMessage = "فُتح مخزن جديد. لاستعادة بياناتك افتح الإعدادات ← النسخ الاحتياطي واختر نسخة."
            }
        } catch { startupError = madarUserMessage(error) }
    }
    private func openSession() async {
        do {
            guard var group = MadarPlatform.dataDirectory else { throw DataError.missingAppGroup }
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
            opened.authorizeProtectedData() // no app lock: the open store is the only gate (owner, 10 Nov 2026)
#if DEBUG
            try opened.seedMalformedNotificationBudgetForUITestIfRequested()
#endif
            await opened.attachPrayerNotifications(prayerNotifications)
#if DEBUG
            await opened.resumeNotificationBudgetRecoveryUITestIfRequested()
#endif
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
