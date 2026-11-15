import Foundation
import Observation
import CloudKit
import CoreData
import SwiftData
import MadarData

private struct PendingCloudImport: Equatable {
    let storeIdentifier: String
    let generationID: UUID
    let date: Date
}

@MainActor @Observable public final class SyncCoordinator {
    public private(set) var health = SyncHealth(phase: .idle, message: "لا معلومات عن آخر مزامنة")
    public private(set) var pendingAccountHash: String?
    public private(set) var checkpoint: VerifiedSyncCheckpoint?
    public private(set) var lastHistoryReport: HistoryDrainReport?
    /// The last account state read from iCloud (nil until read; never inferred).
    public private(set) var observedAccount: CloudAccount?
    private let adapter: any SyncLifecycleAdapter
    private let accountProvider: any CloudAccountProviding
    private let provisioning: SyncProvisioning
    private let history: HistoryProcessor
    private var busy = false
    private var observer: (any NSObjectProtocol)?
    private var mirroringObserver: (any NSObjectProtocol)?
    private var knownAccount: CloudAccount = .temporarilyUnavailable
    private var lastImport: Date?
    private var lastExport: Date?
    private var pendingImports: [PendingCloudImport] = []
    private var importRetryTask: Task<Void, Never>?
    private var pendingPreference: Bool?
    private let onCloudImportSuccess: (@MainActor () -> Void)?
    public init(adapter: any SyncLifecycleAdapter, accountProvider: any CloudAccountProviding, provisioning: SyncProvisioning,
                history: HistoryProcessor = .init(), onCloudImportSuccess: (@MainActor () -> Void)? = nil) {
        self.adapter = adapter; self.accountProvider = accountProvider; self.provisioning = provisioning
        self.history = history; self.onCloudImportSuccess = onCloudImportSuccess
    }
    public func startObserving() {
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refreshAccount() }
            }
        }
        guard mirroringObserver == nil else { return }
        mirroringObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.endDate != nil else { return }
            let isImport = event.type == .import
            let isExport = event.type == .export
            let succeeded = event.succeeded
            let date = event.endDate ?? Date()
            let error = event.error as NSError?
            let errorDomain = error?.domain ?? ""
            let errorCode = error?.code ?? 0
            let storeIdentifier = event.storeIdentifier
            guard isImport || isExport else { return }
            Task { @MainActor [weak self] in
                self?.finishMirroringEvent(storeIdentifier: storeIdentifier, isImport: isImport, isExport: isExport, succeeded: succeeded,
                                           date: date, errorDomain: errorDomain, errorCode: errorCode)
            }
        }
    }
    public func stopObserving() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let mirroringObserver { NotificationCenter.default.removeObserver(mirroringObserver) }
        observer = nil; mirroringObserver = nil
    }
    public func refreshAccount() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        guard provisioning.appGroupAvailable else { set(.failed, "حاوية مدار غير متاحة — لم تُفتح المزامنة"); return }
        guard provisioning.mayOpenCloudMirror else { set(.localOnly, "المزامنة السحابية غير مهيأة — بياناتك على هذا الجهاز فقط"); return }
        set(.checkingAccount, "يتحقق مدار من حساب iCloud")
        do {
            let account = try await accountProvider.account(); knownAccount = account; observedAccount = account
            let binding = adapter.binding
            let preference = try pendingPreference ?? adapter.syncPreference
            switch account {
            case .available(let hash):
                guard !hash.isEmpty else { throw SyncFailure.unknownAccount }
                if binding.accountHash == nil {
                    // The preference is false on a new install. If the person explicitly enabled it
                    // earlier on this device, attach only after the app adapter checkpoints first.
                    let mirror = preference && provisioning.mayOpenCloudMirror
                    try await adapter.activate(.init(accountHash: hash, cloudEnabled: mirror, dataChoice: .keepDevice, checkpoint: nil, generationBefore: binding.generationID, requestedDevicePreference: preference))
                    set(mirror ? .cloudConfigured : .localOnly, mirror ? "يجهّز مدار المزامنة" : "المزامنة مطفأة — بياناتك محفوظة على هذا الجهاز")
                } else if binding.accountHash != hash {
                    if checkpoint == nil {
                        set(.transitioning, "يحفظ مدار نسخة قبل تغيير الحساب")
                        let saved = try await adapter.checkpointAndSuspend(reason: .accountChange)
                        guard saved.generationID == binding.generationID else { throw SyncFailure.generationChanged }
                        try saved.verifyFile(); checkpoint = saved; pendingPreference = preference
                    }
                    pendingAccountHash = hash
                    set(.waitingForAccountChoice, "تغيّر حساب iCloud — أبقِ بيانات هذا الجهاز أو استعمل بيانات الحساب الجديد")
                } else {
                    if binding.cloudEnabled != preference || checkpoint != nil {
                        try await adapter.activate(.init(accountHash: hash, cloudEnabled: preference, dataChoice: .keepDevice, checkpoint: nil, generationBefore: binding.generationID, requestedDevicePreference: preference))
                    }
                    pendingAccountHash = nil; checkpoint = nil; pendingPreference = nil
                    set(preference ? .cloudConfigured : .localOnly, preference ? "لا معلومات عن آخر مزامنة" : "المزامنة مطفأة — بياناتك محفوظة على هذا الجهاز")
                }
            case .signedOut, .restricted:
                if binding.cloudEnabled || checkpoint != nil {
                    try await adapter.activate(.init(accountHash: binding.accountHash, cloudEnabled: false, dataChoice: .keepDevice, checkpoint: nil, generationBefore: binding.generationID, requestedDevicePreference: preference))
                }
                pendingAccountHash = nil; checkpoint = nil; pendingPreference = nil
                set(.localOnly, "iCloud غير متاح — بياناتك على هذا الجهاز فقط")
            case .temporarilyUnavailable: set(binding.cloudEnabled ? .cloudConfigured : .localOnly, "لا معلومات عن آخر مزامنة — الكتابة على الجهاز متاحة")
            }
        } catch { set(.failed, "لم تكتمل تهيئة المزامنة — بيانات الجهاز محفوظة؛ أعد المحاولة") }
    }
    public func setSyncEnabled(_ enabled: Bool) async throws {
        guard !busy, pendingAccountHash == nil else { throw SyncFailure.transitionInProgress }
        busy = true; defer { busy = false }
        let binding = adapter.binding
        let canMirror = enabled && provisioning.mayOpenCloudMirror && knownAccount.identityHash == binding.accountHash && binding.accountHash != nil
        set(.transitioning, enabled ? "يجهّز مدار المزامنة" : "يوقف مدار المزامنة مع إبقاء البيانات")
        do {
            try await adapter.activate(.init(accountHash: binding.accountHash, cloudEnabled: canMirror, dataChoice: .keepDevice, checkpoint: nil, generationBefore: binding.generationID, requestedDevicePreference: enabled))
            set(canMirror ? .cloudConfigured : .localOnly, canMirror ? "لا معلومات عن آخر مزامنة" : "بياناتك على هذا الجهاز؛ لم يُحذف شيء من iCloud")
        } catch { set(.failed, "تعذّر تغيير المزامنة — بقي مخزن البيانات محفوظًا"); throw error }
    }
    public func resolveAccountChange(_ choice: AccountDataChoice) async throws {
        guard !busy, let hash = pendingAccountHash, let saved = checkpoint else { throw SyncFailure.transitionInProgress }
        busy = true; defer { busy = false }
        try saved.verifyFile()
        guard adapter.binding.generationID == saved.generationID else { throw SyncFailure.generationChanged }
        // The account can change again while the choice sheet is open. Never bind a
        // stale destination account or transplant A's data into an unintended C.
        let currentAccount = try await accountProvider.account()
        guard currentAccount.identityHash == hash else { throw SyncFailure.unknownAccount }
        knownAccount = currentAccount
        let pref = try pendingPreference ?? adapter.syncPreference
        set(.transitioning, "يجهّز مدار بيانات الحساب المختار")
        do {
            try await adapter.activate(.init(accountHash: hash, cloudEnabled: pref && provisioning.mayOpenCloudMirror, dataChoice: choice, checkpoint: saved, generationBefore: saved.generationID, requestedDevicePreference: pref))
            pendingAccountHash = nil; checkpoint = nil; pendingPreference = nil
            lastImport = nil; lastExport = nil
            _ = try adapter.withExclusiveStoreAccess { container, _ in try history.reset(container: container) }
            try adapter.publishSnapshots(changedModels: Set(MadarSchema.syncedNames))
            set(adapter.binding.cloudEnabled ? .cloudConfigured : .localOnly, adapter.binding.cloudEnabled ? "لا معلومات عن آخر مزامنة" : "بيانات الحساب محفوظة على هذا الجهاز")
        } catch { set(.failed, "لم يكتمل تغيير الحساب — النسخة السابقة محفوظة؛ أعد المحاولة"); throw error }
    }
    @discardableResult public func processHistory() throws -> HistoryDrainReport {
        guard !busy, pendingAccountHash == nil else { throw SyncFailure.transitionInProgress }
        let expectedGeneration = adapter.binding.generationID
        let result = try adapter.withExclusiveStoreAccess { container, binding -> (HistoryDrainReport, String?) in
            guard binding.generationID == expectedGeneration else { throw SyncFailure.generationChanged }
            let report = try history.drain(container: container, generationID: binding.generationID) { models in
                try adapter.publishSnapshots(changedModels: models)
            }
            return (report, container.storeIdentifier(forConfigurationNamed: "synced"))
        }
        let report = result.0
        lastHistoryReport = report
        let activeGeneration = adapter.binding.generationID
        let matchingImports = pendingImports.filter {
            $0.generationID == activeGeneration && $0.storeIdentifier == result.1
        }
        if let latestImport = matchingImports.map(\.date).max(), adapter.binding.cloudEnabled {
            // HistoryProcessor already reconciles imported rows and refreshes snapshots when it
            // sees transactions. An empty drain still gets one reload before the event is consumed.
            if report.transactions == 0 { onCloudImportSuccess?() }
            pendingImports.removeAll()
            lastImport = latestImport
            set(health.phase, health.message)
        } else {
            // A different generation/store became active while an import was queued. Discard those
            // stale events so they can never be reported as imports into the new store.
            pendingImports.removeAll {
                !adapter.binding.cloudEnabled || $0.generationID != activeGeneration || $0.storeIdentifier != result.1
            }
        }
        return report
    }
    /// Only call for an actual observed mirror event, never infer from local saves/history.
    public func observeCloudImportSuccess(at date: Date) { lastImport = date; set(health.phase, health.message) }
    public func observeCloudExportSuccess(at date: Date) { lastExport = date; set(health.phase, "آخر إرسال إلى iCloud مسجّل") }
    public func observeCloudError(_ error: CKError) {
        switch error.code {
        case .quotaExceeded: set(adapter.binding.cloudEnabled ? .cloudConfigured : .localOnly, "مساحة iCloud ممتلئة — الكتابة على الجهاز مستمرة")
        case .notAuthenticated: set(.localOnly, "iCloud غير متاح — بياناتك على هذا الجهاز فقط")
        default: set(adapter.binding.cloudEnabled ? .cloudConfigured : .localOnly, "لم تكتمل المزامنة — الكتابة على الجهاز مستمرة")
        }
    }
    private func finishMirroringEvent(storeIdentifier: String, isImport: Bool, isExport: Bool, succeeded: Bool, date: Date,
                                      errorDomain: String, errorCode: Int) {
        guard isImport || isExport, adapter.binding.cloudEnabled else { return }
        let eventGeneration = adapter.binding.generationID
        if isImport, succeeded {
            let pending = PendingCloudImport(storeIdentifier: storeIdentifier, generationID: eventGeneration, date: date)
            if let index = pendingImports.firstIndex(where: {
                $0.storeIdentifier == pending.storeIdentifier && $0.generationID == pending.generationID
            }) {
                if pendingImports[index].date < date { pendingImports[index] = pending }
            } else {
                pendingImports.append(pending)
            }
        }
        guard let identity = activeCloudStoreIdentity() else {
            if isImport, succeeded { scheduleImportRetry() }
            return
        }
        guard identity.storeIdentifier == storeIdentifier, identity.generationID == eventGeneration else {
            if isImport { pendingImports.removeAll { $0.storeIdentifier == storeIdentifier && $0.generationID == eventGeneration } }
            return
        }
        guard succeeded else {
            if errorDomain == CKErrorDomain, errorCode == CKError.Code.quotaExceeded.rawValue {
                set(adapter.binding.cloudEnabled ? .cloudConfigured : .localOnly, "مساحة iCloud ممتلئة — الكتابة على الجهاز مستمرة")
            } else if errorDomain == CKErrorDomain, errorCode == CKError.Code.notAuthenticated.rawValue {
                set(.localOnly, "iCloud غير متاح — بياناتك على هذا الجهاز فقط")
            } else {
                set(adapter.binding.cloudEnabled ? .cloudConfigured : .localOnly, "لم تكتمل المزامنة — الكتابة على الجهاز مستمرة")
            }
            return
        }
        if isImport {
            do { _ = try processHistory() }
            catch { scheduleImportRetry() }
        }
        if isExport { observeCloudExportSuccess(at: date) }
    }

    private func activeCloudStoreIdentity() -> (storeIdentifier: String, generationID: UUID)? {
        guard adapter.binding.cloudEnabled else { return nil }
        let expectedGeneration = adapter.binding.generationID
        do {
            return try adapter.withExclusiveStoreAccess { container, binding in
                guard binding.cloudEnabled, binding.generationID == expectedGeneration,
                      let identifier = container.storeIdentifier(forConfigurationNamed: "synced") else { return nil }
                return (identifier, binding.generationID)
            }
        } catch { return nil }
    }

    /// A busy transition must not consume a successful import event. Retry briefly, then leave it
    /// pending for the next ordinary history drain if a transition still holds the store.
    private func scheduleImportRetry() {
        guard importRetryTask == nil, !pendingImports.isEmpty else { return }
        importRetryTask = Task { @MainActor [weak self] in
            for delay in [250, 750, 1_500] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard let self, !self.pendingImports.isEmpty, !Task.isCancelled else { break }
                do { _ = try self.processHistory() } catch { continue }
                if self.pendingImports.isEmpty { break }
            }
            self?.importRetryTask = nil
        }
    }
    private func set(_ phase: SyncHealth.Phase, _ message: String) { health = .init(phase: phase, message: message, lastObservedImportAt: lastImport, lastObservedExportAt: lastExport) }
}
