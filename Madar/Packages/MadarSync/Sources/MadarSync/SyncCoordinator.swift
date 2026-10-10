import Foundation
import Observation
import CloudKit
import SwiftData
import MadarData

@MainActor @Observable public final class SyncCoordinator {
    public private(set) var health = SyncHealth(phase: .idle, message: "لا معلومات عن آخر مزامنة")
    public private(set) var pendingAccountHash: String?
    public private(set) var checkpoint: VerifiedSyncCheckpoint?
    public private(set) var lastHistoryReport: HistoryDrainReport?
    private let adapter: any SyncLifecycleAdapter
    private let accountProvider: any CloudAccountProviding
    private let provisioning: SyncProvisioning
    private let history: HistoryProcessor
    private var busy = false
    private var observer: (any NSObjectProtocol)?
    private var knownAccount: CloudAccount = .temporarilyUnavailable
    private var lastImport: Date?
    private var lastExport: Date?
    private var pendingPreference: Bool?
    public init(adapter: any SyncLifecycleAdapter, accountProvider: any CloudAccountProviding, provisioning: SyncProvisioning, history: HistoryProcessor = .init()) {
        self.adapter = adapter; self.accountProvider = accountProvider; self.provisioning = provisioning; self.history = history
    }
    public func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshAccount() }
        }
    }
    public func stopObserving() { if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil }
    public func refreshAccount() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        guard provisioning.appGroupAvailable else { set(.failed, "حاوية مدار غير متاحة — لم تُفتح المزامنة"); return }
        guard provisioning.mayOpenCloudMirror else { set(.localOnly, "المزامنة السحابية غير مهيأة — بياناتك على هذا الجهاز فقط"); return }
        set(.checkingAccount, "يتحقق مدار من حساب iCloud")
        do {
            let account = try await accountProvider.account(); knownAccount = account
            let binding = adapter.binding
            let preference = try pendingPreference ?? adapter.syncPreference
            switch account {
            case .available(let hash):
                guard !hash.isEmpty else { throw SyncFailure.unknownAccount }
                if binding.accountHash != hash {
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
        let generation = adapter.binding.generationID
        let report = try adapter.withExclusiveStoreAccess { container, binding in
            guard binding.generationID == generation else { throw SyncFailure.generationChanged }
            return try history.drain(container: container, generationID: generation) { models in try adapter.publishSnapshots(changedModels: models) }
        }
        lastHistoryReport = report; return report
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
    private func set(_ phase: SyncHealth.Phase, _ message: String) { health = .init(phase: phase, message: message, lastObservedImportAt: lastImport, lastObservedExportAt: lastExport) }
}
