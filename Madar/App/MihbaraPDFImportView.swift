import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import MadarDesign

@MainActor extension AppMihbaraService {
    func stagePDF(_ source: URL, id: UUID) async throws -> PDFBookInspection {
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        let root = app.bookStagingDirectory
        let inspection = try await Task.detached(priority: .userInitiated) {
            try PDFBookFiles.stage(source: source, root: root, id: id)
        }.value
        do {
            guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
            _ = try AppMihbaraService(app: app).bookRestorableFromFile(sha256: inspection.sha256, sizeBytes: inspection.sizeBytes, formats: ["pdf", "pdfScanned"])
            return inspection
        } catch { PDFBookFiles.discard(id: id, root: root); throw error }
    }

    func confirmPDF(_ inspection: PDFBookInspection, bookID: UUID, commandID: UUID, title: String, author: String, language: String) async throws {
        let service = AppMihbaraService(app: app)
        if let existing = try service.bookRestorableFromFile(sha256: inspection.sha256, sizeBytes: inspection.sizeBytes, formats: ["pdf", "pdfScanned"]) {
            try await app.executeBookCommand("book.restoreFile", payload: [
                "id": .string(existing.id.uuidString), "fileID": .string(inspection.id.uuidString), "sha256": .string(inspection.sha256)
            ], id: commandID, undoMessage: "أُعيد ملف الكتاب")
        } else {
            try await app.executeBookCommand("book.importPDF", payload: [
                "id": .string(bookID.uuidString), "fileID": .string(inspection.id.uuidString),
                "sha256": .string(inspection.sha256), "title": .string(title), "author": .string(author), "language": .string(language)
            ], id: commandID)
        }
        PDFBookFiles.discard(id: inspection.id, root: app.bookStagingDirectory)
    }
}

struct MihbaraPDFImportView: View {
    let app: AppSession
    let source: URL
    let onImported: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var fileID = UUID()
    @State private var bookID = UUID()
    @State private var commandID = UUID()
    @State private var inspection: PDFBookInspection?
    // AU-36: a dimmed add button names what it waits for.
    private var waiting: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "اكتب عنوان الكتاب لتضيفه" }
        if title.count > 300 { return "العنوان أطول من ٣٠٠ حرف" }
        if author.count > 300 { return "اسم المؤلف أطول من ٣٠٠ حرف" }
        return nil
    }
    @State private var recoveryBook: MihbaraBook?
    @State private var title = ""
    @State private var author = ""
    @State private var language = "ar"
    @State private var error: String?
    @State private var saving = false
    @State private var finished = false
    @State private var confirmedMetadata: [String]?
    private var service: AppMihbaraService { .init(app: app) }
    private var digits: MadarNumberFormatter { service.digits }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    Text("من ملف").font(.custom("thmanyahserifdisplay-Bold", size: 21, relativeTo: .title2))
                    HStack {
                        Button { dismiss() } label: { Label("رجوع", systemImage: "chevron.right").font(MadarTypography.caption()).frame(minHeight: 44) }
                            .disabled(saving).accessibilityIdentifier("mihbara-import-back")
                        Spacer()
                    }
                }
                HStack(spacing: 10) {
                    Text(inspection.map { $0.scanned ? "PDF مصوّر" : "PDF" } ?? "PDF")
                        .font(MadarTypography.fine()).foregroundStyle(theme.onAccent).padding(.horizontal, 9).padding(.vertical, 7)
                        .background(theme.accentFill, in: .rect(cornerRadius: 8))
                    Text(source.lastPathComponent).font(MadarTypography.section()).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12).frame(maxWidth: .infinity, minHeight: 58)
                .background(theme.surface, in: .rect(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.line, lineWidth: 1) }

                VStack(alignment: .leading, spacing: 15) {
                    Text(inspection == nil && error == nil ? "أفهم الكتاب…" : "ما وجدناه")
                        .font(MadarTypography.cardTitle())
                    if inspection == nil && error == nil { ProgressView().tint(theme.ink).frame(maxWidth: .infinity).accessibilityLabel("يفحص ملف PDF") }
                    else if inspection != nil {
                        ProgressView(value: 1)
                            .progressViewStyle(.linear)
                            .tint(theme.ink)
                            .accessibilityLabel("اكتمل فحص الملف")
                    }

                    if let value = inspection {
                        row("نوع الملف", detail: value.scanned ? "مصوّر: صفحاته صور بلا طبقة نص." : value.textPages >= value.pages ? "كل صفحاته نصّية وقابلة للبحث." : "بعض صفحاته نصّية (\(digits.string(value.textPages)) من \(digits.string(value.pages)))، والباقي صور.", detected: true)
                        row("اللغة", detail: value.detectedLanguage == "ar" ? "تعرّف النص العربي؛ تُفتح القراءة بالعربية." : value.detectedLanguage == "en" ? "تعرّف النص الإنجليزي؛ تُفتح القراءة بالإنجليزية." : "لا يمكن تحديد اللغة بثقة من هذا الملف؛ اختر لغة القراءة أدناه.", detected: value.detectedLanguage == "ar" || value.detectedLanguage == "en")
                        row("قراءة النص", detail: value.scanned ? "يستخرج مدار نص الصور تقريبيًا على جهازك لتبحث فيه داخل القارئ." : "النص الموجود في الملف محفوظ كما هو؛ صفحات الصور تُقرأ ضوئيًا عند البحث في القارئ.", detected: !value.scanned)
                        row("الفهرس", detail: value.outline.isEmpty ? "بلا فهرس إلكتروني قابل للتنقّل؛ لم نخمن فصول الكتاب." : "فهرس جاهز للتنقّل فيه " + arabicCount(value.outline.count, ["عنوان واحد", "عنوانان", "عناوين", "عنوانًا"], digits) + ".", detected: !value.outline.isEmpty)
                        row("أرقام الصفحات", detail: value.hasPageLabels ? "توجد تسميات صفحات؛ مطابقتها للمطبوع غير متحققة." : "فيه " + arabicCount(value.pages, ["صفحة واحدة", "صفحتان", "صفحات", "صفحة"], digits) + "؛ لم تُكتشف أرقام مطبوعة، فيُشار إليها بترتيبها في الملف.", detected: value.hasPageLabels)
                        row("الحواشي", detail: "لم تُكتشف بنية حواشٍ منفصلة؛ تبقى كما وردت في الصفحة.", detected: false)
                        if let recoveryBook {
                            row("ملف كتابك", detail: "يعود هذا الملف إلى «\(recoveryBook.title)»؛ يبقى رفّه وموضعه وسجل قراءته كما هي.", detected: true)
                        }
                    }
                }

                if let error {
                    Text(error).font(MadarTypography.body()).foregroundStyle(theme.ink).accessibilityIdentifier("mihbara-import-error")
                }
                if inspection != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(recoveryBook == nil ? "على رفّك" : "الكتاب الموجود").font(MadarTypography.section())
                        if let recoveryBook {
                            Text(recoveryBook.title).font(MadarTypography.cardTitle())
                            Text(recoveryBook.author).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            Text("لن ينشأ كتاب مكرر؛ يعود الملف إلى سجلّك المحفوظ.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        } else {
                            TextField("عنوان الكتاب", text: $title, prompt: Text("عنوان الكتاب").foregroundStyle(theme.secondaryInk)).textFieldStyle(.plain).accessibilityIdentifier("mihbara-import-title")
                            TextField("المؤلف، إن عُرف", text: $author, prompt: Text("المؤلف، إن عُرف").foregroundStyle(theme.secondaryInk)).textFieldStyle(.plain).accessibilityIdentifier("mihbara-import-author")
                            Picker("لغة القراءة", selection: $language) { Text("العربية").tag("ar"); Text("الإنجليزية").tag("en") }
                                .font(MadarTypography.caption()).accessibilityIdentifier("mihbara-import-language")
                            Text("يبقى الأصل على جهازك. لا يُضاف شيء حتى تؤكد.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        }
                    }.font(MadarTypography.body()).padding(14).background(theme.surface, in: .rect(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.line.opacity(0.7), lineWidth: 1) }
                        .disabled(saving || confirmedMetadata != nil)
                    if !saving && recoveryBook == nil && confirmedMetadata == nil, let waiting { Text(waiting).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("mihbara-import-waiting") }
                    Button(saving ? (recoveryBook == nil ? "يُضاف…" : "يُعاد الملف…") : (recoveryBook == nil ? "أضفه إلى «أبي أقرأها»" : "أعد الملف إلى الكتاب")) { confirm() }
                        .buttonStyle(MadarPrimaryButton()).disabled(saving || (recoveryBook == nil && (title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 300 || author.count > 300)))
                        .accessibilityIdentifier("mihbara-import-confirm")
                }
            }
            .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 24)
            .frame(maxWidth: 650).frame(maxWidth: .infinity)
        }
        .foregroundStyle(theme.ink).background(theme.background.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft).toolbarVisibility(.hidden, for: .navigationBar).statusBarHidden(true)
        .interactiveDismissDisabled(saving)
        .task { await inspect() }
        .onDisappear { if !saving && !finished { PDFBookFiles.discard(id: fileID, root: app.bookStagingDirectory) } }
    }

    private func row(_ title: String, detail: String, detected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Found → filled check; not in this file → a quiet dash, so information never reads as an unfinished task.
            Image(systemName: detected ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 20, weight: .regular)).foregroundStyle(detected ? theme.color("sunnah") : theme.secondaryInk.opacity(0.6))
                .frame(width: 25).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(MadarTypography.section())
                Text(detail).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine)
    }

    @MainActor private func inspect() async {
        guard inspection == nil, error == nil else { return }
        do {
            let value = try await service.stagePDF(source, id: fileID)
            guard !Task.isCancelled else { PDFBookFiles.discard(id: fileID, root: app.bookStagingDirectory); return }
            recoveryBook = try service.bookRestorableFromFile(sha256: value.sha256, sizeBytes: value.sizeBytes, formats: ["pdf", "pdfScanned"])
            inspection = value
            title = recoveryBook?.title ?? value.title; author = recoveryBook?.author ?? value.author
            language = recoveryBook?.language ?? (value.detectedLanguage == "en" ? "en" : "ar")
        } catch {
            if case DataError.invalidValue(let message) = error { self.error = message }
            else { self.error = "تعذّر فتح الملف المحلي. اختره من الملفات مرة أخرى." }
        }
    }

    @MainActor private func confirm() {
        guard let inspection, !saving else { return }
        if confirmedMetadata == nil { confirmedMetadata = [title, author, language] }
        guard let metadata = confirmedMetadata else { return }
        saving = true; error = nil
        Task { @MainActor in
            do {
                try await service.confirmPDF(inspection, bookID: bookID, commandID: commandID, title: metadata[0], author: metadata[1], language: metadata[2])
                finished = true; saving = false; onImported()
            } catch {
                if case DataError.invalidValue(let message) = error { self.error = message }
                else { self.error = "لم يكتمل الحفظ. أعد المحاولة عندما تكون بيانات مدار مفتوحة." }
                saving = false
            }
        }
    }
}

struct MihbaraImportedPDFSummary: View {
    let book: MihbaraBook
    let fileUnavailable: Bool
    let onRestoreFile: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(book.title).font(MadarTypography.title()); Spacer(); Button("تمّ") { dismiss() } }
            Text(book.author).font(MadarTypography.body())
            Text(book.format == "pdfScanned" ? "ملف PDF مصوّر من جهازك" : "ملف PDF من جهازك").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            if fileUnavailable {
                Text("ملف الكتاب غير موجود على هذا الجهاز. يبقى سجل قراءتك محفوظًا.").font(MadarTypography.body())
                    .accessibilityIdentifier("mihbara-book-file-unavailable")
                Button("أعد استيراد الملف نفسه") { onRestoreFile() }
                    .buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("mihbara-book-file-restore-detail")
            }
            Spacer()
        }.padding(24).foregroundStyle(theme.ink).background(theme.background.ignoresSafeArea())
    }
}
