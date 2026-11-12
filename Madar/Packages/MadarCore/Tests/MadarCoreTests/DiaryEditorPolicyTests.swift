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
    @Test func audioInsightsAndIntentionReviewsHaveStrictBoundedPayloads() {
        let id = UUID()
        let levels: [JSONValue] = [.number(0), .number(0.43), .number(1)]
        let audio: [String: JSONValue] = ["mediaID": .string(id.uuidString), "title": .string("لحظة هادئة"),
            "audioLevels": .array(levels)]
        #expect(DiaryEditorCommand.parse("diary.setAudioInsights", audio) != nil)
        let legacyAudio = audio.merging(["voiceTone": .string("calm")]) { _, next in next }
        #expect(DiaryEditorCommand.parse("diary.setAudioInsights", legacyAudio) != nil)
        #expect(DiaryEditorCommand.parse("diary.setAudioInsights", audio.merging(["audioLevels": .array([.number(1.2)])]) { _, next in next }) == nil)
        #expect(DiaryEditorCommand.parse("diary.setAudioInsights", legacyAudio.merging(["voiceTone": .string("loud")]) { _, next in next }) == nil)
        #expect(DiaryEditorCommand.parse("diary.setAudioInsights", audio.merging(["unexpected": .bool(true)]) { _, next in next }) == nil)

        let review: [String: JSONValue] = ["id": .string(id.uuidString), "period": .string("weekly"), "text": .string("تعلمت أن أبدأ بخطوة أصغر.")]
        #expect(DiaryEditorCommand.parse("diary.setIntentionReview", review) != nil)
        #expect(DiaryEditorCommand.parse("diary.setIntentionReview", review.merging(["period": .string("daily")]) { _, next in next }) == nil)
        #expect(DiaryEditorCommand.parse("diary.setIntentionReview", review.merging(["text": .string("  ")]) { _, next in next }) == nil)
        #expect(DiaryEditorCommand.parse("diary.setIntentionReview", review.merging(["text": .string(String(repeating: "ا", count: 2001))]) { _, next in next }) == nil)
    }
    @Test func elapsedVoiceDurationSwitchesFromSecondsToMinutesAndHours() {
        #expect(DiaryDurationFormat.elapsed(0) == "٠ ثانية")
        #expect(DiaryDurationFormat.elapsed(1) == "١ ثانية")
        #expect(DiaryDurationFormat.elapsed(59) == "٥٩ ثانية")
        #expect(DiaryDurationFormat.elapsed(60) == "١:٠٠")
        #expect(DiaryDurationFormat.elapsed(125) == "٢:٠٥")
        #expect(DiaryDurationFormat.elapsed(3599) == "٥٩:٥٩")
        #expect(DiaryDurationFormat.elapsed(3600) == "١:٠٠:٠٠")
        #expect(DiaryDurationFormat.elapsed(3661) == "١:٠١:٠١")
        #expect(DiaryDurationFormat.elapsed(65, digits: .init(style: .western)) == "1:05")
        #expect(DiaryDurationFormat.totalSeconds(3661) == "٣٦٦١ ثانية")
    }
    /// Owner, 24 Oct 2026: a photo may be linked to the Photos library by its identifier; audio may not, nor an empty one.
    @Test func appendMediaAcceptsALibraryLinkOnlyForPhotos() {
        let base: [String:JSONValue] = ["fileID": .string(UUID().uuidString), "kind": .string("photo"), "contentType": .string("image/jpeg"), "caption": .string(""), "day": .string("today"), "writingDayKey": .string("2026-10-24")]
        guard case .appendMedia(_, _, _, _, _, _, _, let asset, _)? = DiaryEditorCommand.parse("diary.appendMedia", base.merging(["assetID": .string("ABC-123/L0/001")]) { _, new in new }) else { Issue.record("A linked photo must parse"); return }
        #expect(asset == "ABC-123/L0/001")
        #expect(DiaryEditorCommand.parse("diary.appendMedia", base.merging(["assetID": .string("")]) { _, new in new }) == nil)
        #expect(DiaryEditorCommand.parse("diary.appendMedia", base.merging(["kind": .string("audio"), "assetID": .string("ABC")]) { _, new in new }) == nil)
        #expect(DiaryPhotoLink.assetID(sourceID: "photos:ABC") == "ABC" && DiaryPhotoLink.assetID(sourceID: "dayone:ABC") == nil && DiaryPhotoLink.assetID(sourceID: nil) == nil)
    }
}
