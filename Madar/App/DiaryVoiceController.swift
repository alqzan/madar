import Foundation
import Observation
import AVFoundation
import Speech
import UIKit
import MadarCore

/// Owns UI-bound microphone, permission and recognition state. Audio is committed before recognition starts.
@Observable @MainActor final class DiaryVoiceController: NSObject {
    unowned let app: AppSession
    var language = "ar-SA"
    private(set) var recording = false
    private(set) var savingAudio = false
    private(set) var converting = false
    private(set) var message = ""
    /// True after the system ended a take (a call, an alarm, a lost microphone): the writing page offers a fresh take.
    private(set) var interrupted = false
    private(set) var partialText = ""
    private(set) var canDownload = false
    private(set) var downloadProgress: Double?
    var needsConsent = false
    private(set) var microphoneDenied = false
    private(set) var pendingAudioCount = 0
    private(set) var lastMedia: DiaryDisplayMedia?
    private(set) var elapsedSeconds = 0
    private(set) var meterLevels: [Double] = []
    private(set) var recordedAudioLevels: [Double] = []
    private(set) var generatedTitle: String?
    private(set) var insightStatus = ""
    private(set) var transcriptText = ""
    private(set) var transcriptIsDirty = false
    private(set) var runtimeDescription = "سجّل صوتًا"
    private var installedLocale: Locale?
    private var supportedLocale: Locale?
    private var recorder: AVAudioRecorder?
    /// Live words while recording (read from the recorder's own file; never a second microphone session).
    let live = DiaryLiveTranscriber()
    private var recordingDay: GregorianDay?
    private var meterWindowSecond = 0
    private var meterWindowTotal = 0.0
    private var meterWindowCount = 0
    private var meterTask: Task<Void, Never>?
    private var audioEventTask: Task<Void, Never>?
    private var transcriptMedia: DiaryDisplayMedia?
    private var savedTranscript = ""
    private var processed: Set<URL> = []
    private var recognition: DiaryRecognitionRequest?
    private var job: UUID?
    private var timeout: Task<Void, Never>?
    private var analysis: Task<Void, Never>?
    private var download: Task<Void, Never>?
    private var installation: AssetInstallationRequest?
    private var consentMedia: DiaryDisplayMedia?
    private static let microphoneDeniedMessage = "الميكروفون غير مسموح. يمكنك الكتابة، أو تفعيله من إعدادات النظام."
    init(app: AppSession) {
        self.app = app
        super.init()
        refreshMicrophoneAuthorization()
    }

    /// Permission belongs to the system, so rebuilding an editor after its prompt must not lose it.
    func refreshMicrophoneAuthorization() {
        if AVAudioApplication.shared.recordPermission == .denied {
            microphoneDenied = true
            message = Self.microphoneDeniedMessage
        } else if microphoneDenied {
            microphoneDenied = false
            if message == Self.microphoneDeniedMessage { message = "" }
        }
    }

    func refreshLanguage() async {
        let selected = language
        var installed: Locale?, supported: Locale?
        if SpeechTranscriber.isAvailable {
            supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: selected))
            let locales = await SpeechTranscriber.installedLocales
            if let supported, locales.contains(where: { $0.identifier == supported.identifier }) { installed = supported }
        }
        guard selected == language else { return }
        installedLocale = installed; supportedLocale = supported; canDownload = supported != nil && installed == nil
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: selected))
        runtimeDescription = installed != nil ? "التحويل على الجهاز" : recognizer?.isAvailable == true && recognizer?.supportsOnDeviceRecognition == true ? "التحويل على الجهاز" : recognizer?.isAvailable == true ? "تحويل Apple بعد موافقتك" : "سجّل صوتًا"
    }
    private var starting = false
    func start(writingDay: GregorianDay) async {
        guard !recording, !savingAudio, !starting else { return }
        starting = true; defer { starting = false }
        lastMedia = nil; transcriptMedia = nil; transcriptText = ""; savedTranscript = ""; transcriptIsDirty = false; interrupted = false
        generatedTitle = nil; insightStatus = ""
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else { refreshMicrophoneAuthorization(); return }
        var sessionActive = false
        do {
            try AppDiaryService(app: app).authorizeRead()
            app.diaryPlayback.stop()
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
            sessionActive = true
            recordingDay = writingDay; microphoneDenied = false; message = "الحبر يسمعك · اضغط للإيقاف"
        elapsedSeconds = 0; meterLevels = []; recordedAudioLevels = []
        meterWindowSecond = 0; meterWindowTotal = 0; meterWindowCount = 0
            try startChunk()
            recording = true
            if let url = recorder?.url { live.start(url: url, locale: installedLocale) { [weak self] in self?.recording == true } }
            startMetering()
            observeAudioSession()
        } catch {
            recording = false; recorder = nil; if sessionActive { endAudioSession() }; message = madarUserMessage(error)
            // A take that never began leaves nothing staged to be "recovered" later.
            if let staged = try? FileManager.default.contentsOfDirectory(at: app.diaryStagingDirectory, includingPropertiesForKeys: nil) {
                for file in staged where file.pathExtension == "caf" && (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 < 1_024 {
                    for ext in ["json", "caf"] { try? FileManager.default.removeItem(at: file.deletingPathExtension().appendingPathExtension(ext)) }
                }
            }
        }
    }
    private func startChunk() throws {
        let root = app.diaryStagingDirectory
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        // 11 Nov: an .m4a has no index until it is closed, so a take cut by a crash or by the system was unplayable. A PCM CAF is readable up to the last byte; it is turned into .m4a when stored.
        let url = root.appending(path: UUID().uuidString + ".caf")
        // Linear PCM: unlike AAC it has no packet table written at the end, so a take cut by a crash is still readable. Export turns it into AAC.
        let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 22_050, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
        if let recordingDay {
            try JSONEncoder().encode(RecordingTicket(day: recordingDay.description, startedAt: Date().timeIntervalSince1970)).write(to: url.deletingPathExtension().appendingPathExtension("json"), options: [.atomic, .completeFileProtection])
        }
        recorder.delegate = self; self.recorder = recorder
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
    }
    /// `startedAt` lets a recovered take keep the time (and so the ink) it was recorded at, not the time it was recovered; old tickets have none.
    private struct RecordingTicket: Codable { let day: String; var startedAt: Double? = nil }
    nonisolated private static func stagedAudio(for ticket: URL) -> URL? {
        let base = ticket.deletingPathExtension()
        return ["caf", "m4a"].map { base.appendingPathExtension($0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    /// A playable .m4a for a staged take: a CAF is exported, an .m4a is only checked. Throws for audio that cannot be played, so the file stays staged.
    @concurrent private static func playableM4A(from url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable), try await asset.load(.duration).seconds > 0 else { throw CocoaError(.fileReadCorruptFile) }
        if url.pathExtension == "m4a" { return url }
        let output = url.deletingPathExtension().appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: output)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw CocoaError(.fileWriteUnknown) }
        try await session.export(to: output, as: .m4a)
        return output
    }
    func recoverRecordings() async {
        guard !recording, !savingAudio else { return }
        do {
            try AppDiaryService(app: app).authorizeRead()
            let files = try FileManager.default.contentsOfDirectory(at: app.diaryStagingDirectory, includingPropertiesForKeys: nil)
            for ticket in files where ticket.pathExtension == "json" {
                guard let url = Self.stagedAudio(for: ticket), let record = try? JSONDecoder().decode(RecordingTicket.self, from: Data(contentsOf: ticket)), let day = try? GregorianDay(record.day) else { continue }
                guard !recording, !savingAudio else { return }
                await storeChunk(url: url, successful: true, day: day, levels: [], startedAt: record.startedAt.map { Date(timeIntervalSince1970: $0) })
            }
        } catch { if FileManager.default.fileExists(atPath: app.diaryStagingDirectory.path) { message = "تعذّر فتح التسجيلات المؤقتة. ملفاتها محفوظة لإعادة المحاولة." } }
    }
    private func refreshPendingAudio() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: app.diaryStagingDirectory, includingPropertiesForKeys: nil) else { return }
        pendingAudioCount = files.filter { $0.pathExtension == "json" && Self.stagedAudio(for: $0) != nil }.count
    }
    /// Every way a take ends hands the audio session back, so other apps' audio can resume.
    private func endAudioSession() { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    func stop() async {
        guard let recorder else { return }; recording = false
        // A call or the lock screen sends the app to the background right as the take ends; this asks the system for the time to finish saving it.
        let background = UIApplication.shared.beginBackgroundTask(withName: "diary-take-save")
        defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }
        stopMetering(); stopObservingAudioSession(); elapsedSeconds = Int(recorder.currentTime.rounded(.down))
        let url = recorder.url; recorder.stop(); self.recorder = nil
        // Other apps' audio resumes at once, not after the file is exported.
        endAudioSession()
        await storeChunk(url: url, successful: true)
        if let lastMedia { await transcribe(lastMedia) }
    }
    // MARK: Interruptions (B1-11): a call, an alarm or a lost microphone ends the take cleanly with what was recorded.
    private func observeAudioSession() {
        audioEventTask?.cancel()
        audioEventTask = Task { [weak self] in
            let center = NotificationCenter.default, session = AVAudioSession.sharedInstance()
            await withTaskGroup(of: Void.self) { group in
                for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification] {
                    group.addTask { [weak self] in
                        for await note in center.notifications(named: name, object: session) {
                            guard !Task.isCancelled, let event = DiaryVoiceInterruption.event(from: note) else { continue }
                            // Unstructured: stopping cancels this observer, and the save that follows must not run inside a cancelled task.
                            Task { @MainActor [weak self] in await self?.handleAudioEvent(event) }
                        }
                    }
                }
            }
        }
    }
    private func stopObservingAudioSession() { audioEventTask?.cancel(); audioEventTask = nil }
    func handleAudioEvent(_ event: DiaryVoiceInterruption.Event) async {
        guard DiaryVoiceInterruption.action(recording: recording, event: event) == .stopAndSave else { return }
        await stop()
        interrupted = true
        message = "توقف التسجيل لأن النظام قاطعه؛ حُفظ ما سُجّل"
    }
    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.recording, let recorder = self.recorder else { return }
                recorder.updateMeters()
                self.elapsedSeconds = Int(recorder.currentTime.rounded(.down))
                // A take forgotten in the background ends by itself; two hours is far beyond a diary entry.
                if self.elapsedSeconds >= 7_200 {
                    Task { @MainActor in await self.stop(); self.message = "بلغ التسجيل ساعتين فتوقف وحُفظ ما سُجّل" }
                    return
                }
                let decibels = Double(recorder.averagePower(forChannel: 0))
                let level = min(1, max(0, (decibels + 54) / 54))
                self.meterLevels.append(level)
                if self.meterLevels.count > 36 { self.meterLevels.removeFirst(self.meterLevels.count - 36) }
                let second = Int(recorder.currentTime.rounded(.down))
                if second > self.meterWindowSecond {
                    self.appendCompletedMeterWindow()
                    self.meterWindowSecond = second
                }
                self.meterWindowTotal += level; self.meterWindowCount += 1
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }
    private func stopMetering() {
        meterTask?.cancel(); meterTask = nil
        appendCompletedMeterWindow()
    }
    private func appendCompletedMeterWindow() {
        guard meterWindowCount > 0 else { return }
        recordedAudioLevels.append(min(1, max(0, meterWindowTotal / Double(meterWindowCount))))
        if recordedAudioLevels.count > 36_000 { recordedAudioLevels.removeFirst(recordedAudioLevels.count - 36_000) }
        meterWindowTotal = 0; meterWindowCount = 0
    }
    fileprivate func storeChunk(url: URL, successful: Bool, day explicitDay: GregorianDay? = nil, levels: [Double]? = nil, startedAt: Date? = nil) async {
        guard processed.insert(url).inserted, let day = explicitDay ?? recordingDay else { return }
        savingAudio = true
        defer { savingAudio = false; refreshPendingAudio() }
        do {
            // A long take is read off the main actor, so the screen keeps answering while it is saved.
            let playable = try await Self.playableM4A(from: url)
            let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: playable) }.value
            guard !data.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            let duration = (try? await AVURLAsset(url: playable).load(.duration).seconds) ?? 0
            let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID()
            _ = try await AppDiaryService(app: app).appendMedia(data: data, kind: "audio", contentType: "audio/mp4", day: "today", writingDay: day, duration: Int(duration.rounded()), at: startedAt, id: id)
            let samples = levels ?? recordedAudioLevels
            lastMedia = .init(id: id, entryID: id.uuidString, kind: "audio", contentType: "audio/mp4", data: data, duration: Int(duration.rounded()), title: nil, levelSamples: samples)
            try? await saveAudioInsights(mediaID: id, title: nil, levels: samples)
            // Only now, after the durable media write, is the staged take released.
            for ext in ["json", "caf", "m4a"] { try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension(ext)) }
            message = successful ? "حُفظ التسجيل · يبدأ التفريغ الآن" : "توقف التسجيل؛ حُفظ ما أمكن من الصوت"
            // The staged file is removed only by a successful durable media write.
        } catch { processed.remove(url); message = "تعذّر إدخال الصوت في الصفحة؛ الملف محفوظ لإعادة المحاولة. " + madarUserDetail(error) }
    }
    func transcribe(_ media: DiaryDisplayMedia) async {
        guard !converting, media.kind == "audio" else { return }
        transcriptMedia = media; recordedAudioLevels = media.levelSamples
        generatedTitle = media.title
        do { try AppDiaryService(app: app).authorizeRead() } catch { message = madarUserMessage(error); return }
        let token = UUID(); job = token; converting = true; partialText = ""; message = "يُجهّز التحويل…"
        await refreshLanguage(); guard job == token else { return }
        var authorization = SFSpeechRecognizer.authorizationStatus()
        if authorization == .notDetermined { authorization = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } } }
        guard job == token else { return }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
        let route = DiarySpeechPolicy.route(authorized: authorization == .authorized, transcriberInstalled: installedLocale != nil,
            recognizerAvailable: recognizer?.isAvailable == true, recognizerOnDevice: recognizer?.supportsOnDeviceRecognition == true,
            serverConsent: app.bool("notes.serverDictationConsent"))
        guard route != .audioOnly else { cancelConversion(); message = "التحويل غير متاح لهذه اللغة أو الإذن. الصوت محفوظ، والكتابة متاحة."; return }
        if route == .needsConsent { cancelConversion(); consentMedia = media; needsConsent = true; return }
        message = "يُحوّل الصوت المحفوظ…"
        // Scales with the take (a long one used to be cut at 4 minutes and reported as failed).
        let timeoutSeconds = max(60, (media.duration ?? 0) * 2 + 60)
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(timeoutSeconds)) } catch { return }
            guard let self, self.job == token else { return }; self.cancelConversion(); self.message = "لم يتحوّل؛ الصوت محفوظ · أعد المحاولة"
        }
        let locale = installedLocale, language = language
        analysis = Task { [weak self] in
            guard let self else { return }
            do {
                let root = self.app.diaryStagingDirectory.appending(path: "Playback", directoryHint: .isDirectory).appending(path: token.uuidString, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
                defer { try? FileManager.default.removeItem(at: root) }
                let url = root.appending(path: media.id.uuidString + ".m4a"); try media.data.write(to: url, options: [.atomic, .completeFileProtection])
                let text: String
                if route == .transcriber, let locale { text = try await Self.onDevice(url: url, locale: locale) }
                else {
                    let files = route == .appleServer ? try await Self.serverChunks(url: url, root: root) : [url]
                    var parts: [String] = []
                    for file in files {
                        try Task.checkCancellation(); guard self.job == token else { return }
                        let request = DiaryRecognitionRequest(); self.recognition = request
                        let value = try await request.run(url: file, language: language, onDevice: route == .recognizerOnDevice)
                        parts.append(value); self.partialText = parts.joined(separator: " ")
                    }
                    text = parts.joined(separator: " ")
                }
                try Task.checkCancellation(); await self.accept(text, media: media, token: token)
            } catch { self.fail(madarUserMessage(error), token: token) }
        }
    }
    private func accept(_ text: String, media: DiaryDisplayMedia, token: UUID) async {
        guard job == token else { return }
        do {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CocoaError(.coderInvalidValue) }
            try await app.executeDiaryCommand("diary.setTranscript", payload: ["entryID": .string(media.entryID), "text": .string(text)])
            guard job == token else { return }
            transcriptMedia = media; transcriptText = text; savedTranscript = text; transcriptIsDirty = false
            cancelConversion(); message = "حُفظ النص بجانب صوته؛ عدّله هنا إن احتجت"
        } catch { fail(madarUserMessage(error), token: token) }
    }
    func saveTranscriptEdits() async {
        guard let media = transcriptMedia, transcriptIsDirty else { return }
        do {
            try await app.executeDiaryCommand("diary.setTranscript", payload: ["entryID": .string(media.entryID), "text": .string(transcriptText)])
            savedTranscript = transcriptText; transcriptIsDirty = false; message = "حُفظ تعديل التفريغ بجانب التسجيل"
        } catch { message = "لم يُحفظ التعديل؛ أعد المحاولة. " + madarUserDetail(error) }
    }
    func editTranscript(_ text: String) { transcriptText = text; transcriptIsDirty = text != savedTranscript }
    func loadExistingTranscript(_ media: DiaryDisplayMedia, text: String) {
        guard media.kind == "audio", !transcriptIsDirty else { return }
        if transcriptMedia?.id != media.id || transcriptText != text {
            transcriptMedia = media; transcriptText = text; savedTranscript = text
        }
    }
    var currentTranscriptMedia: DiaryDisplayMedia? { transcriptMedia }
    func saveAudioInsights(mediaID: UUID, title: String?, levels: [Double]) async throws {
        try await app.executeDiaryCommand("diary.setAudioInsights", payload: [
            "mediaID": .string(mediaID.uuidString),
            "title": title.map(MadarCore.JSONValue.string) ?? .null,
            "audioLevels": .array(levels.map(MadarCore.JSONValue.number))
        ])
        if let title { generatedTitle = title }
        insightStatus = title != nil ? "اكتمل العنوان التلقائي" : ""
    }
    func setInsightStatus(_ value: String) { insightStatus = value }
    private func fail(_ error: String, token: UUID) {
        guard job == token else { return }; cancelConversion(); message = "لم يتحوّل؛ الصوت محفوظ · أعد المحاولة. " + error
    }
    func cancelConversion() {
        job = nil; converting = false; timeout?.cancel(); timeout = nil; recognition?.cancel(); recognition = nil; analysis?.cancel(); analysis = nil; partialText = ""
        message = "أُلغي التحويل؛ الصوت محفوظ"
    }
    func consent(_ allow: Bool) async {
        let media = consentMedia; consentMedia = nil; needsConsent = false
        guard allow, let media else { message = "الصوت محفوظ دون إرسال"; return }
        do { try await app.applySettingsAndWait(["notes.serverDictationConsent": .bool(true)]); await transcribe(media) }
        catch { message = madarUserMessage(error) }
    }
    func downloadLanguage() {
        guard let supportedLocale, download == nil else { return }
        downloadProgress = 0
        download = Task { [weak self] in
            guard let self else { return }
            do {
                let module = SpeechTranscriber(locale: supportedLocale, preset: .transcription)
                guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { self.downloadProgress = nil; self.download = nil; await self.refreshLanguage(); return }
                self.installation = request
                let progress = Task { [weak self] in
                    while !Task.isCancelled { self?.downloadProgress = request.progress.fractionCompleted; do { try await Task.sleep(for: .milliseconds(300)) } catch { break } }
                }
                defer { progress.cancel() }
                try await request.downloadAndInstall(); self.message = "أصبحت لغة الإملاء على الجهاز"
            } catch { self.message = "لم يكتمل تحميل اللغة. التسجيل والكتابة متاحان." }
            self.download = nil; self.downloadProgress = nil; self.installation = nil; await self.refreshLanguage()
        }
    }
    func cancelDownload() { installation?.progress.cancel(); download?.cancel(); download = nil; downloadProgress = nil; installation = nil }
    /// Server requests each receive less than a minute, including imported recordings.
    @concurrent static func serverChunks(url: URL, root: URL) async throws -> [URL] {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat, frames = AVAudioFrameCount(55 * format.sampleRate)
        guard input.length > AVAudioFramePosition(frames) else { return [url] }
        var files: [URL] = []
        while input.framePosition < input.length {
            try Task.checkCancellation()
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { throw CocoaError(.fileReadUnknown) }
            try input.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            let file = root.appending(path: UUID().uuidString + ".m4a")
            let output = try AVAudioFile(forWriting: file, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: Int(format.channelCount)], commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            try output.write(from: buffer); files.append(file)
        }
        return files
    }
    @concurrent private static func onDevice(url: URL, locale: Locale) async throws -> String {
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [module])
        return try await withTaskCancellationHandler {
            let results = Task { var text = ""; for try await result in module.results { try Task.checkCancellation(); text += String(result.text.characters) }; return text }
            do { try await analyzer.start(inputAudioFile: AVAudioFile(forReading: url), finishAfterFile: true); return try await results.value }
            catch { results.cancel(); await analyzer.cancelAndFinishNow(); throw error }
        } onCancel: { Task { await analyzer.cancelAndFinishNow() } }
    }
}
extension DiaryVoiceController: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self else { return }
            let endedHere = self.recorder === recorder
            if endedHere { self.recorder = nil; self.recording = false; self.stopMetering(); self.stopObservingAudioSession() }
            if !flag { self.message = "توقف التسجيل؛ نحفظ المقطع الذي اكتمل" }
            await self.storeChunk(url: url, successful: flag)
            if endedHere, !self.recording { self.endAudioSession() }
            if endedHere, !self.recording, let media = self.lastMedia { await self.transcribe(media) }
        }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.recording = false; self.recorder = nil; self.stopMetering()
            self.message = "توقف التسجيل بسبب خطأ؛ نحفظ ما أمكن من الصوت"
            await self.storeChunk(url: url, successful: false)
            if !self.recording { self.endAudioSession() }
        }
    }
}

/// A single native recognition request; cancellation resumes its waiter exactly once.
@MainActor private final class DiaryRecognitionRequest {
    private var continuation: CheckedContinuation<String, Error>?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    func run(url: URL, language: String, onDevice: Bool) async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)), recognizer.isAvailable else { finish(.failure(CocoaError(.featureUnsupported))); return }
                self.recognizer = recognizer
                let request = SFSpeechURLRecognitionRequest(url: url); request.requiresOnDeviceRecognition = onDevice; request.shouldReportPartialResults = false
                task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    let text = result?.isFinal == true ? result?.bestTranscription.formattedString : nil
                    let failure = error?.localizedDescription
                    Task { @MainActor in
                        if let text { self?.finish(.success(text)) }
                        else if let failure { self?.finish(.failure(NSError(domain: "DiarySpeech", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]))) }
                    }
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }
    func cancel() { task?.cancel(); task = nil; finish(.failure(CancellationError())) }
    private func finish(_ result: Result<String, Error>) { let waiter = continuation; continuation = nil; task = nil; recognizer = nil; waiter?.resume(with: result) }
}

/// What an audio-session notification means for a take in progress. Pure, so it is tested without a microphone.
enum DiaryVoiceInterruption {
    enum Event: Equatable { case interruptionBegan, inputLost }
    enum Action: Equatable { case ignore, stopAndSave }
    static func action(recording: Bool, event: Event) -> Action { recording ? .stopAndSave : .ignore }
    static func event(from note: Notification) -> Event? {
        guard let info = note.userInfo else { return nil }
        if note.name == AVAudioSession.interruptionNotification {
            guard let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt, AVAudioSession.InterruptionType(rawValue: raw) == .began else { return nil }
            return .interruptionBegan
        }
        if note.name == AVAudioSession.routeChangeNotification {
            guard let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable,
                  let previous = info[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
                  !previous.inputs.isEmpty, AVAudioSession.sharedInstance().currentRoute.inputs.isEmpty else { return nil }
            return .inputLost
        }
        return nil
    }
}
