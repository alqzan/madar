import SwiftUI
import MadarCore
import MadarDesign
import PhotosUI
import UniformTypeIdentifiers

struct DiaryTextEditor: View {
    @Bindable var app: AppSession
    let margin: GregorianDay?
    var initialDay = "today"
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var text = ""
    @State private var draftID = UUID()
    @State private var loaded = false
    @State private var draftTask: Task<Void, Never>?
    @State private var draftStatus = ""
    @State private var photo: PhotosPickerItem?
    @State private var choosingFile = false
    @State private var attachmentSaved = false
    @State private var importing = false
    @State private var editorUndo = false
    @State private var voice: DiaryVoiceController?
    @State private var day = "today"
    @State private var writingDay: GregorianDay?
    @State private var saving = false
    @State private var failure: String?
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let margin {
                    Text("هامش " + AppDiaryService(app: app).bothDates(margin)).font(MadarTypography.caption()).padding(14)
                } else {
                    HStack(spacing: 8) {
                        choice("today", "اليوم"); choice("yesterday", "أمس")
                        Spacer()
                    }.padding(.horizontal, 16).padding(.bottom, 14)
                }
                if let writingDay, let today = try? AppDiaryService(app: app).currentDay(), writingDay < today.adding(days: -1) {
                    Text("مسودة عن " + AppDiaryService(app: app).bothDates(writingDay) + " · تُحفظ في صفحتها الأصلية").font(MadarTypography.fine()).padding(.horizontal, 16)
                }
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        var path = Path()
                        for y in stride(from: 12.0, through: size.height, by: 34) { path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y)) }
                        context.stroke(path, with: .color(theme.line), lineWidth: 0.5)
                        var marginLine = Path(); marginLine.move(to: .init(x: size.width - 22, y: 0)); marginLine.addLine(to: .init(x: size.width - 22, y: size.height))
                        context.stroke(marginLine, with: .color(theme.color("margin")), lineWidth: 1)
                    }.accessibilityHidden(true)
                    TextEditor(text: $text).scrollContentBackground(.hidden)
                        .font(.custom("thmanyahseriftext-Regular", size: 19, relativeTo: .body)).lineSpacing(12)
                        .padding(.horizontal, 30).padding(.top, 10).focused($focused).disabled(saving).accessibilityIdentifier("diary-editor-text")
                    if text.isEmpty { Text("اكتب ما تيسّر…").font(.custom("thmanyahseriftext-Regular", size: 21, relativeTo: .body)).foregroundStyle(theme.color("ink3Text")).padding(.horizontal, 38).padding(.top, 19).allowsHitTesting(false) }
                }
                if margin == nil {
                    HStack(spacing: 8) {
                        PhotosPicker(selection: $photo, matching: .images) { Label("صورة", systemImage: "photo").font(MadarTypography.caption()).frame(minHeight: 44) }.labelStyle(.iconOnly).accessibilityIdentifier("diary-editor-photo")
                        Button { focused = false; choosingFile = true } label: { Label("مرفق", systemImage: "doc").font(MadarTypography.caption()).frame(minHeight: 44) }.labelStyle(.iconOnly).accessibilityIdentifier("diary-editor-file")
                        if let voice, focused { recordButton(voice, large: false) }
                        Spacer(minLength: 0)
                        Button { text += "\n" + AppDiaryService(app: app).time(app.prayerNow()) + " " } label: { Image(systemName: "clock").frame(width: 44, height: 44) }.accessibilityLabel("أدرج الوقت")
                        Button { text += "\n• " } label: { Image(systemName: "list.bullet").frame(width: 44, height: 44) }.accessibilityLabel("سطر في قائمة")
                        if focused { Button { focused = false } label: { Image(systemName: "keyboard.chevron.compact.down").frame(width: 44, height: 44) }.accessibilityLabel("أخفِ لوحة الكتابة").accessibilityIdentifier("diary-editor-hide-keyboard") }

                    }.padding(.horizontal, 16)
                }
                if margin == nil, let voice, !focused {
                    VStack(alignment: .leading, spacing: 8) {
                        DiaryVoiceControls(controller: voice, compact: true)
                        HStack {
                            Button { focused = true } label: { Label("الكتابة", systemImage: "keyboard").frame(minHeight: 44) }.accessibilityIdentifier("diary-editor-keyboard")
                            Spacer()
                            recordButton(voice, large: true)
                            Spacer()
                            PhotosPicker(selection: $photo, matching: .images) { Label("صورة", systemImage: "photo").font(MadarTypography.caption()).padding(.horizontal, 12).frame(minHeight: 44).overlay { Capsule().stroke(theme.line) } }
                        }
                        Text(voice.recording ? "اضغط لإيقاف التسجيل وحفظ الصوت" : "اضغط وتكلّم").font(MadarTypography.fine()).frame(maxWidth: .infinity)
                        HStack {
                            if let media = voice.lastMedia, !voice.converting { Button("حوّله إلى نص") { Task { await voice.transcribe(media) } }.frame(minHeight: 44).accessibilityIdentifier("diary-editor-transcribe") }
                        }.font(MadarTypography.caption())
                    }.padding(.horizontal, 16).padding(.vertical, 8)
                }
                HStack {
                    Text(AppDiaryService(app: app).digits.string(text.split(whereSeparator: { $0.isWhitespace }).count) + " كلمة").font(MadarTypography.fine())
                    Spacer()
                    Text(draftStatus).font(MadarTypography.fine()).accessibilityIdentifier("diary-draft-status")
                    if day == "yesterday" { Text("كُتبت لاحقًا").font(MadarTypography.caption()).foregroundStyle(theme.color("late")) }
                }.padding(14)
                if let failure { Text(failure).font(MadarTypography.caption()).padding(12).accessibilityIdentifier("diary-editor-error") }
            }
            .foregroundStyle(theme.ink).background(theme.background)
            .navigationTitle(margin == nil ? "صفحة اليوم" : "اكتب في هامشها").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("إغلاق") { Task { await close() } }.disabled(saving || importing || voice?.savingAudio == true).accessibilityIdentifier("diary-editor-cancel") }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(saving ? "يُحفظ…" : "تمّ") { Task { await save() } }.fontWeight(.bold)
                        .disabled(saving || importing || voice?.savingAudio == true || (!attachmentSaved && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        .accessibilityIdentifier("diary-editor-save")
                }
            }.tint(theme.accent)
        }
        .task {
            day = initialDay
            writingDay = (try? AppDiaryService(app: app).currentDay()).map { initialDay == "yesterday" ? $0.adding(days: -1) : $0 }
            do { if let draft = try AppDiaryService(app: app).draft(margin: margin) { draftID = draft.id; text = draft.text; day = draft.day; writingDay = draft.writingDay; draftStatus = "مسودة مستعادة" } }
            catch { failure = error.localizedDescription }
            loaded = true
            if voice == nil { voice = DiaryVoiceController(app: app); await voice?.recoverRecordings() }
            // A room-tab write link presents during the native sheet transition; an earlier
            // focus request can be dropped before the text view joins its window.
            if !app.bool("notes.dictationFirst") {
                do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                if !Task.isCancelled, voice?.recording != true { focused = true }
            }
        }
        .onChange(of: text) { _, _ in scheduleDraft() }
        .onChange(of: day) { _, _ in scheduleDraft() }
        .onChange(of: photo) { _, item in Task {
            guard let item else { return }; importing = true
            defer { importing = false }
            do { if let data = try await item.loadTransferable(type: Data.self) { try await add(data, kind: "photo", type: item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg") } else { failure = "تعذّر فتح الصورة. اخترها مرة أخرى." } }
            catch { failure = error.localizedDescription }
        } }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.data]) { result in Task {
            do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType ?? .data
                try await add(Data(contentsOf: url), kind: type.conforms(to: .image) ? "photo" : type.conforms(to: .audio) ? "audio" : type.conforms(to: .movie) ? "video" : "document", type: type.preferredMIMEType ?? "application/octet-stream", caption: url.lastPathComponent)
            } catch { failure = error.localizedDescription }
        } }
        .onChange(of: voice?.lastMedia?.id) { _, id in if id != nil { attachmentSaved = true; editorUndo = true } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { Task { draftTask?.cancel(); if loaded { try? await persistDraft() }; await voice?.stop() } } }
        .safeAreaInset(edge: .bottom) { if editorUndo, app.undoToken != nil { UndoToast(message: app.undoMessage, undo: app.undo) } }
        .interactiveDismissDisabled(!text.isEmpty || saving || importing || voice?.recording == true || voice?.savingAudio == true)
        .onDisappear { draftTask?.cancel(); voice?.cancelConversion(); voice?.cancelDownload(); if let voice { Task { await voice.stop() } } }
    }
    private func recordButton(_ voice: DiaryVoiceController, large: Bool) -> some View {
        Button { focused = false; Task { if voice.recording { await voice.stop() } else if let writingDay { await voice.start(writingDay: writingDay) } } } label: {
            Image(systemName: voice.recording ? "stop.fill" : "mic").font(.system(size: large ? 28 : 20)).frame(width: large ? 72 : 44, height: large ? 72 : 44)
                .foregroundStyle(large ? theme.onAccent : theme.ink).background(large ? theme.accent : .clear, in: .circle)
        }.buttonStyle(.plain).disabled(saving || importing || voice.savingAudio || voice.converting)
            .accessibilityLabel(voice.recording ? "أوقف التسجيل واحفظه" : "سجّل صوتًا").accessibilityIdentifier("diary-editor-record")
    }
    private func choice(_ value: String, _ label: String) -> some View {
        Button { day = value; writingDay = (try? AppDiaryService(app: app).currentDay()).map { value == "yesterday" ? $0.adding(days: -1) : $0 } } label: { Text(label).font(MadarTypography.caption()).padding(.horizontal, 16).frame(minHeight: 42).foregroundStyle(day == value ? theme.background : theme.ink).background(day == value ? theme.ink : theme.surface, in: .capsule).overlay { Capsule().stroke(theme.line, lineWidth: 1) } }
            .buttonStyle(.plain).disabled(saving || importing || voice?.recording == true).accessibilityIdentifier("diary-editor-" + value).accessibilityAddTraits(day == value ? .isSelected : [])
    }
    private func scheduleDraft() {
        guard loaded, !saving else { return }
        draftTask?.cancel(); draftStatus = "تُحفظ المسودة…"
        draftTask = Task {
            do { try await Task.sleep(for: .milliseconds(500)); try Task.checkCancellation(); try await persistDraft(); draftStatus = "المسودة محفوظة" }
            catch is CancellationError {} catch { draftStatus = "لم تُحفظ المسودة"; failure = error.localizedDescription }
        }
    }
    private func persistDraft() async throws { guard let writingDay else { throw CocoaError(.coderInvalidValue) }; try await AppDiaryService(app: app).saveDraft(id: draftID, text: text, day: day, margin: margin, writingDay: writingDay) }
    private func close() async {
        draftTask?.cancel(); saving = true
        do { await voice?.stop(); if loaded { try await persistDraft() }; dismiss() }
        catch { failure = error.localizedDescription; saving = false }
    }
    private func add(_ data: Data, kind: String, type: String, caption: String = "") async throws {
        guard let writingDay else { throw CocoaError(.coderInvalidValue) }; importing = true
        defer { importing = false }
        _ = try await AppDiaryService(app: app).appendMedia(data: data, kind: kind, contentType: type, caption: caption, day: day, writingDay: writingDay)
        attachmentSaved = true; editorUndo = true; draftStatus = "حُفظ المرفق في الصفحة"
    }
    private func save() async {
        guard !saving else { return }; saving = true; draftTask?.cancel()
        do {
            await voice?.stop()
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await persistDraft()
                try await app.executeDiaryCommand("diary.commitDraft", payload: ["id": .string(draftID.uuidString)], id: draftID)
            }
            dismiss()
        } catch { failure = error.localizedDescription; saving = false }
    }
}
