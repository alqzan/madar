import SwiftUI
import SwiftData
import UIKit
import ImageIO
import MadarCore
import MadarData
import MadarCommands
import MadarDesign

@MainActor extension AppMihbaraService {
    func stageEPUB(_ source: URL, id: UUID) async throws -> EPUBBookInspection {
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        let root = app.bookStagingDirectory
        let inspection = try await Task.detached(priority: .userInitiated) {
            try EPUBBookFiles.stage(source: source, root: root, id: id)
        }.value
        do {
            guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
            let books = try ModelContext(app.container).fetch(FetchDescriptor<Book>())
            guard !books.contains(where: { $0.fileHash == inspection.sha256 && $0.mergedInto == nil }) else {
                throw DataError.invalidValue("هذا الكتاب عندك بالفعل، أو أُزيل سابقًا؛ لن يُضاف مكررًا.")
            }
            return inspection
        } catch { EPUBBookFiles.discard(id: id, root: root); throw error }
    }

    func confirmEPUB(_ inspection: EPUBBookInspection, bookID: UUID, commandID: UUID, title: String, author: String, language: String, shelf: String, turathID: Int? = nil) async throws {
        var payload: [String: MadarCore.JSONValue] = [
            "id": .string(bookID.uuidString), "fileID": .string(inspection.id.uuidString), "sha256": .string(inspection.sha256),
            "title": .string(title), "author": .string(author), "language": .string(language), "shelf": .string(shelf)
        ]
        if let turathID { payload["turathID"] = .number(Double(turathID)) }
        try await app.executeBookCommand("book.importEPUB", payload: payload, id: commandID)
        EPUBBookFiles.discard(id: inspection.id, root: app.bookStagingDirectory)
    }
}

struct MihbaraEPUBImportView: View {
    let app: AppSession
    let source: URL
    var turathID: Int? = nil
    let onImported: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var fileID = UUID()
    @State private var bookID = UUID()
    @State private var commandID = UUID()
    @State private var inspection: EPUBBookInspection?
    @State private var printedShape: MihbaraBookShape?
    @State private var cover: UIImage?
    @State private var title = ""
    @State private var author = ""
    @State private var language = "ar"
    @State private var shelf = "want"
    @State private var error: String?
    @State private var saving = false
    @State private var finished = false
    @State private var confirmedMetadata = false
    @State private var showingFullIndex = false
    @State private var scan: EPUBBookScan?
    @State private var scanProgress = 0.0
    @State private var scanDone = false
    private static let indexPreview = 8
    private var service: AppMihbaraService { .init(app: app) }
    private var digits: MadarNumberFormatter { service.digits }
    // The index preview keeps the page short; only the full index needs the pinned button (it hid the shelf row).
    private var needsPersistentImportAction: Bool { showingFullIndex && (inspection?.outline.count ?? 0) > 12 }

    private var languageLabel: String {
        guard let code = inspection?.languageCode else { return "غير محددة في الملف" }
        if code.lowercased().hasPrefix("en") { return "الإنجليزية" }
        if code.lowercased().hasPrefix("ar") { return "العربية" }
        return code
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    Text("من ملف").font(.custom("thmanyahserifdisplay-Bold", size: 21, relativeTo: .title2))
                    HStack {
                        Button { dismiss() } label: { Label("رجوع", systemImage: "chevron.right").font(MadarTypography.caption()).frame(minHeight: 44) }
                            .disabled(saving).accessibilityIdentifier("mihbara-epub-import-back")
                        Spacer()
                    }
                }

                HStack(spacing: 10) {
                    Text("EPUB").font(MadarTypography.fine()).foregroundStyle(theme.onAccent).padding(.horizontal, 9).padding(.vertical, 7)
                        .background(theme.accentFill, in: .rect(cornerRadius: 8))
                    Text(source.lastPathComponent).font(MadarTypography.section()).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12).frame(maxWidth: .infinity, minHeight: 58)
                .background(theme.surface, in: .rect(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.line, lineWidth: 1) }

                VStack(alignment: .leading, spacing: 15) {
                    if inspection == nil && error == nil {
                        Text("أفهم الكتاب…").font(MadarTypography.cardTitle())
                        ProgressView().tint(theme.ink).frame(maxWidth: .infinity).accessibilityLabel("يفحص ملف EPUB")
                    }
                    if let value = inspection {
                        Text("ما وجدناه").font(MadarTypography.cardTitle())
                        row("نوع الملف", detail: "كتاب إلكتروني سليم؛ فُحصت بنيته وحدوده الأمنية.", detected: true)
                        row("اللغة", detail: value.appLanguage == "en" ? "\(languageLabel)؛ يفتح وضع القراءة الإنجليزية." : value.appLanguage == "ar" ? "\(languageLabel)؛ يفتح وضع القراءة العربية." : "اللغة في البيانات: \(languageLabel). اختر وضع القراءة أدناه.", detected: value.languageCode != nil)
                        row("البيانات", detail: value.author.isEmpty ? "العنوان من الملف؛ لم يُسجل مؤلف." : "العنوان والمؤلف من بيانات الملف.", detected: !value.author.isEmpty)
                        row("الحجم", detail: sizeLine(value), detected: printedShape != nil).accessibilityElement(children: .combine).accessibilityIdentifier("mihbara-epub-import-size")
                        row("الفهرس", detail: value.outline.isEmpty ? "بلا فهرس إلكتروني قابل للتنقّل؛ لم نخمن فصول الكتاب." : "فهرس جاهز للتنقّل بين عناوينه.", detected: !value.outline.isEmpty)
                        let pageList = value.hasPageList ? "توجد قائمة صفحات للمصدر المطبوع" : "لا توجد قائمة صفحات مطبوعة"
                        let notes = value.hasFootnotes == true ? "اكتُشفت حواشٍ" : value.hasFootnotes == false ? "لم تُكتشف حواشٍ" : "تعذّر حسم وجود الحواشي"
                        row("الصور والجداول", detail: "تبقى ضمن الملف كما حفظها؛ \(pageList)؛ \(notes).", detected: true)
                        scanRows
                    }
                }

                if let error {
                    Text(error).font(MadarTypography.body()).foregroundStyle(theme.ink).accessibilityIdentifier("mihbara-epub-import-error")
                }

                if let value = inspection {
                    VStack(alignment: .trailing, spacing: 10) {
                        HStack(alignment: .top, spacing: 16) {
                            Group {
                                if let cover {
                                    Image(uiImage: cover).resizable().scaledToFill()
                                } else {
                                    VStack(spacing: 8) {
                                        Image(systemName: "book.closed.fill").font(.title2)
                                        Text(value.hasCover ? "تعذّر عرض الغلاف" : "لا توجد صورة غلاف").font(MadarTypography.fine()).multilineTextAlignment(.center)
                                    }.frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(theme.color("onNavy"))
                                        .background(theme.color("navy"))
                                }
                            }
                            .frame(width: 92, height: 138).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel(value.hasCover ? "غلاف من ملف EPUB" : "لا توجد صورة غلاف في الملف")

                            VStack(alignment: .trailing, spacing: 8) {
                                TextField("عنوان الكتاب", text: $title, prompt: Text("عنوان الكتاب").foregroundStyle(theme.secondaryInk), axis: .vertical)
                                    .lineLimit(1...3).textFieldStyle(.plain).font(MadarTypography.cardTitle()).multilineTextAlignment(.trailing)
                                    .accessibilityIdentifier("mihbara-epub-import-title")
                                // The spine shows the name the book is known by; the full title stays on the book.
                                if BookTitle.parts(title).short != title.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                                    Text("على الرف: «" + BookTitle.parts(title).short + "»").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                                        .accessibilityIdentifier("mihbara-epub-import-shelf-name")
                                }
                                TextField("المؤلف، إن عُرف", text: $author, prompt: Text("المؤلف، إن عُرف").foregroundStyle(theme.secondaryInk))
                                    .textFieldStyle(.plain).font(MadarTypography.body()).multilineTextAlignment(.trailing)
                                    .accessibilityIdentifier("mihbara-epub-import-author")
                                Picker("لغة القراءة", selection: $language) {
                                    Text("العربية").tag("ar")
                                    Text("الإنجليزية").tag("en")
                                }
                                .font(MadarTypography.caption()).accessibilityIdentifier("mihbara-epub-import-language")
                                Text(value.direction == "rtl" ? "تُقرأ من اليمين إلى اليسار" : value.direction == "ltr" ? "تُقرأ من اليسار إلى اليمين" : "اتجاه القراءة غير محدد")
                                    .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(14).background(theme.surface, in: .rect(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line.opacity(0.7), lineWidth: 1) }
                    .disabled(saving || confirmedMetadata)

                    VStack(alignment: .trailing, spacing: 12) {
                        Text("أين تضعه؟").font(MadarTypography.section())
                        HStack(spacing: 8) {
                            shelfButton("reading", title: "أقرأها الآن")
                            shelfButton("want", title: "أبي أقرأها")
                            shelfButton("finished", title: "أنهيتها")
                        }
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.color("sunnah"))
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("نسخة محلية على جهازك").font(MadarTypography.section())
                                Text("تقرأه بلا إنترنت").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12).frame(maxWidth: .infinity, minHeight: 56, alignment: .trailing)
                        .background(theme.surface, in: .rect(cornerRadius: 14))
                    }
                    .padding(14).background(theme.surface, in: .rect(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line.opacity(0.7), lineWidth: 1) }
                    .disabled(saving || confirmedMetadata)

                    HStack {
                        Text("الفهرس المستخرج").font(MadarTypography.section())
                        Spacer()
                        Text(arabicCount(value.outline.count, ["عنوان واحد", "عنوانان", "عناوين", "عنوانًا"], digits)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    }
                    if value.outline.isEmpty {
                        Text("لا يوجد فهرس إلكتروني في هذا الملف.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading).padding(.horizontal, 16)
                            .background(theme.surface, in: .rect(cornerRadius: 16))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(value.outline.prefix(showingFullIndex ? value.outline.count : Self.indexPreview).enumerated()), id: \.offset) { index, item in
                                HStack(spacing: 12) {
                                    Text(digits.string(index + 1)).font(MadarTypography.caption().weight(.semibold)).foregroundStyle(theme.secondaryInk).lineLimit(1).fixedSize().frame(minWidth: 24, alignment: .leading)
                                    Text(item.title).font(MadarTypography.body()).lineLimit(2).padding(.leading, CGFloat(min(item.depth, 4) * 12)).frame(maxWidth: .infinity, alignment: .leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .environment(\.layoutDirection, value.direction == "ltr" ? .leftToRight : .rightToLeft)
                                .accessibilityIdentifier("mihbara-epub-import-toc-\(index + 1)")
                                if index < min(value.outline.count, showingFullIndex ? .max : Self.indexPreview) - 1 { Divider().padding(.leading, 42) }
                            }
                        }
                        .background(theme.surface, in: .rect(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.line.opacity(0.7), lineWidth: 1) }
                        // A long index (Turath books reach thousands of headings) shows a preview; the reader has it all.
                        if value.outline.count > Self.indexPreview {
                            Button(showingFullIndex ? "اختصر الفهرس" : "اعرض الفهرس كاملًا") { showingFullIndex.toggle() }
                                .font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 44)
                                .accessibilityIdentifier("mihbara-epub-import-toc-all")
                        }
                    }

                    if !needsPersistentImportAction { confirmButton }
                }
            }
            .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 24)
            .frame(maxWidth: 650).frame(maxWidth: .infinity)
        }
        .foregroundStyle(theme.ink).background(theme.background.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft).toolbarVisibility(.hidden, for: .navigationBar).statusBarHidden(true)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if needsPersistentImportAction {
                confirmButton
                    .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 8)
                    .frame(maxWidth: 650).frame(maxWidth: .infinity)
                    .background(theme.background.ignoresSafeArea(edges: .bottom))
            }
        }
        .interactiveDismissDisabled(saving)
        .task { await inspect() }
        .onDisappear { if !saving && !finished { EPUBBookFiles.discard(id: fileID, root: app.bookStagingDirectory) } }
    }

    private var confirmButton: some View {
        Button(saving ? "يُضاف…" : "أضفه إلى مكتبتي") { confirm() }
            .buttonStyle(MadarPrimaryButton())
            .disabled(saving || !scanDone || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 300 || author.count > 300)
            .accessibilityIdentifier("mihbara-epub-import-confirm")
    }

    private func row(_ title: String, detail: String, detected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Found → filled check; absent from the file → a quiet dash, so information never reads as an unfinished task.
            Image(systemName: detected ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 20, weight: .regular)).foregroundStyle(detected ? theme.color("sunnah") : theme.secondaryInk.opacity(0.6))
                .frame(width: 25).padding(.top, 2)
            VStack(alignment: .trailing, spacing: 4) {
                Text(title).font(MadarTypography.section())
                Text(detail).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine)
    }

    private func shelfButton(_ value: String, title: String) -> some View {
        let selected = shelf == value
        return Button { shelf = value } label: {
            Text(title).font(MadarTypography.caption().weight(.semibold)).lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 4)
                .foregroundStyle(selected ? theme.color("onAccent") : theme.ink)
                .background(selected ? theme.color("sunnahLeather") : theme.background, in: .capsule)
                .overlay { Capsule().stroke(selected ? .clear : theme.line, lineWidth: 1) }
        }
        .buttonStyle(.plain).accessibilityIdentifier("mihbara-epub-shelf-\(value)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Owner, 24 Oct 2026: the whole book is read before it reaches the shelf, and what was found is said plainly.
    @ViewBuilder private var scanRows: some View {
        if let scan {
            row("القراءة الكاملة", detail: count(scan.chapters, ("فصل واحد", "فصلان", "فصول", "فصلًا")) + "، " + count(scan.words, ("كلمة واحدة", "كلمتان", "كلمات", "كلمةً"))
                + (scan.emptyChapters.isEmpty ? (scan.unreadChapters == 0 ? "؛ كل فصل فيه نص." : "؛ الفصول المقروءة فيها نص.") : "؛ " + count(scan.emptyChapters.count, ("فصل واحد", "فصلان", "فصول", "فصلًا")) + " بلا نص.")
                + (scan.unreadChapters > 0 ? " تعذّر فحص " + count(scan.unreadChapters, ("فصل واحد", "فصلين", "فصول", "فصلًا")) + "." : ""),
                detected: scan.emptyChapters.isEmpty && scan.unreadChapters == 0).accessibilityIdentifier("mihbara-epub-scan-text")
            if scan.tocEntries > 0 {
                row("روابط الفهرس", detail: (scan.brokenTOC.isEmpty ? "كل عناوين الفهرس تصل إلى مواضعها"
                    : count(scan.brokenTOC.count, ("عنوان واحد", "عنوانان", "عناوين", "عنوانًا")) + " لا يصل إلى موضعه: " + scan.brokenTOC.prefix(3).joined(separator: "، ") + (scan.brokenTOC.count > 3 ? "…" : ""))
                    + (scan.tocOutOfOrder > 0 ? "، وبعضها ليس بترتيب الكتاب." : "."),
                    detected: scan.brokenTOC.isEmpty && scan.tocOutOfOrder == 0).accessibilityIdentifier("mihbara-epub-scan-toc")
            }
            if scan.pageLabels > 0 {
                row("أرقام الصفحات", detail: scan.pageGaps == 0 && scan.pageRepeats == 0 && scan.pageOutOfOrder == 0 && scan.unverifiedPageLinks == 0 ? "الأرقام وروابطها متتابعة بلا نقص ولا تكرار."
                    : [scan.pageGaps > 0 ? "تنقص " + count(scan.pageGaps, ("صفحة واحدة", "صفحتان", "صفحات", "صفحةً")) : nil,
                       scan.pageRepeats > 0 ? "يتكرر " + count(scan.pageRepeats, ("رقم واحد", "رقمان", "أرقام", "رقمًا")) : nil,
                       scan.pageOutOfOrder > 0 ? "تحتاج بعض الأرقام أو روابطها إلى مراجعة الترتيب" : nil,
                       scan.unverifiedPageLinks > 0 ? "تعذّر التحقق من " + count(scan.unverifiedPageLinks, ("رابط صفحة واحد", "رابطي صفحتين", "روابط صفحات", "رابط صفحة")) : nil].compactMap { $0 }.joined(separator: "، ") + ".",
                    detected: scan.pageGaps == 0 && scan.pageRepeats == 0 && scan.pageOutOfOrder == 0 && scan.unverifiedPageLinks == 0).accessibilityIdentifier("mihbara-epub-scan-pages")
            }
            if scan.verses > 0 {
                row("الآيات", detail: count(scan.verses, ("آية واحدة", "آيتان", "آيات", "آيةً")) + " تُعرض بخط المصحف.", detected: true).accessibilityIdentifier("mihbara-epub-scan-verses")
            }
        } else if scanDone {
            row("القراءة الكاملة", detail: "تعذّر فحص الكتاب كاملًا؛ يمكنك إضافته كما هو.", detected: false)
        } else if inspection != nil, error == nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("يقرأ الكتاب كاملًا قبل إضافته…").font(MadarTypography.body())
                ProgressView(value: scanProgress).tint(theme.ink)
            }.accessibilityElement(children: .combine).accessibilityIdentifier("mihbara-epub-scan-progress")
        }
    }
    private func count(_ n: Int, _ forms: (String, String, String, String)) -> String {
        switch n { case 1: forms.0; case 2: forms.1; case 0, 3...10: digits.string(n) + " " + forms.2; default: digits.string(n) + " " + forms.3 }
    }
    @MainActor private func runScan() async {
        let file = EPUBBookFiles.stagedURL(id: fileID, root: app.bookStagingDirectory)
        let report = Task.detached(priority: .userInitiated) { () -> EPUBBookScan? in
            try? EPUBBookFiles.scan(file: file) { value in Task { @MainActor in scanProgress = value } }
        }
        let value = await report.value
        guard !Task.isCancelled else { return }
        // A scan that cannot run never blocks a book that already passed the import checks.
        scan = value; scanDone = true
    }

    /// «٤ مجلدات، ١٬٢٠٠ صفحة مطبوعة؛ الملف ٣٫٢ م.ب» — the size the shelf will show, from the moment of download.
    private func sizeLine(_ value: EPUBBookInspection) -> String {
        let file = "الملف " + digits.localized(ByteCountFormatter.string(fromByteCount: Int64(value.sizeBytes), countStyle: .file))
        if let scan, scan.pageGaps > 0 || scan.pageRepeats > 0 || scan.pageOutOfOrder > 0 || scan.unverifiedPageLinks > 0 {
            return file + "؛ عدد صفحات المطبوع غير متحقق."
        }
        guard let shape = printedShape, let pages = shape.pages, pages > 0 else { return file + "؛ لا يذكر الملف عدد صفحات المطبوع." }
        let printed = MihbaraCopy.pages(pages, digits) + " مطبوعة"
        return (shape.volumes > 1 ? (MihbaraBookCovers.sizeWord(shape, digits) ?? "") + "، " + printed : printed) + "؛ " + file
    }

    @MainActor private func inspect() async {
        guard inspection == nil, error == nil else { return }
        do {
            let value = try await service.stageEPUB(source, id: fileID)
            guard !Task.isCancelled else { EPUBBookFiles.discard(id: fileID, root: app.bookStagingDirectory); return }
            let publication = try await MihbaraEPUBLoader.open(at: EPUBBookFiles.stagedURL(id: fileID, root: app.bookStagingDirectory))
            defer { publication.close() }
            guard !Task.isCancelled else { EPUBBookFiles.discard(id: fileID, root: app.bookStagingDirectory); return }
            inspection = value
            printedShape = (try? EPUBBookFiles.printedShape(file: EPUBBookFiles.stagedURL(id: fileID, root: app.bookStagingDirectory))).map { MihbaraBookShape(pages: $0.pages, volumes: $0.volumes) }
            if let readiumTitle = publication.metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines), !readiumTitle.isEmpty { title = readiumTitle }
            else { title = value.title }
            author = value.author.isEmpty ? publication.metadata.authors.map(\.name).joined(separator: "، ") : value.author
            language = value.appLanguage ?? "ar"
            cover = Self.thumbnail(value.coverData)
            confirmedMetadata = false
            await runScan()
        } catch {
            EPUBBookFiles.discard(id: fileID, root: app.bookStagingDirectory)
            if case DataError.invalidValue(let message) = error { self.error = message }
            else { self.error = "تعذّر فحص EPUB أو فتحه بالقارئ؛ لم يُنسخ إلى مكتبتك." }
        }
    }

    private func confirm() {
        guard !saving, let inspection else { return }
        saving = true
        Task { @MainActor in
            do {
                try await service.confirmEPUB(inspection, bookID: bookID, commandID: commandID,
                                              title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                              author: author.trimmingCharacters(in: .whitespacesAndNewlines), language: language, shelf: shelf,
                                              turathID: turathID)
                saving = false; finished = true; onImported()
            } catch {
                saving = false
                self.error = (error as? DataError).map { $0.localizedDescription } ?? "تعذّر إضافة الكتاب. لم يُضف إلى مكتبتك."
            }
        }
    }

    private static func thumbnail(_ data: Data?) -> UIImage? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
