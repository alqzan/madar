import SwiftUI
import MadarCore
import MadarDesign
import PhotosUI
import Photos
import UIKit
import UniformTypeIdentifiers

struct DiaryTextEditor: View {
    @Bindable var app: AppSession
    let margin: GregorianDay?
    var initialDay = "today"
    /// Set when writing from a «اكتب هنا» between two lines of the day page: the new line lands at this moment.
    var insertAt: Date?
    /// A question chosen from «أسئلة من مذكراتك»: shown quietly above the page, never saved into the text.
    var prompt: String?
    var embeddedInNavigationStack = false
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var text = ""
    @State private var selection: TextSelection?
    @State private var draftID = UUID()
    @State private var hasDraftRecord = false
    @State private var loaded = false
    @State private var draftTask: Task<Void, Never>?
    @State private var draftStatus = ""
    @State private var photo: PhotosPickerItem?
    @State private var cameraOpen = false
    @State private var choosingFile = false
    @State private var attachmentSaved = false
    @State private var importing = false
    @State private var editorUndo = false
    @State private var voice: DiaryVoiceController?
    @State private var day = "today"
    @State private var writingDay: GregorianDay?
    @State private var savedDay: DiaryDisplayDay?
    @State private var savedDayTask: Task<Void, Never>?
    @State private var currentMadarDay: GregorianDay?
    @State private var saving = false
    @State private var mediaExpanded = false
    @State private var failure: String?
    /// AU-95: a failed «تمّ» stays on screen; the next quiet draft save must not wipe it while the page is uncommitted.
    @State private var commitFailed = false
    @FocusState private var focused: Bool
    /// Counted when the text changes, not on every redraw.
    @State private var words = 0
    /// Whether the page has anything but whitespace; kept here so the toolbar does not scan the text on every keystroke.
    @State private var hasContent = false
    private var blocksRootRoute: Bool {
        !text.isEmpty || saving || importing || voice?.recording == true || voice?.savingAudio == true || voice?.converting == true
    }
    var body: some View {
        Group {
            if embeddedInNavigationStack { editorContent }
            else { NavigationStack { editorContent } }
        }
        .task {
            day = initialDay
            writingDay = (try? AppDiaryService(app: app, clock: { app.prayerNow() }).currentDay()).map { initialDay == "yesterday" ? $0.adding(days: -1) : $0 }
            do { if let draft = try AppDiaryService(app: app).draft(margin: margin) { draftID = draft.id; hasDraftRecord = true; text = draft.text
                // 10 Nov owner report: a draft left on an old day used to pull the writer back to that day. Only today and the late-writing «أمس» keep their own page; anything older moves to the page chosen now.
                if let today = writingDay?.adding(days: initialDay == "yesterday" ? 1 : 0), draft.writingDay >= today.adding(days: -1) { day = draft.day; writingDay = draft.writingDay } else { day = initialDay }; // «مستعادة» is for a real recovery only: a draft left on an earlier day. Words moved here from the page's composer a moment ago are not "recovered".
                draftStatus = draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : (draft.writingDay < (currentMadarDay ?? (try? AppDiaryService(app: app, clock: { app.prayerNow() }).currentDay()) ?? draft.writingDay) ? "مسودة مستعادة" : "") } }
            catch { failure = madarUserMessage(error) }
            // AU-38: let the restored text's onChange pass first, so the status stays until the user types.
            await Task.yield()
            loaded = true
            refreshSavedDay()
            if voice == nil {
                voice = app.diaryVoice
                // Recovery never holds the keyboard back.
                Task { await voice?.recoverRecordings() }
            }
            // A room-tab write link presents during the native sheet transition; an earlier
            // focus request can be dropped before the text view joins its window.
            if !app.bool("notes.dictationFirst") {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                if !Task.isCancelled, voice?.recording != true { focused = true }
            }
        }
        .task {
            while !Task.isCancelled {
                currentMadarDay = try? AppDiaryService(app: app, clock: { app.prayerNow() }).currentDay()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
#if DEBUG
        .task(id: app.diaryBoundaryUITestClockOverride) {
            currentMadarDay = try? AppDiaryService(app: app, clock: { app.prayerNow() }).currentDay()
        }
#endif
        .onAppear { DiaryDraftFlush.livePages += 1 }
        .onChange(of: text) { _, new in
            scheduleDraft()
            let count = new.split(whereSeparator: { $0.isWhitespace }).count
            if count != words { words = count }
            let has = new.contains { !$0.isWhitespace }
            if has != hasContent { hasContent = has }
        }
        .onChange(of: day) { _, _ in scheduleDraft() }
        .onChange(of: photo) { _, item in Task {
            guard let item else { return }; importing = true
            // Cleared so the same photo can be chosen again.
            defer { importing = false; photo = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { failure = "تعذّر فتح الصورة. اخترها مرة أخرى."; return }
                // A library photo is linked: its identifier and a small copy, never a second full image.
                if let id = item.itemIdentifier, let copy = DiaryPhotoLibrary.smallCopy(of: data) { try await add(copy, kind: "photo", type: "image/jpeg", assetID: id) }
                else { try await add(data, kind: "photo", type: item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg") }
            }
            catch { failure = madarUserMessage(error) }
        } }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.data]) { result in Task {
            do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType ?? .data
                try await add(Data(contentsOf: url), kind: type.conforms(to: .image) ? "photo" : type.conforms(to: .audio) ? "audio" : type.conforms(to: .movie) ? "video" : "document", type: type.preferredMIMEType ?? "application/octet-stream", caption: url.lastPathComponent)
            } catch { failure = madarUserMessage(error) }
        } }
        .fullScreenCover(isPresented: $cameraOpen) {
            DiaryCameraCapture(captured: cameraCaptured, cancelled: { cameraOpen = false }).ignoresSafeArea()
        }
        .onChange(of: voice?.lastMedia?.id) { _, id in if id != nil { attachmentSaved = true; editorUndo = true; refreshSavedDay() } }
        .onChange(of: writingDay) { _, _ in refreshSavedDay() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { voice?.refreshMicrophoneAuthorization() }
            else if phase == .background {
                // Owner 11 Nov: leaving the app (lock, Home, a call's banner) saved the words and then ended the take. The words are kept; the recording goes on (background audio).
                Task { draftTask?.cancel(); if loaded { do { try await persistDraft() } catch { draftStatus = "لم تُحفظ المسودة"; failure = madarUserMessage(error) } } }
            }
        }
        .safeAreaInset(edge: .bottom) { if editorUndo, app.undoToastVisible { UndoToast(message: app.undoMessage, undo: app.undo, dismiss: app.hideUndoToast).hostsUndo(app) } }
        .madarSheetLock(saving: saving || importing || voice?.savingAudio == true || voice?.converting == true, draft: !text.isEmpty || voice?.recording == true)
        .onDisappear {
            // B2-2: leaving never loses words; a pending 500 ms draft write is flushed unless the page was just saved.
            if loaded, !saving, hasDraftRecord || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { DiaryDraftFlush.run { try? await persistDraft() } }
            DiaryDraftFlush.livePages = max(0, DiaryDraftFlush.livePages - 1)
            // The voice controller belongs to the session now: a take and its transcription outlive this view's teardown.
            draftTask?.cancel(); savedDayTask?.cancel() }
        .diaryRootDraftBlocking(app, isBlocking: blocksRootRoute)
        .modifier(EditorVoiceHost(voice: voice))
    }
    @ViewBuilder private var editorContent: some View {
            VStack(spacing: 0) {
#if DEBUG
                if ProcessInfo.processInfo.environment["MADAR_UI_DIARY_ROOT_ROUTE_HARNESS"] == "1" {
                    HStack(spacing: 10) {
                        Button(app.diaryRootDraftBlockers.isEmpty ? "اختبر الجذر" : "اختبر الجذر مع مسودة") { app.open(URL(string: "madar://notes")!) }
                            .accessibilityIdentifier("ui-test-open-diary-root")
                        if margin == nil {
                            Button("اختبر الكتابة اليوم") { app.open(URL(string: "madar://notes/write")!) }
                                .accessibilityIdentifier("ui-test-open-diary-today")
                            Button("اختبر الكتابة في أمس") { app.open(URL(string: "madar://notes/write?day=yesterday")!) }
                                .accessibilityIdentifier("ui-test-open-diary-yesterday")
                            if ProcessInfo.processInfo.environment["MADAR_UI_DIARY_DAY_BOUNDARY_HARNESS"] == "1" {
                                Button("قدّم الساعة ٦ ساعات") { app.advanceDiaryBoundaryUITestClock(hours: 6) }
                                    .accessibilityIdentifier("ui-test-advance-diary-clock")
                                Button("اختبر صفحة يوم المسودة") {
                                    if let writingDay { app.open(URL(string: "madar://notes/day/\(writingDay.description)")!) }
                                }.accessibilityIdentifier("ui-test-open-diary-original-day")
                            }
                        }
                    }.frame(minHeight: 40)
                }
#endif
                if let margin {
                    Text("هامش " + AppDiaryService(app: app).diaryDates(margin)).font(MadarTypography.caption()).padding(14)
                } else {
                    HStack(spacing: 8) {
                        choice("today", "اليوم"); choice("yesterday", "أمس")
                        Spacer()
                    }.padding(.horizontal, 16).padding(.bottom, 14)
                }
                if let writingDay, let today = currentMadarDay,
                   (day == "today" && writingDay < today || day == "yesterday" && writingDay < today.adding(days: -1)) {
                    Text(MadarInlineText.joined(["مسودة عن " + AppDiaryService(app: app).diaryDates(writingDay), "تُحفظ في صفحتها الأصلية"])).font(MadarTypography.fine()).padding(.horizontal, 16)
                }
                if let prompt {
                    Text(prompt).font(.custom("thmanyahseriftext-Regular", size: 17, relativeTo: .body)).foregroundStyle(theme.color("ink3Text"))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22).padding(.bottom, 8)
                        .accessibilityIdentifier("diary-editor-prompt")
                }
                if margin == nil, let excerpt = savedDay?.lines.last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.text {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("كتبت في هذه الصفحة").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        Text(excerpt).font(DiaryType.writing).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .accessibilityIdentifier("diary-editor-saved-context")
                }
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        var path = Path()
                        for y in stride(from: 12.0, through: size.height, by: 34) { path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y)) }
                        context.stroke(path, with: .color(theme.line), lineWidth: 0.5)
                        var marginLine = Path(); marginLine.move(to: .init(x: size.width - 22, y: 0)); marginLine.addLine(to: .init(x: size.width - 22, y: size.height))
                        context.stroke(marginLine, with: .color(theme.color("margin")), lineWidth: 1)
                    }.accessibilityHidden(true)
                    TextEditor(text: $text, selection: $selection).scrollContentBackground(.hidden)
                        .font(.custom("thmanyahseriftext-Regular", size: 19, relativeTo: .body)).lineSpacing(12)
                        .padding(.horizontal, 30).padding(.top, 10).focused($focused).disabled(saving).accessibilityIdentifier("diary-editor-text")
                    if text.isEmpty { Text("اكتب ما تيسّر…").font(.custom("thmanyahseriftext-Regular", size: 21, relativeTo: .body)).foregroundStyle(theme.color("ink3Text")).padding(.horizontal, 38).padding(.top, 19).allowsHitTesting(false) }
                }
                if margin == nil, let writingDay {
                    DiaryDayPhotos(app: app, day: writingDay) { asset in await linkLibraryPhoto(asset) }.padding(.horizontal, 16)
                }
                if margin == nil, let savedDay, !savedDay.media.isEmpty {
                    // Recordings and photos already on this page stay one quiet line until asked for; the text keeps the screen.
                    Button { withAnimation(.snappy) { mediaExpanded.toggle() } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "paperclip")
                            Text(AppDiaryService(app: app).attachmentSummary(savedDay.media)).font(MadarTypography.caption())
                            Spacer()
                            Image(systemName: mediaExpanded ? "chevron.down" : "chevron.up").font(.caption)
                        }.foregroundStyle(theme.secondaryInk).padding(.horizontal, 18).frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-editor-saved-media")
                    if mediaExpanded {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(Array(savedDay.media.suffix(6))) { media in
                                    DiaryMediaCard(app: app, media: media,
                                        transcript: savedDay.lines.first(where: { $0.id == media.entryID })?.text ?? "")
                                        .frame(width: 280, alignment: .leading)
                                }
                            }.padding(.horizontal, 12)
                        }
                    }
                }
                if margin == nil {
                    ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) {
                        PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) { Label("صورة", systemImage: "photo").font(MadarTypography.caption()).frame(minHeight: 44) }.labelStyle(.iconOnly).accessibilityIdentifier("diary-editor-photo")
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { focused = false; cameraOpen = true } label: { Image(systemName: "camera").frame(width: 44, height: 44) }
                                .buttonStyle(.madarPlain).accessibilityLabel("التقط صورة").accessibilityIdentifier("diary-editor-camera")
                        }
                        Button { focused = false; choosingFile = true } label: { Label("مرفق", systemImage: "doc").font(MadarTypography.caption()).frame(minHeight: 44) }.labelStyle(.iconOnly).accessibilityIdentifier("diary-editor-file")
                        if let voice {
                            recordButton(voice, large: false)
                            languageMenu(voice)
                        }
                        Spacer(minLength: 0)
                        // B2-2: one «التنسيق» menu replaces five bar buttons; the identifiers stay for tests.
                        Menu {
                            Button { insertAtCursor(AppDiaryService(app: app).time(app.prayerNow()) + " ") } label: { Label("أدرج الوقت", systemImage: "clock") }
                            Button { insertAtCursor("• ") } label: { Label("سطر في قائمة", systemImage: "list.bullet") }
                                                    } label: { Image(systemName: "textformat").frame(width: 44, height: 44).contentShape(Rectangle()) }
                            .accessibilityLabel("أدوات الكتابة").accessibilityIdentifier("diary-editor-format")
                        if focused { Button { focused = false } label: { Image(systemName: "keyboard.chevron.compact.down").frame(width: 44, height: 44) }.accessibilityLabel("أخفِ لوحة الكتابة").accessibilityIdentifier("diary-editor-hide-keyboard") }
                    }.padding(.horizontal, 16) }.scrollBounceBehavior(.basedOnSize)
                }
                // 11 Nov owner: the keyboard coming up made the screen jump and stutter because a whole block of voice controls swapped in and out with focus.
                // The bar above is the same with or without the keyboard; this area exists only while the voice has something to say.
                if margin == nil, let voice, voiceStatusShown(voice) {
                    VStack(alignment: .leading, spacing: 8) {
                        DiaryVoiceFeedback(controller: voice)
                        if voice.interrupted, !voice.recording {
                            Text("قاطع النظام التسجيل وحُفظ ما سُجّل · اضغط الميكروفون لتكمل بتسجيل جديد").font(MadarTypography.fine()).foregroundStyle(theme.color("ink3Text"))
                        }
                        if let media = voice.lastMedia, attachmentSaved, !voice.converting, !voice.recording {
                            Button { Task { await voice.transcribe(media) } } label: { Text("حوّله إلى نص").font(MadarTypography.caption()).frame(minHeight: 44).contentShape(Rectangle()) }
                                .accessibilityIdentifier("diary-editor-transcribe")
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 8)
                }
                HStack {
                    Text(wordCount(words)).font(MadarTypography.fine())
                    Spacer()
                    Text(draftStatus).font(MadarTypography.fine()).accessibilityIdentifier("diary-draft-status")
                    if day == "yesterday" { Text("كُتبت لاحقًا").font(MadarTypography.caption()).foregroundStyle(theme.color("late")) }
                }.padding(14)
                if let failure { Text(failure).font(MadarTypography.caption()).padding(12).accessibilityIdentifier("diary-editor-error") }
            }
            .foregroundStyle(theme.ink).background(theme.background)
            .navigationTitle(margin == nil ? "الورقة الكاملة" : "اكتب في هامشها").navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("تمّ") { Task { await close() } }.disabled(saving || importing || voice?.savingAudio == true || voice?.converting == true).accessibilityIdentifier("diary-editor-cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(saving ? "يُحفظ…" : "احفظ الصفحة") { Task { await save() } }.fontWeight(.bold)
                        .disabled(saving || importing || voice?.savingAudio == true || voice?.converting == true || (!attachmentSaved && !hasContent))
                        .accessibilityIdentifier("diary-editor-save")
                }
            }.tint(theme.accent)
    }

    /// The selected range, or an empty range at the cursor (the end when nothing is focused yet).
    private var selectedOffsets: Range<Int> {
        if case .selection(let range) = selection?.indices, range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex {
            return text.distance(from: text.startIndex, to: range.lowerBound)..<text.distance(from: text.startIndex, to: range.upperBound)
        }
        return text.count..<text.count
    }
    /// Text goes where the cursor is, on its own line; an empty page or a line already empty takes no extra line break.
    private func insertAtCursor(_ piece: String) {
        let offset = min(text.count, selectedOffsets.upperBound)
        let at = text.index(text.startIndex, offsetBy: offset)
        let lead = (at == text.startIndex || text[..<at].last == "\n") ? "" : "\n"
        text.insert(contentsOf: lead + piece, at: at)
        selection = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: offset + lead.count + piece.count)); focused = true
    }
    private func recordButton(_ voice: DiaryVoiceController, large: Bool) -> some View {
        Button { Task { if voice.recording { await voice.stop() } else if let writingDay { await voice.start(writingDay: writingDay) } } } label: {
            Image(systemName: voice.recording ? "stop.fill" : "mic").font(.system(size: large ? 28 : 20)).frame(width: large ? 72 : 44, height: large ? 72 : 44)
                .foregroundStyle(large ? theme.onAccent : theme.ink).background(large ? theme.accent : .clear, in: .circle)
        }.buttonStyle(.madarPlain).disabled(saving || importing || voice.savingAudio || voice.converting)
            .accessibilityLabel(voice.recording ? "أوقف التسجيل واحفظه" : "سجّل صوتًا").accessibilityIdentifier("diary-editor-record")
    }
    private func voiceStatusShown(_ voice: DiaryVoiceController) -> Bool {
        voice.recording || voice.savingAudio || voice.converting || voice.needsConsent || voice.microphoneDenied || voice.interrupted || (attachmentSaved && voice.lastMedia != nil)
    }
    private func languageMenu(_ voice: DiaryVoiceController) -> some View {
        Menu {
            Picker("لغة التسجيل", selection: Binding(get: { voice.language }, set: { voice.language = $0 })) {
                Text("العربية").tag("ar-SA"); Text("الإنجليزية").tag("en-US")
            }
            if voice.canDownload, voice.downloadProgress == nil { Button { voice.downloadLanguage() } label: { Label("حمّل لغة الإملاء", systemImage: "arrow.down.circle") } }
            if voice.downloadProgress != nil { Button { voice.cancelDownload() } label: { Label("ألغِ التحميل", systemImage: "xmark.circle") } }
        } label: { Image(systemName: "globe").frame(width: 44, height: 44).contentShape(Rectangle()) }
            .disabled(voice.recording || voice.converting).accessibilityLabel("لغة التسجيل").accessibilityIdentifier("diary-voice-language")
    }
    private func choice(_ value: String, _ label: String) -> some View {
        Button { day = value; writingDay = (try? AppDiaryService(app: app, clock: { app.prayerNow() }).currentDay()).map { value == "yesterday" ? $0.adding(days: -1) : $0 } } label: { Text(label).font(MadarTypography.caption()).padding(.horizontal, 16).frame(minHeight: 42).foregroundStyle(day == value ? theme.background : theme.ink).background(day == value ? theme.ink : theme.surface, in: .capsule).glassEffect(.regular.interactive(), in: .capsule) }
            .buttonStyle(.madarPlain).disabled(saving || importing || voice?.recording == true).accessibilityIdentifier("diary-editor-" + value).accessibilityAddTraits(day == value ? .isSelected : [])
    }
    private func scheduleDraft() {
        guard loaded, !saving else { return }
        draftTask?.cancel(); if draftStatus != "تُحفظ المسودة…" { draftStatus = "تُحفظ المسودة…" }
        draftTask = Task {
            do { try await Task.sleep(for: .milliseconds(500)); try Task.checkCancellation(); try await persistDraft(); if !commitFailed { failure = nil }; draftStatus = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "المسودة محفوظة" }
            catch is CancellationError {} catch { draftStatus = "لم تُحفظ المسودة"; failure = madarUserMessage(error) }
        }
    }
    private func persistDraft() async throws {
        guard let writingDay else { throw CocoaError(.coderInvalidValue) }
        guard hasDraftRecord || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try await AppDiaryService(app: app).saveDraft(id: draftID, text: text, day: day, margin: margin, writingDay: writingDay)
        hasDraftRecord = true
    }
    /// Cancels the pending debounce and waits for a write already under way, so an old write never lands after the commit.
    private func settleDraftTask() async {
        let pending = draftTask
        pending?.cancel(); await pending?.value
        draftTask = nil
    }
    private func close() async {
        saving = true; failure = nil; await settleDraftTask()
        do { await voice?.stop(); if loaded { try await persistDraft() }; dismiss() }
        catch { failure = madarUserMessage(error); saving = false }
    }
    private func add(_ data: Data, kind: String, type: String, caption: String = "", assetID: String? = nil) async throws {
        guard let writingDay else { throw CocoaError(.coderInvalidValue) }; importing = true
        defer { importing = false }
        failure = nil // AU-36: a stale error never sits beside a success.
        _ = try await AppDiaryService(app: app).appendMedia(data: data, kind: kind, contentType: type, caption: caption, day: day, writingDay: writingDay, assetID: assetID)
        attachmentSaved = true; editorUndo = true; draftStatus = "حُفظ المرفق في الصفحة"
        refreshSavedDay()
    }
    private func save() async {
        guard !saving else { return }; saving = true; failure = nil; commitFailed = false
        await settleDraftTask()
        do {
            await voice?.stop()
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await persistDraft()
                var payload: [String: MadarCore.JSONValue] = ["id": .string(draftID.uuidString)]
                if let insertAt, margin == nil, day == "today", insertAt < app.prayerNow() { payload["at"] = .number(insertAt.timeIntervalSince1970) }
                try await app.executeDiaryCommand("diary.commitDraft", payload: payload, id: draftID)
            }
            dismiss()
        } catch { failure = madarUserMessage(error); commitFailed = true; saving = false }
    }
    private func linkLibraryPhoto(_ asset: PHAsset) async -> Bool {
        guard let data = await DiaryPhotoLibrary.data(asset), let copy = DiaryPhotoLibrary.smallCopy(of: data) else { failure = "تعذّر فتح الصورة من تطبيق الصور."; return false }
        do { try await add(copy, kind: "photo", type: "image/jpeg", assetID: asset.localIdentifier); return true }
        catch { failure = madarUserMessage(error); return false }
    }
    private func cameraCaptured(_ image: UIImage) {
        cameraOpen = false
        guard let original = image.jpegData(compressionQuality: 0.82),
              let data = DiaryPhotoLibrary.cameraCopy(of: original) else {
            failure = "تعذّر تجهيز الصورة. التقطها مرة أخرى."; return
        }
        Task {
            do { try await add(data, kind: "photo", type: "image/jpeg") }
            catch { failure = madarUserMessage(error) }
        }
    }
    private func refreshSavedDay() {
        guard margin == nil, let writingDay else { savedDay = nil; return }
        if savedDay?.day != writingDay { savedDay = nil }
        savedDayTask?.cancel()
        savedDayTask = Task { @MainActor in
            do {
                let value = try await AppDiaryService(app: app).dayOffMain(writingDay)
                guard !Task.isCancelled, self.writingDay == writingDay else { return }
                self.savedDay = value
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, self.writingDay == writingDay else { return }
                self.failure = madarUserMessage(error)
            }
        }
    }
    /// «كلمة واحدة»، «كلمتان»، «٥ كلمات»، «١١ كلمةً»; nothing before the first word.
    private func wordCount(_ n: Int) -> String {
        let digits = AppDiaryService(app: app).digits
        if n == 0 { return "" }; if n == 1 { return "كلمة واحدة" }; if n == 2 { return "كلمتان" }
        switch n % 100 { case 3...10: return digits.string(n) + " كلمات"; case 11...99: return digits.string(n) + " كلمةً"; default: return digits.string(n) + " كلمة" }
    }
}


/// Hosts what the shared voice controller needs while this page is open: the Apple-dictation consent ask, the title task and the language check.
private struct EditorVoiceHost: ViewModifier {
    let voice: DiaryVoiceController?
    func body(content: Content) -> some View {
        if let voice {
            content.modifier(DiaryVoiceConsentAlert(controller: voice))
                .background { DiaryVoiceInsightTask(controller: voice).frame(width: 1, height: 1).accessibilityHidden(true) }
                .task(id: voice.language) { await voice.refreshLanguage() }
        } else { content }
    }
}
