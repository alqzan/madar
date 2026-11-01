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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("ملاحظاتك الخاصة").font(MadarTypography.title()); Spacer(); Button { editor = .init(id: UUID(), text: "") } label: { Label("ملاحظة جديدة", systemImage: "plus") }.accessibilityIdentifier("mihbara-note-add") }
                if let failure {
                    Text(failure).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        .accessibilityIdentifier("mihbara-notebook-read-error")
                    Button("أعِد المحاولة") { load() }.font(MadarTypography.body()).frame(minHeight: 44)
                        .accessibilityIdentifier("mihbara-notebook-retry")
                } else if notes.isEmpty {
                    Text("ابدأ بملاحظة صغيرة؛ ستجدها هنا حين تعود.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
                } else {
                    ForEach(notes) { note in
                        Button { editor = .init(id: note.id, text: note.text) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                if note.isBookNote {
                                    Label(note.bookTitle.map { "من كتاب «\($0)»" } ?? "ملاحظة مرتبطة بكتاب", systemImage: "book.closed")
                                        .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(2)
                                }
                                Text(note.text).font(MadarTypography.body()).lineLimit(5).multilineTextAlignment(.leading)
                                MadarDateLabel(app.dateLabels(GregorianDay.containing(note.updatedAt, in: app.activePlace.timeZone))).foregroundStyle(theme.secondaryInk)
                            }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(16).background(theme.surface, in: .rect(cornerRadius: 14))
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
            ToolbarItem(placement: .principal) { Text("دفتر المحبرة").font(MadarTypography.section()) }
            ToolbarItem(placement: .topBarTrailing) { Button("تمّ") { dismiss() }.accessibilityIdentifier("mihbara-notebook-close") }
        }
        .safeAreaInset(edge: .bottom) { if app.undoToastVisible { UndoToast(message: app.undoMessage, undo: { app.undo(); load() }, dismiss: app.hideUndoToast).accessibilityIdentifier("mihbara-undo") } }
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
                    guard let note = loadedNotes.first(where: { $0.id == initialNoteID }) else {
                        failure = "فكرة الدفتر لم تعد موجودة."
                        return
                    }
                    editor = .init(id: note.id, text: note.text)
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
            case .delete: "يمكنك التراجع عن الحذف من دفتر المحبرة."
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
                .accessibilityIdentifier("mihbara-note-text")
                .toolbar {
                    ToolbarItem(placement: .principal) { Text("ملاحظة خاصة").font(MadarTypography.section()) }
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
