import SwiftUI
import ImageIO
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
    var missingCount = 1
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
                    .buttonStyle(.madarPlain).accessibilityLabel("افتح الصورة").accessibilityIdentifier("diary-media-" + media.id.uuidString)
            } else if media.kind == "audio" {
                HStack(spacing: 12) {
                    Button { togglePlayback() } label: { Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44).foregroundStyle(theme.onAccent).background(theme.accent, in: .circle) }
                        .buttonStyle(.madarPlain).accessibilityLabel(playing ? "أوقف الصوت مؤقتًا" : "شغّل التسجيل").accessibilityIdentifier("diary-play-" + media.id.uuidString)
                    ProgressView(value: playback.activeID == media.id ? playback.position : 0).tint(theme.accent)
                    Text(media.duration.map(seconds) ?? "تسجيل صوتي").font(MadarTypography.fine())
                }.padding(10).background(theme.surface, in: .capsule)
                if let voice {
                    DisclosureGroup("التسجيل والنص") {
                        DiaryVoiceControls(controller: voice)
                        if !voice.converting { Button { Task { await voice.transcribe(media) } } label: { Text(transcript.isEmpty ? "حوّله إلى نص" : "أعِد التحويل").frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("diary-transcribe-" + media.id.uuidString) }
                        Button { editingTranscript = true } label: { Text("عدّل النص مع إبقاء الصوت").frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("diary-transcript-edit-" + media.id.uuidString)
                    }.font(MadarTypography.caption())
                }
            } else if media.kind == "missing" {
                // N01: the export referenced this file but did not contain it; the entry keeps the marker.
                Label(missingText, systemImage: "exclamationmark.circle")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).padding(.horizontal, 14).frame(minHeight: 44)
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
                    .accessibilityIdentifier("diary-media-missing")
            } else {
                Button { open() } label: { Label(media.kind == "video" ? "افتح المقطع" : "افتح المرفق", systemImage: media.kind == "video" ? "play.rectangle" : "doc").font(MadarTypography.caption()).padding(.horizontal, 14).frame(minHeight: 44).background(theme.surface, in: .rect(cornerRadius: 10)).overlay { RoundedRectangle(cornerRadius: 10).stroke(theme.line) } }
                    .buttonStyle(.madarPlain).accessibilityIdentifier("diary-media-" + media.id.uuidString)
            }
            if let error { Text(error).font(MadarTypography.fine()) }
        }.padding(.vertical, 10).padding(.leading, 58).padding(.trailing, 18)
            .task { if voice == nil { voice = DiaryVoiceController(app: app) } }
            .sheet(item: $preview) { item in DiaryQuickLook(url: item.url).onDisappear { try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent()) } }
            .sheet(isPresented: $editingTranscript) { DiaryTranscriptEditor(app: app, media: media, original: transcript).environment(\.roomTheme, theme).diaryRootDraftBlocking(app) }
            .onDisappear { if playback.activeID == media.id { playback.stop() }; voice?.cancelConversion(); voice?.cancelDownload() }
    }
    /// «ثانية واحدة»، «ثانيتان»، «٥ ثوانٍ»، «٤٠ ثانيةً».
    private func seconds(_ n: Int) -> String {
        let digits = AppDiaryService(app: app).digits
        switch n { case 1: return "ثانية واحدة"; case 2: return "ثانيتان"; case 0, 3...10: return digits.string(n) + " ثوانٍ"; default: return digits.string(n) + (n % 100 >= 11 ? " ثانيةً" : " ثانية") }
    }
    private var missingText: String {
        let digits = AppDiaryService(app: app).digits
        guard missingCount > 1 else { return "مرفق ناقص: " + (["photo": "صورة", "audio": "تسجيل صوتي", "video": "مقطع"][media.contentType] ?? "ملف") + " لم يكن في ملف داي ون" }
        let noun = media.contentType == "photo" ? (missingCount == 2 ? "صورتان" : missingCount <= 10 ? digits.string(missingCount) + " صور" : digits.string(missingCount) + " صورةً")
            : (missingCount == 2 ? "مرفقان" : missingCount <= 10 ? digits.string(missingCount) + " مرفقات" : digits.string(missingCount) + " مرفقًا")
        return "مرفقات ناقصة: " + noun + " لم تكن في ملف داي ون"
    }
    private func togglePlayback() {
        do {
            try AppDiaryService(app: app).authorizeRead()
            try playback.toggle(id: media.id, data: media.data)
        } catch { self.error = "تعذّر تشغيل الصوت. الملف محفوظ." }
    }
    private func open() {
        if let id = media.assetID, let asset = DiaryPhotoLibrary.asset(id) {
            Task {
                if let data = await DiaryPhotoLibrary.data(asset) { show(data) } else { show(media.data) }
            }
            return
        }
        show(media.data)
    }
    private func show(_ data: Data) {
        do {
            try AppDiaryService(app: app).authorizeRead()
            let ext = UTType(mimeType: media.contentType)?.preferredFilenameExtension ?? "data"
            let root = FileManager.default.temporaryDirectory.appending(path: "DiaryPreview-" + media.id.uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            let original = String((transcript as NSString).lastPathComponent.prefix(100))
            let name = media.kind == "document" && !original.isEmpty && original != "." && original != ".." ? original : "مرفق." + ext
            let url = root.appending(path: name)
            try data.write(to: url, options: [.atomic, .completeFileProtection]); preview = .init(id: media.id, url: url)
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
    @State private var loaded = false
    @State private var confirmDiscard = false
    @State private var error: String?
    @FocusState private var editing: Bool
    private var hasUnsavedText: Bool { loaded && text != original }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                Text("الصوت هو الأصل، ويبقى محفوظًا مع هذا النص.").font(MadarTypography.caption()).padding()
                TextEditor(text: $text).font(DiaryType.writing).scrollContentBackground(.hidden).padding().focused($editing).accessibilityIdentifier("diary-transcript-text")
                if let error { Text(error).font(MadarTypography.caption()).padding() }
            }.background(theme.background).foregroundStyle(theme.ink).navigationTitle("نص التسجيل").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("إلغاء") { if hasUnsavedText { editing = false; confirmDiscard = true } else { dismiss() } }.madarWaitsForSave().accessibilityIdentifier("diary-transcript-close") }
                    ToolbarItem(placement: .topBarTrailing) { Button("احفظ") { Task { saving = true; do { try await app.executeDiaryCommand("diary.setTranscript", payload: ["entryID": .string(media.entryID), "text": .string(text)]); dismiss() } catch { self.error = madarUserMessage(error); saving = false } } }.disabled(saving).accessibilityIdentifier("diary-transcript-save") }
                }
        }
        .confirmationDialog("تتجاهل تعديل النص؟", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("تجاهل التعديل", role: .destructive) { dismiss() }.accessibilityIdentifier("diary-transcript-discard")
            Button("أكمل التعديل") { }.accessibilityIdentifier("diary-transcript-continue")
        } message: { Text("التعديلات غير محفوظة.") }
        .task { text = original; loaded = true }
        .madarSheetLock(saving: saving, draft: hasUnsavedText)
        .diaryRootDraftBlocking(app)
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

/// A small picture of stored photo data: shrunk off the main thread when the row appears, so a list never decodes a full-size photo in `body`.
struct DiaryDataThumbnail<Content: View>: View {
    let data: Data
    var maxPixel: CGFloat = 400
    @ViewBuilder let content: (Image) -> Content
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { content(Image(uiImage: image)) } else { Color.clear }
        }.task(id: data.count) {
            let source = data, side = maxPixel
            image = await Task.detached(priority: .utility) { () -> UIImage? in
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: side]
                guard let imageSource = CGImageSourceCreateWithData(source as CFData, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { return UIImage(data: source) }
                return UIImage(cgImage: cg)
            }.value
        }
    }
}
