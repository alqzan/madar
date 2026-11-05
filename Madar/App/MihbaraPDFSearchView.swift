import SwiftUI
import MadarCore
import MadarDesign
import MadarCommands

/// The index belongs to this sheet. Dismissal, backgrounding and locking cancel
/// its task; OCR text is never persisted, exported or passed to Spotlight.
struct MihbaraPDFSearchView: View {
    let app: AppSession
    let book: MihbaraBook
    let select: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var pages: [PDFBookPageText] = []
    @State private var query = ""
    @State private var total = 0
    @State private var jobID: UUID? = UUID()
    @State private var phase = "scanning"
    @State private var failure: String?
    private var digits: MadarNumberFormatter { AppMihbaraService(app: app).digits }
    private var matches: [PDFBookPageText] {
        let needle = PDFBookPageText.normalize(query)
        return needle.isEmpty ? pages : pages.filter { $0.normalizedText.contains(needle) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("بين صفحات الكتاب").font(MadarTypography.cardTitle())
                    Spacer()
                    Button { dismiss() } label: { Text("تمّ").padding(.horizontal, 16).frame(minHeight: 44).glassEffect(.regular.interactive(), in: .capsule) }.buttonStyle(.madarPlain)
                        .accessibilityIdentifier("mihbara-pdf-search-close")
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryInk)
                    TextField("ابحث عن كلمة أو عبارة", text: $query)
                        .font(MadarTypography.body())
                        .submitLabel(.search).autocorrectionDisabled()
                        .accessibilityIdentifier("mihbara-pdf-search-query")
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("امسح البحث")
                        .accessibilityIdentifier("mihbara-pdf-search-clear")
                    }
                }
                .padding(.horizontal, 12).frame(minHeight: 52)
                .background(theme.surface, in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 8) {
                    if phase == "scanning" {
                        ProgressView(value: Double(pages.count), total: Double(max(1, total)))
                            .tint(theme.accentFill)
                        Text("أقرأ صفحة الملف \(digits.string(min(pages.count + 1, max(1, total)))) من \(digits.string(total))…")
                            .font(MadarTypography.caption())
                        Button("أوقف استخراج النص") { jobID = nil; phase = "stopped" }
                            .font(MadarTypography.caption()).frame(minHeight: 44)
                            .accessibilityIdentifier("mihbara-pdf-ocr-cancel")
                    } else if phase == "done" {
                        Text("اكتمل النص المتاح لصفحات الملف.").font(MadarTypography.caption())
                            .accessibilityIdentifier("mihbara-pdf-ocr-complete")
                    } else {
                        Text(failure ?? "توقف الاستخراج؛ يمكنك البحث في الصفحات المقروءة.")
                            .font(MadarTypography.caption())
                        Button("واصل استخراج النص") { failure = nil; phase = "scanning"; jobID = UUID() }
                            .frame(minHeight: 44).accessibilityIdentifier("mihbara-pdf-ocr-resume")
                    }
                    Text("يُقرأ النص الموجود أولًا، وتُقرأ صفحات الصور على جهازك. النص الضوئي قد يخطئ؛ راجع صورة الصفحة. يُحذف هذا النص عند إغلاق البحث.")
                        .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }
                if !PDFBookPageText.normalize(query).isEmpty {
                    Text(matches.isEmpty ? "لا صفحات مطابقة" : matches.count == 2 ? "العبارة في صفحتين" : "العبارة في " + MihbaraCopy.pages(matches.count, digits))
                        .font(MadarTypography.section())
                        .accessibilityIdentifier("mihbara-pdf-search-count")
                    if matches.isEmpty {
                        Text(phase == "done" ? "لم تظهر العبارة؛ راجع صورة الصفحة فقد يخطئ النص المستخرج." : "لم تظهر العبارة في الصفحات المقروءة حتى الآن.")
                            .font(MadarTypography.body())
                            .accessibilityIdentifier("mihbara-pdf-search-empty")
                    }
                }
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(matches) { page in
                        VStack(alignment: .leading, spacing: 8) {
                            Button { select(page.index) } label: {
                                HStack {
                                    Text("صفحة الملف \(digits.string(page.index + 1))")
                                    Spacer()
                                    Image(systemName: "arrow.up.forward")
                                }.font(MadarTypography.section()).frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("mihbara-pdf-result-\(page.index)")
                            if let excerpt = page.excerpt(matching: query) {
                                Text(excerpt).font(MadarTypography.body())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("mihbara-pdf-result-excerpt-\(page.index)")
                            } else if page.hasUnreliableArabicMapping {
                                Text("النص المستخرج غير واضح؛ راجع الصفحة الأصلية.")
                                    .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                                    .accessibilityIdentifier("mihbara-pdf-result-unreliable-\(page.index)")
                            }
                            Text(page.source == .optical ? "نص ضوئي تقريبي" : "من طبقة النص الأصلية")
                                .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                            DisclosureGroup("اقرأ النص المستخرج") {
                                Text(page.text.isEmpty ? "لم يتضح نص في هذه الصفحة." : page.text)
                                    .font(MadarTypography.body()).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.font(MadarTypography.caption())
                        }
                        .padding(14).background(theme.surface, in: .rect(cornerRadius: 16))
                    }
                }
            }.padding(20)
        }
        .foregroundStyle(theme.ink).background(theme.background.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
        .scrollDismissesKeyboard(.interactively)
        .task(id: jobID) { if let jobID { await scan(jobID) } }
    }

    @MainActor private func scan(_ id: UUID) async {
        do {
            let authorized = app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized
            guard authorized else { return }
            let bytes = try AppMihbaraService(app: app).pdfData(for: book)
            let reader = PDFBookTextReader(data: bytes, language: book.language)
            total = try await reader.pageCount()
            for index in pages.count..<total {
                let page: PDFBookPageText
                do { page = try await reader.page(at: index) }
                catch is CancellationError { throw CancellationError() }
                catch PDFBookTextReader.Failure.unsupportedLanguage { throw PDFBookTextReader.Failure.unsupportedLanguage }
                // One unreadable page is passed over (searched as empty) instead of stopping the whole scan.
                catch { page = PDFBookPageText(index: index, text: "", source: .optical) }
                try Task.checkCancellation()
                guard jobID == id, app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { return }
                pages.append(page)
            }
            try Task.checkCancellation()
            if jobID == id { phase = "done" }
        } catch is CancellationError {
            // A newer task, dismissal or the lock now owns the visible state.
        } catch {
            guard jobID == id, !Task.isCancelled else { return }
            phase = "failed"
            if case PDFBookTextReader.Failure.unsupportedLanguage = error {
                failure = "لغة الكتاب غير متاحة للتعرّف الضوئي على هذا الجهاز. تبقى صور الصفحات قابلة للقراءة."
            } else { failure = "لم يكتمل استخراج النص. يمكنك المحاولة من آخر صفحة قرأناها." }
        }
    }
}
