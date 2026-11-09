import SwiftUI
import SwiftData
import MadarCore
import MadarDesign
import MadarData
import MadarCommands

struct MihbaraNotebookContent: View {
    struct Note: Identifiable { let id: UUID; let text: String; let updatedAt: Date; let bookTitle: String?; let isBookNote: Bool }
    struct Editor: Identifiable { let id: UUID; let text: String }
    let app: AppSession
    let initialNoteID: UUID?
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var notes: [Note] = []
    @State private var editor: Editor?
    @State private var failure: String?
    @State private var initialNoteHandled = false
    #if DEBUG
    @State private var injectedLoadFailure = false
    #endif

    init(app: AppSession, initialNoteID: UUID? = nil) {
        self.app = app
        self.initialNoteID = initialNoteID
    }

    @State private var query = ""
    @State private var missingNote = false

    private var shown: [Note] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return notes }
        return notes.filter { $0.text.localizedStandardContains(needle) || ($0.bookTitle?.localizedStandardContains(needle) ?? false) }
    }

    /// The first line reads as the note's title; the rest is a short preview.
    private func parts(_ text: String) -> (title: String, rest: String) {
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = lines.first else { return ("", "") }
        return (String(first), lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespacesAndNewlines) : "")
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Button { editor = .init(id: UUID(), text: "") } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.pencil").foregroundStyle(theme.accent)
                        Text("اكتب فكرة أو اقتباسًا أو سؤالًا…").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).padding(.horizontal, 16)
                    .background(theme.surface, in: .rect(cornerRadius: 14)).contentShape(Rectangle())
                }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-note-add")
                if notes.count > 5 {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryInk)
                        TextField("ابحث في ملاحظاتك", text: $query).font(MadarTypography.body())
                    }.padding(.horizontal, 14).frame(minHeight: 44).background(theme.surface, in: .rect(cornerRadius: 12))
                }
                if missingNote {
                    Text("هذه الملاحظة لم تعد موجودة.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
                if let failure {
                    Text(failure).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        .accessibilityIdentifier("mihbara-notebook-read-error")
                    Button { load() } label: { Text("أعِد المحاولة").font(MadarTypography.body()).frame(minHeight: 44).contentShape(Rectangle()) }
                        .accessibilityIdentifier("mihbara-notebook-retry")
                } else if notes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.book.closed").font(.system(size: 34)).foregroundStyle(theme.accent)
                        Text("دفترك فارغ").font(MadarTypography.section())
                        Text("اكتب هنا ما يخطر لك وأنت تقرأ: فكرة، سؤال، أو سطر أعجبك. وستجده كله في مكان واحد.")
                            .font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 36).padding(.horizontal, 12)
                } else if shown.isEmpty {
                    Text("لا ملاحظة تحتوي «\(query)».").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    ForEach(shown) { note in
                        let split = parts(note.text)
                        Button { editor = .init(id: note.id, text: note.text) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                if note.isBookNote {
                                    Label(note.bookTitle.map { "من كتاب «\($0)»" } ?? "ملاحظة مرتبطة بكتاب", systemImage: "book.closed")
                                        .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(2)
                                }
                                Text(split.title).font(MadarTypography.section()).lineLimit(2).multilineTextAlignment(.leading)
                                if !split.rest.isEmpty {
                                    Text(split.rest).font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).lineLimit(3).multilineTextAlignment(.leading)
                                }
                                MadarDateLabel(app.dateLabels(GregorianDay.containing(note.updatedAt, in: app.activePlace.timeZone))).foregroundStyle(theme.secondaryInk)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16).background(theme.surface, in: .rect(cornerRadius: 14)).contentShape(Rectangle())
                        }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-note-" + note.id.uuidString)
                    }
                }
            }.padding(18)
        }
        .background(theme.background)
        .sheet(item: $editor) { current in
            MihbaraNotebookEditor(app: app, note: current, save: save, delete: delete)
                .environment(\.roomTheme, theme).presentationDragIndicator(.visible)
        }
        .toolbar {
            ToolbarItem(placement: .principal) { Text("الدفتر").font(MadarTypography.section()) }
            ToolbarItem(placement: .topBarTrailing) { Button("تمّ") { dismiss() }.accessibilityIdentifier("mihbara-notebook-close") }
        }
        .safeAreaInset(edge: .bottom) { if app.undoToastVisible { UndoToast(message: app.undoMessage, undo: { app.undo(); load() }, dismiss: app.hideUndoToast).hostsUndo(app).accessibilityIdentifier("mihbara-undo") } }
        .task { load() }
        .onChange(of: app.undoToken?.id) { load() }
        .onDisappear { notes.removeAll(); editor = nil }
    }

    private func load() {
        do {
            #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if !injectedLoadFailure, UUID(uuidString: environment["MADAR_UI_STORE_ID"] ?? "") != nil,
               environment["MADAR_UI_NOTE_READ_FAILURE_ONCE"] == "1" {
                injectedLoadFailure = true
                throw CocoaError(.fileReadUnknown)
            }
            #endif
            let context = ModelContext(app.container)
            let rows = try context.fetch(FetchDescriptor<NotebookNote>())
            let books = try context.fetch(FetchDescriptor<Book>())
            let titles = books.reduce(into: [UUID: String]()) { result, book in
                if book.deletedAt == nil && book.mergedInto == nil { result[book.id] = book.title }
            }
            let loadedNotes = rows.filter {
                $0.isPrivate && $0.deletedAt == nil && $0.mergedInto == nil
                    && $0.link == "general"
                    && ($0.targetID == nil || $0.targetID.map { titles[$0] != nil } == true)
            }.map {
                Note(id: $0.id, text: $0.text, updatedAt: $0.updatedAt,
                     bookTitle: $0.targetID.flatMap { titles[$0] },
                     isBookNote: $0.targetID.map { titles[$0] != nil } == true)
            }.sorted { $0.updatedAt > $1.updatedAt }
            notes = loadedNotes
            failure = nil
            if !initialNoteHandled {
                initialNoteHandled = true
                if let initialNoteID {
                    if let note = loadedNotes.first(where: { $0.id == initialNoteID }) { editor = .init(id: note.id, text: note.text) }
                    else { missingNote = true }
                }
            }
        } catch { notes.removeAll(); failure = "تعذّر فتح الملاحظات المحفوظة." }
    }

    private func save(_ note: Editor, text: String) async throws {
        try await app.executeBookCommand("notebook.savePrivate", payload: ["id": .string(note.id.uuidString), "text": .string(text)], undoMessage: "حُفظت الملاحظة")
        load()
    }

    private func delete(_ note: Editor) async throws {
        try await app.executeBookCommand("notebook.deletePrivate", payload: ["id": .string(note.id.uuidString)], undoMessage: "حُذفت الملاحظة")
        load()
    }
}

private struct MihbaraNotebookEditor: View {
    let app: AppSession
    let note: MihbaraNotebookContent.Editor
    let save: (MihbaraNotebookContent.Editor, String) async throws -> Void
    let delete: (MihbaraNotebookContent.Editor) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var text: String
    @State private var isSaving = false
    @State private var rootBlockerID = UUID()
    @State private var prompt: Prompt?
    @FocusState private var focused: Bool
    private enum Prompt {
        case delete, discard, saveFailed, deleteFailed
        var title: String {
            switch self {
            case .delete: "احذف هذه الملاحظة؟"
            case .discard: "اترك التعديلات؟"
            case .saveFailed: "لم تُحفظ الملاحظة"
            case .deleteFailed: "لم تُحذف الملاحظة"
            }
        }
        var message: String {
            switch self {
            case .delete: "يمكنك التراجع فور الحذف من زر «تراجع»."
            case .discard: "لن يُحفظ ما كتبته منذ فتح الملاحظة."
            case .saveFailed: "بقي نصك هنا. حاول الحفظ مرة أخرى أو أكمل الكتابة."
            case .deleteFailed: "ما زالت الملاحظة محفوظة. حاول مرة أخرى أو أبقها."
            }
        }
    }
    init(app: AppSession, note: MihbaraNotebookContent.Editor, save: @escaping (MihbaraNotebookContent.Editor, String) async throws -> Void, delete: @escaping (MihbaraNotebookContent.Editor) async throws -> Void) {
        self.app = app; self.note = note; self.save = save; self.delete = delete; _text = State(initialValue: note.text)
    }
    var body: some View {
        NavigationStack {
            TextEditor(text: $text).font(MadarTypography.body()).scrollContentBackground(.hidden).padding(12).background(theme.background)
                .focused($focused).task { if note.text.isEmpty { focused = true } }
                .accessibilityIdentifier("mihbara-note-text")
                .toolbar {
                    ToolbarItem(placement: .principal) { Text("ملاحظة").font(MadarTypography.section()) }
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button("إلغاء") { if text != note.text { prompt = .discard } else { dismiss() } }.madarWaitsForSave()
                            .accessibilityIdentifier("mihbara-note-cancel")
                        if !note.text.isEmpty { Button("احذف", role: .destructive) { prompt = .delete }.accessibilityIdentifier("mihbara-note-delete") }
#if DEBUG
                        if ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_ROOT_ROUTE_HARNESS"] == "1" {
                            Button("اختبر الرابط") { app.open(URL(string: "madar://mihbara/hadith/today")!) }.accessibilityIdentifier("ui-test-open-mihbara-link")
                        }
#endif
                    }
                    ToolbarItem(placement: .topBarTrailing) { Button("احفظ") { write(deleting: false) }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000).accessibilityIdentifier("mihbara-note-save") }
                }
        }.environment(\.roomTheme, theme).disabled(isSaving)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
#if DEBUG
                if ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_ROOT_ROUTE_HARNESS"] == "1",
                   ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_MULTIPLE_NOTES"] == "1" {
                    let noteID = StableIdentity.uuid(for: "mihbara-fixture-second-private-note")
                    Button("اختبر الملاحظة الثانية") { app.open(URL(string: "madar://mihbara/notebook/\(noteID.uuidString)")!) }
                        .accessibilityIdentifier("ui-test-open-mihbara-second-note")
                }
#endif
                if text.count > 2000 {
                    Text("اختصر الملاحظة إلى ألفي حرف حتى تُحفظ.")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(theme.surface)
                        .accessibilityIdentifier("mihbara-note-length-hint")
                }
            }
        }
        .madarSheetLock(saving: isSaving, draft: text != note.text)
        .onChange(of: isSaving || text != note.text, initial: true) { _, blocked in app.setMihbaraRootDraftBlocker(rootBlockerID, active: blocked) }
        .onDisappear { app.setMihbaraRootDraftBlocker(rootBlockerID, active: false) }
        .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }), presenting: prompt) { current in
            switch current {
            case .delete:
                Button("احذف", role: .destructive) { write(deleting: true) }
                Button("أبقها", role: .cancel) {}
            case .discard:
                Button("اتركها", role: .destructive) { dismiss() }
                Button("أكمل الكتابة", role: .cancel) {}
            case .saveFailed:
                Button("حاول مرة أخرى") { write(deleting: false) }
                Button("أكمل الكتابة", role: .cancel) {}
            case .deleteFailed:
                Button("حاول مرة أخرى") { write(deleting: true) }
                Button("أبقها", role: .cancel) {}
            }
        } message: { Text($0.message) }
    }
    private func write(deleting: Bool) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                if deleting { try await delete(note) } else { try await save(note, text) }
                dismiss()
            } catch { prompt = deleting ? .deleteFailed : .saveFailed }
        }
    }
}
