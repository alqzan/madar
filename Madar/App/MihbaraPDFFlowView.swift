import SwiftUI
import MadarCore
import MadarDesign
import MadarCommands

/// Owner, 21 October 2026: a PDF can become a flowing book in two ways. Turath first, because its text is
/// edited, indexed and footnoted; otherwise the device reads every page (OCR for scanned pages) in the
/// background (`MihbaraConversions`). The PDF itself stays unchanged as the book's original.
struct MihbaraPDFFlowView: View {
    let app: AppSession
    let book: MihbaraBook
    let onImported: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    private var conversions: MihbaraConversions { .shared }
    private var job: MihbaraConversions.Job? { conversions.job(for: book.id) }
    private var running: Bool { job?.state == .running }

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
                            Button { dismiss() } label: { Label("رجوع", systemImage: "chevron.right").font(MadarTypography.caption()).frame(minHeight: 44) }
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
                    .buttonStyle(.plain).disabled(running).accessibilityIdentifier("mihbara-pdf-flow-turath")

                    // Owner, 25 Oct 2026: the conversion runs while the person moves around the app.
                    Button { conversions.start(book, app: app); dismiss() } label: {
                        option("حوّله على جهازك", "نقرأ كل صفحة على جهازك، والمصوّرة ضوئيًا، وتتنقل في التطبيق وهو يعمل. يصير الكتاب منسابًا على رفّه، والـPDF أصله.", "text.page.fill", "navy", "onNavy")
                    }
                    .buttonStyle(.plain).disabled(running).accessibilityIdentifier("mihbara-pdf-flow-device")

                    status
                }
                .padding(16).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            .foregroundStyle(theme.ink).background(theme.background.ignoresSafeArea())
            .environment(\.layoutDirection, .rightToLeft).toolbarVisibility(.hidden, for: .navigationBar)
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
        if let job { MihbaraConversionCard(job: job, digits: AppMihbaraService(app: app).digits, onOpen: nil) }
    }
}

/// A conversion in the room: its progress while it runs, and «افتحه» once the book is on its shelf.
struct MihbaraConversionCard: View {
    let job: MihbaraConversions.Job
    let digits: MadarNumberFormatter
    let onOpen: ((UUID) -> Void)?
    @Environment(\.roomTheme) private var theme

    var body: some View {
        MadarCard {
            VStack(alignment: .leading, spacing: 10) {
                switch job.state {
                case .running:
                    Text("يحوّل «\(job.title)» إلى كتاب منساب").font(MadarTypography.section())
                    Text(job.total == 0 ? "يفتح الملف…" : "يقرأ الصفحة \(digits.string(min(job.done + 1, job.total))) من \(digits.string(job.total))")
                        .font(MadarTypography.caption()).contentTransition(.numericText())
                    ProgressView(value: Double(job.done), total: Double(max(job.total, 1))).tint(theme.color("accentText"))
                    Text("تنقّل في التطبيق كما تشاء؛ يكمل وحده ويضعه على رفّه.")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                    Button("إيقاف") { MihbaraConversions.shared.cancel(job.id) }.font(MadarTypography.caption()).frame(minHeight: 44)
                        .accessibilityIdentifier("mihbara-pdf-flow-cancel")
                case .finished(let bookID):
                    Label("صار «\(job.title)» كتابًا منسابًا", systemImage: "checkmark.circle").font(MadarTypography.section())
                    if let summary = job.summary {
                        Text(readyLine(summary)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 12) {
                        if let bookID, let onOpen {
                            Button("افتحه") { MihbaraConversions.shared.dismiss(job.id); onOpen(bookID) }.buttonStyle(MadarPrimaryButton())
                                .accessibilityIdentifier("mihbara-pdf-flow-open")
                        }
                        Button("حسنًا") { MihbaraConversions.shared.dismiss(job.id) }.font(MadarTypography.caption()).frame(minHeight: 44)
                    }
                case .failed(let message):
                    Text(message).font(MadarTypography.caption()).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("mihbara-pdf-flow-error")
                    Button("حسنًا") { MihbaraConversions.shared.dismiss(job.id) }.font(MadarTypography.caption()).frame(minHeight: 44)
                }
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("mihbara-pdf-flow-progress")
    }

    private func readyLine(_ s: PDFBookEPUB.Summary) -> String {
        var parts = [MihbaraCopy.pages(s.pages, digits)]
        if s.opticalPages > 0 { parts.append("\(digits.string(s.opticalPages)) منها قُرئت من صورها") }
        if s.picturedPages > 0 { parts.append("\(digits.string(s.picturedPages)) بلا نص بقيت بصورتها كالغلاف والزخارف") }
        if !s.skippedPages.isEmpty { parts.append("\(digits.string(s.skippedPages.count)) لم يُستخرج نصها، ومكانها ملاحظة برقمها") }
        return parts.joined(separator: "، ") + ". والـPDF أصله تفتحه من «الأصل»."
    }
}
