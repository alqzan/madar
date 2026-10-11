import Foundation
import SwiftData
import MadarData
import MadarSync
import WidgetKit

@MainActor final class AppBackupService: BackupUIService {
    private weak var session: AppSession?
    let coordinator: BackupCoordinator
    private var previews: [UUID: RestorePreview] = [:]
    private var previewPasswords: [UUID: String] = [:]
    private var cancellation = BackupCancellation()
    private var exportCancellation: BackupCancellation?
    private var exportID: UUID?
    private var exportTicket: PrivacyAuthorization?
    private var artifactTickets: [URL: PrivacyAuthorization] = [:]
    private var artifactFeatures: [URL: Set<MadarProtectedFeature>] = [:]
    private weak var observedController: MadarLockController?
    private var lockObserver: UUID?
    private var revocationObservers: [UUID: @MainActor (Bool) -> Void] = [:]
    private let presentShare: @MainActor (URL, PrivacyAuthorization) throws -> Void
    init(session: AppSession, store: ManagedDataStore, backupDirectory: URL, keyStore: any BackupKeyStore = KeychainBackupKeyStore(service: "com.alqzan.madar2.backup"),
         sharePresentation: (@MainActor (URL, PrivacyAuthorization) throws -> Void)? = nil) {
        self.session = session
        presentShare = sharePresentation ?? { [weak session] file, ticket in
            guard let presenter = session?.privacyPresenter else { throw PrivacyAuthorizationError.stale }
            try presenter.present(file: file, authorization: ticket)
        }
        let lifecycle = BackupLifecycle(
            quiesce: { [weak session] in
                guard let session else { throw DataError.invalidValue("session unavailable") }
                try await session.quiesceWriters()
            },
            bindContainer: { [weak session] container in session?.bindContainer(container) },
            rebuildSnapshots: { [weak session] _ in
                guard let session else { throw DataError.invalidValue("session unavailable") }
                try session.reload(); try session.publishSnapshot(); WidgetCenter.shared.reloadAllTimelines()
            },
            resetHistory: { [weak store] _ in
                guard let store else { throw DataError.invalidValue("store unavailable") }
                try HistoryProcessor().reset(container: store.container)
            },
            resume: { [weak session] in session?.resumeWriters() }
        )
        coordinator = BackupCoordinator(store: store, backupDirectory: backupDirectory,
            keyStore: keyStore, lifecycle: lifecycle)
    }
    func status() async throws -> BackupUIStatus {
        guard let session else { throw DataError.invalidValue("session unavailable") }
        let actual = try coordinator.status(), catalog = try coordinator.catalog()
        return BackupUIStatus(schedule: BackupUISchedule(rawValue: session.string("core.backup")) ?? .weekly,
            lastSuccess: actual.lastSuccessAt, lastResult: Self.resultLabel(actual.lastResult), localOnly: actual.localOnly,
            automaticCount: catalog.filter { $0.kind == .automatic }.count,
            manualCount: catalog.filter { $0.kind == .manual }.count, keyConfigured: try coordinator.hasConfiguredKey())
    }
    func setSchedule(_ schedule: BackupUISchedule) async throws {
        guard let session else { throw DataError.invalidValue("session unavailable") }
        try await session.applySettingsAndWait(["core.backup": .string(schedule.rawValue)])
    }
    func export(passphrase: String, progress: @escaping @MainActor @Sendable (BackupUIProgress) -> Void) async throws -> URL {
        try await protectedExport(passphrase: passphrase, progress: progress)
    }
    func exportPlain(progress: @escaping @MainActor @Sendable (BackupUIProgress) -> Void) async throws -> URL {
        try await protectedExport(passphrase: nil, progress: progress)
    }
    private func protectedExport(passphrase: String?, progress: @escaping @MainActor @Sendable (BackupUIProgress) -> Void) async throws -> URL {
        guard exportID == nil else { throw BackupOperationError.busy }
        let controller = try privacyController(), id = UUID(), token = BackupCancellation()
        exportID = id; exportCancellation = token
        defer { if exportID == id { exportID = nil; exportTicket = nil; exportCancellation = nil } }
        var granted: PrivacyAuthorization?
        // Coordinator invokes this after its writer barrier + store lease, before
        // reading rows or keys. The private-note query reads presence metadata only.
        let authorization: @MainActor () async throws -> Void = { [self] in
            var features: Set<MadarProtectedFeature> = [.export]
            if try containsPrivateExportRows() { features.insert(.privateNote) }
            let ticket = try await controller.authorize(features)
            try validate(ticket, controller: controller, operation: id); granted = ticket; exportTicket = ticket
            if let passphrase, try !coordinator.hasConfiguredKey() {
                try await coordinator.configurePassphrase(passphrase, validation: { [self] in
                    try validate(ticket, controller: controller, operation: id)
                })
                try validate(ticket, controller: controller, operation: id)
            }
        }
        let guardedProgress: @MainActor @Sendable (BackupUIProgress) -> Void = { [weak self] update in
            guard let self, let ticket = exportTicket,
                  (try? validate(ticket, controller: controller, operation: id)) != nil else { return }
            progress(update)
        }
        do {
            let file: URL
            if let passphrase {
                file = try await coordinator.export(kind: .manual, passphrase: passphrase, progress: reporter(guardedProgress), cancellation: token, authorization: authorization).fileURL
            } else {
                file = try await coordinator.exportPlain(progress: reporter(guardedProgress), cancellation: token, authorization: authorization)
            }
            guard let ticket = granted else { throw PrivacyAuthorizationError.stale }
            try validate(ticket, controller: controller, operation: id)
            artifactTickets[file] = ticket; artifactFeatures[file] = ticket.features
            return file
        } catch { token.cancel(); throw error }
    }
    private func containsPrivateExportRows() throws -> Bool {
        let context = ModelContext(coordinator.store.container)
        // Backups include tombstones/aliases, so any stored private row counts.
        return try context.fetchCount(FetchDescriptor<NotebookNote>(predicate: #Predicate { $0.isPrivate })) > 0
    }
    private func validate(_ ticket: PrivacyAuthorization, controller: MadarLockController, operation: UUID? = nil) throws {
        guard session?.lockController === controller, operation == nil || exportID == operation else { throw PrivacyAuthorizationError.stale }
        try controller.validate(ticket)
    }
    private func privacyController() throws -> MadarLockController {
        guard let controller = session?.lockController else { throw PrivacyAuthorizationError.stale }
        if observedController !== controller {
            if let lockObserver { observedController?.removeObserver(lockObserver) }
            observedController = controller
            lockObserver = controller.observeRevocation { [weak self] cancelRequests in
                guard let self else { return }
                let cancelExport = cancelRequests || exportTicket != nil
                artifactTickets.removeAll()
                if cancelExport { exportCancellation?.cancel(); exportID = nil; exportTicket = nil }
                for observer in Array(revocationObservers.values) { observer(cancelExport) }
            }
        }
        return controller
    }
    func validateExport(file: URL) throws {
        guard let ticket = artifactTickets[file] else { throw PrivacyAuthorizationError.stale }
        try validate(ticket, controller: privacyController())
    }
    func share(file: URL) async throws {
        guard let features = artifactFeatures[file] else { throw PrivacyAuthorizationError.stale }
        let controller = try privacyController()
        let ticket = try await controller.authorize(features)
        try validate(ticket, controller: controller)
        try presentShare(file, ticket)
    }
    func observeExportRevocation(_ observer: @escaping @MainActor (Bool) -> Void) -> UUID {
        _ = try? privacyController()
        let id = UUID(); revocationObservers[id] = observer; return id
    }
    func removeExportObserver(_ id: UUID) { revocationObservers.removeValue(forKey: id) }
    func previewRestore(file: URL, passphrase: String, progress: @escaping @MainActor @Sendable (BackupUIProgress) -> Void) async throws -> BackupRestorePreview {
        clearPreviews()
        cancellation = BackupCancellation()
        let cache = FileManager.default.temporaryDirectory.appending(path: "MadarImport-\(UUID().uuidString).madarbackup")
        do {
            try await Task.detached(priority: .utility) { try FileManager.default.copyItem(at: file, to: cache) }.value
            let preview = try await coordinator.preview(file: cache, passphrase: passphrase, progress: reporter(progress), cancellation: cancellation)
            previews[preview.id] = preview
            // Retained only until explicit restoration when an automatic safety key is not configured.
            if try !coordinator.hasConfiguredKey() { previewPasswords[preview.id] = passphrase }
            return BackupRestorePreview(id: preview.id, fileName: file.lastPathComponent, createdAt: preview.createdAt,
                counts: Self.displayCounts(preview),
                additions: preview.additions, updates: preview.updates, deletions: preview.deletions,
                earliestDate: preview.earliestDate, latestDate: preview.latestDate, skippedCount: preview.skippedCount, warnings: preview.warnings)
        } catch { try? FileManager.default.removeItem(at: cache); throw error }
    }
    func restore(previewID: UUID, mode: BackupUIRestoreMode, progress: @escaping @MainActor @Sendable (BackupUIProgress) -> Void) async throws -> BackupRestoreResult {
        guard let preview = previews[previewID] else { throw BackupOperationError.stalePreview }
        cancellation = BackupCancellation()
        if try !coordinator.hasConfiguredKey() {
            guard let password = previewPasswords[previewID] else { throw BackupOperationError.backupNotConfigured }
            try await coordinator.configurePassphrase(password)
        }
        previewPasswords.removeValue(forKey: previewID)
        let result = try await coordinator.restore(preview: preview, mode: mode == .merge ? .merge : .replace,
            progress: reporter(progress), cancellation: cancellation)
        previews.removeValue(forKey: previewID)
        try? FileManager.default.removeItem(at: preview.fileURL)
        return BackupRestoreResult(restoredCount: result.restoredCount, skippedCount: result.skippedCount, warnings: result.warnings)
    }
    func cancel() async {
        exportCancellation?.cancel(); cancellation.cancel(); clearPreviews()
    }
    private func clearPreviews() {
        previewPasswords.removeAll()
        for preview in previews.values { try? FileManager.default.removeItem(at: preview.fileURL) }
        previews.removeAll()
    }
    func runScheduledBackup() async throws {
        guard let session else { return }
        guard try coordinator.hasConfiguredKey() else { return }
        let raw = session.string("core.backup")
        let schedule: BackupSchedule = raw == "daily" ? .daily : raw == "weekly" ? .weekly : .off
        _ = try await coordinator.performScheduledBackupIfDue(schedule: schedule)
    }
    private static func resultLabel(_ raw: String) -> String? {
        switch raw { case "success": "آخر عملية نسخ نجحت."; case "failed": "لم تكتمل آخر محاولة نسخ."; case "cancelled": "أُلغيت آخر محاولة نسخ."; default: nil }
    }
    private static func displayCounts(_ preview: RestorePreview) -> [BackupRestoreCount] {
        let groups: [(String, [String])] = [
            ("الإعدادات والأنماط", ["Setting", "LayoutState", "Preset"]),
            ("الصلاة", ["PrayerLog", "QadaItem", "QiyamNight"]),
            ("القرآن", ["HifzPlan", "HifzSession", "PageGrade", "MistakeSpot", "MistakeEvent", "QuranDayState", "QuranAllotment", "RecoveryPlan"]),
            ("المذكرات", ["DayPage", "Niyya", "Entry", "HiddenAutoLine", "MarginNote", "Letter", "Project"]),
            ("الصور والصوت والملفات", ["Media"]),
            ("المال", ["Account", "Card", "Statement", "CashbackEntry", "MoneyTransaction", "Allocation", "Reconciliation", "BankMessage", "Cycle", "CyclePolicy", "Envelope", "EnvelopePlan", "Obligation", "InstallmentItem", "Category", "CategoryLimit", "MerchantRule", "ZakatProfile"]),
            ("المحبرة", ["Book", "ReadingSession", "Highlight", "NotebookNote", "HadithProgress", "UserWord"]),
            ("العادات", ["Habit", "HabitPolicy", "HabitPause", "HabitLog"]),
            ("السفر والأيام القادمة", ["Trip", "UpcomingDay"]),
            ("الودجات", ["WidgetConfig"]),
            ("سجل النقل", ["ImportBatch", "ImportLink"])
        ]
        return groups.compactMap { title, models in
            let saved = models.reduce(0) { $0 + (preview.counts[$1] ?? 0) }
            let current = models.reduce(0) { $0 + (preview.currentCounts[$1] ?? 0) }
            guard saved > 0 || current > 0 else { return nil }
            return BackupRestoreCount(id: models[0], title: title, current: current, saved: saved)
        }
    }
    private func reporter(_ report: @escaping @MainActor @Sendable (BackupUIProgress) -> Void) -> @Sendable (BackupProgress) -> Void {
        { update in
            let message: String = switch update.phase {
            case .reading: "يقرأ بيانات النسخة…"
            case .decrypting: "يفتح النسخة المشفّرة…"
            case .validating: "يفحص السجلات والمرفقات…"
            case .automaticBackup: "يحفظ نسخة الأمان…"
            case .encrypting: "يشفّر النسخة…"
            case .writing: "يحفظ الملف…"
            case .staging: "يجهّز البيانات المستعادة…"
            case .promoting: "يثبّت الاستعادة…"
            case .completed: "اكتملت العملية."
            }
            Task { @MainActor in report(BackupUIProgress(message: message, completedUnits: update.completedUnits, totalUnits: update.totalUnits)) }
        }
    }
}
