import SwiftUI
import SwiftData
import MadarData
import MadarCore
import MadarDesign

@main
struct MadarApp: App {
    var body: some Scene { WindowGroup { MadarSceneContent() } }
}

private struct MadarSceneContent: View {
    @State private var session: AppSession?
    @State private var startupError: String?
    @State private var pendingURL: URL?
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
                }
            }
            .onOpenURL { url in
                if let session { session.open(url) }
                else { pendingURL = url }
            }
    }
    private var mainContent: some View {
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
            if let fixture = ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"], !fixture.isEmpty, fixture.count <= 100,
               fixture.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) {
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
            let backup = AppBackupService(session: opened, store: managed, backupDirectory: group.appending(path: "Backups", directoryHint: .isDirectory), keyStore: KeychainBackupKeyStore(service: backupKeyService))
            opened.backupService = backup
            opened.syncService = AppSyncService(session: opened, store: managed, backup: backup)
            opened.lockController = MadarLockController(scope: MadarLockScope(rawValue: opened.string("core.faceIDLock")) ?? .notesOnly, service: AppPrivacyService(session: opened))
            if managed.recoveryRequiresRefresh {
                let warnings = try await backup.coordinator.recoverPendingLifecycle()
                guard warnings.isEmpty else { throw DataError.invalidValue(warnings.joined(separator: "\n")) }
            }
            session = opened; startupError = nil
            do { try await opened.drainInbox() }
            catch BackupOperationError.busy { }
            catch { opened.errorMessage = "لم يكتمل تحديث البيانات. \(error.localizedDescription)" }
            if let pendingURL { opened.open(pendingURL); self.pendingURL = nil }
        } catch { startupError = error.localizedDescription }
    }
    @Environment(\.scenePhase) private var scenePhase
}
