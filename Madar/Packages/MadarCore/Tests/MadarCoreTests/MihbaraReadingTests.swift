import Foundation
import Testing
@testable import MadarCore

@Suite struct MihbaraReadingTests {
    @Test func threeReadingSlotsRequireAnExplicitReplacement() {
        let ids = (0..<4).map { _ in UUID() }, reading = Set([UUID(),UUID(),UUID()])
        #expect(!MihbaraReading.canRead(id: ids[0], reading: reading, replacing: nil))
        #expect(!MihbaraReading.canRead(id: ids[0], reading: reading, replacing: ids[1]))
        #expect(MihbaraReading.canRead(id: ids[0], reading: reading, replacing: reading.first))
        #expect(MihbaraReading.canRead(id: reading.first!, reading: reading, replacing: nil))
        #expect(MihbaraReading.canRead(id: ids[0], reading: Set(reading.prefix(2)), replacing: nil))
    }
    @Test func hadithIdentitiesSurviveReorderingAndTodaysCompletedWirdDoesNotAdvanceAgain() {
        let numbers = Array((1...42).reversed())
        #expect(MihbaraReading.nextHadith(numbers: numbers, read: Set(1...12), readToday: [], count: 1) == [13])
        #expect(MihbaraReading.nextHadith(numbers: numbers, read: Set(1...13), readToday: [13], count: 1).isEmpty)
        #expect(MihbaraReading.nextHadith(numbers: numbers, read: Set(1...13), readToday: [13], count: 3) == [14,15])
        #expect(MihbaraReading.nextHadith(numbers: numbers, read: Set(1...42), readToday: [], count: 1).isEmpty)
    }
    @Test func aPaperPositionIsAnHonestRatioAndUnknownLengthStaysUnknown() {
        #expect(MihbaraReading.progress(page: 147, pages: 250) == 0.588)
        #expect(MihbaraReading.progress(page: 147, pages: nil) == nil)
        #expect(MihbaraReading.progress(page: nil, pages: 250) == nil)
        #expect(MihbaraReading.progress(page: 300, pages: 250) == 1)
    }
    @Test func activeReadingStopsAtFiveIdleMinutesAndBackground() {
        let start = Date(timeIntervalSince1970: 0)
        var clock = ActiveReadingClock(startedAt: start)
        clock.advance(to: start.addingTimeInterval(10 * 60))
        #expect(clock.activeSeconds == 300)
        clock.interaction(at: start.addingTimeInterval(10 * 60))
        clock.advance(to: start.addingTimeInterval(10 * 60 + 12))
        #expect(clock.activeSeconds == 312)
        clock.setForeground(false, at: start.addingTimeInterval(10 * 60 + 12))
        clock.setForeground(true, at: start.addingTimeInterval(60 * 60))
        clock.advance(to: start.addingTimeInterval(60 * 60 + 30))
        #expect(clock.activeSeconds == 312)
        clock.interaction(at: start.addingTimeInterval(60 * 60 + 30))
        clock.advance(to: start.addingTimeInterval(60 * 60 + 35))
        #expect(clock.activeSeconds == 317)
    }
    @Test func pageProgressCountsForwardOnceAndSkipsFastJumps() {
        let start = Date(timeIntervalSince1970: 0)
        var progress = ReadingPositionProgress(startingAt: 10, at: start)
        progress.observe(position: 11, at: start.addingTimeInterval(10))
        progress.observe(position: 12, at: start.addingTimeInterval(20))
        progress.observe(position: 11, at: start.addingTimeInterval(30))
        progress.observe(position: 12, at: start.addingTimeInterval(40))
        #expect(progress.pagesCounted == 2)
        progress.observe(position: 45, at: start.addingTimeInterval(50))
        #expect(progress.pagesCounted == 2)
        progress.observe(position: 46, at: start.addingTimeInterval(65))
        #expect(progress.pagesCounted == 3)
        progress.observe(position: 90, at: start.addingTimeInterval(70), explicitJump: true)
        #expect(progress.pagesCounted == 3)
        #expect(progress.furthestPosition == 90)
    }

    @Test func returningBelowTheStartingPageAndBelowAJumpNeverCreditsPages() {
        let start = Date(timeIntervalSince1970: 0)
        var progress = ReadingPositionProgress(startingAt: 10, at: start)
        progress.observe(position: 8, at: start.addingTimeInterval(10))
        progress.observe(position: 10, at: start.addingTimeInterval(20))
        #expect(progress.pagesCounted == 0)
        progress.observe(position: 30, at: start.addingTimeInterval(30), explicitJump: true)
        progress.observe(position: 29, at: start.addingTimeInterval(40))
        progress.observe(position: 30, at: start.addingTimeInterval(50))
        #expect(progress.pagesCounted == 0)
        progress.observe(position: 31, at: start.addingTimeInterval(70))
        #expect(progress.pagesCounted == 1)
    }

    @Test func estimatedPagesRequireAKnownPrintedTotal() {
        #expect(ReadingPageEstimate.page(progression: 0.25, totalPages: 200) == 50)
        #expect(ReadingPageEstimate.page(progression: 0.255, totalPages: 200) == 51)
        #expect(ReadingPageEstimate.page(progression: 0.5, totalPages: nil) == nil)
        #expect(ReadingPageEstimate.page(progression: nil, totalPages: 200) == nil)
        #expect(ReadingPageEstimate.page(progression: .nan, totalPages: 200) == nil)
    }

    @Test func coveredReaderCountsNoTimeAndNewDayDoesNotRenewIdleAllowance() {
        let start = Date(timeIntervalSince1970: 0)
        var clock = ActiveReadingClock(startedAt: start)
        clock.setForeground(false, at: start.addingTimeInterval(45))
        clock.advance(to: start.addingTimeInterval(600))
        #expect(clock.activeSeconds == 45)
        clock.setForeground(true, at: start.addingTimeInterval(600))
        clock.interaction(at: start.addingTimeInterval(600))
        clock.startSegment(at: start.addingTimeInterval(660))
        #expect(clock.activeSeconds == 0)
        clock.advance(to: start.addingTimeInterval(1200))
        #expect(clock.activeSeconds == 240)
    }

    @Test func epubPolicyAllowsOnlyReadiumAssetsForStylesAndFontsAndStillBlocksScripts() {
        let directives = Dictionary(uniqueKeysWithValues: ReadingDocumentPolicy.content.split(separator: ";").map {
            let parts = $0.split(separator: " ").map(String.init)
            return (parts[0], Set(parts.dropFirst()))
        })
        #expect(directives["style-src"]?.contains("readium://assets") == true)
        #expect(directives["font-src"]?.contains("readium://assets") == true)
        #expect(directives["script-src"] == ["'none'"])
        #expect(directives["default-src"]?.contains("readium://assets") == false)
        #expect(directives["img-src"]?.contains("readium://assets") == false)
    }

    @Test func epubPolicyPrecedesAuthorScriptsEvenWhenAuthorProvidesAPolicy() throws {
        let source = "<?xml version=\"1.0\"?><html xmlns=\"http://www.w3.org/1999/xhtml\"><head><meta http-equiv=\"Content-Security-Policy\" content=\"script-src *\"/><script>alert(1)</script></head><body>نص الكتاب</body></html>"
        let secured = try #require(ReadingDocumentPolicy.secure(source))
        #expect(secured.contains("<head><meta http-equiv=\"Content-Security-Policy\" content=\"default-src"))
        let restrictive = try #require(secured.range(of: "script-src 'none'"))
        let author = try #require(secured.range(of: "script-src *"))
        #expect(restrictive.lowerBound < author.lowerBound)
        #expect(secured.contains("<body>نص الكتاب</body>"))
    }

    @Test func epubPolicyIgnoresCommentHeadsAndRejectsActiveContentBeforeHead() throws {
        let secured = try #require(ReadingDocumentPolicy.secure("<!DOCTYPE html><!-- <head> --><html><head data-label='>'><title>كتاب</title></head><body/></html>"))
        #expect(secured.contains("<head data-label='>'><meta http-equiv=\"Content-Security-Policy\""))
        #expect(ReadingDocumentPolicy.secure("<html><script>alert(1)</script><head></head></html>") == nil)
        #expect(ReadingDocumentPolicy.secure("<html><body>لا رأس</body></html>") == nil)
        #expect(ReadingDocumentPolicy.secure("<!DOCTYPE html [<!ENTITY x '<script/>'>]><html><head/></html>") == nil)
    }

    @Test func rejectedPausedSessionKeepsItsExactPayloadAndCommandUntilAcknowledged() throws {
        var queue = PendingReadingSessionQueue()
        let sessionID = UUID(), commandID = UUID()
        let payload: [String: JSONValue] = ["id": .string(sessionID.uuidString), "activeSeconds": .number(90)]
        queue.enqueue(sessionID: sessionID, payload: payload, commandID: commandID)
        let firstAttempt = queue.beginNext()
        let first = try #require(firstAttempt)
        queue.finish(commandID: first.commandID, acknowledged: false)
        #expect(!queue.isEmpty)
        let nextAttempt1 = queue.beginNext()
        #expect(nextAttempt1 == nil) // A rejected write must not spin while covered.
        queue.authorizedForegroundReturned()
        let retryAttempt = queue.beginNext()
        let retry = try #require(retryAttempt)
        #expect(retry == first)
        #expect(retry.sessionID == sessionID && retry.commandID == commandID && retry.payload == payload)
        queue.finish(commandID: retry.commandID, acknowledged: true)
        #expect(queue.isEmpty)
    }

    @Test func authorizationReturnDuringAnAttemptDoesNotStartAConcurrentRetry() throws {
        var queue = PendingReadingSessionQueue()
        queue.enqueue(sessionID: UUID(), payload: ["activeSeconds": .number(120)])
        let firstAttempt = queue.beginNext()
        let first = try #require(firstAttempt)
        queue.authorizedForegroundReturned()
        let nextAttempt2 = queue.beginNext()
        #expect(nextAttempt2 == nil)
        queue.finish(commandID: first.commandID, acknowledged: false)
        let nextAttempt3 = queue.beginNext()
        #expect(nextAttempt3 == first) // The newer authorization may retry the earlier failure.
    }

    @Test func sameSessionUpdateWaitsBehindItsImmutableInFlightSnapshot() throws {
        var queue = PendingReadingSessionQueue()
        let sessionID = UUID()
        queue.enqueue(sessionID: sessionID, payload: ["activeSeconds": .number(90)])
        let firstAttempt = queue.beginNext()
        let first = try #require(firstAttempt)
        queue.enqueue(sessionID: sessionID, payload: ["activeSeconds": .number(200)])
        queue.finish(commandID: UUID(), acknowledged: true)
        let nextAttempt4 = queue.beginNext()
        #expect(!queue.isEmpty && nextAttempt4 == nil)
        queue.finish(commandID: first.commandID, acknowledged: false)
        queue.authorizedForegroundReturned()
        let nextAttempt5 = queue.beginNext()
        #expect(nextAttempt5 == first)
        queue.finish(commandID: first.commandID, acknowledged: true)
        #expect(!queue.isEmpty)
        let updatedAttempt = queue.beginNext()
        let updated = try #require(updatedAttempt)
        #expect(updated.sessionID == sessionID)
        #expect(updated.commandID != first.commandID)
        #expect(updated.payload == ["activeSeconds": .number(200)])
        queue.finish(commandID: first.commandID, acknowledged: true)
        #expect(!queue.isEmpty) // An old acknowledgement cannot remove the newer snapshot.
        queue.finish(commandID: updated.commandID, acknowledged: true)
        #expect(queue.isEmpty)
    }

    @Test func laterSegmentsWaitForTheEarlierSegmentToBeAcknowledged() throws {
        var queue = PendingReadingSessionQueue()
        let old = UUID(), new = UUID()
        queue.enqueue(sessionID: old, payload: ["activeSeconds": .number(90)])
        queue.enqueue(sessionID: new, payload: ["activeSeconds": .number(75)])
        let firstAttempt = queue.beginNext()
        let first = try #require(firstAttempt)
        #expect(first.sessionID == old)
        queue.finish(commandID: first.commandID, acknowledged: false)
        let nextAttempt6 = queue.beginNext()
        #expect(nextAttempt6 == nil)
        queue.authorizedForegroundReturned()
        let retryAttempt = queue.beginNext()
        let retry = try #require(retryAttempt)
        queue.finish(commandID: retry.commandID, acknowledged: true)
        let secondAttempt = queue.beginNext()
        let second = try #require(secondAttempt)
        #expect(second.sessionID == new)
        queue.finish(commandID: second.commandID, acknowledged: true)
        #expect(queue.isEmpty)
    }

    @Test func identicalQueuedUpdatesDeduplicateButReturningToAnOlderValueIsPreserved() throws {
        var queue = PendingReadingSessionQueue()
        let sessionID = UUID()
        let initial: [String: JSONValue] = ["activeSeconds": .number(90)]
        let updated: [String: JSONValue] = ["activeSeconds": .number(200)]
        queue.enqueue(sessionID: sessionID, payload: initial)
        let firstAttempt = queue.beginNext()
        let first = try #require(firstAttempt)
        queue.enqueue(sessionID: sessionID, payload: updated)
        queue.enqueue(sessionID: sessionID, payload: updated) // Exact duplicate adds no command.
        queue.enqueue(sessionID: sessionID, payload: initial) // A later correction still needs its own command.
        queue.finish(commandID: first.commandID, acknowledged: true)
        let secondAttempt = queue.beginNext()
        let second = try #require(secondAttempt)
        #expect(second.payload == updated)
        queue.finish(commandID: second.commandID, acknowledged: true)
        let correctionAttempt = queue.beginNext()
        let correction = try #require(correctionAttempt)
        #expect(correction.payload == initial && correction.commandID != first.commandID)
        queue.finish(commandID: correction.commandID, acknowledged: true)
        #expect(queue.isEmpty)
    }
}
