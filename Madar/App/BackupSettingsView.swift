import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import MadarDesign
import MadarCore

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
    var estimatedBytes: Int? = nil
    var excludedBooks: [BackupUIExcludedBook] = []
    var folderName: String? = nil
    var folderCopiedAt: Date? = nil
    var folderUploadConfirmed: Bool? = nil
    var folderMessage: String? = nil
    var canUndoFolderChange = false
}
struct BackupUIExcludedBook: Sendable, Hashable { let title: String; let bytes: Int; let fromTurath: Bool }
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
    func chooseFolder(_ folder: URL) async throws
    func clearFolder() async throws
    func undoFolderChange() async throws
    func retryFolderDelivery() async throws
    func exportPlain(progress: @escaping @MainActor @Sendable (BackupUIProgress) -> Void) async throws -> URL
    func export(passphrase: String, progress: @escaping @MainActor @Sendable (BackupUIProgress) -> Void) async throws -> URL
    func validateExport(file: URL) throws
    func share(file: URL) async throws
    func observeExportRevocation(_ observer: @escaping @MainActor (Bool) -> Void) -> UUID
    func removeExportObserver(_ id: UUID)
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
    private(set) var restoreResult: BackupRestoreResult?
    var errorMessage: String?
    var exportPassphrase = ""
    var exportConfirmation = ""
    var restorePassphrase = ""
    var selectedFile: URL?
    var restoreMode: BackupUIRestoreMode = .merge
    private var operation: Task<Void, Never>?
    private var operationID: UUID?
    private var protectedOperation = false
    private var revocationObserver: UUID?
    init(service: any BackupUIService) { self.service = service; observePrivacy() }
    private func observePrivacy() {
        guard revocationObserver == nil else { return }
        revocationObserver = service.observeExportRevocation { [weak self] cancel in
            guard let self else { return }
            exportedURL = nil; plainExportedURL = nil; exportPassphrase = ""; exportConfirmation = ""; resultMessage = nil
            if cancel && protectedOperation {
                operation?.cancel(); operationID = nil; busy = false; progress = nil; operation = nil; protectedOperation = false
            }
        }
    }
    var canExport: Bool { !busy && exportPassphrase.count >= 10 && exportPassphrase == exportConfirmation }
    var canInspect: Bool { !busy && selectedFile != nil && !restorePassphrase.isEmpty }
    func refresh() async {
        observePrivacy()
        do { status = try await service.status() }
        catch { errorMessage = "تعذّر قراءة حالة النسخ. \(error.localizedDescription)" }
    }
    func setSchedule(_ schedule: BackupUISchedule) {
        run(initial: "يحفظ موعد النسخ…") { [self] _, _ in try await service.setSchedule(schedule); status = try await service.status() }
    }
    func chooseFolder(_ folder: URL) {
        run(initial: "يحفظ مجلد النسخ…") { [self] _, _ in
            do { try await service.chooseFolder(folder); status = try await service.status() }
            catch {
                status = try? await service.status()
                errorMessage = "تعذّر الوصول إلى مجلد النسخ. النسخ الأصلية محفوظة داخل مدار؛ جرّب مجلدًا آخر أو أعد المحاولة."
            }
        }
    }
    func clearFolder() {
        run(initial: "يوقف النسخ إلى المجلد…") { [self] _, _ in try await service.clearFolder(); status = try await service.status() }
    }
    func undoFolderChange() {
        run(initial: "يعيد المجلد السابق…") { [self] _, _ in try await service.undoFolderChange(); status = try await service.status() }
    }
    func retryFolder() {
        run(initial: "ينسخ الملفات المشفّرة إلى المجلد…") { [self] _, _ in
            do { try await service.retryFolderDelivery() } catch { }
            status = try await service.status()
        }
    }
    func export() {
        guard canExport else { return }
        let passphrase = exportPassphrase
        run(initial: "يجهّز النسخة المشفّرة…", protected: true) { [self] report, id in
            let file = try await service.export(passphrase: passphrase, progress: report)
            try checkRequest(id); try service.validateExport(file: file)
            let current = try? await service.status()
            try checkRequest(id); try service.validateExport(file: file)
            exportedURL = file; exportPassphrase = ""; exportConfirmation = ""
            if let current { status = current }; resultMessage = "حُفظت النسخة المشفّرة."
        }
    }
    func exportPlain() {
        guard !busy else { return }
        run(initial: "يجهّز ملف التصدير…", protected: true) { [self] report, id in
            let file = try await service.exportPlain(progress: report)
            try checkRequest(id); try service.validateExport(file: file)
            plainExportedURL = file
            resultMessage = "التصدير جاهز للحفظ أو المشاركة. الملف غير مشفّر."
        }
    }
    func sharePlain() { if let file = plainExportedURL { share(file) } }
    func shareEncrypted() { if let file = exportedURL { share(file) } }
    private func share(_ file: URL) {
        run(initial: "يفتح المشاركة…", protected: true) { [self] _, id in
            try await service.share(file: file); try checkRequest(id)
        }
    }
    private func checkRequest(_ id: UUID) throws {
        try Task.checkCancellation()
        guard operationID == id else { throw PrivacyAuthorizationError.stale }
    }
    func inspect() {
        guard canInspect, let file = selectedFile else { return }
        let passphrase = restorePassphrase
        preview = nil
        run(initial: "يفحص النسخة دون تغيير بياناتك…") { [self] report, _ in
            let access = file.startAccessingSecurityScopedResource()
            defer { if access { file.stopAccessingSecurityScopedResource() } }
            let validated = try await service.previewRestore(file: file, passphrase: passphrase, progress: report)
            try Task.checkCancellation(); preview = validated
        }
    }
    func restore() {
        guard !busy, let preview else { return }
        let mode = restoreMode
        run(initial: "يستعيد النسخة…") { [self] report, _ in
            let result = try await service.restore(previewID: preview.id, mode: mode, progress: report)
            self.preview = nil; restorePassphrase = ""; selectedFile = nil
            if let current = try? await service.status() { status = current }
            restoreResult = result
        }
    }
    func dismissPreview() { preview = nil }
    func close() {
        let wasProtected = protectedOperation
        operation?.cancel(); exportPassphrase = ""; exportConfirmation = ""; restorePassphrase = ""; preview = nil
        exportedURL = nil; plainExportedURL = nil; operationID = nil; busy = false; progress = nil; protectedOperation = false
        if let revocationObserver { service.removeExportObserver(revocationObserver) }; revocationObserver = nil
        if !wasProtected { Task { [service] in await service.cancel() } }
    }
    func cancel() {
        guard busy else { return }
        operation?.cancel()
        if !protectedOperation { Task { [service] in await service.cancel() } }
    }
    private func run(initial: String, protected: Bool = false, action: @escaping @MainActor (@escaping @MainActor @Sendable (BackupUIProgress) -> Void, UUID) async throws -> Void) {
        guard !busy else { return }
        let id = UUID(); operationID = id; busy = true; protectedOperation = protected; resultMessage = nil; restoreResult = nil
        progress = BackupUIProgress(message: initial)
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if operationID == id { busy = false; progress = nil; operation = nil; protectedOperation = false } }
            do {
                try await action({ [weak self] update in
                    guard let self, operationID == id else { return }
                    progress = update
                }, id)
            } catch is CancellationError { if operationID == id { resultMessage = "أُلغي الإجراء. النسخ السابقة محفوظة." } }
            catch { if operationID == id { errorMessage = "لم يكتمل الإجراء. \(error.localizedDescription)" } }
        }
    }
}

struct BackupSettingsView: View {
    let numerals: NumeralStyle
    /// Both calendars for every date shown here (owner rule); the caller supplies the app's labels.
    let dates: (Date) -> MadarDateLabels
    let time: (Date) -> String
    @State private var model: BackupSettingsModel
    @State private var importing = false
    @State private var choosingFolder = false
    @State private var confirmingRestore = false
    @FocusState private var focusedPassword: Int?
    @Environment(\.roomTheme) private var theme
    init(service: any BackupUIService, numerals: NumeralStyle = .hindi,
         dates: @escaping (Date) -> MadarDateLabels,
         time: @escaping (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }) {
        self.numerals = numerals; self.dates = dates; self.time = time
        _model = State(initialValue: BackupSettingsModel(service: service))
    }
    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard
                folderCard
                encryptedCard
                restoreCard
                plainCard
                if let progress = model.progress {
                    MadarCard {
                        VStack(alignment: .leading, spacing: 12) {
                            if let done = progress.completedUnits, let total = progress.totalUnits, total > 0 {
                                ProgressView(progress.message, value: Double(done), total: Double(total))
                            } else { ProgressView(progress.message) }
                            Button("إلغاء الإجراء", role: .cancel, action: model.cancel).frame(minHeight: 44).accessibilityIdentifier("backup-cancel")
                        }
                    }.accessibilityElement(children: .contain).accessibilityIdentifier("backup-progress")
                }
                if let result = resultCopy { MadarCard { Text(result).font(MadarTypography.body()).accessibilityIdentifier("backup-result") } }
            }
            .padding(16).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.background).foregroundStyle(theme.ink)
        .navigationTitle("النسخ والاستعادة").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); keyboardDoneButton } }
            .task { await model.refresh() }
            .onDisappear { model.close() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "madarbackup") ?? .data], allowsMultipleSelection: false) { result in
                switch result { case .success(let urls): model.selectedFile = urls.first; model.dismissPreview(); case .failure(let error): model.errorMessage = error.localizedDescription }
            }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let folder = urls.first { model.chooseFolder(folder) }
            }
            .confirmationDialog(model.restoreMode == .replace ? "استبدل بيانات مدار بهذه النسخة؟" : "ادمج النسخة مع بيانات مدار؟", isPresented: $confirmingRestore, titleVisibility: .visible) {
                Button(model.restoreMode == .replace ? "استبدل بعد نسخة أمان" : "ادمج النسخة", role: model.restoreMode == .replace ? .destructive : nil, action: model.restore)
            } message: {
                Text(BackupCopy.restoreConfirmation(mode: model.restoreMode, keyConfigured: model.status?.keyConfigured != false))
            }
            .alert("لم يكتمل الإجراء", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("حسنًا") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
    }

    private func heading(_ title: String, _ symbol: String) -> some View {
        Label { Text(title).font(MadarTypography.section()) } icon: { Image(systemName: symbol).foregroundStyle(theme.color("accentText")) }
    }
    private func note(_ text: String) -> some View {
        Text(text).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
    }

    /// What is protected now, when the next copy is due, how large it is, and where it lives.
    @ViewBuilder private var statusCard: some View {
        MadarCard {
            if let status = model.status {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: status.lastSuccess == nil ? "shield" : "lock.shield.fill").font(.title2)
                            .foregroundStyle(theme.color("accentText")).frame(width: 44, height: 44).background(theme.background, in: .rect(cornerRadius: 14)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            if let success = status.lastSuccess {
                                Text("آخر نسخة ناجحة").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                                let labels = dates(success)
                                MadarDateLabel(.init(primary: labels.primary + "، " + time(success), secondary: labels.secondary), primaryFont: MadarTypography.section())
                            } else {
                                Text("لم تُحفظ نسخة بعد").font(MadarTypography.section())
                                note("أول نسخة مشفّرة تحدد كلمة المرور، وبعدها يعمل النسخ التلقائي وحده.")
                            }
                        }
                    }
                    if let next = nextLine(status) { note(next).accessibilityIdentifier("backup-next") }
                    if status.schedule != .manual {
                        note("يحاول مدار النسخ في الخلفية عندما يسمح الجهاز، ويُستدرك عند فتحه. موعد التنفيذ غير مضمون.")
                            .accessibilityIdentifier("backup-background-policy")
                    }
                    if let result = status.lastResult, status.lastResult != "آخر عملية نسخ نجحت." { Text(result).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                    Divider().overlay(theme.line)
                    HStack {
                        Text("موعد النسخ").font(MadarTypography.body())
                        Spacer()
                        Picker("موعد النسخ", selection: Binding(get: { status.schedule }, set: { model.setSchedule($0) })) {
                            ForEach(BackupUISchedule.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.menu).disabled(model.busy).accessibilityIdentifier("backup-schedule")
                    }
                    if let bytes = status.estimatedBytes { Text("حجم النسخة الآن نحو " + size(bytes) + ".").font(MadarTypography.body()).accessibilityIdentifier("backup-size") }
                    if let bytes = status.estimatedBytes, bytes > 256 * 1024 * 1024 {
                        // RD4: say before the backup runs that big book files will stay out of it.
                        note("هذا أكبر مما تتسع له النسخة، فتبقى ملفات كتب كبيرة خارجها، بدءًا بكتب تراث. تبقى الكتب على جهازك، ونسمّيها لك بعد النسخ.")
                            .accessibilityIdentifier("backup-size-over")
                    }
                    Text("النسخ المحفوظة: \(digits(status.automaticCount)) تلقائية، \(digits(status.manualCount)) يدوية.").font(MadarTypography.body())
                        .accessibilityIdentifier("backup-saved-counts")
                    note("نحتفظ بآخر أربع نسخ تلقائية وكل النسخ اليدوية.")
                    if !status.excludedBooks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("كتب لم تدخل آخر نسخة لكبر حجمها").font(MadarTypography.body())
                            ForEach(status.excludedBooks, id: \.self) { book in
                                note("• " + book.title + "، " + size(book.bytes) + (book.fromTurath ? "، يُنزَّل من تراث مجددًا" : "، احتفظ بملفه الأصلي"))
                            }
                        }.accessibilityElement(children: .combine).accessibilityIdentifier("backup-excluded-books")
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "internaldrive").foregroundStyle(theme.secondaryInk).accessibilityHidden(true)
                        note("النسخ محفوظة داخل مدار على هذا الجهاز، وتُحذف إن حذفت التطبيق. احفظ نسخة يدوية في «الملفات» أو على حاسوبك.")
                    }.accessibilityElement(children: .combine)
                }
            } else { ProgressView("يقرأ حالة النسخ…").frame(maxWidth: .infinity, minHeight: 80) }
        }
    }
    private var folderCard: some View {
        MadarCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("نسخة في «الملفات»", systemImage: "folder.badge.shieldcheckmark").font(MadarTypography.section())
                if let status = model.status, let name = status.folderName {
                    Text(name).font(MadarTypography.body()).accessibilityIdentifier("backup-folder-name")
                    if let copied = status.folderCopiedAt {
                        Text("آخر نسخة إلى المجلد").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        let labels = dates(copied)
                        MadarDateLabel(.init(primary: labels.primary + "، " + time(copied), secondary: labels.secondary))
                    } else if status.automaticCount + status.manualCount == 0 {
                        note("لم تُنسخ ملفات إلى هذا المجلد بعد. أنشئ نسخة مشفّرة أولًا.")
                    } else { note("لم تصل نسخة إلى هذا المجلد بعد.") }
                    if status.folderUploadConfirmed == true {
                        note("أكّد iCloud رفع آخر نسخة.").accessibilityIdentifier("backup-folder-uploaded")
                    } else if status.folderUploadConfirmed == false {
                        note("النسخة في مجلد iCloud؛ لم يكتمل رفعها بعد.")
                    } else if status.folderCopiedAt != nil { note("نُسخت الملفات إلى المجلد في التاريخ أعلاه، ولا تتوفر معلومات مؤكدة عن رفعها للسحابة.") }
                    if let message = status.folderMessage { note(message).accessibilityIdentifier("backup-folder-message") }
                    HStack {
                        Button("أعد المحاولة", action: model.retryFolder).accessibilityIdentifier("backup-folder-retry")
                        Spacer()
                        Button("غيّر المجلد") { choosingFolder = true }.accessibilityIdentifier("backup-folder-change")
                    }.font(MadarTypography.caption()).frame(minHeight: 44)
                    Button("أوقف النسخ إلى المجلد", action: model.clearFolder).font(MadarTypography.caption()).frame(minHeight: 44)
                        .accessibilityIdentifier("backup-folder-clear")
                } else {
                    note("اختر مجلدًا في iCloud Drive لتبقى نسخة مشفّرة عند فقدان الجهاز. المجلد في «على الـ iPhone» يبقى على الجهاز نفسه.")
                    Button("اختر مجلدًا في الملفات") { choosingFolder = true }.buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("backup-folder-choose")
                }
                note("تُنسخ الملفات المشفّرة فقط، بعد إنشائها وعند فتح مدار. نحتفظ بآخر أربع نسخ تلقائية وكل اليدوية. تغيير المجلد أو إيقافه يبقي الملفات السابقة.")
                if model.status?.canUndoFolderChange == true {
                    Button("تراجع عن تغيير المجلد", action: model.undoFolderChange).font(MadarTypography.caption()).frame(minHeight: 44).accessibilityIdentifier("backup-folder-undo")
                }
            }.disabled(model.busy)
        }
    }
    private func nextLine(_ status: BackupUIStatus) -> String? {
        guard status.schedule != .manual else { return "النسخ يدوي فقط؛ اضغط «انسخ الآن» متى شئت." }
        guard status.keyConfigured else { return nil }
        guard let last = status.lastSuccess else { return "تنتظر أول نسخة تلقائية فرصةً في الخلفية أو فتح مدار." }
        let next = last.addingTimeInterval(status.schedule == .daily ? 86_400 : 7 * 86_400)
        if next <= .now { return "حلّ موعد النسخة التالية؛ ستُحاوَل في الخلفية أو عند فتح مدار." }
        let labels = dates(next)
        return "موعد المحاولة التالية: " + labels.primary + (labels.secondary.isEmpty ? "" : "، " + labels.secondary)
    }

    @ViewBuilder private var encryptedCard: some View {
        @Bindable var model = model
        MadarCard {
            VStack(alignment: .leading, spacing: 12) {
                heading("نسخة مشفّرة", "lock.doc")
                note("تشمل بياناتك وصورها وصوتها؛ إعدادات هذا الجهاز لا تدخل في النسخة.")
                SecureField("كلمة مرور — عشرة أحرف على الأقل", text: $model.exportPassphrase).textContentType(.newPassword).focused($focusedPassword, equals: 1).submitLabel(.next).onSubmit { focusedPassword = 2 }
                    .padding(12).background(theme.background, in: .rect(cornerRadius: 12)).accessibilityIdentifier("backup-password")
                SecureField("أعِد كلمة المرور", text: $model.exportConfirmation).textContentType(.newPassword).focused($focusedPassword, equals: 2).submitLabel(.done).onSubmit { focusedPassword = nil }
                    .padding(12).background(theme.background, in: .rect(cornerRadius: 12)).accessibilityIdentifier("backup-password-confirmation")
                note("احفظ كلمة المرور في مكان آمن. فقدانها يجعل النسخة غير قابلة للقراءة.")
                if model.status?.keyConfigured == false { note("تُستخدم كلمة مرور أول نسخة للنسخ التلقائي أيضًا. يُحفظ مفتاح مشتق منها على هذا الجهاز، وتبقى كلمة المرور عندك.").accessibilityIdentifier("backup-key-setup") }
                exportButton.buttonStyle(MadarPrimaryButton())
                if model.exportedURL != nil {
                    Button(action: model.shareEncrypted) { Label("احفظ النسخة أو شاركها", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44) }.disabled(model.busy).accessibilityIdentifier("backup-export")
                }
            }
        }
    }

    @ViewBuilder private var restoreCard: some View {
        @Bindable var model = model
        MadarCard {
            VStack(alignment: .leading, spacing: 12) {
                heading("استعادة نسخة", "arrow.counterclockwise")
                note("الفحص والمعاينة لا يغيران بياناتك. تبدأ الاستعادة بعد اختيارك وتأكيدك.")
                Button("اختر ملف النسخة") { importing = true }.frame(minHeight: 44).disabled(model.busy).accessibilityIdentifier("restore-select-file")
                if let file = model.selectedFile { Text(file.lastPathComponent).font(MadarTypography.caption()) }
                SecureField("كلمة مرور النسخة", text: $model.restorePassphrase).textContentType(.password).focused($focusedPassword, equals: 3).submitLabel(.done).onSubmit { focusedPassword = nil }
                    .padding(12).background(theme.background, in: .rect(cornerRadius: 12)).accessibilityIdentifier("restore-password")
                Button("افحص وعاين", action: model.inspect).frame(minHeight: 44).disabled(!model.canInspect).accessibilityIdentifier("restore-inspect")
                if let preview = model.preview { Divider().overlay(theme.line); previewRows(preview) }
            }
        }
    }

    @ViewBuilder private var plainCard: some View {
        MadarCard {
            VStack(alignment: .leading, spacing: 12) {
                heading("تصدير بياناتك", "square.and.arrow.up.on.square")
                note("ملف ZIP غير مشفّر يحتوي سجلاتك بصيغة JSONL وصورها وصوتها، ويمكن فتحه خارج مدار. شاركه مع من تثق به. إعدادات هذا الجهاز وقفل التطبيق لا تدخل فيه.")
                Button("جهّز ملف التصدير", action: model.exportPlain).frame(minHeight: 44).disabled(model.busy).accessibilityIdentifier("plain-export-now")
                if model.plainExportedURL != nil {
                    Button(action: model.sharePlain) { Label("احفظ التصدير أو شاركه", systemImage: "square.and.arrow.up") }.frame(minHeight: 44).disabled(model.busy).accessibilityIdentifier("plain-export-share")
                }
            }
        }
    }
    private func size(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb < 1 ? "أقل من ميغابايت" : digits(Int(mb.rounded())) + " ميغابايت"
    }
    @ViewBuilder private var exportButton: some View {
        let button = Button("انسخ الآن", action: model.export).disabled(!model.canExport).accessibilityIdentifier("backup-now")
        #if DEBUG
        if let diagnostic = fixtureInputDiagnostic {
            button.accessibilityValue(Text(verbatim: diagnostic))
        } else { button }
        #else
        button
        #endif
    }
    @ViewBuilder private var keyboardDoneButton: some View {
        let button = Button("تم") { focusedPassword = nil }.accessibilityIdentifier("backup-keyboard-done")
        #if DEBUG
        if let diagnostic = fixtureInputDiagnostic {
            // AX3 virtualizes the export row while a secure field is focused.
            // Read the same non-secret state on the visible keyboard accessory.
            button.accessibilityValue(Text(verbatim: diagnostic + ";can-export=" + String(model.canExport)))
        } else { button }
        #else
        button
        #endif
    }
    #if DEBUG
    private var fixtureInputDiagnostic: String? {
        guard let fixture = ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"], UUID(uuidString: fixture) != nil else { return nil }
        // Only an isolated UI fixture exposes counts and state, never passwords.
        return "passphrase-count=" + String(model.exportPassphrase.count)
            + ";confirmation-count=" + String(model.exportConfirmation.count)
            + ";matches=" + String(model.exportPassphrase == model.exportConfirmation)
            + ";busy=" + String(model.busy)
    }
    #endif
    @ViewBuilder private func previewRows(_ preview: BackupRestorePreview) -> some View {
        Text("معاينة \(preview.fileName)").font(MadarTypography.section())
        MadarDateLabel(dates(preview.createdAt))
        ForEach(preview.counts) { row in
            LabeledContent(row.title) { Text("حاليًا \(digits(row.current))، في النسخة \(digits(row.saved))") }
        }
        Text("إضافة \(digits(preview.additions))، تحديث \(digits(preview.updates))، حذف عند الاستبدال \(digits(preview.deletions))")
        if let first = preview.earliestDate, let last = preview.latestDate {
            let a = dates(first), b = dates(last)
            MadarDateLabel(.init(primary: "الفترة: " + a.primary + " — " + b.primary, secondary: a.secondary.isEmpty ? "" : a.secondary + " — " + b.secondary))
        }
        if preview.skippedCount > 0 { Text(BackupCopy.skipped(count: preview.skippedCount, formattedCount: digits(preview.skippedCount))) }
        ForEach(preview.warnings, id: \.self) { Text($0).foregroundStyle(theme.secondaryInk) }
        Picker("طريقة الاستعادة", selection: $model.restoreMode) {
            Text("دمج").tag(BackupUIRestoreMode.merge)
            Text("استبدال").tag(BackupUIRestoreMode.replace)
        }.pickerStyle(.segmented).disabled(model.busy).accessibilityIdentifier("restore-mode")
        Text(model.restoreMode == .replace ? "سيُستبدل محتوى مدار على هذا الجهاز." : "تبقى السجلات الحالية، وتُصالح معها النسخة.").font(MadarTypography.caption())
        Button("استعد النسخة") { confirmingRestore = true }.buttonStyle(MadarPrimaryButton()).disabled(model.busy).accessibilityIdentifier("restore-confirm")
    }
    private func digits(_ number: Int) -> String { MadarNumberFormatter(style: numerals).string(number) }
    private var resultCopy: String? {
        guard let result = model.restoreResult else { return model.resultMessage }
        return BackupCopy.restoreSummary(result, numerals: numerals)
    }
}
