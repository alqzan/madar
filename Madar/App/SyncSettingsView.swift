import Foundation
import Observation
import SwiftUI
import MadarDesign

enum SyncUIAvailability: Sendable {
    case available, noAccount, restricted, localBuild, quotaFull, unavailable
}
enum SyncUIAccountChoice: Sendable { case keepDeviceData, useNewAccountData }
struct SyncUIAccountChange: Identifiable, Sendable {
    let id: UUID
    let safetyBackupAt: Date
}
struct SyncUIStatus: Sendable {
    let enabled: Bool
    let availability: SyncUIAvailability
    let lastSyncedAt: Date?
    let observedMessage: String?
    /// Emitted only after an actual identity change and successful safety backup.
    let accountChange: SyncUIAccountChange?
}
@MainActor protocol SyncUIService: AnyObject {
    func status() async throws -> SyncUIStatus
    /// Rebuilds the same managed store configuration; never deletes local/cloud rows.
    func setEnabled(_ enabled: Bool) async throws
    func resolveAccountChange(id: UUID, choice: SyncUIAccountChoice) async throws
}

@MainActor @Observable final class SyncSettingsModel {
    private let service: any SyncUIService
    private(set) var status: SyncUIStatus?
    private(set) var busy = false
    var errorMessage: String?
    init(service: any SyncUIService) { self.service = service }
    func refresh() async {
        do { status = try await service.status() }
        catch { errorMessage = "تعذّرت قراءة حالة iCloud. \(error.localizedDescription)" }
    }
    func setEnabled(_ enabled: Bool) {
        guard !busy else { return }; busy = true
        Task { [self] in
            defer { busy = false }
            do { try await service.setEnabled(enabled); status = try await service.status() }
            catch { errorMessage = "لم يتغيّر إعداد المزامنة. \(error.localizedDescription)" }
        }
    }
    func resolve(_ choice: SyncUIAccountChoice) {
        guard !busy, let change = status?.accountChange else { return }; busy = true
        Task { [self] in
            defer { busy = false }
            do { try await service.resolveAccountChange(id: change.id, choice: choice); status = try await service.status() }
            catch { errorMessage = "لم يكتمل اختيار الحساب. \(error.localizedDescription)" }
        }
    }
}

struct SyncSettingsView: View {
    @State private var model: SyncSettingsModel
    @Environment(\.scenePhase) private var scenePhase
    init(service: any SyncUIService) { _model = State(initialValue: SyncSettingsModel(service: service)) }
    var body: some View {
        Form {
            Section {
                if let status = model.status {
                    Toggle("زامن عبر iCloud", isOn: Binding(get: { status.enabled }, set: model.setEnabled))
                        .disabled(model.busy || !canConfigure(status.availability))
                        .accessibilityIdentifier("sync-enabled")
                    Text(statusLine(status)).accessibilityIdentifier("sync-status")
                    if let instant = status.lastSyncedAt {
                        Text("آخر مزامنة: \(instant.formatted(.dateTime.locale(Locale(identifier: "ar_SA")).day().month().year().hour().minute()))")
                    } else { Text("لا معلومات عن آخر مزامنة.") }
                    if let message = status.observedMessage { Text(message) }
                } else { ProgressView("يقرأ حالة المزامنة…") }
                if model.busy { ProgressView("يحدّث الاتصال…") }
            } header: { Text("البيانات والمزامنة") } footer: { Text("تبقى بياناتك على الجهاز عند إيقاف المزامنة. لا يُحذف شيء من iCloud، والأجهزة الأخرى تحتفظ بنسخها.") }
        }.navigationTitle("المزامنة")
            .task { await model.refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
            .sheet(item: Binding(get: { model.status?.accountChange }, set: { _ in })) { change in
                NavigationStack {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("تغيّر حساب iCloud").font(MadarTypography.title())
                        Text("حُفظت نسخة أمان في \(change.safetyBackupAt.formatted(.dateTime.day().month().year().hour().minute())). اختر بياناتك لهذا الحساب.")
                        Button("أبقِ بيانات هذا الجهاز في الحساب الجديد") { model.resolve(.keepDeviceData) }
                            .buttonStyle(MadarPrimaryButton()).disabled(model.busy).accessibilityIdentifier("sync-account-keep-device")
                        Button("استعمل بيانات الحساب الجديد") { model.resolve(.useNewAccountData) }
                            .frame(minHeight: 44).disabled(model.busy).accessibilityIdentifier("sync-account-use-new")
                        if model.busy { ProgressView("ينفّذ اختيارك…") }
                        Spacer()
                    }.padding(24).font(MadarTypography.body())
                }.interactiveDismissDisabled()
            }
            .alert("لم تكتمل العملية", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("حسنًا") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }
    private func canConfigure(_ state: SyncUIAvailability) -> Bool {
        switch state { case .available, .quotaFull: true; default: false }
    }
    private func statusLine(_ status: SyncUIStatus) -> String {
        switch status.availability {
        case .available: status.enabled ? "المزامنة مفعّلة." : "المزامنة متوقفة؛ بياناتك على هذا الجهاز محفوظة."
        case .noAccount, .restricted, .unavailable: "iCloud غير متاح — بياناتك على هذا الجهاز فقط."
        case .localBuild: "هذه النسخة تعمل محليًا؛ اتصال iCloud غير مهيّأ."
        case .quotaFull: "مساحة iCloud ممتلئة. الحفظ على هذا الجهاز مستمر."
        }
    }
}
