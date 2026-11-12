import Foundation
import AVFoundation
import Synchronization

/// What the diary voice controller needs from a recorder. `AVAudioRecorder` already has all of it.
@MainActor protocol DiaryTakeRecorder: AnyObject {
    var url: URL { get }
    var currentTime: TimeInterval { get }
    func stop()
    func updateMeters()
    func averagePower(forChannel channelNumber: Int) -> Float
}
extension AVAudioRecorder: DiaryTakeRecorder {}

/// Owner 12 Nov: «زي المكالمة… عزل الصوت». Records through the system's voice processing (the same noise suppression, echo
/// cancellation and level control as a call; the user's Voice Isolation mic mode applies on top) and writes exactly the file the
/// plain recorder wrote: PCM CAF, 22.05 kHz, mono, Int16 little-endian. A CAF still being written keeps an unknown data size, so a
/// take cut by a crash reads to its last byte, and the live words read it unchanged. Any setup failure throws, voice processing is
/// switched off again, and the controller falls back to `AVAudioRecorder`.
@MainActor final class DiaryCleanRecorder: DiaryTakeRecorder {
    static let fileSettings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 22_050, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
    let url: URL
    private let engine = AVAudioEngine()
    private let tap: Tap
    private var configurationObserver: NSObjectProtocol?
    /// Called once when the take cannot go on (the route changed and the engine would not restart, or the disk refuses writes);
    /// the controller then saves what was recorded.
    var onEnded: (@MainActor () -> Void)?

    init(url: URL) throws {
        self.url = url
        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)
        do {
            guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 22_050, channels: 1, interleaved: true) else { throw CocoaError(.featureUnsupported) }
            let file = try AVAudioFile(forWriting: url, settings: Self.fileSettings, commonFormat: .pcmFormatInt16, interleaved: true)
            tap = Tap(file: file, target: target)
        } catch {
            try? input.setVoiceProcessingEnabled(false)
            throw error
        }
        let tap = tap
        tap.onFailure = { [weak self] in Task { @MainActor in self?.end() } }
        // No fixed format: voice processing may change the input format when it starts or when the route changes; the tap
        // converts whatever arrives (a new converter for a new format, several channels mixed down to one).
        Self.install(on: input, tap: tap)
        engine.prepare()
    }
    /// Outside the main actor on purpose: a closure written inside this @MainActor class would inherit main-actor isolation and
    /// trap on the audio thread at the first buffer.
    nonisolated private static func install(on input: AVAudioInputNode, tap: Tap) {
        input.installTap(onBus: 0, bufferSize: 4_096, format: nil) { buffer, _ in tap.write(buffer) }
    }
    func record() throws {
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            // A route or format change (Bluetooth, a new sample rate) stops the engine; the take carries on if it restarts.
            MainActor.assumeIsolated { guard let self else { return }; do { try self.engine.start() } catch { self.end() } }
        }
        do { try engine.start() } catch { stop(); throw error }
    }
    var currentTime: TimeInterval { Double(tap.frames) / 22_050 }
    func updateMeters() {}
    func averagePower(forChannel channelNumber: Int) -> Float { tap.power }
    private func end() { guard let ended = onEnded else { return }; onEnded = nil; ended() }
    func stop() {
        onEnded = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        tap.close()
        try? engine.inputNode.setVoiceProcessingEnabled(false)
    }

    /// Runs on the audio thread: converts each buffer to the file's format and appends it; keeps the frame count and level.
    final class Tap: @unchecked Sendable {
        private struct State { var file: AVAudioFile?; var frames: Int64 = 0; var power: Float = -160; var failures = 0 }
        private let state: Mutex<State>
        private let target: AVAudioFormat
        /// Touched only on the audio thread.
        private var converter: AVAudioConverter?
        var onFailure: (@Sendable () -> Void)?
        init(file: AVAudioFile, target: AVAudioFormat) { state = Mutex(State(file: file)); self.target = target }
        var frames: Int64 { state.withLock { $0.frames } }
        var power: Float { state.withLock { $0.power } }
        func write(_ buffer: AVAudioPCMBuffer) {
            guard buffer.frameLength > 0, buffer.format.sampleRate > 0 else { return }
            if converter?.inputFormat != buffer.format {
                converter = AVAudioConverter(from: buffer.format, to: target)
                converter?.downmix = true
            }
            guard let converter else { return }
            let level = Self.decibels(buffer)
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate).rounded(.up)) + 64
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var handed = false
            var error: NSError?
            _ = converter.convert(to: output, error: &error) { _, status in
                if handed { status.pointee = .noDataNow; return nil }
                handed = true; status.pointee = .haveData; return buffer
            }
            guard error == nil, output.frameLength > 0 else { return }
            let failed = state.withLock { state -> Bool in
                guard let file = state.file else { return false }
                do { try file.write(from: output); state.frames += Int64(output.frameLength); state.power = level; state.failures = 0; return false }
                catch { state.failures += 1; return state.failures == 20 }
            }
            // A full disk or a refused write: end the take (and save what is there) instead of a frozen timer.
            if failed { onFailure?() }
        }
        func close() { state.withLock { state in state.file?.close(); state.file = nil } }
        private static func decibels(_ buffer: AVAudioPCMBuffer) -> Float {
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return -160 }
            var sum: Float = 0
            let count = Int(buffer.format.channelCount), frames = Int(buffer.frameLength)
            for channel in 0..<count { for index in 0..<frames { sum += channels[channel][index] * channels[channel][index] } }
            let rms = (sum / Float(frames * max(1, count))).squareRoot()
            return rms > 0 ? max(-160, 20 * log10(rms)) : -160
        }
    }
}
