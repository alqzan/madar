import XCTest
import SwiftData
import AVFoundation
import UIKit
import MadarCore
import MadarData
@testable import Madar

@MainActor final class DiaryEditorIntegrationTests: XCTestCase {
    func testSavingAnEmptiedDraftLeavesNothingToRestore() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryEmptied-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data")), app = try AppSession(container: container, groupDirectory: root)
        app.authorizeProtectedData(); let service = AppDiaryService(app: app), day = try service.currentDay(), id = UUID()
        try await service.saveDraft(id: id, text: "سطر سيُمسح", day: "today", margin: nil, writingDay: day)
        XCTAssertEqual(try service.draft(margin: nil)?.text, "سطر سيُمسح")
        try await service.saveDraft(id: id, text: "", day: "today", margin: nil, writingDay: day)
        XCTAssertEqual(try service.draft(margin: nil)?.text ?? "", "")
    }
    func testDraftPhotoAndAudioPersistWithTheirEntryAndOriginalBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryMedia-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data")), app = try AppSession(container: container, groupDirectory: root)
        app.authorizeProtectedData(); let service = AppDiaryService(app: app), day = try service.currentDay(), id = UUID()
        try await service.saveDraft(id: id, text: "مسودة لا تضيع", day: "today", margin: nil, writingDay: day)
        XCTAssertEqual(try service.draft(margin: nil)?.text, "مسودة لا تضيع")
        try await app.executeDiaryCommand("diary.commitDraft", payload: ["id": .string(id.uuidString)], id: id)
        XCTAssertNil(try service.draft(margin: nil))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).jpegData(withCompressionQuality: 0.9) { canvas in UIColor.brown.setFill(); canvas.fill(CGRect(x: 0,y: 0,width: 40,height: 40)) }
        let photo = try await service.appendMedia(data: image, kind: "photo", contentType: "image/jpeg", day: "today", writingDay: day)
        let page = try service.day(day); XCTAssertTrue(page.media.contains { $0.id == photo && $0.data == image }); XCTAssertTrue(page.lines.contains { $0.id == photo.uuidString })
        let audioURL = root.appending(path: "audio.m4a")
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)); buffer.frameLength = 44_100; buffer.floatChannelData![0].initialize(repeating: 0, count: 44_100)
        do { let file = try AVAudioFile(forWriting: audioURL, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1]); try file.write(from: buffer) }
        let originalAudio = try Data(contentsOf: audioURL), audioID = UUID()
        _ = try await service.appendMedia(data: originalAudio, kind: "audio", contentType: "audio/mp4", day: "today", writingDay: day, duration: 1, id: audioID)
        let savedAudio = try XCTUnwrap(service.day(day).media.first { $0.id == audioID }); XCTAssertEqual(savedAudio.data, originalAudio)
        XCTAssertNoThrow(try AVAudioPlayer(data: savedAudio.data))
        let transcript = "سجلت الفكرة بصوتي، وأريد أن أراجعها لاحقًا."
        try await app.executeDiaryCommand("diary.setTranscript", payload: ["entryID": .string(audioID.uuidString), "text": .string(transcript)])
        let records = try service.analysisRecords(from: day, through: day)
        let aiRequest = try MadarAIAnalysisRequest.diary(records: records, scopeTitle: "هذا اليوم", rangeSummary: "اليوم", digits: service.digits)
        XCTAssertTrue(aiRequest.sourceSegments.joined().contains(transcript), "A saved voice transcript must be present in the diary AI source.")
        let staged = app.diaryStagingDirectory.appending(path: audioID.uuidString)
        try originalAudio.write(to: staged.appendingPathExtension("m4a")); try JSONEncoder().encode(["day": day.description]).write(to: staged.appendingPathExtension("json"))
        let recovering = DiaryVoiceController(app: app); await recovering.recoverRecordings()
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Media>()).filter { $0.id == audioID }.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.appendingPathExtension("json").path))
        for locale in ["ar-SA", "en-US"] {
            let voice = DiaryVoiceController(app: app); voice.language = locale; await voice.refreshLanguage()
            print("N06 runtime \(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? UIDevice.current.model), iOS \(UIDevice.current.systemVersion), \(locale): \(voice.runtimeDescription)")
        }
    }
    func testImportedServerAudioIsSplitBelowOneMinuteWithoutChangingOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryChunks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appending(path: "original.caf"), sampleRate = 16_000.0, duration = 122
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false))
        let frames = AVAudioFrameCount(duration) * AVAudioFrameCount(sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)); buffer.frameLength = frames
        buffer.floatChannelData![0].initialize(repeating: 0, count: Int(frames))
        do { let file = try AVAudioFile(forWriting: input, settings: format.settings); try file.write(from: buffer) }
        let original = try Data(contentsOf: input)
        let chunks = try await DiaryVoiceController.serverChunks(url: input, root: root)
        let durations = try chunks.map { url in let file = try AVAudioFile(forReading: url); return Double(file.length)/file.processingFormat.sampleRate }
        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        XCTAssertTrue(durations.allSatisfy { $0 > 0 && $0 < 60 }, "Every server request must be shorter than a minute: \(durations)")
        XCTAssertEqual(durations.reduce(0, +), Double(duration), accuracy: 0.1, "All 122 seconds must remain represented")
        XCTAssertEqual(try Data(contentsOf: input), original)
    }
}

/// B1-12: the take stops and keeps its audio on a system interruption; nothing happens when no take is running.
@MainActor final class DiaryVoiceInterruptionTests: XCTestCase {
    func testARecordingTakeStopsAndSavesOnInterruptionOrLostInput() {
        XCTAssertEqual(DiaryVoiceInterruption.action(recording: true, event: .interruptionBegan), .stopAndSave)
        XCTAssertEqual(DiaryVoiceInterruption.action(recording: true, event: .inputLost), .stopAndSave)
        XCTAssertEqual(DiaryVoiceInterruption.action(recording: false, event: .interruptionBegan), .ignore)
    }
    func testOnlyTheBeginningOfAnInterruptionCountsNotItsEnd() {
        let began = Notification(name: AVAudioSession.interruptionNotification, object: nil,
                                 userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        let ended = Notification(name: AVAudioSession.interruptionNotification, object: nil,
                                 userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        XCTAssertEqual(DiaryVoiceInterruption.event(from: began), .interruptionBegan)
        XCTAssertNil(DiaryVoiceInterruption.event(from: ended))
        XCTAssertNil(DiaryVoiceInterruption.event(from: Notification(name: .init("other"))))
    }

    /// A draft write begun as a page closes must finish before the next reader looks at the draft.
    func testDraftFlushSettlesBeforeTheNextReaderContinues() async {
        @MainActor final class Log { var items: [String] = [] }
        let log = Log()
        DiaryDraftFlush.run { try? await Task.sleep(for: .milliseconds(60)); log.items.append("first") }
        DiaryDraftFlush.run { log.items.append("second") }
        await DiaryDraftFlush.settle()
        log.items.append("reader")
        XCTAssertEqual(log.items, ["first", "second", "reader"])
    }
    /// Diary dates lead with the diary's own calendar (`notes.calendarFirst`), whatever the app-wide first calendar is.
    func testDiaryDatesFollowTheDiaryCalendarNotTheAppOne() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryDates-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        _ = try SettingsStore(context: context).stage(["core.firstCalendar": .string("hijri"), "notes.calendarFirst": .string("gregorian"), "core.numerals": .string("arabicIndic")])
        try context.save()
        let app = try AppSession(container: container, groupDirectory: root); app.authorizeProtectedData()
        let text = AppDiaryService(app: app).diaryDates(try GregorianDay("2026-10-09"))
        XCTAssertEqual(text, "٩ أكتوبر ٢٠٢٦ م، ٢٨ ربيع الآخر ١٤٤٨ هـ")
    }
}
