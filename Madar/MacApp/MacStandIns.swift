import Foundation
import MadarData

// The Mac app shares `AppSession` with iPhone and iPad. Prayer notifications on iOS are built on ActivityKit and the iOS app
// lifecycle and are not part of the Mac app yet, so no Mac screen schedules one. This stand-in keeps the session's types complete;
// it is never created or attached on the Mac, so the session runs its writes directly (as it does whenever no coordinator is attached).

@MainActor final class PrayerNotificationCoordinator {
    // The same category identifiers as the iOS coordinator, so a room reminder built by shared code names the same category.
    static let habitCategoryID = "habits.reminder"
    static let wirdCategoryID = "quran.wird"
    func attach(to session: AppSession) async {}
    func requestRefresh() {}
    func resumeAfterStoreMaintenance() async {}
    func requestAuthorization() async throws {}
    func refreshAfterSerializedMutation() async {}
    func withSerializedMutation<T>(_ operation: @MainActor () async throws -> T) async rethrows -> T { try await operation() }
    #if DEBUG
    func runSimulatorAcceptanceScenarioForTesting() async throws -> String { "UNAVAILABLE — macOS" }
    #endif
}

/// The Mihbara reader (Readium) is not part of the Mac app yet, so there is never a pending reading write to retry here.
@MainActor final class MihbaraReadingSaveCoordinator {
    private static let shared = MihbaraReadingSaveCoordinator()
    static func forSession(_ app: AppSession) -> MihbaraReadingSaveCoordinator { shared }
    static func storeMaintenanceEnded(for app: AppSession) {}
    var canRetryPendingWriteErrorNow: Bool { false }
    func retryPendingWritesNow() {}
    func dismissPendingWriteError() {}
}

/// iOS wakes the app for the automatic backup through BackgroundTasks. The Mac has no such scheduler for a sandboxed app, so the
/// automatic backup runs when the window opens and when it comes back to the front (the root view already asks for it then).
@MainActor final class AppBackupBackgroundTasks {
    func reschedule(using service: AppBackupService) async {}
}

/// The Mac has no camera picker; the diary's camera button checks this and stays hidden, so `DiaryCameraCapture` is never shown.
enum UIImagePickerController {
    enum SourceType { case camera, photoLibrary }
    static func isSourceTypeAvailable(_ type: SourceType) -> Bool { false }
}
import SwiftUI
struct DiaryCameraCapture: View {
    let captured: (NSImage) -> Void
    let cancelled: () -> Void
    var body: some View { Color.clear.onAppear(perform: cancelled) }
}

/// The paper-book scanner (VisionKit) lives in the Mihbara room, which the Mac app does not open yet; the room has no entry point
/// on the Mac, so this is never shown.
struct MihbaraPaperIndexEditor: View {
    init(app: AppSession, readingBooks: [MihbaraBook], onSaved: @escaping () -> Void, existingBook: MihbaraBook? = nil) {}
    var body: some View { EmptyView() }
}
