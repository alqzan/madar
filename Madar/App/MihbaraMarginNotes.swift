import SwiftData
import SwiftUI
import MadarCore
import MadarData
import MadarDesign

/// Owner, 30 Oct 2026: a note written on a passage («دُوّنت الملاحظة في دفتر الكتاب») had no place to be read again or
/// edited. The book card now lists the book's margin notes, and each opens in a full page with the passage above it,
/// so a long note keeps room to breathe while the keyboard is up. Edits reuse `notebook.savePage` with the same id.
struct MihbaraMarginNote: Identifiable, Equatable {
    let id: UUID; let bookID: UUID; var text: String; let locator: String; let page: Int?; let updatedAt: Date
    /// The passage the note was written on, from the saved locator («text.highlight»), when it carries one.
    var passage: String? {
        guard let data = locator.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? [String: Any] else { return nil }
        let value = ((text["highlight"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    @MainActor static func load(_ app: AppSession, bookID: UUID) throws -> [MihbaraMarginNote] {
        try ModelContext(app.container).fetch(FetchDescriptor<NotebookNote>())
            .filter { $0.targetID == bookID && $0.link == "page" && !$0.isPrivate && $0.deletedAt == nil && $0.mergedInto == nil && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .compactMap { row in
                guard let data = row.locatorJSON, let locator = String(data: data, encoding: .utf8) else { return nil }
                return .init(id: row.id, bookID: bookID, text: row.text, locator: locator, page: row.page, updatedAt: row.updatedAt)
            }
            .sorted { ($0.page ?? .max, $1.updatedAt) < ($1.page ?? .max, $0.updatedAt) }
    }
}

struct MihbaraMarginNotesSection: View {
    let app: AppSession
    let bookID: UUID
    @Environment(\.roomTheme) private var theme
    @State private var notes: [MihbaraMarginNote] = []
    private var digits: MadarNumberFormatter { .init(style: app.string("core.numerals") == "western" ? .western : .hindi) }

    var body: some View {
        // A container that always exists, so `.task` runs even before there is anything to list.
        VStack(alignment: .leading, spacing: 0) {
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("هوامشك على الكتاب").font(MadarTypography.section()).accessibilityAddTraits(.isHeader)
                    ForEach(notes) { note in
                        NavigationLink {
                            MihbaraMarginNoteEditor(app: app, note: note) { load() }.environment(\.roomTheme, theme)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                if let passage = note.passage {
                                    Text("«" + passage + "»").font(.custom("Amiri-Regular", size: 15, relativeTo: .callout))
                                        .foregroundStyle(theme.secondaryInk).lineLimit(1)
                                }
                                Text(note.text).font(MadarTypography.body()).lineLimit(3).multilineTextAlignment(.leading)
                                if let page = note.page { Text("صفحة " + digits.string(page)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(theme.surface, in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-margin-note-" + note.id.uuidString)
                    }
                }
            }
        }
        .task { load() }
    }
    private func load() { notes = (try? MihbaraMarginNote.load(app, bookID: bookID)) ?? [] }
}

/// A full page: the passage stays in view above the note, and the editor takes the rest of the screen.
struct MihbaraMarginNoteEditor: View {
    let app: AppSession
    let note: MihbaraMarginNote
    let onSaved: () -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saving = false
    @State private var rootBlockerID = UUID()
    @State private var alert: String?
    @FocusState private var focused: Bool
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var blocksRootRoute: Bool {
        saving || trimmed != note.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
#if DEBUG
            if ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_ROOT_ROUTE_HARNESS"] == "1" {
                Button("اختبر رابط الجذر") { app.open(URL(string: "madar://mihbara")!) }
                    .accessibilityIdentifier("mihbara-margin-root-route")
            }
#endif
            if let passage = note.passage {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(theme.accentFill).frame(width: 3)
                    Text(passage).font(.custom("Amiri-Regular", size: 17, relativeTo: .body)).lineSpacing(4).lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine).accessibilityIdentifier("mihbara-margin-passage")
            }
            TextEditor(text: $text).font(MadarTypography.body()).scrollContentBackground(.hidden).focused($focused)
                .padding(10).background(theme.surface, in: .rect(cornerRadius: 16))
                .accessibilityLabel("نص الملاحظة").accessibilityIdentifier("mihbara-margin-text")
            Text(trimmed.count > 2000 ? "اختصر الملاحظة إلى ألفي حرف حتى تُحفظ." : "تبقى مربوطة بهذه الفقرة في دفتر الكتاب.")
                .font(MadarTypography.fine()).foregroundStyle(trimmed.count > 2000 ? theme.ink : theme.secondaryInk)
        }
        .padding(20)
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.accent)
        .navigationTitle(note.page.map { "هامش صفحة " + MadarNumberFormatter(style: app.string("core.numerals") == "western" ? .western : .hindi).string($0) } ?? "هامش")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("احفظ") { save() }
                    .disabled(saving || trimmed.isEmpty || trimmed.count > 2000 || trimmed == note.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .accessibilityIdentifier("mihbara-margin-save")
            }
        }
        .onAppear { text = note.text; focused = true }
        // The book card is a sheet that covers the app's own alert, so a failed save says so here.
        .alert("الهامش", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Button("حسنًا", role: .cancel) { alert = nil }
        } message: { Text(alert ?? "") }
        .madarSheetLock(saving: saving, draft: trimmed != note.text.trimmingCharacters(in: .whitespacesAndNewlines))
        .onChange(of: blocksRootRoute, initial: true) { _, blocked in
            app.setMihbaraRootDraftBlocker(rootBlockerID, active: blocked)
        }
        .onDisappear { app.setMihbaraRootDraftBlocker(rootBlockerID, active: false) }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        var payload: [String: MadarCore.JSONValue] = ["id": .string(note.id.uuidString), "bookID": .string(note.bookID.uuidString), "text": .string(trimmed), "locator": .string(note.locator)]
        if let page = note.page { payload["page"] = .number(Double(page)) }
        Task {
            defer { saving = false }
            do { try await app.executeBookCommand("notebook.savePage", payload: payload, undoMessage: "عُدّلت الملاحظة"); onSaved(); dismiss() }
            catch { alert = madarUserMessage(error) }
        }
    }
}
