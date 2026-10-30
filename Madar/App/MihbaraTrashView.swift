import SwiftData
import SwiftUI
import MadarCore
import MadarData
import MadarDesign

/// «سلة المحذوفات» (owner, 30 Oct 2026): a book, a highlight or a private note deleted by mistake comes back after the
/// undo toast is gone. Deletes are tombstones, so nothing here is copied or stored: the list reads the tombstones and
/// each «أعِده» runs the room's own command (`book.restore`, `highlight.save`, `notebook.savePrivate`).
struct MihbaraTrashView: View {
    let app: AppSession
    let onRestored: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var items: [Item] = []
    @State private var loaded = false
    @State private var restoring: UUID?

    struct Item: Identifiable {
        enum Kind { case book, highlight, note }
        let id: UUID; let kind: Kind; let title: String; let detail: String; let deletedAt: Date; let payload: [String: MadarCore.JSONValue]
    }
    private var digits: MadarNumberFormatter { .init(style: app.string("core.numerals") == "western" ? .western : .hindi) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("ما حذفته من المحبرة يبقى هنا لتعيده متى شئت.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                if loaded && items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "trash").font(.largeTitle).foregroundStyle(theme.secondaryInk)
                        Text("السلة فارغة").font(MadarTypography.section())
                        Text("إذا حذفت كتابًا أو تظليلًا أو ملاحظة تجده هنا.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    }.frame(maxWidth: .infinity).padding(.vertical, 40).accessibilityIdentifier("mihbara-trash-empty")
                }
                ForEach(items) { item in row(item) }
            }.padding(20)
        }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
        .navigationTitle("سلة المحذوفات").navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind == .book ? "book.closed" : item.kind == .highlight ? "highlighter" : "note.text")
                .font(.title3).foregroundStyle(theme.secondaryInk).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(MadarTypography.body()).lineLimit(2)
                Text(item.detail + "، حُذف " + ago(item.deletedAt)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
            Spacer(minLength: 8)
            Button("أعِده") { restore(item) }
                .font(MadarTypography.caption()).padding(.horizontal, 14).frame(minHeight: 44)
                .background(theme.accentFill, in: .capsule).foregroundStyle(theme.onAccent)
                .buttonStyle(.madarPlain).disabled(restoring != nil)
                .accessibilityIdentifier("mihbara-trash-restore-" + item.id.uuidString)
        }
        .padding(14).background(theme.surface, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine).accessibilityIdentifier("mihbara-trash-item-" + item.id.uuidString)
    }

    /// «قبل ٣ أيام» rather than a date, so no single-calendar date reaches the screen.
    private func ago(_ date: Date) -> String {
        let days = max(0, Int(app.prayerNow().timeIntervalSince(date) / 86_400))
        return days == 0 ? "اليوم" : days == 1 ? "أمس" : "قبل " + arabicCount(days, ["يوم", "يومين", "أيام", "يومًا"], digits)
    }

    private func load() {
        do {
            let context = ModelContext(app.container)
            let books = try context.fetch(FetchDescriptor<Book>()).filter { $0.mergedInto == nil }
            let live = Dictionary(books.filter { $0.deletedAt == nil }.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
            var result: [Item] = []
            for book in books where book.deletedAt != nil && live[book.id] == nil {
                result.append(.init(id: book.id, kind: .book, title: book.title, detail: book.author.isEmpty ? "كتاب" : book.author, deletedAt: book.deletedAt!, payload: ["id": .string(book.id.uuidString)]))
            }
            for h in try context.fetch(FetchDescriptor<Highlight>()) where h.deletedAt != nil && h.mergedInto == nil {
                // A highlight comes back only into a book that is on the shelves.
                guard let bookID = h.bookID, let title = live[bookID], let locator = String(data: h.locatorJSON, encoding: .utf8) else { continue }
                var payload: [String: MadarCore.JSONValue] = ["id": .string(h.id.uuidString), "bookID": .string(bookID.uuidString), "locator": .string(locator), "color": .string(h.color)]
                if let page = h.pageLabel { payload["pageLabel"] = .string(page) }
                result.append(.init(id: h.id, kind: .highlight, title: "تظليل في «" + title + "»", detail: h.pageLabel.map { "صفحة " + $0 } ?? "تظليل", deletedAt: h.deletedAt!, payload: payload))
            }
            for note in try context.fetch(FetchDescriptor<NotebookNote>()) where note.deletedAt != nil && note.mergedInto == nil && note.isPrivate && note.link == "general" {
                guard note.targetID.map({ live[$0] != nil }) ?? true, !note.text.isEmpty else { continue }
                result.append(.init(id: note.id, kind: .note, title: note.text, detail: note.targetID.flatMap { live[$0] }.map { "ملاحظة على «" + $0 + "»" } ?? "من الدفتر الخاص", deletedAt: note.deletedAt!, payload: ["id": .string(note.id.uuidString), "text": .string(String(note.text.prefix(2000)))]))
            }
            items = result.sorted { $0.deletedAt > $1.deletedAt }
        } catch { app.errorMessage = madarUserMessage(error) }
        loaded = true
    }

    private func restore(_ item: Item) {
        guard restoring == nil else { return }
        restoring = item.id
        let (name, message) = switch item.kind {
        case .book: ("book.restore", "أُعيد الكتاب إلى رفوفه")
        case .highlight: ("highlight.save", "أُعيد التظليل")
        case .note: ("notebook.savePrivate", "أُعيدت الملاحظة")
        }
        Task {
            defer { restoring = nil }
            do { try await app.executeBookCommand(name, payload: item.payload, undoMessage: message); load(); onRestored() }
            catch { app.errorMessage = madarUserMessage(error) }
        }
    }
}
