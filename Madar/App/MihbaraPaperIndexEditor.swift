import SwiftUI
import UIKit
import VisionKit
import MadarCore
import MadarDesign

private struct PaperChapterDraft: Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var page = ""
    var source: PaperBookPageSource = .unknown

    var model: PaperBookChapter? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        let pageNumber = MihbaraPaperIndexEditor.integer(page)
        let pageSource: PaperBookPageSource = page.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .unknown : source
        return PaperBookChapter(id: id, title: cleanTitle, page: pageNumber, pageSource: pageSource)
    }
}

private struct PaperIndexDraftSnapshot: Equatable {
    let title: String
    let author: String
    let isbn13: String
    let pages: String
    let positionPage: String
    let firstPage: String
    let chapters: [PaperChapterDraft]
    let shelf: String
}

struct MihbaraPaperIndexEditor: View {
    let app: AppSession
    let readingBooks: [MihbaraBook]
    let onSaved: () -> Void
    let existingBook: MihbaraBook?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var title = ""
    @State private var author = ""
    @State private var isbn13 = ""
    @State private var pages = ""
    @State private var positionPage = "٠"
    @State private var firstPage = ""
    @State private var chapters: [PaperChapterDraft] = [.init()]
    @State private var shelf = "reading"
    @State private var saving = false
    @State private var identity = UUID()
    @State private var choosingSlot = false
    @State private var scanningBarcode = false
    @State private var scanningIndexPage = false
    @State private var hasReadIndexPage = false
    @State private var status = ""
    @State private var errorMessage: String?
    @State private var originalSnapshot: PaperIndexDraftSnapshot
    @State private var confirmDiscard = false

    private var digits: MadarNumberFormatter { AppMihbaraService(app: app).digits }
    private var scanCanRun: Bool { VNDocumentScanAvailability.supported }
    private var draftSnapshot: PaperIndexDraftSnapshot {
        .init(title: title, author: author, isbn13: isbn13, pages: pages, positionPage: positionPage,
              firstPage: firstPage, chapters: chapters, shelf: shelf)
    }
    private var hasUnsavedChanges: Bool { draftSnapshot != originalSnapshot }
    private var shelfTitle: String {
        switch shelf { case "want": "أبي أقرأه"; case "finished": "أنهيته"; case "old": "قرأته قديمًا"; default: "أقرؤه الآن" }
    }

    init(app: AppSession, readingBooks: [MihbaraBook], onSaved: @escaping () -> Void, existingBook: MihbaraBook? = nil) {
        self.app = app
        self.readingBooks = readingBooks
        self.onSaved = onSaved
        self.existingBook = existingBook

        let digits = AppMihbaraService(app: app).digits
        var decodedChapters: [PaperBookChapter] = []
        if let existingBook, let tocJSON = existingBook.tocJSON {
            decodedChapters = PaperBookIndex.decode(tocJSON, pages: existingBook.pages) ?? []
        }
        let drafts = decodedChapters.map {
            PaperChapterDraft(id: $0.id, title: $0.title, page: $0.page.map(digits.string) ?? "", source: $0.pageSource)
        }
        let initialTitle = existingBook?.title ?? ""
        let initialAuthor = existingBook?.author ?? ""
        let initialISBN13 = existingBook?.isbn13 ?? ""
        let initialPages = existingBook?.pages.map(digits.string) ?? ""
        let initialPosition = existingBook?.page.map(digits.string) ?? "" // AU-40: an unstarted book is empty, not «صفحة ٠».
        let initialFirstPage = drafts.first?.page ?? ""
        let initialShelf = existingBook?.shelf ?? "reading"
        let initialChapters: [PaperChapterDraft] = drafts.isEmpty ? [.init()] : drafts
        _originalSnapshot = State(initialValue: .init(title: initialTitle, author: initialAuthor, isbn13: initialISBN13,
            pages: initialPages, positionPage: initialPosition, firstPage: initialFirstPage, chapters: initialChapters, shelf: initialShelf))
        _title = State(initialValue: initialTitle)
        _author = State(initialValue: initialAuthor)
        _isbn13 = State(initialValue: initialISBN13)
        _pages = State(initialValue: initialPages)
        _positionPage = State(initialValue: initialPosition)
        _firstPage = State(initialValue: initialFirstPage)
        _chapters = State(initialValue: initialChapters)
        _shelf = State(initialValue: initialShelf)
        _identity = State(initialValue: existingBook?.id ?? UUID())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button { if hasUnsavedChanges { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil); confirmDiscard = true } else { dismiss() } } label: {
                        Label("رجوع", systemImage: "chevron.right")
                            .font(MadarTypography.caption())
                            .frame(minHeight: 44)
                    }
                    .disabled(saving).accessibilityIdentifier("mihbara-paper-back")
                    Spacer()
                    Text("كتاب ورقي").font(.custom("thmanyahserifdisplay-Bold", size: 24, relativeTo: .title2))
                    Spacer().frame(width: 48)
                }

                HStack(spacing: 12) {
                    scanAction("امسح الباركود", symbol: "barcode.viewfinder", id: "mihbara-paper-scan-barcode") {
                        scanningBarcode = true
                    }
                    scanAction("صوّر صفحة الفهرس", symbol: "text.viewfinder", id: "mihbara-paper-scan-index") {
                        guard scanCanRun else { status = "التصوير غير متاح على هذا الجهاز؛ يمكنك إدخال الفصول يدويًا."; return }
                        scanningIndexPage = true
                    }
                }

                bookCard

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .trailing, spacing: 7) {
                        Text("يبدأ الفصل الأول في طبعتك ص").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        TextField("الصفحة", text: firstPageBinding)
                            .font(MadarTypography.body())
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .padding(15)
                            .background(theme.surface, in: .rect(cornerRadius: 12))
                            .accessibilityIdentifier("mihbara-paper-first-page")
                    }
                    VStack(alignment: .trailing, spacing: 7) {
                        Text("صفحات طبعتك").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        TextField("عدد الصفحات", text: $pages)
                            .font(MadarTypography.body())
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .padding(15)
                            .background(theme.surface, in: .rect(cornerRadius: 12))
                            .accessibilityIdentifier("mihbara-paper-pages")
                    }
                }

                if existingBook != nil {
                    VStack(alignment: .trailing, spacing: 7) {
                        Text("وصلت إلى صفحة").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        TextField("لم أبدأ بعد", text: $positionPage)
                            .font(MadarTypography.body())
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .padding(15)
                            .background(theme.surface, in: .rect(cornerRadius: 12))
                            .accessibilityIdentifier("mihbara-paper-position")
                    }
                }

                VStack(spacing: 0) {
                    ForEach(chapters.indices, id: \.self) { index in
                        chapterRow(index: index)
                        if index < chapters.count - 1 { Divider().overlay(theme.line).padding(.horizontal, 2) }
                    }
                    Button {
                        guard chapters.count < PaperBookIndex.maximumChapters else { return }
                        chapters.append(.init())
                    } label: {
                        Label("أضف فصلًا", systemImage: "plus")
                            .font(MadarTypography.caption())
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .accessibilityIdentifier("mihbara-paper-add-chapter")
                }
                .padding(.horizontal, 16)
                .background(theme.surface, in: .rect(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line, lineWidth: 1) }

                Text("الصفحات التقديرية تتضح كلما سجّلت تقدّمك؛ راجعها على طبعتك.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                if !status.isEmpty {
                    Text(status).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("mihbara-paper-index-status")
                }
                Button(saving ? "يُحفظ…" : "احفظ الفهرس") { save() }
                    .buttonStyle(MadarPrimaryButton())
                    .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("mihbara-paper-save")
            }
            .padding(.horizontal, 22).padding(.top, 0).padding(.bottom, 28)
            .frame(maxWidth: 650).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.background.ignoresSafeArea())
        .foregroundStyle(theme.ink)
        .environment(\.layoutDirection, .rightToLeft)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .sheet(isPresented: $scanningBarcode) {
            PaperBarcodeScannerSheet(onISBN: { value in
                isbn13 = value
                status = "قُرئ الباركود؛ اكتب العنوان والمؤلف يدويًا."
                scanningBarcode = false
            }, onError: { errorMessage = $0 })
            .presentationDetents([.large])
        }
        .sheet(isPresented: $scanningIndexPage) {
            PaperIndexDocumentScanner(isPresented: $scanningIndexPage, onLines: applyOCRLines, onError: { errorMessage = $0 })
                .ignoresSafeArea()
        }
        .confirmationDialog("اختر كتابًا يرجع إلى أبي أقرأها", isPresented: $choosingSlot, titleVisibility: .visible) {
            ForEach(readingBooks) { old in Button(old.title) { save(replacing: old.id) } }
        }
        .confirmationDialog("تتجاهل تعديلات الفهرس؟", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("تجاهل التعديلات", role: .destructive) { dismiss() }.accessibilityIdentifier("mihbara-paper-discard")
            Button("أكمل الكتابة") { }.accessibilityIdentifier("mihbara-paper-continue")
        } message: { Text("الفهرس غير محفوظ.") }
        .interactiveDismissDisabled(hasUnsavedChanges || saving)
        .alert("تعذّر الإكمال", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("حسنًا", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("تمّ") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } } }
        .task { loadUITestDraftIfRequested() }
    }

    private var bookCard: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.ink)
                .frame(width: 56, height: 88)
                .overlay { Image(systemName: "book.closed").font(.title3).foregroundStyle(theme.background.opacity(0.82)) }
                .accessibilityHidden(true)
            VStack(alignment: .trailing, spacing: 7) {
                TextField("عنوان الكتاب", text: $title)
                    .font(MadarTypography.section())
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("mihbara-paper-title")
                TextField("المؤلف", text: $author)
                    .font(MadarTypography.caption())
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(theme.secondaryInk)
                    .accessibilityIdentifier("mihbara-paper-author")
                HStack {
                    Text("كتاب ورقي · \(shelfTitle)")
                        .font(MadarTypography.fine())
                        .foregroundStyle(theme.secondaryInk)
                    Spacer(minLength: 6)
                    if existingBook == nil {
                        Menu {
                            Button("أقرؤه الآن") { shelf = "reading" }
                            Button("أبي أقرأه") { shelf = "want" }
                            Button("أنهيته") { shelf = "finished" }
                        } label: {
                            Label("الرف", systemImage: "chevron.down")
                                .font(MadarTypography.fine())
                                .foregroundStyle(theme.secondaryInk)
                        }
                        .accessibilityIdentifier("mihbara-paper-shelf")
                    }
                }
                TextField("ISBN-13، إن توفر", text: $isbn13)
                    .font(MadarTypography.caption())
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("mihbara-paper-isbn")
                if hasReadIndexPage {
                Text("صوّرت صفحة الفهرس؛ راجع العناوين.")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .background(theme.surface, in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line, lineWidth: 1) }
    }

    private func scanAction(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: symbol).font(.title2)
                Text(title).font(MadarTypography.section())
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(theme.surface, in: .rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line, lineWidth: 1) }
        }
        .buttonStyle(.madarPlain)
        .accessibilityIdentifier(id)
    }

    private func chapterRow(index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("عنوان الفصل", text: $chapters[index].title, axis: .vertical)
                    .font(MadarTypography.section())
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("mihbara-paper-chapter-title-\(index)")
            }
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                TextField("ص", text: $chapters[index].page)
                    .font(MadarTypography.section())
                    .multilineTextAlignment(.leading)
                    .keyboardType(.numberPad)
                    .frame(width: 58)
                    .accessibilityIdentifier("mihbara-paper-chapter-page-\(index)")
                    .onChange(of: chapters[index].page) { _, value in
                        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { chapters[index].source = .unknown }
                        else if chapters[index].source == .unknown { chapters[index].source = .entered }
                        if index == 0 { firstPage = value }
                    }
                Menu {
                    Button("أدخلتها") { chapters[index].source = .entered }
                    Button("تقديري") { chapters[index].source = .estimated }
                    Button("لم أحدد الصفحة") { chapters[index].source = .unknown; chapters[index].page = "" }
                    if chapters.count > 1 {
                        Button("احذف الفصل", role: .destructive) { chapters.remove(at: index) }
                    }
                } label: {
                    Text(pageSourceLabel(chapters[index]))
                        .font(MadarTypography.fine())
                        .foregroundStyle(theme.secondaryInk)
                }
                .accessibilityIdentifier("mihbara-paper-page-source-\(index)")
            }
        }
        .padding(.vertical, 12)
    }

    private var firstPageBinding: Binding<String> {
        Binding(get: { firstPage }, set: { value in
            firstPage = value
            guard !chapters.isEmpty else { chapters = [.init(page: value, source: value.isEmpty ? .unknown : .estimated)]; return }
            chapters[0].page = value
            if value.isEmpty { chapters[0].source = .unknown }
            else if chapters[0].source == .unknown { chapters[0].source = .entered }
        })
    }

    private func pageSourceLabel(_ draft: PaperChapterDraft) -> String {
        switch draft.source { case .entered: "أدخلتها"; case .estimated: "تقديري"; case .unknown: "لم أحدد الصفحة" }
    }

    private func save(replacing: UUID? = nil) {
        if existingBook == nil, shelf == "reading", readingBooks.count >= 3, replacing == nil { choosingSlot = true; return }
        let pageCount: Int?
        if pages.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { pageCount = nil }
        else {
            guard let value = Self.integer(pages), (1...100_000).contains(value) else { errorMessage = "اكتب عدد صفحات بين ١ و١٠٠٬٠٠٠."; return }
            pageCount = value
        }
        let normalizedISBN: String?
        if isbn13.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { normalizedISBN = nil }
        else {
            guard let value = PaperBookIndex.normalizedISBN13(isbn13) else { errorMessage = "تحقق من رقم ISBN-13 والرقم الأخير."; return }
            normalizedISBN = value
        }
        let models = chapters.compactMap(\.model)
        guard chapters.allSatisfy({ $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.model != nil }),
              PaperBookIndex.isValid(models, pages: pageCount) else { errorMessage = "راجع عناوين الفصول وترتيب الصفحات ضمن طبعتك."; return }
        let tocData = models.isEmpty ? nil : PaperBookIndex.encode(models, pages: pageCount)
        guard models.isEmpty || tocData != nil else { errorMessage = "الفهرس أطول من الحد المسموح."; return }
        let position: Int?
        if existingBook != nil {
            guard let value = positionPage.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : Self.integer(positionPage), (0...100_000).contains(value) else { errorMessage = "اكتب رقم صفحة صحيحًا"; return }
            position = value
        } else {
            position = nil
        }

        let command: String
        var payload: [String: MadarCore.JSONValue]
        if existingBook != nil {
            command = "book.updatePaper"
            payload = [
                "id": .string(identity.uuidString),
                "title": .string(title),
                "author": .string(author),
                "pages": pageCount.map { .number(Double($0)) } ?? .null,
                "position": .number(Double(position ?? 0)),
                "isbn13": normalizedISBN.map { .string($0) } ?? .null,
                "tocJSON": tocData.flatMap { String(data: $0, encoding: .utf8) }.map { .string($0) } ?? .null
            ]
        } else {
            command = "book.savePaper"
            payload = ["id": .string(identity.uuidString), "title": .string(title), "author": .string(author), "shelf": .string(shelf)]
            if let pageCount { payload["pages"] = .number(Double(pageCount)) }
            if let normalizedISBN { payload["isbn13"] = .string(normalizedISBN) }
            if let tocData, let tocText = String(data: tocData, encoding: .utf8) { payload["tocJSON"] = .string(tocText) }
            if let replacing { payload["replacing"] = .string(replacing.uuidString) }
        }
        saving = true
        Task {
            do {
                try await app.executeBookCommand(command, payload: payload)
                if existingBook != nil { dismiss() }
                onSaved()
            }
            catch { app.errorMessage = madarUserMessage(error) }
            saving = false
        }
    }

    private func applyOCRLines(_ lines: [String]) {
        let total = Self.integer(pages)
        let parsed = PaperBookIndex.chapters(fromOCRLines: lines, totalPages: total)
        guard !parsed.isEmpty else {
            status = "لم نجد عناوين واضحة بأرقام صفحات؛ يمكنك إدخالها يدويًا."
            return
        }
        chapters = parsed.map { .init(id: $0.id, title: $0.title, page: $0.page.map(digits.string) ?? "", source: .estimated) }
        firstPage = chapters.first?.page ?? ""
        hasReadIndexPage = true
        status = "الفصول المكتشفة: \(digits.string(parsed.count)). راجع كل عنوان وصفحة قبل الحفظ؛ تبقى الأرقام تقديرية حتى تثبّتها."
    }

    private func loadUITestDraftIfRequested() {
        #if DEBUG
        let root = app.bookStagingDirectory
        guard root.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "UITestStores",
              ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_PAPER_INDEX_FIXTURE"] == "1" else { return }
        title = "دفتر البدايات"
        author = "من مكتبتي"
        pages = digits.string(120)
        chapters = [
            .init(title: "مدخل إلى القراءة", page: digits.string(1), source: .entered),
            .init(title: "ملاحظات الطريق", page: digits.string(24), source: .estimated),
            .init(title: "أدوات للتأمل", page: digits.string(38), source: .estimated),
            .init(title: "تجارب صغيرة", page: digits.string(59), source: .estimated),
            .init(title: "خطوات يومية", page: digits.string(77), source: .estimated),
            .init(title: "خاتمة الدفتر", page: digits.string(104), source: .estimated)
        ]
        firstPage = chapters[0].page
        hasReadIndexPage = true
        originalSnapshot = draftSnapshot
        #endif
    }

    fileprivate nonisolated static func integer(_ text: String) -> Int? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.allSatisfy({ $0.wholeNumberValue.map { (0...9).contains($0) } == true }) else { return nil }
        return Int(clean.compactMap { $0.wholeNumberValue.map(String.init) }.joined())
    }
}

private enum VNDocumentScanAvailability {
    @MainActor static var supported: Bool { VNDocumentCameraViewController.isSupported }
}
