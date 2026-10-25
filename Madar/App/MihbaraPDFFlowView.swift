import SwiftUI
import MadarCore
import MadarDesign
import MadarCommands

/// Owner, 21 October 2026: a PDF can become a flowing book in two ways. Turath first, because its text is
/// edited, indexed and footnoted; otherwise the device reads every page (OCR for scanned pages) and
/// builds an EPUB that goes through the usual import review. The PDF itself stays in the library unchanged.
struct MihbaraPDFFlowView: View {
    let app: AppSession
    let book: MihbaraBook
    let onImported: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var phase = Phase.choosing
    @State private var done = 0
    @State private var total = 0
    @State private var converted: URL?
    @State private var summary: PDFBookEPUB.Summary?
    @State private var reviewing = false
    @State private var jobID: UUID?
    private var digits: MadarNumberFormatter { AppMihbaraService(app: app).digits }

    enum Phase: Equatable { case choosing, converting, ready, failed(String) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack {
                        VStack(spacing: 2) {
                            Text("كتاب منساب").font(.custom("thmanyahserifdisplay-Bold", size: 21, relativeTo: .title2))
                            Text(book.title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(1)
                        }
                        HStack {
                            Button { jobID = nil; dismiss() } label: { Label("رجوع", systemImage: "chevron.right").font(MadarTypography.caption()).frame(minHeight: 44) }
                                .accessibilityIdentifier("mihbara-pdf-flow-back")
                            Spacer()
                        }
                    }
                    Text("يتسع النص لشاشتك ويكبر خطه، وتبقى صفحات PDF الأصلية في مكتبتك كما هي.")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)

                    NavigationLink {
                        MihbaraTurathView(app: app, initialQuery: book.title) { dismiss(); onImported() }
                    } label: {
                        option("ابحث عنه في تراث", "إن كان في المكتبة الشاملة فنسخته أدق: نص محقق وفهرس وحواشٍ.", "books.vertical.fill", "desk", "onDesk")
                    }
                    .buttonStyle(.plain).disabled(phase == .converting).accessibilityIdentifier("mihbara-pdf-flow-turath")

                    Button { start() } label: {
                        option("حوّله على جهازك", "نقرأ نص كل صفحة، والصفحات المصوّرة نقرؤها ضوئيًا. لا يخرج شيء من جهازك.", "text.page.fill", "navy", "onNavy")
                    }
                    .buttonStyle(.plain).disabled(phase == .converting || phase == .ready).accessibilityIdentifier("mihbara-pdf-flow-device")

                    status
                }
                .padding(16).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            .foregroundStyle(theme.ink).background(theme.background.ignoresSafeArea())
            .environment(\.layoutDirection, .rightToLeft).toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $reviewing) {
                if let converted {
                    MihbaraEPUBImportView(app: app, source: converted) {
                        try? FileManager.default.removeItem(at: converted)
                        reviewing = false; dismiss(); onImported()
                    }
                }
            }
            .task(id: jobID) { if let jobID { await convert(jobID) } }
            .onDisappear { jobID = nil }
        }
    }

    private func option(_ title: String, _ subtitle: String, _ symbol: String, _ fill: String, _ ink: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.color(ink))
                .frame(width: 48, height: 48).background(theme.color(fill), in: .rect(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.custom("thmanyahserifdisplay-Bold", size: 19, relativeTo: .headline))
                Text(subtitle).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.left").font(.system(size: 13, weight: .medium)).foregroundStyle(theme.secondaryInk.opacity(0.72))
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(theme.surface, in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(theme.line.opacity(0.72), lineWidth: 1) }
        .contentShape(.rect(cornerRadius: 20))
    }

    @ViewBuilder private var status: some View {
        switch phase {
        case .choosing: EmptyView()
        case .converting:
            MadarCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(total == 0 ? "يفتح الملف…" : "يقرأ الصفحة \(digits.string(min(done + 1, total))) من \(digits.string(total))")
                        .font(MadarTypography.section()).contentTransition(.numericText())
                    ProgressView(value: Double(done), total: Double(max(total, 1))).tint(theme.color("accentText"))
                    Text("الصفحات المصوّرة أبطأ قليلًا. أبقِ هذه الصفحة مفتوحة.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    Button("إيقاف") { jobID = nil; phase = .choosing }.font(MadarTypography.caption()).frame(minHeight: 44)
                        .accessibilityIdentifier("mihbara-pdf-flow-cancel")
                }
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("mihbara-pdf-flow-progress")
        case .ready:
            MadarCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("صار جاهزًا", systemImage: "checkmark.circle").font(MadarTypography.section())
                    if let summary { Text(readyLine(summary)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true) }
                    Button("راجعه وأضفه إلى المكتبة") { reviewing = true }.buttonStyle(MadarPrimaryButton())
                        .accessibilityIdentifier("mihbara-pdf-flow-review")
                }
            }
        case .failed(let message):
            MadarCard { Text(message).font(MadarTypography.caption()).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("mihbara-pdf-flow-error") }
        }
    }

    private func readyLine(_ s: PDFBookEPUB.Summary) -> String {
        var parts = [MihbaraCopy.pages(s.pages, digits)]
        if s.opticalPages > 0 { parts.append("\(digits.string(s.opticalPages)) منها قُرئت من صورها") }
        if s.picturedPages > 0 { parts.append("\(digits.string(s.picturedPages)) بلا نص بقيت بصورتها كالغلاف والزخارف") }
        if !s.skippedPages.isEmpty { parts.append("\(digits.string(s.skippedPages.count)) لم يُستخرج نصها، ومكانها ملاحظة برقمها") }
        return parts.joined(separator: "، ") + "."
    }

    private func start() {
        guard phase != .converting else { return }
        done = 0; total = 0; summary = nil; phase = .converting; jobID = UUID()
    }

    private var authorized: Bool { app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized }

    @MainActor private func convert(_ id: UUID) async {
        do {
            guard authorized else { return }
            let bytes = try AppMihbaraService(app: app).pdfData(for: book)
            let reader = PDFBookTextReader(data: bytes, language: book.language)
            total = try await reader.pageCount()
            var pages: [PDFBookEPUB.Page] = []
            var pictures = 0
            /// A page without words keeps its picture (cover, basmala, ornament) instead of a «not extracted» note.
            func picture(_ index: Int) async throws -> (jpeg: Data?, blank: Bool) {
                guard pictures < PDFBookEPUB.maximumPictures else { return (jpeg: nil, blank: false) }
                let result: (jpeg: Data?, blank: Bool) = (try? await reader.pagePicture(at: index)) ?? (jpeg: nil, blank: false)
                if result.jpeg != nil { pictures += 1 }
                return result
            }
            for index in 0..<total {
                let label = try await reader.pageLabel(at: index)
                do {
                    var page = try await reader.page(at: index)
                    // Garbled embedded Arabic: read the page image instead of showing broken words.
                    if page.hasUnreliableArabicMapping, let optical = try? await reader.page(at: index, optical: true),
                       !optical.text.isEmpty { page = optical }
                    let wordless = page.hasUnreliableArabicMapping || PDFBookEPUB.paragraphs(page.text).isEmpty
                    // A scanned book's first page is its cover: keep it as a picture, not its OCR'd title and stamps.
                    let cover = index == 0 && page.source == .optical
                    if wordless || cover {
                        let shot = try await picture(index)
                        pages.append(cover && shot.jpeg != nil ? .init(text: "", optical: true, unreliable: false, label: label, image: shot.jpeg)
                                     : .init(page, label: label, image: shot.jpeg, blank: shot.blank))
                    } else { pages.append(.init(page, label: label)) }
                }
                catch is CancellationError { throw CancellationError() }
                // A page OCR cannot read becomes its picture, or an honest gap with its number, not a failed book.
                catch {
                    let shot = try await picture(index)
                    pages.append(.init(text: "", optical: false, unreliable: true, label: label, image: shot.jpeg, blank: shot.blank))
                }
                try Task.checkCancellation()
                guard jobID == id, authorized else { return }
                done = index + 1
            }
            let outline = try await reader.outline()
            let title = book.title, author = book.author, language = book.language, hash = book.fileHash ?? book.id.uuidString
            let epub = try await Task.detached(priority: .userInitiated) {
                try PDFBookEPUB.build(title: title, author: author, language: language, sourceHash: hash, pages: pages, outline: outline)
            }.value
            guard jobID == id else { return }
            let folder = app.bookStagingDirectory.deletingLastPathComponent().appendingPathComponent("PDFConversions")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-").prefix(80)
            let file = folder.appendingPathComponent((name.isEmpty ? "book" : String(name)) + ".epub")
            try epub.write(to: file, options: [.atomic, .completeFileProtection])
            converted = file; summary = PDFBookEPUB.summary(pages); phase = .ready
        } catch is CancellationError {
        } catch {
            guard jobID == id else { return }
            phase = .failed("تعذّر تحويل هذا الملف. يبقى PDF كما هو وتستطيع قراءته بصفحاته.")
        }
    }
}
