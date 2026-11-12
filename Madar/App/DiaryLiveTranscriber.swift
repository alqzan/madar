import Foundation
import AVFoundation
import Speech
import Observation
import MadarCore

/// Live words under the recorder (volatile results). It never touches the microphone: it only reads the audio file the recorder is
/// already writing (PCM CAF, readable up to its last byte), so the recorder, its staging file and its interruption save are unchanged.
/// Every failure here is silent: the words are a courtesy, the recording and the final transcript are what matter.
@Observable @MainActor final class DiaryLiveTranscriber {
    private(set) var text = ""
    private var task: Task<Void, Never>?

    func start(url: URL, locale: Locale?, dictation: Bool = false, active: @escaping @MainActor () -> Bool) {
        stop()
        guard let locale else { return }
        task = Task { [weak self] in
            await self?.run(url: url, locale: locale, dictation: dictation, active: active)
            self?.text = ""
        }
    }
    func stop() { task?.cancel(); task = nil; text = "" }

    private func run(url: URL, locale: Locale, dictation: Bool, active: @escaping @MainActor () -> Bool) async {
        // Arabic is a dictation language, not a `SpeechTranscriber` one (owner 12 Nov: live words never appeared for Arabic).
        let speech = dictation ? nil : SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        let spoken = dictation ? DictationTranscriber(locale: locale, preset: .progressiveLongDictation) : nil
        let module: any SpeechModule = speech ?? spoken!
        guard let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]),
              let source = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 22_050, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: source, to: target) else { return }
        let analyzer = SpeechAnalyzer(modules: [module])
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let results = Task { [weak self] in
            var finalized = ""
            @MainActor func show(_ words: String, final: Bool) {
                if final { DiaryTranscriptJoin.append(words, to: &finalized); self?.text = finalized }
                else { var shown = finalized; DiaryTranscriptJoin.append(words, to: &shown); self?.text = shown }
            }
            do {
                if let speech { for try await result in speech.results { show(String(result.text.characters), final: result.isFinal) } }
                else if let spoken { for try await result in spoken.results { show(String(result.text.characters), final: result.isFinal) } }
            } catch {}
        }
        do { try await analyzer.start(inputSequence: stream) } catch { continuation.finish(); results.cancel(); return }
        var offset: UInt64?
        var read: UInt64 = 0
        while !Task.isCancelled, active() {
            if let handle = try? FileHandle(forReadingFrom: url) {
                defer { try? handle.close() }
                if offset == nil { offset = Self.samplesOffset(handle); read = offset ?? 0 }
                if offset != nil, let size = try? handle.seekToEnd(), size > read + 2 {
                    let length = ((size - read) / 2) * 2
                    try? handle.seek(toOffset: read)
                    if var data = try? handle.read(upToCount: Int(min(length, 200_000))) {
                        // Whole frames only: a partial frame stays in the file and is read with the next chunk.
                        data = data.prefix(data.count - data.count % 2)
                        read += UInt64(data.count)
                        if !data.isEmpty, let buffer = Self.convert(data, from: source, converter: converter, to: target) { continuation.yield(AnalyzerInput(buffer: buffer)) }
                    }
                }
            }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { break }
        }
        continuation.finish()
        if Task.isCancelled { await analyzer.cancelAndFinishNow() }
        else { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
        results.cancel()
    }

    /// Where the samples begin in a CAF: after its chunk headers up to «data» and the 4-byte edit count. Nil until the header is written.
    nonisolated private static func samplesOffset(_ handle: FileHandle) -> UInt64? {
        var position: UInt64 = 8
        for _ in 0..<12 {
            if position == 8 { guard formatMatches(handle) else { return nil } }
            guard (try? handle.seek(toOffset: position)) != nil, let head = try? handle.read(upToCount: 12), head.count == 12 else { return nil }
            let kind = String(decoding: head.prefix(4), as: UTF8.self)
            let size = head.suffix(8).reduce(Int64(0)) { ($0 << 8) | Int64($1) }
            if kind == "data" { return position + 12 + 4 }
            guard size >= 0 else { return nil }
            position += 12 + UInt64(size)
        }
        return nil
    }

    /// The recorder writes 22.05 kHz, mono, interleaved 16-bit little-endian integer PCM; anything else is not converted.
    nonisolated private static func formatMatches(_ handle: FileHandle) -> Bool {
        guard (try? handle.seek(toOffset: 8)) != nil, let head = try? handle.read(upToCount: 12 + 32), head.count == 44,
              String(decoding: head.prefix(4), as: UTF8.self) == "desc" else { return false }
        let body = [UInt8](head.suffix(32))
        func u32(_ at: Int) -> UInt32 { body[at..<at + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } }
        let rate = Double(bitPattern: body[0..<8].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) })
        let flags = u32(12)
        return rate == 22_050 && String(decoding: body[8..<12], as: UTF8.self) == "lpcm" && flags & 1 == 0 && flags & 2 != 0
            && u32(16) == 2 && u32(20) == 1 && u32(24) == 1 && u32(28) == 16
    }

    nonisolated private static func convert(_ data: Data, from source: AVAudioFormat, converter: AVAudioConverter, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(data.count / 2)
        guard frames > 0, let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: frames), let channel = input.int16ChannelData else { return nil }
        input.frameLength = frames
        let bytes = Int(frames) * 2 * Int(source.channelCount)
        guard source.channelCount == 1, data.count >= bytes else { return nil }
        data.withUnsafeBytes { raw in _ = memcpy(channel[0], raw.baseAddress!, bytes) }
        let capacity = AVAudioFrameCount(Double(frames) * target.sampleRate / source.sampleRate) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return input
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }
}
