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
    private(set) var partialText = ""
    private(set) var canDownload = false
    private(set) var downloadProgress: Double?
    var needsConsent = false
    private(set) var microphoneDenied = false
    private(set) var pendingAudioCount = 0
    private(set) var lastMedia: DiaryDisplayMedia?
    private(set) var elapsedSeconds = 0
    private(set) var meterLevels: [Double] = []
    private(set) var transcriptText = ""
    private(set) var transcriptIsDirty = false
    private(set) var runtimeDescription = "سجّل صوتًا"
    private var installedLocale: Locale?
    private var supportedLocale: Locale?
    private var recorder: AVAudioRecorder?
    private var recordingDay: GregorianDay?
    private var meterTask: Task<Void, Never>?
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
    func start(writingDay: GregorianDay) async {
        guard !recording, !savingAudio else { return }
        lastMedia = nil; transcriptMedia = nil; transcriptText = ""; savedTranscript = ""; transcriptIsDirty = false
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else { refreshMicrophoneAuthorization(); return }
        do {
            try AppDiaryService(app: app).authorizeRead()
            app.diaryPlayback.stop()
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
            recordingDay = writingDay; microphoneDenied = false; message = "الحبر يسمعك · اضغط للإيقاف"
            elapsedSeconds = 0; meterLevels = []
            try startChunk()
            recording = true
            startMetering()
        } catch { recording = false; message = madarUserMessage(error) }
    }
    private func startChunk() throws {
        let root = app.diaryStagingDirectory
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        let url = root.appending(path: UUID().uuidString + ".m4a")
        let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
        if let recordingDay {
            try JSONEncoder().encode(RecordingTicket(day: recordingDay.description)).write(to: url.deletingPathExtension().appendingPathExtension("json"), options: [.atomic, .completeFileProtection])
        }
        recorder.delegate = self; self.recorder = recorder
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
    }
    private struct RecordingTicket: Codable { let day: String }
    func recoverRecordings() async {
        guard !recording, !savingAudio else { return }
        do {
            try AppDiaryService(app: app).authorizeRead()
            let files = try FileManager.default.contentsOfDirectory(at: app.diaryStagingDirectory, includingPropertiesForKeys: nil)
            for ticket in files where ticket.pathExtension == "json" {
                let url = ticket.deletingPathExtension().appendingPathExtension("m4a")
                guard FileManager.default.fileExists(atPath: url.path), let record = try? JSONDecoder().decode(RecordingTicket.self, from: Data(contentsOf: ticket)), let day = try? GregorianDay(record.day) else { continue }
                recordingDay = day; await storeChunk(url: url, successful: true)
            }
        } catch { if FileManager.default.fileExists(atPath: app.diaryStagingDirectory.path) { message = "تعذّر فتح التسجيلات المؤقتة. ملفاتها محفوظة لإعادة المحاولة." } }
    }
    private func refreshPendingAudio() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: app.diaryStagingDirectory, includingPropertiesForKeys: nil) else { return }
        pendingAudioCount = files.filter { $0.pathExtension == "json" && FileManager.default.fileExists(atPath: $0.deletingPathExtension().appendingPathExtension("m4a").path) }.count
    }
    func stop() async {
        guard let recorder else { return }; recording = false
        stopMetering(); elapsedSeconds = Int(recorder.currentTime.rounded(.down))
        let url = recorder.url; recorder.stop(); self.recorder = nil
        await storeChunk(url: url, successful: true)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let lastMedia { await transcribe(lastMedia) }
    }
    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.recording, let recorder = self.recorder else { return }
                recorder.updateMeters()
                self.elapsedSeconds = Int(recorder.currentTime.rounded(.down))
                let decibels = Double(recorder.averagePower(forChannel: 0))
                let level = min(1, max(0, (decibels + 54) / 54))
                self.meterLevels.append(level)
                if self.meterLevels.count > 36 { self.meterLevels.removeFirst(self.meterLevels.count - 36) }
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }
    private func stopMetering() { meterTask?.cancel(); meterTask = nil }
    fileprivate func storeChunk(url: URL, successful: Bool) async {
        guard processed.insert(url).inserted, let day = recordingDay else { return }
        savingAudio = true
        defer { savingAudio = false; refreshPendingAudio() }
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID()
            _ = try await AppDiaryService(app: app).appendMedia(data: data, kind: "audio", contentType: "audio/mp4", day: "today", writingDay: day, duration: Int(duration.rounded()), id: id)
            lastMedia = .init(id: id, entryID: id.uuidString, kind: "audio", contentType: "audio/mp4", data: data, duration: Int(duration.rounded()))
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("json"))
            message = successful ? "حُفظ التسجيل · يبدأ التفريغ الآن" : "توقف التسجيل؛ حُفظ ما أمكن من الصوت"
            // The staged file is removed only by a successful durable media write.
        } catch { processed.remove(url); message = "تعذّر إدخال الصوت في الصفحة؛ الملف محفوظ لإعادة المحاولة. " + madarUserDetail(error) }
    }
    func transcribe(_ media: DiaryDisplayMedia) async {
        guard !converting, media.kind == "audio" else { return }
        transcriptMedia = media
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
        let timeoutSeconds = min(240, max(20, (media.duration ?? 0) + 20))
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
            if self.recorder === recorder { self.recorder = nil; self.recording = false; self.stopMetering() }
            if !flag { self.message = "توقف التسجيل؛ نحفظ المقطع الذي اكتمل" }
            await self.storeChunk(url: url, successful: flag)
            if !self.recording, let media = self.lastMedia { await self.transcribe(media) }
        }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.recording = false; self.recorder = nil; self.stopMetering()
            self.message = "توقف التسجيل بسبب خطأ؛ نحفظ ما أمكن من الصوت"
            await self.storeChunk(url: url, successful: false)
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
