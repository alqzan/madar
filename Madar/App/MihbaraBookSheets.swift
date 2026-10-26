import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers
import MadarCore
import MadarDesign
import MadarData
import MadarCommands

/// Copy for Mihbara amounts: real quantities in Arabic number agreement instead of abstract fractions.
enum MihbaraCopy {
    static func pages(_ count: Int, _ digits: MadarNumberFormatter) -> String {
        arabicCount(count, ["صفحة واحدة", "صفحتان", "صفحات", "صفحة"], digits)
    }
    static func books(_ count: Int, _ digits: MadarNumberFormatter) -> String {
        arabicCount(count, ["كتاب واحد", "كتابان", "كتب", "كتابًا"], digits)
    }
    static func hadiths(_ count: Int, _ digits: MadarNumberFormatter) -> String {
        arabicCount(count, ["حديث واحد", "حديثان", "أحاديث", "حديثًا"], digits)
    }
    /// The same noun as an object: «فهمت حديثًا واحدًا / حديثين / ٣ أحاديث / ١٢ حديثًا».
    static func hadithsObject(_ count: Int, _ digits: MadarNumberFormatter) -> String {
        arabicCount(count, ["حديثًا واحدًا", "حديثين", "أحاديث", "حديثًا"], digits)
    }
    static func years(_ count: Int, _ digits: MadarNumberFormatter) -> String {
        arabicCount(count, ["سنة واحدة", "سنتين", "سنوات", "سنة"], digits)
    }
    /// «بقيت ٤٠ صفحة» (singular, dual and 3-10 take the feminine verb).
    static func pagesLeft(_ count: Int, _ digits: MadarNumberFormatter) -> String {
        (count <= 10 ? "بقيت " : "بقي ") + pages(count, digits)
    }
    /// «نحو ساعة»: an honest estimate at the app's own pace of 1.4 minutes a page (the same pace «حمّسني» uses).
    static func readingTime(pages count: Int, _ digits: MadarNumberFormatter) -> String {
        let minutes = max(1, Int((Double(count) * 1.4).rounded()))
        if minutes < 60 { return "نحو " + PrayerCopy.minutes(minutes, digits: digits) }
        return "نحو " + PrayerCopy.hours(max(1, Int((Double(minutes) / 60).rounded())), digits: digits)
    }
    /// «بقيت ١٠٣ صفحات، نحو ساعتين», or nil when the book is finished.
    static func remaining(pages total: Int?, read: Int?, _ digits: MadarNumberFormatter) -> String? {
        guard let total, total > 0, let read, read >= 0, read < total else { return nil }
        let left = total - read
        return pagesLeft(left, digits) + "، " + readingTime(pages: left, digits)
    }
    /// How far into a file book the reader is, as pages: progress × the stored page count.
    static func pagesRead(_ book: MihbaraBook) -> Int? {
        guard let total = book.pages, total > 0, let progress = book.progress else { return nil }
        return min(total, max(0, Int((progress * Double(total)).rounded())))
    }
}

struct MihbaraAddBookView: View {
    let app: AppSession
    let readingBooks: [MihbaraBook]
    let onPaperBookSaved: () -> Void
    let onPDFImported: () -> Void
    let onEPUBImported: () -> Void
    let onGoodreadsImported: () -> Void
    @Binding var pendingBookFile: URL?
    @Binding var pendingGoodreadsFile: URL?
    @Binding var pendingGoodreadsStage: GoodreadsCSVStage?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var importingBook = false
    @State private var importingGoodreads = false
    @State private var stagingGoodreads = false
    @State private var previewingPDF = false
    @State private var previewingEPUB = false
    @State private var previewingGoodreads = false

    private var bookTypes: [UTType] {
        [.pdf, UTType("org.idpf.epub-container")!]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Button { dismiss() } label: {
                        Label("رجوع", systemImage: "chevron.right")
                            .font(MadarTypography.caption())
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("mihbara-add-back")
                    Spacer()
                    Text("أضف كتابًا").font(.custom("thmanyahserifdisplay-Bold", size: 24, relativeTo: .title2))
                    Spacer().frame(width: 48)
                }

                VStack(spacing: 12) {
                    Button { importingBook = true } label: {
                        MihbaraAddBookSourceCard(
                            title: "من ملف",
                            subtitle: "EPUB أو PDF من تطبيق الملفات",
                            symbol: "square.and.arrow.down.fill",
                            color: theme.color("navy"),
                            foreground: theme.color("onNavy")
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mihbara-add-source-file")
                    // Each importer sits on its own button: stacked on one view, SwiftUI honours only the last.
                    .fileImporter(isPresented: $importingBook, allowedContentTypes: bookTypes, allowsMultipleSelection: false) { result in
                        handle(result, assign: {
                            pendingBookFile = $0
                            if $0.pathExtension.lowercased() == "epub" { previewingEPUB = true }
                            else { previewingPDF = true }
                        })
                    }

                    NavigationLink {
                        MihbaraTurathView(app: app, onImported: onEPUBImported)
                    } label: {
                        MihbaraAddBookSourceCard(
                            title: "من تراث · المكتبة الشاملة",
                            subtitle: "ابحث عن كتاب ونزّله إلى جهازك",
                            symbol: "books.vertical.fill",
                            color: theme.color("desk"),
                            foreground: theme.color("onDesk")
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mihbara-add-source-turath")

                    NavigationLink {
                        MihbaraPaperIndexEditor(app: app, readingBooks: readingBooks, onSaved: onPaperBookSaved)
                            .toolbarVisibility(.hidden, for: .navigationBar)
                    } label: {
                        MihbaraAddBookSourceCard(
                            title: "كتاب ورقي",
                            subtitle: "اكتب عنوانه، وابدأ من الصفحة التي وصلت إليها",
                            symbol: "barcode.viewfinder",
                            color: theme.color("wood"),
                            foreground: theme.background
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mihbara-add-source-paper")

                    Button { importingGoodreads = true } label: {
                        MihbaraAddBookSourceCard(
                            title: "من Goodreads",
                            subtitle: stagingGoodreads ? "أفحص ملف CSV…" : "استورد مكتبتك من ملف CSV",
                            symbol: "g.circle.fill",
                            color: theme.color("sunnahLeather"),
                            foreground: theme.color("onAccent")
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(stagingGoodreads)
                    .accessibilityIdentifier("mihbara-add-source-goodreads")
                    .fileImporter(isPresented: $importingGoodreads, allowedContentTypes: [.commaSeparatedText], allowsMultipleSelection: false) { result in
                        handleGoodreads(result)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("وصل مؤخرًا").font(MadarTypography.section())
                    if let pendingGoodreadsFile {
                        Button { previewingGoodreads = pendingGoodreadsStage != nil } label: {
                            MihbaraRecentImportRow(name: pendingGoodreadsFile.lastPathComponent, kind: "CSV", theme: theme)
                        }.buttonStyle(.plain).disabled(pendingGoodreadsStage == nil).accessibilityIdentifier("mihbara-goodreads-reopen")
                    }
                    if let pendingBookFile {
                        Button {
                            if pendingBookFile.pathExtension.lowercased() == "epub" { previewingEPUB = true }
                            else { previewingPDF = true }
                        } label: {
                            MihbaraRecentImportRow(name: pendingBookFile.lastPathComponent, kind: pendingBookFile.pathExtension.lowercased() == "epub" ? "EPUB" : "PDF", theme: theme)
                        }.buttonStyle(.plain).accessibilityIdentifier("mihbara-import-reopen")
                    }
                    if pendingBookFile == nil && pendingGoodreadsFile == nil {
                        HStack(spacing: 12) {
                            Image(systemName: "tray").font(.title3).foregroundStyle(theme.secondaryInk)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("لا يوجد ملف وصل مؤخرًا").font(MadarTypography.caption())
                                Text("اختر ملف EPUB أو PDF من تطبيق الملفات.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                        .background(theme.surface, in: .rect(cornerRadius: 20))
                        .overlay { RoundedRectangle(cornerRadius: 20).stroke(theme.line.opacity(0.7), lineWidth: 1) }
                        .accessibilityIdentifier("mihbara-no-recent-import")
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("يقرأ مدار").font(MadarTypography.section())
                    HStack(spacing: 8) {
                        ForEach(["EPUB", "PDF", "PDF مصوّر"], id: \.self) { value in
                            Text(value)
                                .font(MadarTypography.fine())
                                .padding(.horizontal, 11).padding(.vertical, 8)
                                .background(theme.surface, in: .capsule)
                                .overlay { Capsule().stroke(theme.line, lineWidth: 1) }
                        }
                    }
                    Text("كل كتاب يبقى على جهازك ويُقرأ بلا إنترنت؛ البحث في تراث وحده يحتاج الاتصال. راجع معاينته قبل إضافته إلى رفّك.")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
            }
            .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 32)
            .frame(maxWidth: 650).frame(maxWidth: .infinity)
        }
        .background(theme.background.ignoresSafeArea())
        .foregroundStyle(theme.ink)
        .environment(\.layoutDirection, .rightToLeft)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .navigationDestination(isPresented: $previewingPDF) {
            if let pendingBookFile {
                MihbaraPDFImportView(app: app, source: pendingBookFile) {
                    self.pendingBookFile = nil
                    previewingPDF = false
                    onPDFImported()
                }
            }
        }
        .navigationDestination(isPresented: $previewingEPUB) {
            if let pendingBookFile {
                MihbaraEPUBImportView(app: app, source: pendingBookFile) {
                    self.pendingBookFile = nil
                    previewingEPUB = false
                    onEPUBImported()
                }
            }
        }
        .navigationDestination(isPresented: $previewingGoodreads) {
            if let stage = pendingGoodreadsStage {
                MihbaraGoodreadsImportView(app: app, stage: stage) {
                    GoodreadsCSVFiles.discard(id: stage.id, root: app.bookStagingDirectory)
                    pendingGoodreadsStage = nil
                    pendingGoodreadsFile = nil
                    previewingGoodreads = false
                    onGoodreadsImported()
                }
            }
        }
        .task {
            #if DEBUG
            let root = app.bookStagingDirectory
            if root.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "UITestStores",
               let encoded = ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_IMPORT_PDF"], let bytes = Data(base64Encoded: encoded),
               bytes.count < 1024 * 1024, pendingBookFile == nil {
                let fixtureName = ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_IMPORT_PDF_NAME"] ?? "ملف اختبار مصوّر"
                let safeName = String(fixtureName.prefix(80)).replacingOccurrences(of: "/", with: "-")
                let file = root.deletingLastPathComponent().appendingPathComponent("\(safeName).pdf")
                do {
                    // Simulate one file arrival. Reopening Add Book must not inject the
                    // already-confirmed fixture again after the production binding is cleared.
                    if !FileManager.default.fileExists(atPath: file.path) {
                        try bytes.write(to: file, options: .atomic); pendingBookFile = file; previewingPDF = true
                    }
                }
                catch { app.errorMessage = "لم تُجهز عينة الاستيراد." }
            }
            if root.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "UITestStores",
               let encoded = ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_IMPORT_EPUB"], let bytes = Data(base64Encoded: encoded),
               bytes.count < 2 * 1024 * 1024, pendingBookFile == nil {
                let file = root.deletingLastPathComponent().appendingPathComponent("كتاب اختبار.epub")
                do {
                    if !FileManager.default.fileExists(atPath: file.path) {
                        try bytes.write(to: file, options: .atomic); pendingBookFile = file; previewingEPUB = true
                    }
                }
                catch { app.errorMessage = "لم تُجهز عينة الاستيراد." }
            }
            // Owner-book trial: a real book is too large for a launch-environment string, so the test passes its path.
            if root.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "UITestStores",
               let path = ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_IMPORT_EPUB_PATH"], pendingBookFile == nil {
                let file = root.deletingLastPathComponent().appendingPathComponent("كتاب التجربة.epub")
                do {
                    if !FileManager.default.fileExists(atPath: file.path) {
                        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: file); pendingBookFile = file; previewingEPUB = true
                    }
                }
                catch { app.errorMessage = "لم تُجهز عينة الاستيراد." }
            }
            // Owner PDF trial: same as the EPUB path, through the PDF preview and on-device conversion.
            if root.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "UITestStores",
               let path = ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_IMPORT_PDF_PATH"], pendingBookFile == nil {
                let name = String((ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_IMPORT_PDF_NAME"] ?? "كتاب التجربة").prefix(80)).replacingOccurrences(of: "/", with: "-")
                let file = root.deletingLastPathComponent().appendingPathComponent("\(name).pdf")
                do {
                    if !FileManager.default.fileExists(atPath: file.path) {
                        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: file); pendingBookFile = file; previewingPDF = true
                    }
                }
                catch { app.errorMessage = "لم تُجهز عينة الاستيراد." }
            }
            if root.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "UITestStores",
               let encoded = ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_IMPORT_GOODREADS"],
               let bytes = Data(base64Encoded: encoded), bytes.count <= 1024 * 1024, pendingGoodreadsStage == nil {
                let file = root.deletingLastPathComponent().appendingPathComponent("goodreads-ui-fixture.csv")
                do {
                    if !FileManager.default.fileExists(atPath: file.path) { try bytes.write(to: file, options: .atomic) }
                    let staged = try GoodreadsCSVFiles.stage(source: file, id: UUID(), root: root)
                    pendingGoodreadsFile = file; pendingGoodreadsStage = staged; previewingGoodreads = true
                } catch { app.errorMessage = "لم تُجهز عينة Goodreads." }
            }
            #endif
        }
    }

    private func handle(_ result: Result<[URL], Error>, assign: (URL) -> Void) {
        switch result {
        case .success(let urls):
            if let url = urls.first { assign(url) }
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain != NSCocoaErrorDomain || nsError.code != NSUserCancelledError {
                app.errorMessage = "لم يُفتح الملف. \(error.localizedDescription)"
            }
        }
    }

    private func handleGoodreads(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain != NSCocoaErrorDomain || nsError.code != NSUserCancelledError {
                app.errorMessage = error.localizedDescription
            }
        case .success(let urls):
            guard let source = urls.first else { return }
            let root = app.bookStagingDirectory
            stagingGoodreads = true
            Task {
                defer { stagingGoodreads = false }
                do {
                    let id = UUID()
                    let stage = try await Task.detached(priority: .userInitiated) {
                        try GoodreadsCSVFiles.stage(source: source, id: id, root: root)
                    }.value
                    pendingGoodreadsFile = source
                    pendingGoodreadsStage = stage
                    previewingGoodreads = true
                } catch { app.errorMessage = error.localizedDescription }
            }
        }
    }
}

private struct MihbaraAddBookSourceCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let foreground: Color
    @Environment(\.roomTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 48, height: 48)
                .background(color, in: .rect(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.custom("thmanyahserifdisplay-Bold", size: 19, relativeTo: .headline)).foregroundStyle(theme.ink)
                Text(subtitle).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.left").font(.system(size: 13, weight: .medium)).foregroundStyle(theme.secondaryInk.opacity(0.72))
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(theme.surface, in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(theme.line.opacity(0.72), lineWidth: 1) }
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct MihbaraRecentImportRow: View {
    let name: String
    let kind: String
    let theme: RoomTheme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(MadarTypography.caption()).lineLimit(1)
                Text("جاهز للمراجعة قبل الإضافة").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
            Spacer(minLength: 8)
            Text(kind).font(MadarTypography.fine()).foregroundStyle(theme.background).padding(.horizontal, 9).padding(.vertical, 6).background(theme.color("sunnahLeather"), in: .capsule)
        }
        .padding(15)
        .background(theme.surface, in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line.opacity(0.72), style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
    }
}

struct MihbaraPaperEditor: View {
    let app: AppSession
    let readingBooks: [MihbaraBook]
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var title = ""
    @State private var author = ""
    @State private var pages = ""
    @State private var shelf = "reading"
    @State private var saving = false
    @State private var identity = UUID()
    @State private var choosingSlot = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("كتاب ورقي").font(MadarTypography.title()); Spacer(); Button("إلغاء") { dismiss() } }
                Text("كتابك على الطاولة، وموضعك في مدار.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                field("العنوان", text: $title, id: "mihbara-paper-title")
                field("المؤلف", text: $author, id: "mihbara-paper-author")
                field("عدد الصفحات، إن عرفته", text: $pages, id: "mihbara-paper-pages").keyboardType(.numberPad)
                Text("يمكنك ترك الصفحات فارغة حتى تتأكد من طبعتك.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                Picker("ضعه على رف", selection: $shelf) { Text("أقرؤه الآن").tag("reading"); Text("أبي أقرأه").tag("want"); Text("أنهيته").tag("finished") }.pickerStyle(.menu).font(MadarTypography.section())
                Button { save() } label: { Text(saving ? "يُحفظ…" : "ضعه على الرف") }.buttonStyle(MadarPrimaryButton()).disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("mihbara-paper-save")
            }.padding(22)
        }.scrollDismissesKeyboard(.interactively).background(theme.background).foregroundStyle(theme.ink)
        .confirmationDialog("اختر كتابًا يرجع إلى أبي أقرأها", isPresented: $choosingSlot, titleVisibility: .visible) { ForEach(readingBooks) { old in Button(old.title) { save(replacing: old.id) } } }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("تمّ") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } } }
    }
    private func field(_ label: String, text: Binding<String>, id: String) -> some View { VStack(alignment: .leading, spacing: 7) { Text(label).font(MadarTypography.caption()); TextField(label, text: text).font(MadarTypography.body()).padding(15).background(theme.surface, in: .rect(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).stroke(theme.line) }.accessibilityIdentifier(id) } }
    private func save(replacing: UUID? = nil) {
        if shelf == "reading", readingBooks.count >= 3, replacing == nil { choosingSlot = true; return }
        var p: [String:MadarCore.JSONValue] = ["id":.string(identity.uuidString),"title":.string(title),"author":.string(author),"shelf":.string(shelf)]
        if !pages.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let n = mihbaraInteger(pages), n > 0 else { app.errorMessage = "اكتب عدد صفحات صحيحًا"; return }; p["pages"] = .number(Double(n))
        }
        if let replacing { p["replacing"] = .string(replacing.uuidString) }
        saving = true
        Task { do { try await app.executeBookCommand("book.savePaper", payload: p); onSaved() } catch { app.errorMessage = error.localizedDescription }; saving = false }
    }
}
struct MihbaraBookCard: View {
    let app: AppSession
    let book: MihbaraBook
    let books: [MihbaraBook]
    let fileUnavailable: Bool
    let onTable: () -> Void
    let onRestoreFile: () -> Void
    let onPaperIndexSaved: () -> Void
    /// The printed size from the file's page list, in the same words as the spine.
    var shape: MihbaraBookShape? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var page = ""
    @State private var finish = false
    @State private var choosingSlot = false
    @State private var saving = false
    @State private var paperTitlePinned = false
    private var digits: MadarNumberFormatter { AppMihbaraService(app: app).digits }
    private var paperChapters: [PaperBookChapter] {
        guard let data = book.tocJSON, let chapters = PaperBookIndex.decode(data, pages: book.pages) else { return [] }
        return chapters
    }
    private var shelfTitle: String {
        switch book.shelf { case "want": "أبي أقرأها"; case "finished": "أنهيتها"; default: "أقرؤها الآن" }
    }
    /// «أنهيته قبل ١٠ سنوات» for a book finished a year or more ago; plain «أنهيته» otherwise.
    private func finishedAgo(_ finished: Date) -> String {
        let years = Calendar(identifier: .gregorian).dateComponents([.year], from: finished, to: Date()).year ?? 0
        return years >= 1 ? "أنهيته قبل " + MihbaraCopy.years(years, digits) : "أنهيته"
    }
    private var paperBookPrimaryAction: String {
        if book.shelf == "finished" { return "أعد قراءته" }
        if let page = book.page, page > 0 { return "واصل القراءة" }
        return "ابدأه"
    }
    /// A book already on the table just continues; one on another shelf names the move it makes.
    private var paperBookStartTitle: String {
        if book.shelf == "reading" { return paperBookPrimaryAction }
        if book.shelf == "finished" { return "ضعه على الطاولة وأعد قراءته" }
        return "ضعه على الطاولة و" + (paperBookPrimaryAction == "ابدأه" ? "ابدأه" : "واصل القراءة")
    }
    private var paperIndexEditor: some View {
        MihbaraPaperIndexEditor(
            app: app,
            readingBooks: books.filter { $0.shelf == "reading" && $0.id != book.id },
            onSaved: onPaperIndexSaved,
            existingBook: book
        )
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if book.kind == "paper" {
                    paperBookContent
                } else {
                    HStack { Text(book.title).font(MadarTypography.title()); Spacer(); Button("تمّ") { dismiss() } }
                    Text(book.author).font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                    if let size = MihbaraBookCovers.sizeWord(shape, digits) {
                        Text(shape.flatMap { s in s.volumes > 1 ? s.pages.map { size + "، " + MihbaraCopy.pages($0, digits) } : nil } ?? size)
                            .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("mihbara-book-size")
                    }
                    if let finished = book.finished {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(finishedAgo(finished)).font(MadarTypography.caption()).accessibilityIdentifier("mihbara-book-finished-ago")
                            MadarDateLabel(app.dateLabels(GregorianDay.containing(finished, in: app.activePlace.timeZone)))
                        }
                    }
                    if book.shelf != "reading" { Button("ضعه على الطاولة") { moveToReading() }.buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("mihbara-put-on-table") }
                    if fileUnavailable {
                        Label("ملف الكتاب غير موجود على هذا الجهاز.", systemImage: "doc.badge.ellipsis")
                            .font(MadarTypography.body()).accessibilityIdentifier("mihbara-book-file-unavailable")
                        Text("اختر النسخة نفسها من «من ملف» لإعادته؛ يبقى اسم الكتاب وموضعك وسجل قراءتك محفوظًا.")
                            .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        Button("أعد استيراد الملف نفسه") { onRestoreFile() }
                            .buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("mihbara-book-file-restore-detail")
                    }
                    if book.shelf != "finished" {
                        Button("أنهيت الكتاب") { move("finished") }.buttonStyle(MadarPrimaryButton()).disabled(saving).accessibilityIdentifier("mihbara-book-mark-finished")
                    }
                    Button("أعده إلى أبي أقرأها") { move("want") }.frame(minHeight: 44).accessibilityIdentifier("mihbara-book-to-want")
                }
            }.padding(22)
        }.background(theme.background).foregroundStyle(theme.ink).scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > 48
        } action: { _, isPinned in
            if book.kind == "paper" { paperTitlePinned = isPinned }
        }
        .overlay(alignment: .top) {
            if book.kind == "paper", paperTitlePinned {
                HStack(spacing: 8) {
                    Image(systemName: "book.closed.fill").font(.system(size: 13, weight: .medium))
                        .accessibilityHidden(true)
                    Text(book.title).font(MadarTypography.caption()).lineLimit(1).truncationMode(.middle)
                        .accessibilityIdentifier("mihbara-paper-title-pinned")
                }
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .trailing)
                .padding(.horizontal, 22)
                .background(theme.background.opacity(0.98))
                .overlay(alignment: .bottom) { Rectangle().fill(theme.line.opacity(0.65)).frame(height: 0.5) }
                .environment(\.layoutDirection, .rightToLeft)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if book.kind == "paper" {
                paperBookFooter
            }
        }
        .task { page = digits.string(book.page ?? 0).filter { $0.wholeNumberValue != nil } }
        .confirmationDialog("اختر كتابًا يرجع إلى أبي أقرأها", isPresented: $choosingSlot, titleVisibility: .visible) { ForEach(books.filter { $0.shelf == "reading" && $0.id != book.id }) { old in Button(old.title) { move("reading", replacing: old.id) } } }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("تمّ") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } } }
        .presentationDetents(book.kind == "paper" ? [.height(360)] : [.large])
    }
    private var paperBookContent: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .center, spacing: 16) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(theme.ink.gradient)
                    .frame(width: 62, height: 88)
                    .overlay(alignment: .leading) { Rectangle().fill(theme.line.opacity(0.8)).frame(width: 4) }
                    .shadow(color: theme.ink.opacity(0.16), radius: 7, x: 0, y: 5)
                    .accessibilityHidden(true)
                VStack(alignment: .trailing, spacing: 7) {
                    Text(book.title).font(.custom("thmanyahserifdisplay-Bold", size: 24, relativeTo: .title2)).fixedSize(horizontal: false, vertical: true)
                    Text(book.author).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    Text("على رف «\(shelfTitle)»، " + (book.pages.map { MihbaraCopy.pages($0, digits) } ?? "عدد الصفحات غير محدد"))
                        .font(MadarTypography.caption())
                    if let page = book.page, page > 0 {
                        let total = book.pages.flatMap { $0 >= page ? digits.string($0) : nil }
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("وصلت إلى الصفحة " + digits.string(page) + (total.map { " من " + $0 } ?? ""))
                                .accessibilityIdentifier("mihbara-paper-position-summary")
                            if book.shelf != "finished", let left = MihbaraCopy.remaining(pages: book.pages, read: page, digits) {
                                Text(left).accessibilityIdentifier("mihbara-paper-remaining")
                            }
                        }
                        .font(MadarTypography.fine())
                        .foregroundStyle(theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            if paperChapters.isEmpty {
                NavigationLink { paperIndexEditor } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("جهّز فهرسه").font(.custom("thmanyahserifdisplay-Bold", size: 17, relativeTo: .headline))
                            Text("صوّر فهرس طبعتك أو أضف عناوينه وصفحاته يدويًا")
                                .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    }
                    .padding(13).frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                    .background(theme.surface, in: .rect(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mihbara-paper-index-prompt")
            } else {
                VStack(alignment: .trailing, spacing: 7) {
                    Text("فهرس طبعتك").font(MadarTypography.cardTitle())
                    ForEach(paperChapters.prefix(2)) { chapter in
                        HStack {
                            Text(chapter.title).font(MadarTypography.caption())
                            Spacer(minLength: 8)
                            if let chapterPage = chapter.page { Text("ص " + digits.string(chapterPage)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                        }
                    }
                }
                .padding(15).frame(maxWidth: .infinity, alignment: .trailing)
                .background(theme.surface, in: .rect(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line, lineWidth: 1) }
            }

        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var paperBookFooter: some View {
        VStack(spacing: 10) {
            Button { startPaperBook() } label: {
                Text(paperBookStartTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.background)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(theme.ink, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(saving)
            .accessibilityIdentifier("mihbara-paper-start")

            NavigationLink { paperIndexEditor } label: {
                Text("الفهرس والتفاصيل")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(theme.background, in: .rect(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.line, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mihbara-paper-index-details")
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(theme.background)
        .environment(\.layoutDirection, .rightToLeft)
    }
    private func startPaperBook() {
        if book.shelf == "reading" { onTable() } else { moveToReading() }
    }
    private func moveToReading() { if books.filter({ $0.shelf == "reading" }).count >= 3 { choosingSlot = true } else { move("reading") } }
    private func move(_ shelf: String, replacing: UUID? = nil) {
        var p: [String:MadarCore.JSONValue] = ["id":.string(book.id.uuidString),"shelf":.string(shelf)]; if let replacing { p["replacing"] = .string(replacing.uuidString) }
        saving = true; Task { do { try await app.executeBookCommand("book.moveShelf", payload: p); if shelf == "reading" { onTable() } else { dismiss() } } catch { app.errorMessage = error.localizedDescription }; saving = false }
    }
    private func savePosition() {
        guard let n = mihbaraInteger(page) else { app.errorMessage = "اكتب رقم صفحة صحيحًا"; return }
        saving = true; Task { do { try await app.executeBookCommand("book.setPosition", payload: ["id":.string(book.id.uuidString),"page":.number(Double(n)),"finished":.bool(finish)]); dismiss() } catch { app.errorMessage = error.localizedDescription }; saving = false }
    }
}
struct MihbaraHadithView: View {
    let app: AppSession; let hadith: MihbaraHadith; let collection: MihbaraCollection; let day: GregorianDay
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var saving = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Text(collection.title).font(MadarTypography.cardTitle()); Spacer(); Button("تمّ") { dismiss() } }
                Text(hadith.title).font(MadarTypography.title())
                MihbaraHadithText(text: hadith.text, ink: theme.ink)
                Divider()
                Text(collection.edition).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                if let source = URL(string: collection.source) { Link("المصدر والنسخة", destination: source).font(MadarTypography.caption()) }
                if let license = URL(string: collection.licenseURL) { Link("حقوق النص وعزوه إلى ويكي مصدر", destination: license).font(MadarTypography.fine()) }
                Button("فهمته") { mark(true) }.buttonStyle(MadarPrimaryButton()).disabled(saving).accessibilityIdentifier("mihbara-hadith-understood")
                Button("أرجع له") { mark(false) }.frame(maxWidth: .infinity, minHeight: 44).disabled(saving).accessibilityIdentifier("mihbara-hadith-return")
            }.padding(24)
        }.background(theme.background).foregroundStyle(theme.ink)
    }
    private func mark(_ understood: Bool) { saving = true; Task { do { try await app.executeBookCommand("hadith.mark", payload: ["number":.number(Double(hadith.number)),"edition":.string(collection.editionID),"understood":.bool(understood),"day":.string(day.description)]); dismiss() } catch { app.errorMessage = error.localizedDescription }; saving = false } }
}
private func mihbaraInteger(_ value: String) -> Int? { let clean = value.trimmingCharacters(in: .whitespacesAndNewlines); guard !clean.isEmpty, clean.allSatisfy({ $0.wholeNumberValue != nil }) else { return nil }; return Int(clean.compactMap { $0.wholeNumberValue.map(String.init) }.joined()) }

/// R01: the bundled Sunnah text uses native TextKit 2, without custom pagination.
private struct MihbaraHadithText: UIViewRepresentable {
    var text: String
    var ink: Color
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.isEditable = false; view.isScrollEnabled = false; view.backgroundColor = .clear
        view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true; view.semanticContentAttribute = .forceRightToLeft
        view.accessibilityIdentifier = "mihbara-hadith-text"
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        let style = NSMutableParagraphStyle(); style.alignment = .right; style.baseWritingDirection = .rightToLeft; style.lineSpacing = 8
        let font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: UIFont(name: "Amiri-Regular", size: 26) ?? UIFont.preferredFont(forTextStyle: .title2))
        view.attributedText = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor(ink), .paragraphStyle: style])
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return .init(width: width, height: uiView.sizeThatFits(.init(width: width, height: .greatestFiniteMagnitude)).height)
    }
}

private struct MihbaraGoodreadsImportView: View {
    let app: AppSession
    let stage: GoodreadsCSVStage
    let onImported: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var entries: [GoodreadsCSVEntry] = []
    @State private var candidates: [GoodreadsBookCandidate] = []
    @State private var preview: GoodreadsPreview?
    @State private var selectedMatches: [String: UUID] = [:]
    @State private var cutoffYear = GoodreadsCSV.defaultCutoffYear
    @State private var missingDateShelf = "old"
    @State private var loading = true
    @State private var saving = false
    @State private var failure: String?

    private var digits: MadarNumberFormatter { .init(style: app.string("core.numerals") == "western" ? .western : .hindi) }
    private var targetsAreUnique: Bool {
        guard let preview else { return false }
        let targets = preview.rows.compactMap(\.targetBookID)
        return targets.count == Set(targets).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("معاينة مكتبة Goodreads").font(MadarTypography.title())
                    Text(stage.fileName).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).lineLimit(2)
                }
                if loading { ProgressView("أفحص الكتب…").tint(theme.ink).frame(maxWidth: .infinity, minHeight: 150) }
                else if let failure {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("تعذّرت المعاينة").font(MadarTypography.cardTitle())
                        Text(failure).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        Button("العودة لاختيار الملف") { dismiss() }.buttonStyle(MadarPrimaryButton())
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 18))
                } else if let preview {
                    Text("أراجع الملف قبل إضافته. الكتب المطابقة لا تُدمج إلا بعد اختيارك.")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    HStack(spacing: 9) {
                        GoodreadsCountCard(title: "كتب جديدة", value: digits.string(preview.createCount), theme: theme)
                        GoodreadsCountCard(title: "تحديثات", value: digits.string(preview.updateCount), theme: theme)
                        GoodreadsCountCard(title: "تحتاج اختيارك", value: digits.string(preview.suggestionCount), theme: theme)
                    }
                    if entries.contains(where: { $0.exclusiveShelf == "read" && $0.dateRead != nil }) { cutoffCard }
                    if entries.contains(where: { $0.exclusiveShelf == "read" && $0.dateRead == nil }) { missingDateCard }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("الكتب في الملف").font(MadarTypography.section())
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(preview.rows, id: \.entry.rowKey) { row in goodreadsRow(row) }
                        }
                    }
                }
            }.padding(18).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
        .environment(\.layoutDirection, .rightToLeft)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if !loading && failure == nil {
                Button(action: importBooks) {
                    HStack(spacing: 9) {
                        if saving { ProgressView().tint(theme.background) }
                        Text(saving ? "يُضاف إلى المحبرة…" : importButtonTitle)
                    }.font(MadarTypography.body()).foregroundStyle(theme.background)
                        .frame(maxWidth: .infinity).frame(height: 52).background(theme.ink, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain).disabled(saving || !targetsAreUnique || preview == nil)
                .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 12).background(theme.background)
                .accessibilityIdentifier("mihbara-goodreads-import")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("رجوع") { dismiss() }.disabled(saving) }
            ToolbarItem(placement: .principal) { Text("مكتبة Goodreads").font(MadarTypography.section()) }
        }
        .task(id: stage.id) { load() }
        .onChange(of: cutoffYear) { _, _ in rebuildPreview() }
        .onChange(of: missingDateShelf) { _, _ in rebuildPreview() }
        .onChange(of: selectedMatches) { _, _ in rebuildPreview() }
    }

    private var cutoffCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("رفّ الكتب المقروءة").font(MadarTypography.cardTitle())
            Text("ما قُرئ قبل سنة \(digits.string(cutoffYear)) يذهب إلى «قديمًا»، وما قُرئ فيها أو بعدها إلى «أنهيتها».")
                .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            HStack(spacing: 16) {
                Button { cutoffYear = max(1900, cutoffYear - 1) } label: { Image(systemName: "minus.circle.fill").font(.title2) }
                    .accessibilityLabel("سنة أقدم")
                Text(digits.string(cutoffYear)).font(MadarTypography.title()).monospacedDigit().accessibilityIdentifier("mihbara-goodreads-cutoff-year")
                Button { cutoffYear = min(2100, cutoffYear + 1) } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                    .accessibilityLabel("سنة أحدث")
                Spacer(minLength: 0)
            }.foregroundStyle(theme.color("accentText"))
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 16))
    }

    private var missingDateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("كتاب مقروء بلا تاريخ قراءة").font(MadarTypography.cardTitle())
            Text("لا أضيف تاريخًا من عندي؛ اختر الرف الذي يناسب الكتب التي لم يذكر الملف تاريخها.")
                .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            HStack(spacing: 8) { missingDateChoice("قديمًا", value: "old"); missingDateChoice("أنهيتها", value: "finished") }
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 16))
    }

    private func missingDateChoice(_ title: String, value: String) -> some View {
        let selected = missingDateShelf == value
        return Button { missingDateShelf = value } label: {
            Text(title).font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 42)
                .foregroundStyle(selected ? theme.background : theme.ink)
                .background(selected ? theme.ink : theme.background, in: .rect(cornerRadius: 11))
                .overlay { RoundedRectangle(cornerRadius: 11).stroke(theme.line, lineWidth: selected ? 0 : 1) }
        }.buttonStyle(.plain).accessibilityIdentifier("mihbara-goodreads-missing-\(value)")
    }

    @ViewBuilder private func goodreadsRow(_ row: GoodreadsPreviewRow) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.entry.title).font(MadarTypography.cardTitle()).lineLimit(3)
                    Text(row.entry.author.isEmpty ? "المؤلف غير مذكور" : row.entry.author)
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).lineLimit(2)
                }
                Spacer(minLength: 0)
                Text(shelfName(row.targetShelf)).font(MadarTypography.fine()).padding(.horizontal, 9).padding(.vertical, 6)
                    .background(theme.background, in: .capsule)
            }
            HStack(spacing: 8) {
                if let rating = row.entry.rating { Text("التقييم \(digits.string(rating))/٥") }
                Text("قُرئت \(digits.string(row.entry.readCount)) مرات")
                if let pages = row.entry.pages { Text("\(digits.string(pages)) صفحة") }
            }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            if let date = row.entry.dateRead {
                MadarDateLabel(app.dateLabels(GregorianDay.containing(date, in: app.activePlace.timeZone)),
                               primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            } else if row.entry.exclusiveShelf == "read" {
                Text(row.entry.dateReadText.isEmpty ? "بلا تاريخ قراءة؛ سيبقى التاريخ فارغًا" : "لم أتعرف على تاريخ القراءة؛ لن أضيف تاريخًا")
                    .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
            if let review = row.entry.review, !review.isEmpty {
                Text(review).font(MadarTypography.caption()).lineLimit(3).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.background, in: .rect(cornerRadius: 10))
                    .accessibilityIdentifier("mihbara-goodreads-review-\(row.entry.rowKey)")
            }
            if let note = row.entry.privateNote {
                Label("ملاحظة خاصة: " + note, systemImage: "lock.fill").font(MadarTypography.fine())
                    .lineLimit(3).foregroundStyle(theme.secondaryInk)
                    .accessibilityIdentifier("mihbara-goodreads-private-note-\(row.entry.rowKey)")
            }
            if !row.suggestions.isEmpty && row.targetBookID == nil {
                Menu {
                    Button("أضفه ككتاب مستقل") { selectedMatches.removeValue(forKey: row.entry.rowKey) }
                    ForEach(row.suggestions, id: \.id) { candidate in
                        Button("حدّث «\(candidate.title)»") { selectedMatches[row.entry.rowKey] = candidate.id }
                            .disabled(selectedMatches.contains(where: { $0.key != row.entry.rowKey && $0.value == candidate.id }))
                    }
                } label: {
                    Label("قد يكون هذا الكتاب موجودًا — اختر المطابقة", systemImage: "arrow.triangle.merge")
                        .font(MadarTypography.fine()).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .foregroundStyle(theme.color("accentText"))
                }.accessibilityIdentifier("mihbara-goodreads-match-\(row.entry.rowKey)")
            } else if row.targetBookID != nil {
                Label("سيُحدّث الكتاب الموجود", systemImage: "checkmark.circle")
                    .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: .rect(cornerRadius: 15))
            .overlay { RoundedRectangle(cornerRadius: 15).stroke(theme.line.opacity(0.7), lineWidth: 1) }
            .accessibilityIdentifier("mihbara-goodreads-row-\(row.entry.rowKey)")
    }

    private func shelfName(_ shelf: String) -> String {
        switch shelf { case "reading": "أقرأها"; case "want": "لاحقًا"; case "finished": "أنهيتها"; default: "قديمًا" }
    }

    private var importButtonTitle: String {
        let noun = entries.count == 1 ? "كتابًا واحدًا" : entries.count == 2 ? "كتابين" : MihbaraCopy.books(entries.count, digits)
        return "أضف \(noun) إلى المحبرة"
    }

    private func load() {
        loading = true; failure = nil
        do {
            let (data, _) = try GoodreadsCSVFiles.read(id: stage.id, root: app.bookStagingDirectory, expectedHash: stage.sha256)
            entries = try GoodreadsCSV.parse(data)
            let stored = try ModelContext(app.container).fetch(FetchDescriptor<Book>())
            candidates = stored.filter { $0.deletedAt == nil && $0.mergedInto == nil }.map {
                GoodreadsBookCandidate(id: $0.id, title: $0.title, author: $0.author, isbn13: $0.isbn13,
                                       sourceGoodreadsID: $0.sourceGoodreadsID, shelf: $0.shelf)
            }
            rebuildPreview()
        } catch { failure = error.localizedDescription }
        loading = false
    }

    private func rebuildPreview() {
        guard !entries.isEmpty else { preview = nil; return }
        preview = GoodreadsCSV.preview(entries: entries, existing: candidates, cutoffYear: cutoffYear,
                                       missingDateShelf: missingDateShelf, selectedMatches: selectedMatches)
    }

    private func importBooks() {
        guard preview != nil, targetsAreUnique else { return }
        saving = true
        Task {
            do {
                let selectedData = try JSONEncoder().encode(selectedMatches)
                let payload: [String: MadarCore.JSONValue] = [
                    "id": .string(UUID().uuidString), "fileID": .string(stage.id.uuidString),
                    "sha256": .string(stage.sha256), "fileName": .string(stage.fileName),
                    "cutoffYear": .number(Double(cutoffYear)), "missingDateShelf": .string(missingDateShelf),
                    "selectedMatchesJSON": .string(String(decoding: selectedData, as: UTF8.self))
                ]
                try await app.executeBookCommand("book.importGoodreads", payload: payload, undoMessage: "أُضيفت كتب Goodreads إلى المحبرة")
                GoodreadsCSVFiles.discard(id: stage.id, root: app.bookStagingDirectory)
                onImported()
            } catch { failure = error.localizedDescription }
            saving = false
        }
    }
}

private struct GoodreadsCountCard: View {
    let title: String
    let value: String
    let theme: RoomTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(MadarTypography.cardTitle())
            Text(title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(2)
        }.frame(maxWidth: .infinity, minHeight: 58, alignment: .leading).padding(10)
            .background(theme.surface, in: .rect(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).stroke(theme.line.opacity(0.7), lineWidth: 1) }
    }
}
