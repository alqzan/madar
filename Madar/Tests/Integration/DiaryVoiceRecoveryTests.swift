import XCTest
import SwiftData
import AVFoundation
import MadarCore
import MadarData
@testable import Madar

/// A take that the system or a crash cut short stays on disk as an unfinished PCM CAF with its ticket. The next launch must turn it into saved,
/// playable audio. (The simulator cannot start the real recorder, so the unfinished file is written the way a cut take looks: still open.)
@MainActor final class DiaryVoiceRecoveryTests: XCTestCase {
    func testAnUnfinishedPCMTakeIsRecoveredAsPlayableSavedAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "VoiceRecover-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data")), app = try AppSession(container: container, groupDirectory: root)
        app.authorizeProtectedData()
        let day = try AppDiaryService(app: app).currentDay(), id = UUID()
        try FileManager.default.createDirectory(at: app.diaryStagingDirectory, withIntermediateDirectories: true)
        let caf = app.diaryStagingDirectory.appending(path: id.uuidString + ".caf")
        // Same settings as the diary's recorder; the file object stays open, so its length is never finalized, as after a cut.
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 22_050, AVNumberOfChannelsKey: 1,
                                       AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let open = try AVAudioFile(forWriting: caf, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
        let format = open.processingFormat, frames = AVAudioFrameCount(2 * 22_050)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)); buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.int16ChannelData![0][i] = Int16(8_000 * sin(Double(i) * 2 * .pi * 440 / 22_050)) }
        try open.write(from: buffer)
        try JSONEncoder().encode(["day": day.description]).write(to: caf.deletingPathExtension().appendingPathExtension("json"))

        let nextLaunch = DiaryVoiceController(app: app)
        await nextLaunch.recoverRecordings()
        let media = try XCTUnwrap(nextLaunch.lastMedia, "The unfinished take must be recovered: \(nextLaunch.message)")
        XCTAssertEqual(media.id, id)
        XCTAssertGreaterThanOrEqual(media.duration ?? 0, 1, "About two seconds were recorded")
        XCTAssertNoThrow(try AVAudioPlayer(data: media.data), "The saved bytes must play")
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Media>()).filter { $0.id == id }.count, 1)
        let staged = (try? FileManager.default.contentsOfDirectory(at: app.diaryStagingDirectory, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(staged.filter { ["json", "caf", "m4a"].contains($0.pathExtension) }.isEmpty, "Nothing stays staged after the save: \(staged.map(\.lastPathComponent))")
        withExtendedLifetime(open) {}
    }

    func testABrokenTakeIsKeptStagedForALaterTryNotDeleted() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "VoiceBroken-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data")), app = try AppSession(container: container, groupDirectory: root)
        app.authorizeProtectedData()
        let day = try AppDiaryService(app: app).currentDay(), id = UUID()
        try FileManager.default.createDirectory(at: app.diaryStagingDirectory, withIntermediateDirectories: true)
        let caf = app.diaryStagingDirectory.appending(path: id.uuidString + ".caf")
        try Data(repeating: 7, count: 4_096).write(to: caf)
        try JSONEncoder().encode(["day": day.description]).write(to: caf.deletingPathExtension().appendingPathExtension("json"))
        let voice = DiaryVoiceController(app: app)
        await voice.recoverRecordings()
        XCTAssertNil(voice.lastMedia)
        XCTAssertTrue(FileManager.default.fileExists(atPath: caf.path), "A file that cannot be read yet is not thrown away")
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Media>()).filter { $0.id == id }.count, 0)
    }
}
