import Foundation
import Observation
import SwiftUI
import MadarDesign
import MadarCore

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
        catch { errorMessage = "تعذّرت قراءة حالة iCloud. \(madarUserMessage(error))" }
    }
    func setEnabled(_ enabled: Bool) {
        guard !busy else { return }; busy = true
        Task { [self] in
            defer { busy = false }
            do { try await service.setEnabled(enabled); status = try await service.status() }
            catch { errorMessage = "لم يتغيّر إعداد المزامنة. \(madarUserMessage(error))" }
        }
    }
    func resolve(_ choice: SyncUIAccountChoice) {
        guard !busy, let change = status?.accountChange else { return }; busy = true
        Task { [self] in
            defer { busy = false }
            do { try await service.resolveAccountChange(id: change.id, choice: choice); status = try await service.status() }
            catch { errorMessage = "لم يكتمل اختيار الحساب. \(madarUserMessage(error))" }
        }
    }
}

struct SyncSettingsView: View {
    @State private var model: SyncSettingsModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.roomTheme) private var theme
    let dates: (Date) -> MadarDateLabels
    let time: (Date) -> String
    init(service: any SyncUIService, dates: @escaping (Date) -> MadarDateLabels, time: @escaping (Date) -> String) {
        _model = State(initialValue: SyncSettingsModel(service: service)); self.dates = dates; self.time = time
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MadarCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label { Text("iCloud").font(MadarTypography.section()) } icon: { Image(systemName: "icloud").foregroundStyle(theme.color("accentText")) }
                        if let status = model.status {
                            Toggle("زامن عبر iCloud", isOn: Binding(get: { status.enabled }, set: model.setEnabled))
                                .font(MadarTypography.body()).frame(minHeight: 44)
                                .disabled(model.busy || !canConfigure(status.availability))
                                .accessibilityIdentifier("sync-enabled")
                            Text(statusLine(status)).font(MadarTypography.body()).accessibilityIdentifier("sync-status")
                            if let instant = status.lastSyncedAt {
                                let labels = dates(instant)
                                Text("آخر مزامنة").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                                MadarDateLabel(.init(primary: labels.primary + "، " + time(instant), secondary: labels.secondary))
                            }
                            if let message = status.observedMessage { Text(message).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                        } else { ProgressView("يقرأ حالة المزامنة…") }
                        if model.busy { ProgressView("يحدّث الاتصال…") }
                    }
                }
                Text("قبل أول رفع يحفظ مدار نسخة احتياطية مشفّرة. إيقاف المزامنة يُبقي بياناتك على هذا الجهاز، ولا يحذف شيئًا من iCloud.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .background(theme.background).foregroundStyle(theme.ink)
        .navigationTitle("المزامنة").navigationBarTitleDisplayMode(.inline)
            .task { await model.refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
            .sheet(item: Binding(get: { model.status?.accountChange }, set: { _ in })) { change in
                NavigationStack {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("تغيّر حساب iCloud").font(MadarTypography.title())
                        let labels = dates(change.safetyBackupAt)
                        Text("حُفظت نسخة أمان. تبقى بيانات هذا الجهاز وتُرفع إلى الحساب الجديد.")
                        MadarDateLabel(.init(primary: labels.primary + "، " + time(change.safetyBackupAt), secondary: labels.secondary))
                        Button("أبقِ بيانات هذا الجهاز في الحساب الجديد") { model.resolve(.keepDeviceData) }
                            .buttonStyle(MadarPrimaryButton()).disabled(model.busy).accessibilityIdentifier("sync-account-keep-device")
                        if model.busy { ProgressView("ينفّذ اختيارك…") }
                        Spacer()
                    }.padding(24).font(MadarTypography.body())
                    .background(theme.background).foregroundStyle(theme.ink)
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
        case .localBuild: "هذه النسخة تعمل على الجهاز فقط."
        case .quotaFull: "مساحة iCloud ممتلئة. الحفظ على هذا الجهاز مستمر."
        }
    }
}
