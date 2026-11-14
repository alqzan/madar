import MadarCore
import MadarDesign
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
            .background { DiaryVoiceInsightTask(controller: voice).frame(width: 1, height: 1).accessibilityHidden(true) }
    }
}

/// 10 Nov owner: writing in the diary is direct. One quiet field at the foot of today's page — type and send, pick a photo, change a line or write
/// after one right here. 12 Nov: the same field grows in place into the full writing surface (tools, voice, formatting) and folds back with the
/// same words and the same draft; there is no second page to push.
struct DiaryInlineComposer: View {
    @Bindable var app: AppSession
    @Binding var insertAt: Date?
    @Binding var anchor: String?
    @Binding var edit: DiaryLineEdit?
    @Binding var focusTick: Int
    /// The composer fills the page (drag the grabber up, or the expand button); «تمّ» or a drag down folds it back.
    @Binding var expanded: Bool
    /// The page behind the grown field, so the surface can say what is already written there.
    var page: DiaryDisplayDay? = nil
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
    @State private var rich = AttributedString()
    @State private var richSelection = AttributedTextSelection()
    @State private var cameraOpen = false
    @State private var choosingFile = false
    @State private var draftStatus = ""
    /// The Markdown the formatted field started from; a change that leaves it equal is not the user's.
    @State private var richBaseline = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @Environment(\.scenePhase) private var scenePhase
    /// True while the field is being folded out or the keyboard bar is used: losing focus then is not a boundary.
    @State private var holdCommit = false

    private var voice: DiaryVoiceController { app.diaryVoice }
    private var voiceBusy: Bool { voice.recording || voice.savingAudio }
    private var voiceShown: Bool { voice.recording || voice.savingAudio || voice.converting || voice.needsConsent || voice.microphoneDenied }
    private var service: AppDiaryService { AppDiaryService(app: app, clock: { app.prayerNow() }) }
    private var field: Binding<String> { edit == nil ? $text : $editText }
    private var trimmed: String { field.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !trimmed.isEmpty && !saving && (edit == nil || editText != edit?.text) }
    /// Words that carry formatting are never shown as raw marks: the folded field shows them formatted (read-only) and a tap opens the full surface.
    private var formatted: Bool { DiaryRichText.hasFormatting(field.wrappedValue) }
    private var words: Int { field.wrappedValue.split(whereSeparator: { $0.isWhitespace }).count }
    private var chipShown: Bool { edit != nil || (insertAt != nil && anchor != nil) }

    private func toggle(_ open: Bool) {
        if reduceMotion { expanded = open } else { withAnimation(.snappy(duration: 0.28)) { expanded = open } }
    }

    var body: some View {
        VStack(spacing: 6) {
            grabber
            if expanded { expandedHeader; dayChoice }
            if let note = staleDayNote { Text(note).font(MadarTypography.fine()).foregroundStyle(theme.color("ink3Text")).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("diary-draft-day-note") }
            if chipShown { chip }
            if draftDay == "yesterday", !expanded, edit == nil {
                Text("ستُحفظ في صفحة أمس").font(MadarTypography.fine()).foregroundStyle(theme.color("late")).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("diary-draft-yesterday-note")
            }
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
            if expanded {
                savedContext
                richField
                if edit == nil, let day = try? service.currentDay() {
                    DiaryDayPhotos(app: app, day: day) { asset in await linkLibraryPhoto(asset) }
                }
                if voiceBusy { voiceRow } else { toolsRow }
            } else if voiceBusy {
                voiceRow
            } else {
                collapsedRow
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8).frame(maxWidth: 680, maxHeight: expanded ? .infinity : nil).frame(maxWidth: .infinity).background(theme.background)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: chipShown)
        .task {
            // The shared draft is read once the page is up (a page that was just left flushes its draft first). What the field holds when the wait
            // begins is remembered: anything different afterwards was typed by the user in the meantime and is never overwritten.
            let before = text
            await DiaryDraftFlush.settleAfterPages()
            await loadDraft(typedSince: before)
        }
        .task {
            while !Task.isCancelled {
                currentDay = try? service.currentDay()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
#if DEBUG
        .task(id: app.diaryBoundaryUITestClockOverride) { currentDay = try? service.currentDay() }
#endif
        .onDisappear { if loaded, edit == nil, !trimmedText.isEmpty { DiaryDraftFlush.run { await keepDraft() } } }
        // 14 Nov owner (T10): leaving the app is a boundary. What was written becomes the line; no idle timer ever commits (one paragraph stays one line).
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background, loaded, edit == nil, canSend, !expanded, !voiceBusy else { return }
            Task { await send() }
        }
        .onChange(of: focused) { old, new in
            // Leaving the field (a tap on the page, another room) is a boundary; folding out or the keyboard bar are not.
            guard old, !new, !holdCommit, loaded, edit == nil, canSend, !expanded, !voiceBusy, !cameraOpen, !choosingFile else { return }
            Task { await send() }
        }
        .toolbar {
            // One bar above the keyboard, only while this composer's field has the cursor.
            ToolbarItemGroup(placement: .keyboard) {
                if focused, edit == nil, !expanded {
                    PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "photo") }.accessibilityLabel("أضف صورة").accessibilityIdentifier("diary-keyboard-photo")
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { holdCommit = true; focused = false; cameraOpen = true } label: { Image(systemName: "camera") }
                            .accessibilityLabel("التقط صورة").accessibilityIdentifier("diary-keyboard-camera")
                    }
                    if trimmed.isEmpty {
                        Button { holdCommit = true; Task { await startRecording(); holdCommit = false } } label: { Image(systemName: "mic") }
                            .accessibilityLabel("سجّل صوتًا").accessibilityIdentifier("diary-keyboard-record")
                    }
                    Spacer()
                    Button("تمّ") { focused = false }.accessibilityIdentifier("diary-keyboard-done")
                }
            }
        }
        .onChange(of: text) { _, _ in if edit == nil { failure = nil; notice = nil; scheduleDraft() } }
        .onChange(of: editText) { _, _ in failure = nil }
        .onChange(of: edit) { _, value in
            if let value {
                editText = value.text; failure = nil
                // A line with formatting is edited on the full surface, where it shows formatted instead of as raw marks.
                if DiaryRichText.hasFormatting(value.text) { toggle(true) } else { focused = true }
            }
        }
        .onChange(of: focusTick) { _, _ in if !expanded { focused = true } else { focusRich() } }
        .onChange(of: photo) { _, item in if let item { Task { await addPhoto(item) } } }
        .onChange(of: expanded) { _, open in
            if open {
                let start = DiaryRichText.attributed(fromMarkdown: field.wrappedValue)
                richBaseline = DiaryRichText.markdown(from: start)
                rich = start
                richSelection = AttributedTextSelection(insertionPoint: rich.endIndex)
                focusRich()
            } else { focused = false }
        }
        .onChange(of: rich) { _, new in
            // The words are kept as Markdown: the draft, the commit and the collapsed field all read this one string.
            let markdown = DiaryRichText.markdown(from: new)
            guard markdown != richBaseline else { return }
            richBaseline = markdown
            if markdown != field.wrappedValue { field.wrappedValue = markdown }
        }
        .fullScreenCover(isPresented: $cameraOpen) {
            DiaryCameraCapture(captured: cameraCaptured, cancelled: { cameraOpen = false; holdCommit = false }).ignoresSafeArea()
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.data]) { result in Task { await addFile(result) } }
        .modifier(InlineVoiceEvents(voice: voice, saved: saved, notice: $notice))
    }

    private func focusRich() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            if expanded { focused = true }
        }
    }

    // MARK: Pieces

    /// A small handle: drag it up to grow the field, down to fold it.
    private var grabber: some View {
        Capsule().fill(theme.line).frame(width: 38, height: 4).frame(maxWidth: .infinity, minHeight: 14)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.height < -24, !expanded { toggle(true) }
                else if value.translation.height > 24, expanded { toggle(false) }
            })
            .accessibilityHidden(true).accessibilityIdentifier("diary-inline-grabber")
    }

    private var expandedHeader: some View {
        HStack(spacing: 10) {
            // 14 Nov owner (T10): no send button for new words. Autosave keeps the draft; «تمّ» (or leaving the field or the app) makes it the line.
            if edit != nil {
                Button { toggle(false) } label: { Text("إلغاء").font(DiaryType.label).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                    .buttonStyle(.madarPlain).foregroundStyle(theme.accent).accessibilityIdentifier("diary-editor-cancel")
            }
            Text(MadarInlineText.joined([wordCount(words), draftStatus].filter { !$0.isEmpty })).font(MadarTypography.fine())
                .foregroundStyle(theme.color("ink3Text")).lineLimit(1).accessibilityIdentifier("diary-draft-status")
            Spacer(minLength: 4)
            Button { finish() } label: {
                Text(saving ? "يُحفظ…" : edit != nil ? "احفظ التعديل" : "تمّ").font(.custom("thmanyahsans-Bold", size: 13, relativeTo: .subheadline))
                    .padding(.horizontal, 16).frame(minHeight: 44).foregroundStyle(theme.background)
                    .background(theme.dark ? theme.accent : theme.ink, in: .capsule).opacity(edit != nil && !canSend ? 0.4 : 1)
            }.buttonStyle(.madarPlain).disabled(saving || (edit != nil && !canSend)).accessibilityIdentifier("diary-editor-save")
        }
    }
    /// «تمّ»: what was written becomes the line (nothing to commit: the surface just folds).
    private func finish() {
        if edit == nil, !canSend { toggle(false); return }
        Task { await send() }
    }

    /// While the field covers the page: the latest line already there and what is attached, in one quiet line each.
    @ViewBuilder private var savedContext: some View {
        if let page {
            if let last = page.lines.last(where: { $0.kind != "intention" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("كتبت في هذه الصفحة").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    Text(last.markdown == true ? DayOneMarkdown.plain(last.text) : last.text).font(DiaryType.writing).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("diary-editor-saved-context")
            }
            if !page.media.isEmpty {
                Label(service.attachmentSummary(page.media), systemImage: "paperclip").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine).accessibilityIdentifier("diary-editor-saved-media")
            }
        }
    }

    @State private var currentDay: GregorianDay?
    /// A draft begun on an earlier day (the day turned at Fajr while it was open) keeps that day's page; the writer is told.
    private var staleDayNote: String? {
        guard edit == nil, let writing = draftWritingDay, let today = currentDay,
              (draftDay == "today" && writing < today) || (draftDay == "yesterday" && writing < today.adding(days: -1)) else { return nil }
        return MadarInlineText.joined(["مسودة عن " + service.diaryDates(writing), "تُحفظ في صفحتها الأصلية"])
    }
    /// «اليوم» or «أمس»: the late-writing choice, only on the grown surface (today's page itself takes today's lines).
    @ViewBuilder private var dayChoice: some View {
        if edit == nil {
            HStack(spacing: 8) {
                dayButton("today", "اليوم"); dayButton("yesterday", "أمس")
                if draftDay == "yesterday" { Text("كُتبت لاحقًا").font(MadarTypography.caption()).foregroundStyle(theme.color("late")) }
                Spacer(minLength: 0)
            }
#if DEBUG
            if ProcessInfo.processInfo.environment["MADAR_UI_DIARY_ROOT_ROUTE_HARNESS"] == "1" { harness }
#endif
        }
    }
    private func dayButton(_ value: String, _ label: String) -> some View {
        Button {
            guard draftDay != value, let today = try? service.currentDay() else { return }
            draftDay = value; draftWritingDay = value == "yesterday" ? today.adding(days: -1) : nil
            // The day is part of the stored draft: write it again even when the words did not change.
            lastSaved = ""; scheduleDraft()
        } label: {
            Text(label).font(MadarTypography.caption()).padding(.horizontal, 16).frame(minHeight: 42)
                .foregroundStyle(draftDay == value ? theme.background : theme.ink).background(draftDay == value ? theme.ink : theme.surface, in: .capsule)
        }.buttonStyle(.madarPlain).disabled(saving || voiceBusy).accessibilityIdentifier("diary-editor-" + value)
            .accessibilityAddTraits(draftDay == value ? .isSelected : [])
    }
#if DEBUG
    private var harness: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button("اختبر الجذر مع مسودة") { app.open(URL(string: "madar://notes")!) }.accessibilityIdentifier("ui-test-open-diary-root")
                Button("اختبر الكتابة اليوم") { app.open(URL(string: "madar://notes/write")!) }.accessibilityIdentifier("ui-test-open-diary-today")
                Button("اختبر الكتابة في أمس") { app.open(URL(string: "madar://notes/write?day=yesterday")!) }.accessibilityIdentifier("ui-test-open-diary-yesterday")
                if ProcessInfo.processInfo.environment["MADAR_UI_DIARY_DAY_BOUNDARY_HARNESS"] == "1" {
                    Button("قدّم الساعة ٦ ساعات") { app.advanceDiaryBoundaryUITestClock(hours: 6) }.accessibilityIdentifier("ui-test-advance-diary-clock")
                    Button("اختبر صفحة يوم المسودة") { if let day = draftWritingDay { app.open(URL(string: "madar://notes/day/\(day.description)")!) } }.accessibilityIdentifier("ui-test-open-diary-original-day")
                }
            }.font(MadarTypography.fine())
        }.frame(minHeight: 40)
    }
#endif
    private var richField: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $rich, selection: $richSelection).scrollContentBackground(.hidden)
                .font(DiaryRichText.regular).lineSpacing(10).focused($focused).disabled(saving)
                .accessibilityIdentifier("diary-editor-text")
            if field.wrappedValue.isEmpty {
                Text(edit != nil ? "عدّل السطر…" : "اكتب ما تيسّر…").font(DiaryType.writing).foregroundStyle(theme.color("ink3Text"))
                    .padding(.horizontal, 8).padding(.top, 8).allowsHitTesting(false)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 0.7) }
    }

    private var voiceRow: some View {
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
    }

    private var collapsedRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(selection: $photo, matching: .images) {
                Image(systemName: "photo").font(.system(size: 19)).frame(width: 44, height: 44).contentShape(Circle())
            }.buttonStyle(.madarPlain).foregroundStyle(theme.color("ink3Text")).disabled(edit != nil || saving)
                .accessibilityLabel("أضف صورة").accessibilityIdentifier("diary-inline-photo")
            Group {
                if formatted {
                    Text(DiaryRichText.attributed(fromMarkdown: field.wrappedValue)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle()).onTapGesture { toggle(true) }.accessibilityIdentifier("diary-inline-field-formatted")
                } else {
                    TextField(edit != nil ? "عدّل السطر…" : "اكتب ما تيسّر…", text: field, axis: .vertical)
                        .font(DiaryType.writing).lineLimit(1...5).focused($focused).accessibilityIdentifier("diary-inline-field")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
            .background(theme.surface, in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.line, lineWidth: 0.7) }
            if edit == nil {
                // The full surface stays one tap away (camera, files, formatting, a longer text); the identifiers keep their old meaning.
                Button { holdCommit = true; Task { await keepDraft(); toggle(true); holdCommit = false } } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 15)).frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.madarPlain).foregroundStyle(theme.color("ink3Text"))
                    .accessibilityLabel("كبّر الحقل: كاميرا وملفات وتنسيق").accessibilityIdentifier(trimmed.isEmpty ? "diary-day-write" : "diary-inline-expand")
            }
            if trimmed.isEmpty && edit == nil {
                Button { Task { await startRecording() } } label: {
                    Image(systemName: "mic").font(.system(size: 19)).frame(width: 44, height: 44).contentShape(Circle())
                }.buttonStyle(.madarPlain).foregroundStyle(theme.color("ink3Text"))
                    .accessibilityLabel("سجّل صوتًا").accessibilityIdentifier("diary-inline-record")
            } else if edit != nil {
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).frame(width: 44, height: 44)
                        .foregroundStyle(theme.background).background(theme.dark ? theme.accent : theme.ink, in: .circle)
                        .contentShape(Circle())
                }.buttonStyle(.madarPlain).disabled(!canSend)
                    .accessibilityLabel("احفظ التعديل").accessibilityIdentifier("diary-inline-send")
            }
        }
    }

    /// Tools that exist only on the full surface.
    private var toolsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo").frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.madarPlain).disabled(edit != nil || saving).accessibilityLabel("أضف صورة").accessibilityIdentifier("diary-editor-photo")
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { focused = false; cameraOpen = true } label: { Image(systemName: "camera").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .buttonStyle(.madarPlain).disabled(edit != nil || saving).accessibilityLabel("التقط صورة").accessibilityIdentifier("diary-editor-camera")
                }
                Button { focused = false; choosingFile = true } label: { Image(systemName: "doc").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.madarPlain).disabled(edit != nil || saving).accessibilityLabel("أرفق ملفًا").accessibilityIdentifier("diary-editor-file")
                if edit == nil {
                    Button { Task { await startRecording() } } label: { Image(systemName: "mic").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .buttonStyle(.madarPlain).accessibilityLabel("سجّل صوتًا").accessibilityIdentifier("diary-editor-record")
                    languageMenu
                }
                if focused {
                    Button { focused = false } label: { Image(systemName: "keyboard.chevron.compact.down").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .buttonStyle(.madarPlain).accessibilityLabel("أخفِ لوحة الكتابة").accessibilityIdentifier("diary-editor-hide-keyboard")
                }
                Divider().frame(height: 24)
                formatButton("bold", "عريض", id: "diary-editor-bold") { toggleEmphasis(bold: true) }
                formatButton("italic", "مائل", id: "diary-editor-italic") { toggleEmphasis(bold: false) }
                formatButton("textformat.size", "عنوان", id: "diary-editor-heading") { toggleHeading() }
                formatButton("clock", "أدرج الوقت", id: "diary-editor-time") { insertAtCursor(service.time(app.prayerNow()) + " ") }
                formatButton("list.bullet", "سطر في قائمة", id: "diary-editor-list") { insertAtCursor("• ", ownLine: true) }
            }
        }.scrollBounceBehavior(.basedOnSize).foregroundStyle(theme.color("ink3Text"))
    }

    private func formatButton(_ symbol: String, _ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.madarPlain).accessibilityLabel(label).accessibilityIdentifier(id)
    }

    private var languageMenu: some View {
        Menu {
            Picker("لغة التسجيل", selection: Binding(get: { voice.language }, set: { voice.language = $0 })) {
                Text("العربية").tag("ar-SA"); Text("الإنجليزية").tag("en-US")
            }
            if voice.canDownload, voice.downloadProgress == nil { Button { voice.downloadLanguage() } label: { Label("حمّل لغة الإملاء", systemImage: "arrow.down.circle") } }
            if voice.downloadProgress != nil { Button { voice.cancelDownload() } label: { Label("ألغِ التحميل", systemImage: "xmark.circle") } }
        } label: { Image(systemName: "globe").frame(width: 44, height: 44).contentShape(Rectangle()) }
            .disabled(voice.recording || voice.converting).accessibilityLabel("لغة التسجيل").accessibilityIdentifier("diary-voice-language")
    }

    // MARK: Formatting (on the formatted text; the Markdown follows through `onChange(of: rich)`)

    private var currentStyle: DiaryRichText.Style {
        let typing = richSelection.typingAttributes(in: rich)
        return DiaryRichText.style(of: typing.inlinePresentationIntent, font: typing.font)
    }
    private func toggleEmphasis(bold: Bool) {
        var style = currentStyle
        style.heading = false
        if bold { style.bold.toggle() } else { style.italic.toggle() }
        rich.transformAttributes(in: &richSelection) { container in DiaryRichText.apply(style, to: &container) }
        focusRich()
    }
    /// The cursor's line becomes a heading, or stops being one.
    private func toggleHeading() {
        let point: AttributedString.Index
        switch richSelection.indices(in: rich) {
        case .insertionPoint(let index): point = index
        case .ranges(let ranges): point = ranges.ranges.first?.lowerBound ?? rich.startIndex
        }
        let chars = rich.characters
        var start = point
        while start > chars.startIndex, chars[chars.index(before: start)] != "\n" { start = chars.index(before: start) }
        var end = point
        while end < chars.endIndex, chars[end] != "\n" { end = chars.index(after: end) }
        let isHeading = start < end ? DiaryRichText.style(of: rich[start..<end].runs.first?.inlinePresentationIntent, font: rich[start..<end].runs.first?.font).heading : currentStyle.heading
        var next = DiaryRichText.Style(); next.heading = !isHeading
        var container = AttributeContainer(); DiaryRichText.apply(next, to: &container)
        if start < end { rich[start..<end].mergeAttributes(container) }
        rich.transformAttributes(in: &richSelection) { c in DiaryRichText.apply(next, to: &c) }
        focusRich()
    }
    /// Text goes where the cursor is; a list line starts on its own line.
    private func insertAtCursor(_ piece: String, ownLine: Bool = false) {
        var lead = ""
        if ownLine, case .insertionPoint(let index) = richSelection.indices(in: rich) {
            let chars = rich.characters
            if index > chars.startIndex, chars[chars.index(before: index)] != "\n" { lead = "\n" }
        } else if ownLine, !rich.characters.isEmpty { lead = "\n" }
        rich.replaceSelection(&richSelection, withCharacters: lead + piece)
        focusRich()
    }

    private func wordCount(_ n: Int) -> String {
        let digits = service.digits
        if n == 0 { return "" }; if n == 1 { return "كلمة واحدة" }; if n == 2 { return "كلمتان" }
        switch n % 100 { case 3...10: return digits.string(n) + " كلمات"; case 11...99: return digits.string(n) + " كلمةً"; default: return digits.string(n) + " كلمة" }
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
                // A draft left more than a day behind moves to the page chosen now (it used to pull the writer back to an old day, 10 Nov).
                if let now = try? service.currentDay(), draft.writingDay < now.adding(days: -1) {
                    draftDay = "today"; draftWritingDay = nil; lastSaved = ""
                }
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
        let writing = try currentWritingDay()
        try await service.saveDraft(id: draftID, text: value, day: draftDay, margin: nil, writingDay: writing)
        // The page the words were begun on stays theirs, even when the day turns at Fajr while they are open.
        draftWritingDay = writing
        hasDraftRecord = true; lastSaved = value
        draftStatus = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "المسودة محفوظة"
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
        let sent = text   // T02: only what was sent is cleared; words typed during the send stay.
        await settleDraftTask()
        do {
            if let edit {
                try await service.edit(edit.id, text: editText)
                self.edit = nil; editText = ""; focused = false
                if expanded { toggle(false) }
            } else {
                try await persistDraft()
                var payload: [String: MadarCore.JSONValue] = ["id": .string(draftID.uuidString)]
                if let insertAt, draftDay == "today", insertAt < app.prayerNow() { payload["at"] = .number(insertAt.timeIntervalSince1970) }
                try await app.executeDiaryCommand("diary.commitDraft", payload: payload, id: draftID)
                let remainder = DiaryDraftRemainder.remaining(current: text, sent: sent)
                text = remainder; lastSaved = ""; hasDraftRecord = false; draftID = UUID(); draftDay = "today"; draftWritingDay = nil
                insertAt = nil; anchor = nil; draftStatus = ""
                rich = remainder.isEmpty ? AttributedString() : DiaryRichText.attributed(fromMarkdown: remainder)
                richBaseline = remainder.isEmpty ? "" : DiaryRichText.markdown(from: rich)
                if expanded { toggle(false) }
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
    private func linkLibraryPhoto(_ asset: PHAsset) async -> Bool {
        guard let data = await DiaryPhotoLibrary.data(asset), let copy = await Task.detached(priority: .userInitiated, operation: { DiaryPhotoLibrary.smallCopy(of: data) }).value else { failure = "تعذّر فتح الصورة من تطبيق الصور."; return false }
        do {
            try await service.appendMedia(data: copy, kind: "photo", contentType: "image/jpeg", day: "today", writingDay: try service.currentDay(), assetID: asset.localIdentifier)
            failure = nil; saved(); return true
        } catch { failure = madarUserMessage(error); return false }
    }
    private func addFile(_ result: Result<URL, Error>) async {
        do {
            let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType ?? .data
            // The file is read off the main thread and refused above 50 MB before anything is loaded.
            let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes <= 50_000_000 else { failure = "الملف أكبر من ٥٠ ميغابايت."; return }
            let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
            try await service.appendMedia(data: data, kind: type.conforms(to: .image) ? "photo" : type.conforms(to: .audio) ? "audio" : type.conforms(to: .movie) ? "video" : "document",
                contentType: type.preferredMIMEType ?? "application/octet-stream", caption: url.lastPathComponent, day: "today", writingDay: try service.currentDay())
            failure = nil; saved()
        } catch { failure = madarUserMessage(error) }
    }
    private func cameraCaptured(_ image: UIImage) {
        cameraOpen = false; holdCommit = false
        guard let original = image.jpegData(compressionQuality: 0.82), let data = DiaryPhotoLibrary.cameraCopy(of: original) else {
            failure = "تعذّر تجهيز الصورة. التقطها مرة أخرى."; return
        }
        Task {
            do { try await service.appendMedia(data: data, kind: "photo", contentType: "image/jpeg", day: "today", writingDay: try service.currentDay()); failure = nil; saved() }
            catch { failure = madarUserMessage(error) }
        }
    }
}
