import SwiftUI
import UIKit
import UniformTypeIdentifiers
import MadarCore
import MadarDesign

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
    @Binding var pendingBookFile: URL?
    @Binding var pendingGoodreadsFile: URL?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var importingBook = false
    @State private var importingGoodreads = false
    @State private var previewingPDF = false
    @State private var previewingEPUB = false

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
                            subtitle: "استورد مكتبتك من ملف CSV",
                            symbol: "g.circle.fill",
                            color: theme.color("sunnahLeather"),
                            foreground: theme.color("onAccent")
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mihbara-add-source-goodreads")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("وصل مؤخرًا").font(MadarTypography.section())
                    if let pendingGoodreadsFile {
                        MihbaraRecentImportRow(name: pendingGoodreadsFile.lastPathComponent, kind: "CSV", theme: theme)
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
        .fileImporter(isPresented: $importingBook, allowedContentTypes: bookTypes, allowsMultipleSelection: false) { result in
            handle(result, assign: {
                pendingBookFile = $0
                if $0.pathExtension.lowercased() == "epub" { previewingEPUB = true }
                else { previewingPDF = true }
            })
        }
        .fileImporter(isPresented: $importingGoodreads, allowedContentTypes: [.commaSeparatedText], allowsMultipleSelection: false) { result in
            handle(result, assign: { pendingGoodreadsFile = $0 })
        }
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
    let onTable: () -> Void
    let onPaperIndexSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var page = ""
    @State private var finish = false
    @State private var choosingSlot = false
    @State private var saving = false
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
                    if let finished = book.finished {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(finishedAgo(finished)).font(MadarTypography.caption()).accessibilityIdentifier("mihbara-book-finished-ago")
                            MadarDateLabel(app.dateLabels(GregorianDay.containing(finished, in: app.activePlace.timeZone)))
                        }
                    }
                    if book.shelf != "reading" { Button("ضعه على الطاولة") { moveToReading() }.buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("mihbara-put-on-table") }
                    Text("وصلت إلى").font(MadarTypography.cardTitle())
                    HStack { Text("صفحة"); TextField("رقم الصفحة", text: $page).keyboardType(.numberPad).padding(14).background(theme.surface, in: .rect(cornerRadius: 12)).accessibilityIdentifier("mihbara-book-page"); if let total = book.pages { Text("من " + digits.string(total)) } }.font(MadarTypography.body())
                    Text("هذا يحفظ موضعك. جلسة القراءة تُحسب من وقت نشاطك في القارئ.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    Toggle("أنهيت الكتاب", isOn: $finish).font(MadarTypography.section()).accessibilityIdentifier("mihbara-book-finished")
                    Button("احفظ موضعي") { savePosition() }.buttonStyle(MadarPrimaryButton()).disabled(saving).accessibilityIdentifier("mihbara-book-save-position")
                    Button("أعده إلى أبي أقرأها") { move("want") }.frame(minHeight: 44).accessibilityIdentifier("mihbara-book-to-want")
                }
            }.padding(22)
        }.background(theme.background).foregroundStyle(theme.ink).scrollDismissesKeyboard(.interactively)
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
