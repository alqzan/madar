import Foundation
import MadarData
import MadarCore
import MadarDesign

// The Mac app shares `AppSession` with iPhone and iPad. Prayer notifications on iOS are built on ActivityKit and the iOS app
// lifecycle and are not part of the Mac app yet, so no Mac screen schedules one. This stand-in keeps the session's types complete;
// it is never created or attached on the Mac, so the session runs its writes directly (as it does whenever no coordinator is attached).

@MainActor final class PrayerNotificationCoordinator {
    // The same category identifiers as the iOS coordinator, so a room reminder built by shared code names the same category.
    static let habitCategoryID = "habits.reminder"
    static let wirdCategoryID = "quran.wird"
    static func habitAmountCategoryID(_ habit: UUID) -> String { "habits.amount." + habit.uuidString }
    func attach(to session: AppSession) async {}
    func requestRefresh() {}
    func resumeAfterStoreMaintenance() async {}
    func requestAuthorization() async throws {}
    func refreshAfterSerializedMutation() async {}
    func withSerializedMutation<T>(_ operation: @MainActor () async throws -> T) async rethrows -> T { try await operation() }
    #if DEBUG
    func runSimulatorAcceptanceScenarioForTesting() async throws -> String { "UNAVAILABLE — macOS" }
    #endif
}


/// iOS wakes the app for the automatic backup through BackgroundTasks. The Mac has no such scheduler for a sandboxed app, so the
/// automatic backup runs when the window opens and when it comes back to the front (the root view already asks for it then).
@MainActor final class AppBackupBackgroundTasks {
    func reschedule(using service: AppBackupService) async {}
}

/// The Mac has no camera picker; the diary's camera button checks this and stays hidden, so `DiaryCameraCapture` is never shown.
enum UIImagePickerController {
    enum SourceType { case camera, photoLibrary }
    static func isSourceTypeAvailable(_ type: SourceType) -> Bool { false }
}
import SwiftUI
struct DiaryCameraCapture: View {
    let captured: (NSImage) -> Void
    let cancelled: () -> Void
    var body: some View { Color.clear.onAppear(perform: cancelled) }
}

/// The paper-book form on the Mac: the same two commands as the iPhone editor (`book.savePaper`, `book.updatePaper`), typed by hand.
/// The barcode scanner and contents scan (VisionKit) are iPhone-only, so the Mac asks only for title, author, pages and shelf.
struct MihbaraPaperIndexEditor: View {
    let app: AppSession
    let readingBooks: [MihbaraBook]
    let onSaved: () -> Void
    let existingBook: MihbaraBook?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var title: String
    @State private var author: String
    @State private var pages: String
    @State private var shelf = "want"
    @State private var saving = false
    @State private var problem: String?

    init(app: AppSession, readingBooks: [MihbaraBook], onSaved: @escaping () -> Void, existingBook: MihbaraBook? = nil) {
        self.app = app; self.readingBooks = readingBooks; self.onSaved = onSaved; self.existingBook = existingBook
        _title = State(initialValue: existingBook?.title ?? ""); _author = State(initialValue: existingBook?.author ?? "")
        _pages = State(initialValue: existingBook?.pages.map(String.init) ?? "")
    }
    private var pageCount: Int? {
        let latin = pages.map { $0.wholeNumberValue.map(String.init) ?? String($0) }.joined()
        return Int(latin).flatMap { (1...100000).contains($0) ? $0 : nil }
    }
    var body: some View {
        Form {
            TextField("عنوان الكتاب", text: $title).accessibilityIdentifier("mihbara-paper-title")
            TextField("المؤلف", text: $author).accessibilityIdentifier("mihbara-paper-author")
            TextField("عدد الصفحات، إن عرفته", text: $pages).accessibilityIdentifier("mihbara-paper-pages")
            if existingBook == nil {
                Picker("الرف", selection: $shelf) { Text("أبي أقرأه").tag("want"); Text("أقرؤه الآن").tag("reading"); Text("قرأته").tag("finished") }
            }
            if let problem { Text(problem).foregroundStyle(theme.color("dueText")) }
            HStack {
                Button("إلغاء") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(saving ? "جارٍ الحفظ…" : "احفظ") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("mihbara-paper-save")
            }
        }.formStyle(.grouped).frame(minWidth: 420, minHeight: 320).environment(\.layoutDirection, .rightToLeft)
    }
    private func save() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        problem = nil
        guard !pages.isEmpty ? pageCount != nil : true else { problem = "عدد الصفحات رقم بين ١ و١٠٠٠٠٠."; return }
        var payload: [String: MadarCore.JSONValue] = ["id": .string((existingBook?.id ?? UUID()).uuidString), "title": .string(name), "author": .string(author.trimmingCharacters(in: .whitespacesAndNewlines))]
        let command: String
        if let existingBook {
            command = "book.updatePaper"
            payload["pages"] = pageCount.map { .number(Double($0)) } ?? .null
            payload["position"] = .number(Double(existingBook.page ?? 0))
            payload["isbn13"] = existingBook.isbn13.map { .string($0) } ?? .null
            payload["tocJSON"] = existingBook.tocJSON.flatMap { String(data: $0, encoding: .utf8) }.map { .string($0) } ?? .null
        } else {
            command = "book.savePaper"; payload["shelf"] = .string(shelf)
            if let pageCount { payload["pages"] = .number(Double(pageCount)) }
            // Three books can be read at once; a fourth never silently pushes another one out.
            if shelf == "reading", readingBooks.count >= 3 { problem = "عندك ثلاثة كتب تقرؤها الآن. اختر «أبي أقرأه» أو أنهِ كتابًا أولًا."; return }
        }
        saving = true
        Task {
            do { try await app.executeBookCommand(command, payload: payload); onSaved(); dismiss() }
            catch { problem = madarUserMessage(error) }
            saving = false
        }
    }
}
