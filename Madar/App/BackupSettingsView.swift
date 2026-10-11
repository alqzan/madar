import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import MadarDesign

// UI contracts intentionally expose verified backend facts, never simulated success.
enum BackupUISchedule: String, CaseIterable, Identifiable, Sendable {
    case weekly, daily, manual
    var id: Self { self }
    var title: String { switch self { case .weekly: "أسبوعيًا"; case .daily: "يوميًا"; case .manual: "يدويًا" } }
}
struct BackupUIStatus: Sendable {
    let schedule: BackupUISchedule
    let lastSuccess: Date?
    let lastResult: String?
    let localOnly: Bool
    let automaticCount: Int
    let manualCount: Int
    let keyConfigured: Bool
}
struct BackupUIProgress: Sendable {
    let message: String
    let completedUnits: Int64?
    let totalUnits: Int64?
    init(message: String, completedUnits: Int64? = nil, totalUnits: Int64? = nil) {
        self.message = message; self.completedUnits = completedUnits; self.totalUnits = totalUnits
    }
}
struct BackupRestoreCount: Identifiable, Sendable {
    let id: String
    let title: String
    let current: Int
    let saved: Int
}
struct BackupRestorePreview: Identifiable, Sendable {
    let id: UUID
    let fileName: String
    let createdAt: Date
    let counts: [BackupRestoreCount]
    let additions: Int
    let updates: Int
    let deletions: Int
    let earliestDate: Date?
    let latestDate: Date?
    let skippedCount: Int
    let warnings: [String]
}
enum BackupUIRestoreMode: String, CaseIterable, Sendable { case merge, replace }
struct BackupRestoreResult: Sendable { let restoredCount: Int; let skippedCount: Int; let warnings: [String] }

@MainActor protocol BackupUIService: AnyObject {
    func status() async throws -> BackupUIStatus
    func setSchedule(_ schedule: BackupUISchedule) async throws
    func exportPlain(progress: @escaping @MainActor @Sendable (BackupUIProgress) -> Void) async throws -> URL
    func export(passphrase: String, progress: @escaping @MainActor @Sendable (BackupUIProgress) -> Void) async throws -> URL
    func previewRestore(file: URL, passphrase: String, progress: @escaping @MainActor @Sendable (BackupUIProgress) -> Void) async throws -> BackupRestorePreview
    func restore(previewID: UUID, mode: BackupUIRestoreMode, progress: @escaping @MainActor @Sendable (BackupUIProgress) -> Void) async throws -> BackupRestoreResult
    /// Stops cooperatively, removes staging and partial outputs, retains prior successful backups.
    func cancel() async
}

@MainActor @Observable final class BackupSettingsModel {
    let service: any BackupUIService
    private(set) var status: BackupUIStatus?
    private(set) var progress: BackupUIProgress?
    private(set) var exportedURL: URL?
    private(set) var plainExportedURL: URL?
    private(set) var preview: BackupRestorePreview?
    private(set) var busy = false
    private(set) var resultMessage: String?
    var errorMessage: String?
    var exportPassphrase = ""
    var exportConfirmation = ""
    var restorePassphrase = ""
    var selectedFile: URL?
    var restoreMode: BackupUIRestoreMode = .merge
    private var operation: Task<Void, Never>?
    private var operationID: UUID?
    init(service: any BackupUIService) { self.service = service }
    var canExport: Bool { !busy && exportPassphrase.count >= 10 && exportPassphrase == exportConfirmation }
    var canInspect: Bool { !busy && selectedFile != nil && !restorePassphrase.isEmpty }
    func refresh() async {
        do { status = try await service.status() }
        catch { errorMessage = "تعذّر قراءة حالة النسخ. \(error.localizedDescription)" }
    }
    func setSchedule(_ schedule: BackupUISchedule) {
        run(initial: "يحفظ موعد النسخ…") { [self] _ in try await service.setSchedule(schedule); status = try await service.status() }
    }
    func export() {
        guard canExport else { return }
        let passphrase = exportPassphrase
        run(initial: "يجهّز النسخة المشفّرة…") { [self] report in
            let file = try await service.export(passphrase: passphrase, progress: report)
            exportedURL = file; exportPassphrase = ""; exportConfirmation = ""
            if let current = try? await service.status() { status = current }; resultMessage = "حُفظت النسخة المشفّرة."
        }
    }
    func exportPlain() {
        guard !busy else { return }
        run(initial: "يجهّز ملف التصدير…") { [self] report in
            plainExportedURL = try await service.exportPlain(progress: report)
            resultMessage = "التصدير جاهز للحفظ أو المشاركة. الملف غير مشفّر."
        }
    }
    func inspect() {
        guard canInspect, let file = selectedFile else { return }
        let passphrase = restorePassphrase
        preview = nil
        run(initial: "يفحص النسخة دون تغيير بياناتك…") { [self] report in
            let access = file.startAccessingSecurityScopedResource()
            defer { if access { file.stopAccessingSecurityScopedResource() } }
            let validated = try await service.previewRestore(file: file, passphrase: passphrase, progress: report)
            try Task.checkCancellation(); preview = validated
        }
    }
    func restore() {
        guard !busy, let preview else { return }
        let mode = restoreMode
        run(initial: "يستعيد النسخة…") { [self] report in
            let result = try await service.restore(previewID: preview.id, mode: mode, progress: report)
            self.preview = nil; restorePassphrase = ""; selectedFile = nil
            if let current = try? await service.status() { status = current }
            resultMessage = "اكتملت الاستعادة: \(arabicNumber(result.restoredCount)) سجلًّا. \(arabicNumber(result.skippedCount)) سجلًّا لم يُطبّق."
            if !result.warnings.isEmpty { resultMessage = (resultMessage ?? "") + "\n" + result.warnings.joined(separator: "\n") }
        }
    }
    func dismissPreview() { preview = nil }
    func close() {
        operation?.cancel(); exportPassphrase = ""; exportConfirmation = ""; restorePassphrase = ""; preview = nil
        Task { [service] in await service.cancel() }
    }
    func cancel() {
        guard busy else { return }
        operation?.cancel()
        Task { [self] in await service.cancel() }
    }
    private func run(initial: String, action: @escaping @MainActor (@escaping @MainActor @Sendable (BackupUIProgress) -> Void) async throws -> Void) {
        guard !busy else { return }
        let id = UUID(); operationID = id; busy = true; resultMessage = nil
        progress = BackupUIProgress(message: initial)
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if operationID == id { busy = false; progress = nil; operation = nil } }
            do {
                try await action { [weak self] update in
                    guard let self, operationID == id else { return }
                    progress = update
                }
            } catch is CancellationError { resultMessage = "أُلغي الإجراء. النسخ السابقة محفوظة." }
            catch { errorMessage = "لم يكتمل الإجراء. \(error.localizedDescription)" }
        }
    }
}

struct BackupSettingsView: View {
    @State private var model: BackupSettingsModel
    @State private var importing = false
    @State private var confirmingRestore = false
    @FocusState private var focusedPassword: Int?
    @Environment(\.roomTheme) private var theme
    init(service: any BackupUIService) { _model = State(initialValue: BackupSettingsModel(service: service)) }
    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                if let status = model.status {
                    Picker("موعد النسخ", selection: Binding(get: { status.schedule }, set: { model.setSchedule($0) })) {
                        ForEach(BackupUISchedule.allCases) { Text($0.title).tag($0) }
                    }.disabled(model.busy).accessibilityIdentifier("backup-schedule")
                    if let success = status.lastSuccess { Text("آخر نسخة ناجحة: \(success.formatted(.dateTime.locale(Locale(identifier: "ar_SA")).day().month().year().hour().minute()))") }
                    else { Text("لم تُحفظ نسخة ناجحة بعد.") }
                    if let result = status.lastResult { Text(result).foregroundStyle(theme.secondaryInk) }
                    if status.localOnly { Label("النسخة على الجهاز فقط", systemImage: "internaldrive") }
                    Text("النسخ المحفوظة: \(arabicNumber(status.automaticCount)) تلقائية، \(arabicNumber(status.manualCount)) يدوية.")
                    Text("نحتفظ بآخر أربع نسخ تلقائية وكل النسخ اليدوية.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                } else { ProgressView("يقرأ حالة النسخ…") }
            } header: { Text("النسخ الاحتياطية") } footer: { Text("النسخ المجدولة تُنفّذ حين يسمح النظام، ويمكنك النسخ يدويًا في أي وقت.") }
            Section {
                Button("جهّز ملف التصدير", action: model.exportPlain).disabled(model.busy).accessibilityIdentifier("plain-export-now")
                if let file = model.plainExportedURL {
                    ShareLink(item: file) { Label("احفظ التصدير أو شاركه", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("plain-export-share")
                }
            } header: { Text("تصدير بياناتك") } footer: { Text("ملف ZIP غير مشفّر يحتوي سجلاتك بصيغة JSONL وصورها وصوتها، ويمكن فتحه خارج مدار. شاركه مع من تثق به. إعدادات هذا الجهاز وقفل التطبيق لا تدخل فيه.") }
            Section {
                SecureField("كلمة مرور — عشرة أحرف على الأقل", text: $model.exportPassphrase).textContentType(.newPassword).focused($focusedPassword, equals: 1).submitLabel(.next).onSubmit { focusedPassword = 2 }.accessibilityIdentifier("backup-password")
                SecureField("أعِد كلمة المرور", text: $model.exportConfirmation).textContentType(.newPassword).focused($focusedPassword, equals: 2).submitLabel(.done).onSubmit { focusedPassword = nil }.accessibilityIdentifier("backup-password-confirmation")
                Text("احفظ كلمة المرور في مكان آمن. فقدانها يجعل النسخة غير قابلة للقراءة.").font(MadarTypography.caption())
                if model.status?.keyConfigured == false { Text("تُستخدم كلمة مرور أول نسخة للنسخ التلقائي أيضًا. يُحفظ مفتاح مشتق منها على هذا الجهاز، وتبقى كلمة المرور عندك.").font(MadarTypography.caption()).accessibilityIdentifier("backup-key-setup") }
                exportButton
                if let file = model.exportedURL {
                    ShareLink(item: file) { Label("احفظ النسخة أو شاركها", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("backup-export")
                }
            } header: { Text("نسخة مشفّرة") } footer: { Text("تشمل بياناتك وصورها وصوتها؛ إعدادات هذا الجهاز لا تدخل في النسخة.") }
            Section {
                Button("اختر ملف النسخة") { importing = true }.disabled(model.busy).accessibilityIdentifier("restore-select-file")
                if let file = model.selectedFile { Text(file.lastPathComponent).font(MadarTypography.caption()) }
                SecureField("كلمة مرور النسخة", text: $model.restorePassphrase).textContentType(.password).focused($focusedPassword, equals: 3).submitLabel(.done).onSubmit { focusedPassword = nil }.accessibilityIdentifier("restore-password")
                Button("افحص وعاين", action: model.inspect).disabled(!model.canInspect).accessibilityIdentifier("restore-inspect")
                if let preview = model.preview { previewRows(preview) }
            } header: { Text("استعادة نسخة") } footer: { Text("الفحص والمعاينة لا يغيران بياناتك. تبدأ الاستعادة بعد اختيارك وتأكيدك.") }
            if let progress = model.progress {
                Section {
                    if let done = progress.completedUnits, let total = progress.totalUnits, total > 0 {
                        ProgressView(progress.message, value: Double(done), total: Double(total))
                    } else { ProgressView(progress.message) }
                    Button("إلغاء الإجراء", role: .cancel, action: model.cancel).accessibilityIdentifier("backup-cancel")
                }.accessibilityIdentifier("backup-progress")
            }
            if let result = model.resultMessage { Section { Text(result).accessibilityIdentifier("backup-result") } }
        }.navigationTitle("النسخ والاستعادة")
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("تم") { focusedPassword = nil }.accessibilityIdentifier("backup-keyboard-done") } }
            .task { await model.refresh() }
            .onDisappear { model.close() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "madarbackup") ?? .data], allowsMultipleSelection: false) { result in
                switch result { case .success(let urls): model.selectedFile = urls.first; model.dismissPreview(); case .failure(let error): model.errorMessage = error.localizedDescription }
            }
            .confirmationDialog(model.restoreMode == .replace ? "استبدل بيانات مدار بهذه النسخة؟" : "ادمج النسخة مع بيانات مدار؟", isPresented: $confirmingRestore, titleVisibility: .visible) {
                Button(model.restoreMode == .replace ? "استبدل بعد نسخة أمان" : "ادمج النسخة", role: model.restoreMode == .replace ? .destructive : nil, action: model.restore)
            } message: {
                Text((model.restoreMode == .replace ? "سيتغيّر هذا على كل أجهزتك. تُحفظ نسخة أمان أولًا، وتُحذف السجلات غير الموجودة في النسخة حذفًا قابلًا للاسترجاع الصريح." : "تُدمج السجلات حسب هوياتها، ولا يعيد الدمج سجلًّا محذوفًا إلا باسترجاع صريح.") + (model.status?.keyConfigured == false ? " كلمة مرور النسخة المختارة ستحمي نسخة الأمان والنسخ التلقائي على هذا الجهاز." : ""))
            }
            .alert("لم يكتمل الإجراء", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("حسنًا") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
    }
    @ViewBuilder private var exportButton: some View {
        let button = Button("انسخ الآن", action: model.export).disabled(!model.canExport).accessibilityIdentifier("backup-now")
        #if DEBUG
        if let fixture = ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"], UUID(uuidString: fixture) != nil {
            // Only an isolated UI fixture exposes non-secret diagnostics to XCTest.
            // Never expose the passphrase itself, even in a failing accessibility snapshot.
            let diagnostic = "passphrase-count=" + String(model.exportPassphrase.count)
                + ";confirmation-count=" + String(model.exportConfirmation.count)
                + ";matches=" + String(model.exportPassphrase == model.exportConfirmation)
                + ";busy=" + String(model.busy)
            button.accessibilityValue(Text(verbatim: diagnostic))
        } else { button }
        #else
        button
        #endif
    }
    @ViewBuilder private func previewRows(_ preview: BackupRestorePreview) -> some View {
        Text("معاينة \(preview.fileName)").font(MadarTypography.section())
        Text(preview.createdAt, format: .dateTime.year().month().day()).font(MadarTypography.caption())
        ForEach(preview.counts) { row in
            LabeledContent(row.title) { Text("حاليًا \(digits(row.current))، في النسخة \(digits(row.saved))") }
        }
        Text("إضافة \(digits(preview.additions))، تحديث \(digits(preview.updates))، حذف عند الاستبدال \(digits(preview.deletions))")
        if let first = preview.earliestDate, let last = preview.latestDate {
            Text("الفترة: \(first.formatted(.dateTime.day().month().year())) — \(last.formatted(.dateTime.day().month().year()))")
        }
        if preview.skippedCount > 0 { Text("لم يُطبّق \(digits(preview.skippedCount)) سجلًّا.") }
        ForEach(preview.warnings, id: \.self) { Text($0).foregroundStyle(theme.secondaryInk) }
        Picker("طريقة الاستعادة", selection: $model.restoreMode) {
            Text("دمج").tag(BackupUIRestoreMode.merge)
            Text("استبدال").tag(BackupUIRestoreMode.replace)
        }.pickerStyle(.segmented).disabled(model.busy).accessibilityIdentifier("restore-mode")
        Text(model.restoreMode == .replace ? "سيتغيّر هذا على كل أجهزتك." : "تبقى السجلات الحالية، وتُصالح معها النسخة.").font(MadarTypography.caption())
        Button("استعد النسخة") { confirmingRestore = true }.disabled(model.busy).accessibilityIdentifier("restore-confirm")
    }
    private func digits(_ number: Int) -> String { number.formatted(.number.locale(Locale(identifier: "ar_SA"))) }
}

private func arabicNumber(_ number: Int) -> String { number.formatted(.number.locale(Locale(identifier: "ar_SA"))) }
