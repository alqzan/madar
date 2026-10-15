import Foundation
import Testing
@testable import MadarCore

struct DiaryEditorPolicyTests {
    @Test func n06SelectsOnlyAvailableLocalModelsAndRequiresServerConsent() {
        #expect(DiarySpeechPolicy.route(authorized: true, transcriberInstalled: true, recognizerAvailable: true, recognizerOnDevice: true, serverConsent: true) == .transcriber)
        #expect(DiarySpeechPolicy.route(authorized: true, transcriberInstalled: false, recognizerAvailable: true, recognizerOnDevice: true, serverConsent: false) == .recognizerOnDevice)
        #expect(DiarySpeechPolicy.route(authorized: true, transcriberInstalled: false, recognizerAvailable: true, recognizerOnDevice: false, serverConsent: false) == .needsConsent)
        #expect(DiarySpeechPolicy.route(authorized: true, transcriberInstalled: false, recognizerAvailable: true, recognizerOnDevice: false, serverConsent: true) == .appleServer)
        #expect(DiarySpeechPolicy.route(authorized: false, transcriberInstalled: true, recognizerAvailable: true, recognizerOnDevice: true, serverConsent: true) == .audioOnly)
        #expect(DiarySpeechPolicy.route(authorized: true, transcriberInstalled: false, recognizerAvailable: false, recognizerOnDevice: false, serverConsent: true) == .audioOnly)
    }
    @Test func nativeDraftIsStrictAndSupportsLongWritingWithoutChangingExternalAppendLimit() {
        let id = UUID()
        let valid: [String:JSONValue] = ["id": .string(id.uuidString), "text": .string(String(repeating: "ا", count: 5000)), "day": .string("today"), "writingDayKey": .string("2026-10-15")]
        #expect(DiaryEditorCommand.parse("diary.saveDraft", valid) != nil)
        #expect(DiaryEditorCommand.parse("diary.saveDraft", valid.merging(["unexpected": .bool(true)]) { _, new in new }) == nil)
        #expect(DiaryEditorCommand.parse("diary.saveDraft", valid.merging(["writingDayKey": .string("2026-02-30")]) { _, new in new }) == nil)
        #expect(DiaryEditorCommand.parse("diary.appendMedia", ["fileID": .string("../../store"), "kind": .string("audio")]) == nil)
    }
}
