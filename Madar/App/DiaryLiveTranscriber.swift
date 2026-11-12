import Foundation
import AVFoundation
import Speech
import Observation

/// Live words under the recorder (volatile results). It never touches the microphone: it only reads the audio file the recorder is
/// already writing (PCM CAF, readable up to its last byte), so the recorder, its staging file and its interruption save are unchanged.
/// Every failure here is silent: the words are a courtesy, the recording and the final transcript are what matter.
@Observable @MainActor final class DiaryLiveTranscriber {
    private(set) var text = ""
    private var task: Task<Void, Never>?

    func start(url: URL, locale: Locale?, active: @escaping @MainActor () -> Bool) {
        stop()
        guard let locale else { return }
        task = Task { [weak self] in
            await self?.run(url: url, locale: locale, active: active)
            self?.text = ""
        }
    }
    func stop() { task?.cancel(); task = nil; text = "" }

    private func run(url: URL, locale: Locale, active: @escaping @MainActor () -> Bool) async {
        let module = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        guard let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]),
              let source = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 22_050, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: source, to: target) else { return }
        let analyzer = SpeechAnalyzer(modules: [module])
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let results = Task { [weak self] in
            var finalized = ""
            do {
                for try await result in module.results {
                    let words = String(result.text.characters)
                    if result.isFinal { finalized += (finalized.isEmpty ? "" : " ") + words; self?.text = finalized }
                    else { self?.text = finalized + (finalized.isEmpty ? "" : " ") + words }
                }
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
                    if let data = try? handle.read(upToCount: Int(min(length, 200_000))), !data.isEmpty {
                        read += UInt64(data.count)
                        if let buffer = Self.convert(data, from: source, converter: converter, to: target) { continuation.yield(AnalyzerInput(buffer: buffer)) }
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
            guard (try? handle.seek(toOffset: position)) != nil, let head = try? handle.read(upToCount: 12), head.count == 12 else { return nil }
            let kind = String(decoding: head.prefix(4), as: UTF8.self)
            let size = head.suffix(8).reduce(Int64(0)) { ($0 << 8) | Int64($1) }
            if kind == "data" { return position + 12 + 4 }
            guard size >= 0 else { return nil }
            position += 12 + UInt64(size)
        }
        return nil
    }

    nonisolated private static func convert(_ data: Data, from source: AVAudioFormat, converter: AVAudioConverter, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(data.count / 2)
        guard frames > 0, let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: frames), let channel = input.int16ChannelData else { return nil }
        input.frameLength = frames
        data.withUnsafeBytes { raw in _ = memcpy(channel[0], raw.baseAddress!, data.count) }
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
