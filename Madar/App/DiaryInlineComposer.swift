import MadarCore
import MadarDesign
import PhotosUI
import SwiftUI
import UIKit

/// A draft write begun as a page closes or the day tab changes. The next composer or the full page waits for it before it reads the draft,
/// so leaving a page never shows an older draft for a moment (or loses the last words).
@MainActor enum DiaryDraftFlush {
    private static var pending: Task<Void, Never>?
    static func run(_ work: @escaping @MainActor () async -> Void) {
        let previous = pending
        pending = Task { await previous?.value; await work() }
    }
    static func settle() async { await pending?.value }
    /// Writing pages still on screen. A swipe back starts the pop long before the page's own flush is queued, so a composer
    /// waits for the page to be gone (never longer than a second) instead of guessing with a fixed sleep.
    static var livePages = 0
    static func settleAfterPages() async {
        var waited = 0
        while livePages > 0, waited < 40 { try? await Task.sleep(for: .milliseconds(25)); waited += 1 }
        await settle()
    }
}

/// What the shared voice controller does to the page around the composer: refresh after a take, host the consent ask and the title task.
private struct InlineVoiceEvents: ViewModifier {
    @Bindable var voice: DiaryVoiceController
    let editorOpen: Bool
    let saved: () -> Void
    @Binding var notice: String?
    func body(content: Content) -> some View {
        content
            .task { await voice.recoverRecordings() }
            .onChange(of: voice.lastMedia?.id) { _, id in if id != nil { saved() } }
            .onChange(of: voice.converting) { _, busy in if !busy { saved() } }
            .onChange(of: voice.message) { _, value in
                if !voice.recording, !voice.microphoneDenied, !value.isEmpty { notice = value }
            }
            .modifier(DiaryVoiceConsentAlert(controller: voice))
            .background { if !editorOpen { DiaryVoiceInsightTask(controller: voice).frame(width: 1, height: 1).accessibilityHidden(true) } }
    }
}

/// 10 Nov owner: writing in the diary is direct. One quiet field at the foot of today's page — type and send, pick a photo, change a line or write
/// after one right here. The full page (voice, camera, files) is one tap away and shares the same draft, so nothing typed is lost.
struct DiaryInlineComposer: View {
    @Bindable var app: AppSession
    @Binding var insertAt: Date?
    @Binding var anchor: String?
    @Binding var edit: DiaryLineEdit?
    @Binding var focusTick: Int
    /// True while the full writing page is open; when it closes the shared draft is read again.
    let editorOpen: Bool
    let openEditor: () -> Void
    let saved: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var text = ""
    @State private var editText = ""
    @State private var draftID = UUID()
    @State private var hasDraftRecord = false
    @State private var draftDay = "today"
    @State private var draftWritingDay: GregorianDay?
    @State private var saving = false
    @State private var failure: String?
    /// A quiet, non-error line (for example where a photo went).
    @State private var notice: String?
    @State private var draftTask: Task<Void, Never>?
    @State private var photo: PhotosPickerItem?
    @State private var loaded = false
    /// The text last written to the store, so reopening or leaving never rewrites an unchanged draft.
    @State private var lastSaved = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    private var voice: DiaryVoiceController { app.diaryVoice }
    private var voiceBusy: Bool { voice.recording || voice.savingAudio }
    private var voiceShown: Bool { voice.recording || voice.savingAudio || voice.converting || voice.needsConsent || voice.microphoneDenied }
    private var service: AppDiaryService { AppDiaryService(app: app, clock: { app.prayerNow() }) }
    private var field: Binding<String> { edit == nil ? $text : $editText }
    private var trimmed: String { field.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !trimmed.isEmpty && !saving && (edit == nil || editText != edit?.text) }

    var body: some View {
        VStack(spacing: 6) {
            if edit != nil || (insertAt != nil && anchor != nil) { chip }
            if let notice, failure == nil {
                Text(notice).font(MadarTypography.fine()).foregroundStyle(theme.color("ink3Text")).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("diary-inline-notice")
            }
            if let failure {
                Text(failure).font(MadarTypography.fine()).foregroundStyle(theme.color("late")).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("diary-inline-failure")
            }
            if voiceShown {
                DiaryVoiceFeedback(controller: voice, showsTranscriptEditor: false).accessibilityIdentifier("diary-inline-voice")
            }
            if voiceBusy {
                // One tap records and one tap stops, right here on the page; nothing opens, nothing moves.
                HStack(spacing: 12) {
                    Text(voice.recording ? "يُسجَّل صوتك…" : "يُحفظ التسجيل…").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                    Spacer(minLength: 4)
                    Button { Task { await voice.stop() } } label: {
                        Image(systemName: "stop.fill").font(.system(size: 18)).frame(width: 44, height: 44)
                            .foregroundStyle(theme.background).background(theme.color("late"), in: .circle).contentShape(Circle())
                    }.buttonStyle(.madarPlain).disabled(voice.savingAudio)
                        .accessibilityLabel("أوقف التسجيل واحفظه").accessibilityIdentifier("diary-inline-stop")
                }.padding(.horizontal, 8).frame(minHeight: 44)
            } else {
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Image(systemName: "photo").font(.system(size: 19)).frame(width: 44, height: 44).contentShape(Circle())
                }.buttonStyle(.madarPlain).foregroundStyle(theme.color("ink3Text")).disabled(edit != nil || saving)
                    .accessibilityLabel("أضف صورة").accessibilityIdentifier("diary-inline-photo")
                TextField(edit != nil ? "عدّل السطر…" : "اكتب ما تيسّر…", text: field, axis: .vertical)
                    .font(DiaryType.writing).lineLimit(1...5).focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
                    .background(theme.surface, in: .rect(cornerRadius: 22))
                    .overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.line, lineWidth: 0.7) }
                    .accessibilityIdentifier("diary-inline-field")
                if edit == nil {
                    // The full page stays one tap away (camera, files, a longer text); the identifiers keep their old meaning.
                    Button { Task { await keepDraft(); openEditor() } } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 15)).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.madarPlain).foregroundStyle(theme.color("ink3Text"))
                        .accessibilityLabel("افتح الورقة الكاملة: كاميرا وملفات").accessibilityIdentifier(trimmed.isEmpty ? "diary-day-write" : "diary-inline-expand")
                }
                if trimmed.isEmpty && edit == nil {
                    Button { Task { await startRecording() } } label: {
                        Image(systemName: "mic").font(.system(size: 19)).frame(width: 44, height: 44).contentShape(Circle())
                    }.buttonStyle(.madarPlain).foregroundStyle(theme.color("ink3Text"))
                        .accessibilityLabel("سجّل صوتًا").accessibilityIdentifier("diary-inline-record")
                } else {
                    Button { Task { await send() } } label: {
                        Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).frame(width: 44, height: 44)
                            .foregroundStyle(theme.background).background(theme.dark ? theme.accent : theme.ink, in: .circle)
                            .contentShape(Circle())
                    }.buttonStyle(.madarPlain).disabled(!canSend)
                        .accessibilityLabel(edit != nil ? "احفظ التعديل" : "أضف إلى الصفحة").accessibilityIdentifier("diary-inline-send")
                }
            }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8).frame(maxWidth: 680).frame(maxWidth: .infinity).background(theme.background)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: edit != nil || (insertAt != nil && anchor != nil))
        .task(id: editorOpen) {
            guard !editorOpen else { return }
            // What the field held when the wait began: anything different afterwards was typed by the user in the meantime.
            let before = text
            // The full page flushes its draft as it closes (a swipe back does it a moment later): read it after that, not before.
            await DiaryDraftFlush.settleAfterPages()
            await loadDraft(typedSince: before)
        }
        .onChange(of: editorOpen) { old, open in
            // Back from the full page (saved or closed) the keyboard goes down: the field above it would otherwise sit hidden behind it.
            if old, !open { focused = false; UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
        .onDisappear { if loaded, edit == nil, !trimmedText.isEmpty { DiaryDraftFlush.run { await keepDraft() } } }
        .onChange(of: text) { _, _ in if edit == nil { failure = nil; notice = nil; scheduleDraft() } }
        .onChange(of: editText) { _, _ in failure = nil }
        .onChange(of: edit) { _, value in if let value { editText = value.text; failure = nil; focused = true } }
        .onChange(of: focusTick) { _, _ in focused = true }
        .onChange(of: photo) { _, item in if let item { Task { await addPhoto(item) } } }
        .modifier(InlineVoiceEvents(voice: voice, editorOpen: editorOpen, saved: saved, notice: $notice))
    }

    private func startRecording() async {
        await keepDraft()
        focused = false
        guard let writingDay = try? service.currentDay() else { return }
        insertAt = nil; anchor = nil
        await voice.start(writingDay: writingDay)
    }

    private var chip: some View {
        HStack(spacing: 8) {
            Text(edit != nil ? "تعدّل هذا السطر" : "بعد: «" + (anchor ?? "") + "»")
                .font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).lineLimit(1)
            Spacer(minLength: 4)
            Button { edit = nil; insertAt = nil; anchor = nil; editText = ""; failure = nil } label: {
                Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.madarPlain).foregroundStyle(theme.color("ink3Text"))
                .accessibilityLabel("ألغِ").accessibilityIdentifier("diary-inline-chip-clear")
        }.padding(.horizontal, 6)
    }

    /// Reads the shared draft into the field, but never over words the user typed after the field appeared (`typedSince` is what it held before).
    private func loadDraft(typedSince before: String) async {
        let typed = text != before ? text : nil
        do {
            if let draft = try service.draft(margin: nil) {
                draftID = draft.id; hasDraftRecord = true; lastSaved = draft.text; draftDay = draft.day; draftWritingDay = draft.writingDay
                text = Self.merged(stored: draft.text, typed: typed)
            } else {
                hasDraftRecord = false; lastSaved = ""; draftID = UUID(); draftDay = "today"; draftWritingDay = nil
                text = typed ?? ""
            }
        } catch { failure = madarUserMessage(error) }
        loaded = true
        // Typed words that arrived before the draft was read are written like any other edit.
        if typed != nil { scheduleDraft() }
    }
    /// The stored draft with the words typed meanwhile after it; with nothing typed, the stored draft as it is.
    static func merged(stored: String, typed: String?) -> String {
        guard let typed, !typed.isEmpty else { return stored }
        if stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || stored == typed { return typed }
        return stored + "\n" + typed
    }
    private func currentWritingDay() throws -> GregorianDay {
        if let draftWritingDay { return draftWritingDay }
        return try service.currentDay()
    }
    private func scheduleDraft() {
        guard loaded, !saving, text != lastSaved else { return }
        draftTask?.cancel()
        draftTask = Task {
            do { try await Task.sleep(for: .milliseconds(600)); try Task.checkCancellation(); try await persistDraft() }
            catch is CancellationError {} catch { failure = madarUserMessage(error) }
        }
    }
    private func persistDraft() async throws {
        guard hasDraftRecord || !trimmedText.isEmpty else { return }
        guard text != lastSaved || !hasDraftRecord else { return }
        let value = text
        try await service.saveDraft(id: draftID, text: value, day: draftDay, margin: nil, writingDay: try currentWritingDay())
        hasDraftRecord = true; lastSaved = value
    }
    /// Cancels the pending debounce and waits for a write already under way, so an old write can never land after the commit.
    private func settleDraftTask() async {
        let pending = draftTask
        pending?.cancel(); await pending?.value
        draftTask = nil
    }
    private func keepDraft() async {
        await settleDraftTask()
        do { try await persistDraft() } catch { failure = madarUserMessage(error) }
    }
    private func send() async {
        guard canSend else { return }
        saving = true; failure = nil
        defer { saving = false }
        await settleDraftTask()
        do {
            if let edit {
                try await service.edit(edit.id, text: editText)
                self.edit = nil; editText = ""; focused = false
            } else {
                try await persistDraft()
                var payload: [String: MadarCore.JSONValue] = ["id": .string(draftID.uuidString)]
                if let insertAt, draftDay == "today", insertAt < app.prayerNow() { payload["at"] = .number(insertAt.timeIntervalSince1970) }
                try await app.executeDiaryCommand("diary.commitDraft", payload: payload, id: draftID)
                text = ""; lastSaved = ""; hasDraftRecord = false; draftID = UUID(); draftDay = "today"; draftWritingDay = nil
                insertAt = nil; anchor = nil
            }
            saved()
        } catch { failure = madarUserMessage(error) }
    }
    private func addPhoto(_ item: PhotosPickerItem) async {
        defer { photo = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let copy = await Task.detached(priority: .userInitiated, operation: { DiaryPhotoLibrary.smallCopy(of: data) }).value else {
                failure = "تعذّر فتح الصورة. اخترها مرة أخرى."; return
            }
            let writingDay = try service.currentDay()
            // D8: after «اكتب بعده» the photo takes the same in-between time a written line would, on today's page only.
            let at = insertAt.flatMap { $0 < app.prayerNow() ? $0 : nil }
            try await service.appendMedia(data: copy, kind: "photo", contentType: "image/jpeg", day: "today", writingDay: writingDay, at: at)
            failure = nil; saved()
            if insertAt != nil { insertAt = nil; anchor = nil }
        } catch { failure = madarUserMessage(error) }
    }
}
