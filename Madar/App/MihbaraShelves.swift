import SwiftData
import SwiftUI
import MadarCore
import MadarData
import MadarDesign

/// FB-34 (owner, 5 Nov 2026): the bookcase stays as it was, and the stand under it is gone; «الاحصائيات حقت الكتب
/// شف لها طريقه». So every book in hand gets one line of what the stand used to tell: where you stand, what is left,
/// how long that is, the margin note waiting ahead of you, and the one button that continues it.
struct MihbaraReadingNow: View {
    let app: AppSession
    let books: [MihbaraBook]
    let shapes: [UUID: MihbaraBookShape]
    let digits: MadarNumberFormatter
    let open: (MihbaraBook) -> Void
    @Environment(\.roomTheme) private var theme
    @State private var margins: [UUID: String] = [:]

    private var reading: [MihbaraBook] { books.filter { $0.shelf == "reading" }.sorted { $0.updated > $1.updated } }
    private var leathers: [UUID: Int] { MihbaraBookCovers.leatherIndices(for: books) }
    private var ink: Color { theme.color("onDesk") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !reading.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("بين يديك").font(MadarTypography.section()).foregroundStyle(ink.opacity(0.9))
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(reading.enumerated()), id: \.element.id) { index, book in
                        if index > 0 { Rectangle().fill(ink.opacity(0.12)).frame(height: 1) }
                        row(book, first: index == 0)
                    }
                    if let summary = finishedSummary { Text(summary).font(MadarTypography.fine()).foregroundStyle(ink.opacity(0.72)).padding(.top, 2) }
                }
                .padding(16)
                .background(LinearGradient(colors: [theme.color("desk").mix(with: theme.color("wood"), by: 0.35), theme.color("desk")], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(ink.opacity(0.1), lineWidth: 1) }
                .shadow(color: theme.ink.opacity(0.16), radius: 8, y: 5)
                .accessibilityElement(children: .contain).accessibilityIdentifier("mihbara-reading-now")
            }
        }
        .task(id: reading.map { "\($0.id)-\($0.page ?? -1)-\($0.progress ?? -1)" }) { loadMargins() }
    }

    private func row(_ b: MihbaraBook, first: Bool) -> some View {
        let stats = numbers(b)
        return HStack(alignment: .top, spacing: 14) {
            Button { open(b) } label: {
                MihbaraBookCover(book: b, shape: shapes[b.id], leather: leathers[b.id] ?? 0, digits: digits)
                    .scaleEffect(0.5).frame(width: 60, height: 84)
            }
            .buttonStyle(.madarPlain).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(MihbaraBookCovers.split(b.title).main).font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline))
                    .foregroundStyle(ink).lineLimit(2)
                if let p = b.progress {
                    Capsule().fill(ink.opacity(0.16)).frame(height: 5)
                        .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(theme.color("goldUnderstand")).frame(width: max(5, g.size.width * min(1, p))) } }
                        .accessibilityHidden(true)
                }
                Text(stats.position).font(MadarTypography.caption()).foregroundStyle(ink)
                if let left = stats.left { Text(left).font(MadarTypography.fine()).foregroundStyle(ink.opacity(0.75)) }
                if let margin = margins[b.id] {
                    Label(margin, systemImage: "text.quote").font(MadarTypography.fine()).foregroundStyle(theme.color("goldUnderstand"))
                        .lineLimit(2).accessibilityIdentifier("mihbara-shelf-margin-" + b.id.uuidString)
                }
                Button { open(b) } label: {
                    Text(stats.action).font(MadarTypography.caption()).bold()
                        .foregroundStyle(RoomTheme(room: "mihbara", dark: false).ink)
                        .padding(.horizontal, 16).frame(minHeight: 40)
                        .background(theme.color("goldUnderstand"), in: .capsule)
                }
                .buttonStyle(.madarPlain).padding(.top, 2)
                // The latest book in hand keeps the desk's old «continue» identity, which routes and tests rely on.
                .accessibilityIdentifier(first ? "mihbara-book-continue" : "mihbara-continue-" + b.id.uuidString)
            }
            Spacer(minLength: 0)
        }
    }

    /// «صفحة ١٤٧ من ٢٥٠، ٥٩٪» / «بقيت ١٠٣ صفحات، نحو ساعتين» / «أكمل من صفحة ١٤٨»; a book not begun says so.
    private func numbers(_ b: MihbaraBook) -> (position: String, left: String?, action: String) {
        let file = b.isReadableEPUB || b.isReadablePDF
        let read = file ? MihbaraCopy.pagesRead(b) : b.page.flatMap { $0 > 0 ? $0 : nil }
        let total = b.pages.flatMap { $0 > 0 ? $0 : nil }
        let percent = MihbaraCopy.progressPercent(b.progress)
        guard let read, read > 0 || percent != nil else {
            return ("لم تبدأه بعد" + (total.map { "، " + MihbaraCopy.pages($0, digits) } ?? ""), nil, "ابدأ القراءة")
        }
        var position = total.map { "صفحة " + digits.string(read) + " من " + digits.string($0) } ?? "صفحة " + digits.string(read)
        if let percent { position += "، " + digits.string(percent) + "٪" }
        let left = MihbaraCopy.remaining(pages: total, read: read, digits)
        let action = total.map { read < $0 } ?? true ? "أكمل من صفحة " + digits.string(read + 1) : (file ? "أكمل القراءة" : "افتح الكتاب")
        return (position, left, action)
    }

    /// The year so far, in the user's first calendar: «أنهيت هذه السنة ٣ كتب».
    private var finishedSummary: String? {
        let hijriFirst = app.string("core.firstCalendar") != "gregorian"
        let calendar = Calendar(identifier: hijriFirst ? .islamicUmmAlQura : .gregorian)
        let year = calendar.component(.year, from: .now)
        let count = books.filter { $0.shelf == "finished" && $0.finished.map { calendar.component(.year, from: $0) == year } == true }.count
        guard count > 0 else { return nil }
        let unit = hijriFirst ? " هـ" : " م"
        return "أنهيت في " + digits.string(year) + unit + " " + (count == 1 ? "كتابًا واحدًا" : count == 2 ? "كتابين" : MihbaraCopy.books(count, digits))
    }

    /// The smart margin: the note at or just ahead of where you stand («حاشيتك في صفحة ٥٢»); with none ahead, the latest.
    private func loadMargins() {
        let ids = Set(reading.map(\.id))
        guard !ids.isEmpty, let rows = try? ModelContext(app.container).fetch(FetchDescriptor<NotebookNote>()) else { margins = [:]; return }
        let live = rows.filter { row in
            guard let target = row.targetID else { return false }
            return ids.contains(target) && row.link == "page" && !row.isPrivate && row.deletedAt == nil && row.mergedInto == nil
                && !row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var next: [UUID: String] = [:]
        for book in reading {
            let notes = live.filter { $0.targetID == book.id }
            guard !notes.isEmpty else { continue }
            let here = (book.isReadableEPUB || book.isReadablePDF ? MihbaraCopy.pagesRead(book) : book.page) ?? 0
            if let ahead = notes.filter({ ($0.page ?? -1) >= here }).min(by: { ($0.page ?? 0) < ($1.page ?? 0) }), let page = ahead.page {
                next[book.id] = "حاشيتك في صفحة " + digits.string(page)
            } else if let latest = notes.max(by: { $0.updatedAt < $1.updatedAt }) {
                next[book.id] = "«" + String(latest.text.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines) + "»"
            }
        }
        margins = next
    }
}
