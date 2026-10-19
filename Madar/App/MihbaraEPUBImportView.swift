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
    @State private var cover: UIImage?
    @State private var title = ""
    @State private var author = ""
    @State private var language = "ar"
    @State private var shelf = "want"
    @State private var error: String?
    @State private var saving = false
    @State private var finished = false
    @State private var confirmedMetadata = false
    private var service: AppMihbaraService { .init(app: app) }
    private var digits: MadarNumberFormatter { service.digits }

    private var languageLabel: String {
        guard let code = inspection?.languageCode else { return "غير محددة في الملف" }
        if code.lowercased().hasPrefix("en") { return "English · الإنجليزية" }
        if code.lowercased().hasPrefix("ar") { return "العربية · Arabic" }
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
                        row("نوع الملف", detail: "EPUB \(value.version)؛ اجتاز فحص بنية الملف والحدود الأمنية.", detected: true)
                        row("اللغة", detail: value.appLanguage == "en" ? "\(languageLabel)؛ يفتح وضع القراءة الإنجليزية." : value.appLanguage == "ar" ? "\(languageLabel)؛ يفتح وضع القراءة العربية." : "اللغة في البيانات: \(languageLabel). اختر وضع القراءة أدناه.", detected: value.languageCode != nil)
                        row("البيانات", detail: value.author.isEmpty ? "العنوان من الملف؛ لم يُسجل مؤلف." : "العنوان والمؤلف من بيانات الملف.", detected: !value.author.isEmpty)
                        row("الفهرس", detail: value.outline.isEmpty ? "بلا فهرس إلكتروني قابل للتنقّل؛ لم نخمن فصول الكتاب." : "فهرس الملف: \(digits.string(value.outline.count)) عنوانًا.", detected: !value.outline.isEmpty)
                        let pageList = value.hasPageList ? "توجد قائمة صفحات للمصدر المطبوع" : "لا توجد قائمة صفحات مطبوعة"
                        let notes = value.hasFootnotes == true ? "اكتُشفت حواشٍ" : value.hasFootnotes == false ? "لم تُكتشف حواشٍ" : "تعذّر حسم وجود الحواشي"
                        row("الصور والجداول", detail: "تبقى ضمن الملف كما حفظها · \(pageList) · \(notes).", detected: true)
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
                                TextField("المؤلف، إن عُرف", text: $author, prompt: Text("المؤلف، إن عُرف").foregroundStyle(theme.secondaryInk))
                                    .textFieldStyle(.plain).font(MadarTypography.body()).multilineTextAlignment(.trailing)
                                    .accessibilityIdentifier("mihbara-epub-import-author")
                                Picker("لغة القراءة", selection: $language) {
                                    Text("العربية").tag("ar")
                                    Text("الإنجليزية").tag("en")
                                }
                                .font(MadarTypography.caption()).accessibilityIdentifier("mihbara-epub-import-language")
                                Text(value.direction == "rtl" ? "العربية · اتجاه من اليمين" : value.direction == "ltr" ? "English · left-to-right" : "اتجاه القراءة غير محدد")
                                    .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(14).background(theme.surface, in: .rect(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line.opacity(0.7), lineWidth: 1) }
                    .disabled(saving || confirmedMetadata)

                    HStack {
                        Text("الفهرس المستخرج").font(MadarTypography.section())
                        Spacer()
                        Text("\(digits.string(value.outline.count)) عناوين").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    }
                    if value.outline.isEmpty {
                        Text("لا يوجد فهرس إلكتروني في هذا الملف.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading).padding(.horizontal, 16)
                            .background(theme.surface, in: .rect(cornerRadius: 16))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(value.outline.enumerated()), id: \.offset) { index, item in
                                HStack(spacing: 12) {
                                    Text(digits.string(index + 1)).font(MadarTypography.caption().weight(.semibold)).foregroundStyle(theme.secondaryInk).frame(width: 24, alignment: .leading)
                                    Text(item.title).font(MadarTypography.body()).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10).padding(.leading, CGFloat(min(item.depth, 4) * 12))
                                .environment(\.layoutDirection, value.direction == "ltr" ? .leftToRight : .rightToLeft)
                                .accessibilityIdentifier("mihbara-epub-import-toc-\(index + 1)")
                                if index < value.outline.count - 1 { Divider().padding(.leading, 42) }
                            }
                        }
                        .background(theme.surface, in: .rect(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.line.opacity(0.7), lineWidth: 1) }
                    }

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

                    Button(saving ? "يُضاف…" : "أضفه إلى مكتبتي") { confirm() }
                        .buttonStyle(MadarPrimaryButton())
                        .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 300 || author.count > 300)
                        .accessibilityIdentifier("mihbara-epub-import-confirm")
                }
            }
            .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 24)
            .frame(maxWidth: 650).frame(maxWidth: .infinity)
        }
        .foregroundStyle(theme.ink).background(theme.background.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft).toolbarVisibility(.hidden, for: .navigationBar).statusBarHidden(true)
        .interactiveDismissDisabled(saving)
        .task { await inspect() }
        .onDisappear { if !saving && !finished { EPUBBookFiles.discard(id: fileID, root: app.bookStagingDirectory) } }
    }

    private func row(_ title: String, detail: String, detected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: detected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .regular)).foregroundStyle(detected ? theme.color("sunnah") : theme.secondaryInk)
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

    @MainActor private func inspect() async {
        guard inspection == nil, error == nil else { return }
        do {
            let value = try await service.stageEPUB(source, id: fileID)
            guard !Task.isCancelled else { EPUBBookFiles.discard(id: fileID, root: app.bookStagingDirectory); return }
            let publication = try await MihbaraEPUBLoader.open(at: EPUBBookFiles.stagedURL(id: fileID, root: app.bookStagingDirectory))
            defer { publication.close() }
            guard !Task.isCancelled else { EPUBBookFiles.discard(id: fileID, root: app.bookStagingDirectory); return }
            inspection = value
            if let readiumTitle = publication.metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines), !readiumTitle.isEmpty { title = readiumTitle }
            else { title = value.title }
            author = value.author.isEmpty ? publication.metadata.authors.map(\.name).joined(separator: "، ") : value.author
            language = value.appLanguage ?? "ar"
            cover = Self.thumbnail(value.coverData)
            confirmedMetadata = false
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
