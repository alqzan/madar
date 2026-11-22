import SwiftUI
import SwiftData
import MadarData
import MadarCore
import MadarDesign
import CoreSpotlight
import Observation
import MadarCommands

@main
struct MadarApp: App {
    @UIApplicationDelegateAdaptor(MadarApplicationDelegate.self) private var appDelegate
    #if DEBUG
    init() {
        // Owner, 22 Nov 2026: `MADAR_CLOUDKIT_SCHEMA_INIT=1` in a team-signed iCloud debug build, on a simulator signed in to iCloud,
        // creates the CloudKit development schema from a throwaway store; the result is written to the app's temporary folder.
        if ProcessInfo.processInfo.environment["MADAR_CLOUDKIT_SCHEMA_INIT"] == "1" {
            let id = Bundle.main.object(forInfoDictionaryKey: "MadarCloudKitContainer") as? String ?? ""
            let result: String
            do { result = "MADAR_SCHEMA_OK " + (try MadarCloudSchemaInitializer.initializeDevelopmentSchema(containerIdentifier: id)).joined(separator: ",") }
            catch { result = "MADAR_SCHEMA_FAILED \(error)" }
            print(result)
            try? result.write(to: FileManager.default.temporaryDirectory.appending(path: "madar-cloud-schema.txt"), atomically: true, encoding: .utf8)
        }
    }
    #endif
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
                guard phase == .active else { return }
                Task {
                    // The root view drains the inbox on every return.
                    await session.reconcileSpotlightIndex()
                    await session.refreshEligibleDiaryLettersForNotificationLifecycle()
                    await MadarIntentHandoff.shared.flush()
                    session.requestPrayerNotificationRefresh()
                }
            }
            // The first time the session exists: a diary line from Siri that arrived before launch lands now.
            .onChange(of: session.map { ObjectIdentifier($0) }) { _, _ in
                Task {
                    guard let session else { await MadarIntentHandoff.shared.flush(); return }
                    session.recordBahwReturnVisit()
                    if session.protectedDataAuthorized {
                        await session.refreshEligibleDiaryLettersForNotificationLifecycle()
                        session.requestPrayerNotificationRefresh()
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
                if let session {
                    MadarRootView(session: session).modelContainer(session.container).environment(session)
                }
                else if let startupError {
                    StartupRecoveryView(error: startupError,
                                        groupDirectory: MadarPlatform.dataDirectory,
                                        retry: { Task { await runtime.load() } },
                                        startFresh: { await runtime.startWithFreshStore() })
                } else {
                    MadarLaunchPlaceholder()
                }
        }
    }
    @Environment(\.scenePhase) private var scenePhase
}
