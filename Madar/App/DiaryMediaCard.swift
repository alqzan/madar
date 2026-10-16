import SwiftUI
import AVFoundation
import Observation
import QuickLook
import UniformTypeIdentifiers
import MadarCore
import MadarDesign

private struct DiaryPreview: Identifiable { let id: UUID; let url: URL }
struct DiaryMediaCard: View {
    @Bindable var app: AppSession
    let media: DiaryDisplayMedia
    let transcript: String
    @Environment(\.roomTheme) private var theme
    @State private var preview: DiaryPreview?
    @State private var error: String?
    private var playback: DiaryPlayback { app.diaryPlayback }
    private var playing: Bool { playback.activeID == media.id && playback.playing }
    @State private var voice: DiaryVoiceController?
    @State private var editingTranscript = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if media.kind == "photo", let image = UIImage(data: media.data) {
                Button { open() } label: { Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 150).padding(8).background(theme.surface).rotationEffect(.degrees(-2)).shadow(color: theme.ink.opacity(0.1), radius: 5, y: 4) }
                    .buttonStyle(.plain).accessibilityLabel("افتح الصورة").accessibilityIdentifier("diary-media-" + media.id.uuidString)
            } else if media.kind == "audio" {
                HStack(spacing: 12) {
                    Button { togglePlayback() } label: { Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44).foregroundStyle(theme.onAccent).background(theme.accent, in: .circle) }
                        .buttonStyle(.plain).accessibilityLabel(playing ? "أوقف الصوت مؤقتًا" : "شغّل التسجيل").accessibilityIdentifier("diary-play-" + media.id.uuidString)
                    ProgressView(value: playback.activeID == media.id ? playback.position : 0).tint(theme.accent)
                    Text(media.duration.map { AppDiaryService(app: app).digits.string($0) + " ثانية" } ?? "تسجيل صوتي").font(MadarTypography.fine())
                }.padding(10).background(theme.surface, in: .capsule)
                if let voice {
                    DisclosureGroup("التسجيل والنص") {
                        DiaryVoiceControls(controller: voice)
                        if !voice.converting { Button(transcript.isEmpty ? "حوّله إلى نص" : "أعِد التحويل") { Task { await voice.transcribe(media) } }.frame(minHeight: 44).accessibilityIdentifier("diary-transcribe-" + media.id.uuidString) }
                        Button("عدّل النص مع إبقاء الصوت") { editingTranscript = true }.frame(minHeight: 44).accessibilityIdentifier("diary-transcript-edit-" + media.id.uuidString)
                    }.font(MadarTypography.caption())
                }
            } else if media.kind == "missing" {
                // N01: the export referenced this file but did not contain it; the entry keeps the marker.
                Label("مرفق ناقص: " + (["photo": "صورة", "audio": "تسجيل صوتي", "video": "مقطع"][media.contentType] ?? "ملف") + " لم يكن في ملف داي ون", systemImage: "exclamationmark.circle")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).padding(.horizontal, 14).frame(minHeight: 44)
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
                    .accessibilityIdentifier("diary-media-missing")
            } else {
                Button { open() } label: { Label(media.kind == "video" ? "افتح المقطع" : "افتح المرفق", systemImage: media.kind == "video" ? "play.rectangle" : "doc").font(MadarTypography.caption()).padding(.horizontal, 14).frame(minHeight: 44).background(theme.surface, in: .rect(cornerRadius: 10)).overlay { RoundedRectangle(cornerRadius: 10).stroke(theme.line) } }
                    .buttonStyle(.plain).accessibilityIdentifier("diary-media-" + media.id.uuidString)
            }
            if let error { Text(error).font(MadarTypography.fine()) }
        }.padding(.vertical, 10).padding(.leading, 58).padding(.trailing, 18)
            .task { if voice == nil { voice = DiaryVoiceController(app: app) } }
            .sheet(item: $preview) { item in DiaryQuickLook(url: item.url).onDisappear { try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent()) } }
            .sheet(isPresented: $editingTranscript) { DiaryTranscriptEditor(app: app, media: media, original: transcript).environment(\.roomTheme, theme) }
            .onDisappear { if playback.activeID == media.id { playback.stop() }; voice?.cancelConversion(); voice?.cancelDownload() }
    }
    private func togglePlayback() {
        do {
            try AppDiaryService(app: app).authorizeRead()
            try playback.toggle(id: media.id, data: media.data)
        } catch { self.error = "تعذّر تشغيل الصوت. الملف محفوظ." }
    }
    private func open() {
        do {
            try AppDiaryService(app: app).authorizeRead()
            let ext = UTType(mimeType: media.contentType)?.preferredFilenameExtension ?? "data"
            let root = FileManager.default.temporaryDirectory.appending(path: "DiaryPreview-" + media.id.uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            let original = String((transcript as NSString).lastPathComponent.prefix(100))
            let name = media.kind == "document" && !original.isEmpty && original != "." && original != ".." ? original : "مرفق." + ext
            let url = root.appending(path: name)
            try media.data.write(to: url, options: [.atomic, .completeFileProtection]); preview = .init(id: media.id, url: url)
        } catch { self.error = "تعذّر فتح المرفق. يمكنك إعادة المحاولة." }
    }
}
struct DiaryQuickLook: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(url: url, close: { dismiss() }) }
    func makeUIViewController(context: Context) -> UINavigationController {
        let viewer = QLPreviewController(); viewer.dataSource = context.coordinator; viewer.title = url.lastPathComponent
        let coordinator = context.coordinator
        viewer.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { _ in coordinator.close() })
        return UINavigationController(rootViewController: viewer)
    }
    func updateUIViewController(_ view: UINavigationController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        let close: @MainActor () -> Void
        init(url: URL, close: @escaping @MainActor () -> Void) { self.url = url; self.close = close }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}
private struct DiaryTranscriptEditor: View {
    @Bindable var app: AppSession
    let media: DiaryDisplayMedia
    let original: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var text = ""
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                Text("الصوت هو الأصل، ويبقى محفوظًا مع هذا النص.").font(MadarTypography.caption()).padding()
                TextEditor(text: $text).font(DiaryType.writing).scrollContentBackground(.hidden).padding().accessibilityIdentifier("diary-transcript-text")
                if let error { Text(error).font(MadarTypography.caption()).padding() }
            }.background(theme.background).foregroundStyle(theme.ink).navigationTitle("نص التسجيل").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("إلغاء") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { Button("احفظ") { Task { saving = true; do { try await app.executeDiaryCommand("diary.setTranscript", payload: ["entryID": .string(media.entryID), "text": .string(text)]); dismiss() } catch { self.error = error.localizedDescription; saving = false } } }.disabled(saving).accessibilityIdentifier("diary-transcript-save") }
                }
        }.task { text = original }.interactiveDismissDisabled(text != original)
    }
}

@Observable @MainActor final class DiaryPlayback {
    private(set) var activeID: UUID?
    private(set) var playing = false
    private(set) var position: Double = 0
    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?
    func toggle(id: UUID, data: Data) throws {
        if activeID != id { stop(); player = try AVAudioPlayer(data: data); activeID = id }
        if playing { player?.pause(); playing = false; ticker?.cancel(); return }
        try AVAudioSession.sharedInstance().setCategory(.playback); playing = player?.play() == true
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player else { break }
                self.position = player.duration > 0 ? player.currentTime / player.duration : 0
                if !player.isPlaying { self.playing = false; break }
                do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
            }
        }
    }
    func stop() { ticker?.cancel(); ticker = nil; player?.stop(); player = nil; playing = false; activeID = nil; position = 0 }
}
