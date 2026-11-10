import Foundation
import SwiftData
import Testing
import MadarCore
import MadarData
@testable import MadarPrayer

@Suite(.serialized) @MainActor struct PrayerTests {
    private func time(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)!
    }
    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    private func ref(_ day: String = "2026-10-07", _ prayer: Prayer = .fajr) throws -> PrayerReference { try .init(day: GregorianDay(day), prayer: prayer) }
    private func container(start: String = "2026-10-07T09:00:00+03:00") throws -> ModelContainer {
        let container = try MadarContainerFactory.makeInMemory()
        _ = try PrayerMutationHandler.stage(operation: .initializeTracking, in: container.mainContext, now: time(start), writer: "test-device")
        try container.mainContext.save(); return container
    }
    @discardableResult private func apply(_ command: PrayerMutation, _ context: ModelContext, at: String = "2026-10-07T12:00:00+03:00") throws -> Data? {
        let inverse = try PrayerMutationHandler.stage(operation: command, in: context, now: time(at), writer: "test-device"); try context.save(); return inverse
    }
    @Test func snapshotValidityHoldsUntilThePrayerClockChangesSomething() throws {
        let container = try container(start: "2026-10-07T04:00:00+03:00")
        let repository = try PrayerRepository(context: container.mainContext)
        let now = time("2026-10-07T12:05:00+03:00")
        let state = try repository.snapshot(now: now)
        #expect(state.validUntil > now && state.validUntil <= now.addingTimeInterval(86_400))
        // Anywhere before validUntil the day shows the same statuses and the same next prayer, so no reload is needed.
        for fraction in [0.0, 0.25, 0.5, 0.99] {
            let later = now.addingTimeInterval(state.validUntil.timeIntervalSince(now) * fraction)
            let again = try repository.snapshot(now: later)
            #expect(again.today.cells.map(\.status) == state.today.cells.map(\.status))
            #expect(again.next == state.next)
        }
        // validUntil is the next prayer time or window end, so the snapshot really does change right after it.
        let after = try repository.snapshot(now: state.validUntil.addingTimeInterval(1))
        #expect(after.today.cells.map(\.status) != state.today.cells.map(\.status) || after.next != state.next || after.today.cells.map(\.canMakeUp) != state.today.cells.map(\.canMakeUp))
    }
    @Test func daysOlderThanThirtyTwoStayReachableThroughEarlier() throws {
        // Tracking began on 8 Aug, 61 days up to 7 Oct 2026; history holds the newest 32 and earlier the rest, in one unbroken run.
        let container = try container(start: "2026-08-08T04:00:00+03:00")
        let state = try PrayerRepository(context: container.mainContext).snapshot(now: time("2026-10-07T12:05:00+03:00"))
        #expect(state.history.count == 32)
        #expect(state.history.first?.day.description == "2026-10-07")
        #expect(state.earlier.count == 29)
        #expect(state.earlier.first?.day.description == "2026-09-05")
        #expect(state.earlier.last?.day.description == "2026-08-08")
    }
    @Test func aPerformedLatePrayerCreatesOneQadaLogAndUndoRemovesIt() throws {
        let container = try container(start: "2026-10-06T04:00:00+03:00")
        let context = container.mainContext
        let reference = try ref()
        let performedAt = time("2026-10-07T12:01:00+03:00")
        let inverse = try #require(try apply(.record(reference, status: .qada, heart: nil, shortened: nil), context, at: iso(performedAt)))
        let row = try #require(context.fetch(FetchDescriptor<PrayerLog>()).first { $0.deletedAt == nil })
        #expect(row.status == "qada" && row.eventAt == performedAt && row.loggedAt == performedAt)
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
        #expect(try apply(.record(reference, status: .qada, heart: nil, shortened: nil), context, at: "2026-10-07T12:02:00+03:00") == nil)
        try PrayerMutationHandler.undo(inverse, in: context, now: time("2026-10-07T12:03:00+03:00"), writer: "test-device")
        try context.save()
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).allSatisfy { $0.deletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
    }
    @Test func retiredBacklogMutationsCannotCreatePrayerOrDebtRows() throws {
        let container = try container(start: "2026-10-07T04:00:00+03:00")
        let context = container.mainContext
        let reference = try ref("2026-10-06", .dhuhr)
        let resolutions = [PrayerGapResolution(reference: try ref(), status: .jamaah)]
        for mutation in [
            PrayerMutation.addOldMissed(reference),
            .addOldMissedRun(prayer: .fajr, count: 7, lastDay: try GregorianDay("2026-10-06")),
            .makeUpOldest(prayer: .fajr, count: 1),
            .markUnrecorded([try ref()]),
            .resolveGap(resolutions)
        ] {
            #expect(throws: PrayerDomainError.invalidRecord) { try apply(mutation, context) }
            context.rollback()
        }
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
    }
    @Test func performedQadaWaitsForEachPrayerWindowEndAndUnperformedStatusIsRejected() throws {
        let day = try GregorianDay("2026-10-07")
        let place = try ActivePlace(latitude: 24.7136, longitude: 46.6753, timeZoneID: "Asia/Riyadh")
        let dayTimes = try #require(PrayerTimesEngine.calculate(day: day, place: place))
        let nextTimes = try #require(PrayerTimesEngine.calculate(day: day.adding(days: 1), place: place))
        let expectedEnds: [Prayer: Date] = [.fajr: dayTimes.sunrise, .dhuhr: dayTimes.asr, .asr: dayTimes.maghrib, .maghrib: dayTimes.isha, .isha: nextTimes.fajr]
        let baseline = try container(start: "2026-10-06T04:00:00+03:00")
        let repository = try PrayerRepository(context: baseline.mainContext)

        for prayer in Prayer.allCases {
            let reference = try ref(day.description, prayer)
            let windowEnd = try #require(expectedEnds[prayer])
            #expect(repository.missedWindowEnd(reference) == windowEnd)
            let testContainer = try container(start: "2026-10-06T04:00:00+03:00")
            let context = testContainer.mainContext
            #expect(throws: PrayerDomainError.prayerWindowOpen) {
                try apply(.record(reference, status: .qada, heart: nil, shortened: nil), context, at: iso(windowEnd.addingTimeInterval(-1)))
            }
            context.rollback()
            #expect(try context.fetch(FetchDescriptor<PrayerLog>()).isEmpty)
            #expect(throws: PrayerDomainError.invalidRecord) {
                try apply(.record(reference, status: .missed, heart: nil, shortened: nil), context, at: iso(windowEnd))
            }
            context.rollback()
            try apply(.record(reference, status: .qada, heart: nil, shortened: nil), context, at: iso(windowEnd))
            let row = try #require(context.fetch(FetchDescriptor<PrayerLog>()).first { $0.deletedAt == nil })
            #expect(row.status == "qada" && row.eventAt == windowEnd)
            #expect(try context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
        }
    }
    @Test func qadaCorrectionDoesNotCreateOrRetainBacklogDebt() throws {
        let container = try container()
        let context = container.mainContext
        let reference = try ref()
        try apply(.record(reference, status: .qada, heart: .present, shortened: nil), context)
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).first?.heart == "present")
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
        try apply(.record(reference, status: .jamaah, heart: nil, shortened: false), context, at: "2026-10-07T12:04:00+03:00")
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).first?.status == "jamaah")
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
        #expect(try PrayerRepository(context: context).snapshot(now: time("2026-10-07T12:05:00+03:00")).statistics.owed == 0)
    }
    @Test func inverseRejectsStaleChangeWithoutOverwritingLaterHeart() throws {
        let container = try container(); let context = container.mainContext; let reference = try ref()
        let inverse = try #require(try apply(.record(reference, status: .jamaah, heart: nil, shortened: nil), context))
        try apply(.answerHeart(reference, .khashi), context, at: "2026-10-07T12:01:00+03:00")
        #expect(throws: PrayerDomainError.staleUndo) { try PrayerMutationHandler.undo(inverse, in: context, now: time("2026-10-07T12:02:00+03:00"), writer: "test-device") }
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).first?.heart == "khashi")
    }
    @Test func futureQadaAndInvalidShorteningAreRejected() throws {
        let container = try container(start: "2026-10-07T12:00:00+03:00")
        let context = container.mainContext
        #expect(throws: PrayerDomainError.futurePrayer) { try apply(.record(ref("2026-10-07", .isha), status: .qada, heart: nil, shortened: nil), context) }
        context.rollback()
        #expect(throws: PrayerDomainError.beforeTrackingStart) { try apply(.record(ref("2026-10-06"), status: .qada, heart: nil, shortened: nil), context) }
        context.rollback()
        #expect(throws: PrayerDomainError.invalidShortening) { try apply(.record(ref(), status: .jamaah, heart: nil, shortened: true), context) }
        context.rollback()
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).isEmpty && context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
    }
    @Test func fridayLatePrayerKeepsKindWithoutCreatingBacklog() throws {
        let container = try container(start: "2026-10-09T09:00:00+03:00")
        let context = container.mainContext
        let fridayDhuhr = try ref("2026-10-09", .dhuhr)
        #expect(throws: PrayerDomainError.invalidRecord) {
            try apply(.record(fridayDhuhr, status: .jamaah, heart: nil, shortened: nil), context, at: "2026-10-09T18:00:00+03:00")
        }
        context.rollback()
        try apply(.record(fridayDhuhr, status: .qada, heart: nil, shortened: nil, fridayKind: .jumuah), context, at: "2026-10-09T19:00:00+03:00")
        let madeUp = try #require(context.fetch(FetchDescriptor<PrayerLog>()).first { $0.deletedAt == nil })
        #expect(madeUp.status == "qada" && madeUp.fridayKind == "jumuah")
        #expect(madeUp.eventAt == time("2026-10-09T19:00:00+03:00"))
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
    }
    @Test func correctingFridayQadaKindPreservesItsPerformanceTime() throws {
        let container = try container(start: "2026-10-08T04:00:00+03:00")
        let context = container.mainContext
        let reference = try ref("2026-10-09", .dhuhr)
        let performedAt = time("2026-10-09T19:00:00+03:00")
        try apply(.record(reference, status: .qada, heart: nil, shortened: nil, fridayKind: .jumuah), context, at: iso(performedAt))
        let row = try #require(context.fetch(FetchDescriptor<PrayerLog>()).first { $0.deletedAt == nil })
        let loggedAt = row.loggedAt

        try apply(.record(reference, status: .qada, heart: nil, shortened: nil, fridayKind: .dhuhr), context, at: "2026-10-09T20:00:00+03:00")

        #expect(row.fridayKind == "dhuhr")
        #expect(row.eventAt == performedAt)
        #expect(row.loggedAt == loggedAt)
        #expect(row.updatedAt == time("2026-10-09T20:00:00+03:00"))
    }
    @Test func unperformedHistoryCommandWritesNothing() throws {
        let container = try container(start: "2026-10-09T16:00:00+03:00")
        let context = container.mainContext
        let fridayDhuhr = try ref("2026-10-09", .dhuhr)
        #expect(throws: PrayerDomainError.invalidRecord) { try apply(.markUnrecorded([fridayDhuhr]), context, at: "2026-10-09T16:01:00+03:00") }
        context.rollback()
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
        let state = try PrayerRepository(context: context).snapshot(now: time("2026-10-09T16:02:00+03:00"))
        #expect(state.statistics.owed == 0 && state.statistics.denominator == 0)
    }
    @Test func legacyMissedStatusIsInvisibleAndCannotBeReclassifiedAsNewQada() throws {
        let container = try container(start: "2026-10-10T12:00:00+03:00")
        let context = container.mainContext
        let legacyDay = try GregorianDay("2026-10-02")
        let legacyLog = PrayerLog(); legacyLog.dayKey = legacyDay.description; legacyLog.prayer = Prayer.dhuhr.rawValue
        legacyLog.status = "missed"; legacyLog.eventAt = time("2026-10-02T12:00:00+03:00"); legacyLog.tzID = "Asia/Riyadh"
        let legacyDebt = QadaItem(); legacyDebt.originalDayKey = legacyDay.description; legacyDebt.prayer = Prayer.dhuhr.rawValue
        context.insert(legacyLog); context.insert(legacyDebt); try context.save()
        #expect(throws: PrayerDomainError.beforeTrackingStart) {
            try apply(.makeUp(PrayerReference(day: legacyDay, prayer: .dhuhr), fridayKind: .dhuhr), context, at: "2026-10-10T12:04:00+03:00")
        }
        context.rollback()
        let state = try PrayerRepository(context: context).snapshot(now: time("2026-10-10T12:05:00+03:00"))
        #expect(state.qada.isEmpty && state.statistics.owed == 0)
        #expect(!state.history.flatMap(\.cells).contains { $0.reference.day == legacyDay && $0.status == .missed })
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).count == 1)
    }
    @Test func test_RP1_unloggedNeverBecomesQada() throws {
        let container = try container(); let context = container.mainContext
        // §7.2's former seven-prayer-day deadline, overridden by RP1.
        let deadline = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-14"), place: .riyadh)?.fajr)
        let returnAfterThreeWeeks = try #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-28"), place: .riyadh)?.fajr)
        for now in [deadline.addingTimeInterval(-1), deadline, deadline.addingTimeInterval(1), returnAfterThreeWeeks] {
            for writer in ["test-device", "repeated-command"] {
                let inverse = try PrayerMutationHandler.stage(operation: .agePending, in: context, now: now, writer: writer, source: .system)
                try context.save()
                #expect(inverse == nil)
            }
            for _ in 0..<2 {
                let state = try PrayerRepository(context: context).snapshot(now: now)
                if now < deadline {
                    #expect(state.pending.contains(try ref()))
                    #expect(!state.unconfirmed.contains(try ref()))
                } else {
                    #expect(!state.pending.contains(try ref()))
                    #expect(state.unconfirmed.contains(try ref()))
                }
                #expect(state.statistics.denominator == 0 && state.statistics.percentage == nil)
                #expect(state.statistics.owed == 0 && state.statistics.madeUp == 0 && state.qada.isEmpty)
                #expect(!state.history.flatMap(\.cells).contains { [.missed, .qada].contains($0.status) })
            }
            #expect(try context.fetch(FetchDescriptor<PrayerLog>()).isEmpty)
            #expect(try context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
        }
    }
    @Test func bulkGapResolutionIsRejectedWithoutWritingAnyPrayer() throws {
        let container = try container(start: "2026-10-13T04:00:00+03:00")
        let context = container.mainContext
        let resolutions = [PrayerGapResolution(reference: try ref("2026-10-13"), status: .jamaah)]
        #expect(throws: PrayerDomainError.invalidRecord) { try apply(.resolveGap(resolutions), context, at: "2026-10-20T09:00:00+03:00") }
        context.rollback()
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
        let state = try PrayerRepository(context: context).snapshot(now: time("2026-10-20T09:03:00+03:00"))
        #expect(state.statistics.owed == 0 && state.statistics.denominator == 0 && state.qada.isEmpty)
    }
    @Test func movedTrackingRemainsUnloggedAndSecondEditFails() throws {
        let container = try container(start: "2026-10-09T12:00:00+03:00"); let context = container.mainContext
        try apply(.editTrackingStart(GregorianDay("2026-10-07")), context, at: "2026-10-10T12:00:00+03:00")
        #expect(throws: PrayerDomainError.trackingAlreadyEdited) { try apply(.editTrackingStart(GregorianDay("2026-10-06")), context, at: "2026-10-10T12:01:00+03:00") }
        context.rollback()
        for day in ["2026-10-14", "2026-10-17"] {
            let deadline = try #require(PrayerTimesEngine.calculate(day: GregorianDay(day), place: .riyadh)?.fajr)
            #expect(try PrayerMutationHandler.stage(operation: .agePending, in: context, now: deadline, writer: "test-device") == nil)
            try context.save()
            let state = try PrayerRepository(context: context).snapshot(now: deadline)
            #expect(state.tracking.day.description == "2026-10-07" && state.tracking.edits == 1)
            #expect(state.unconfirmed.contains(try ref()))
            #expect(state.statistics.denominator == 0 && state.qada.isEmpty)
        }
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
    }
    @Test func explicitUnrecordedPeriodIsRejectedAndLeavesBothPrayersUnlogged() throws {
        let container = try container()
        let context = container.mainContext
        let references = try [ref(), ref("2026-10-07", .dhuhr)]
        #expect(throws: PrayerDomainError.invalidRecord) { try apply(.markUnrecorded(references), context) }
        context.rollback()
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
        let state = try PrayerRepository(context: context).snapshot(now: time("2026-10-07T12:07:00+03:00"))
        #expect(state.statistics.denominator == 0 && state.statistics.percentage == nil && state.qada.isEmpty)
        #expect(state.pending.count == 2)
    }
    @Test func qiyamRakaatContractRejects100WithoutWriting() throws {
        let container = try container(); let context = container.mainContext
        #expect(throws: PrayerDomainError.invalidRakaat) {
            try apply(.logQiyam(night: GregorianDay("2026-10-07"), rakaat: 100, witr: false), context, at: "2026-10-07T23:30:00+03:00")
        }
        #expect(try context.fetchCount(FetchDescriptor<QiyamNight>()) == 0)
        try apply(.logQiyam(night: GregorianDay("2026-10-07"), rakaat: 99, witr: false), context, at: "2026-10-07T23:30:00+03:00")
        #expect(try context.fetch(FetchDescriptor<QiyamNight>()).first?.rakaat == 99)
    }
    @Test func qiyamMidnightBelongsToOneNightAndNeverWritesQuranPages() throws {
        let container = try container(); let context = container.mainContext
        let repository = try PrayerRepository(context: context)
        #expect(repository.defaultNight(at: time("2026-10-07T23:30:00+03:00")).description == "2026-10-07")
        #expect(repository.defaultNight(at: time("2026-10-08T02:10:00+03:00")).description == "2026-10-07")
        #expect(repository.defaultNight(at: time("2026-10-08T08:00:00+03:00")).description == "2026-10-07")
        try apply(.logQiyam(night: GregorianDay("2026-10-07"), rakaat: 8, witr: true), context, at: "2026-10-07T23:30:00+03:00")
        #expect(try apply(.logQiyam(night: GregorianDay("2026-10-07"), rakaat: 8, witr: true), context, at: "2026-10-08T02:10:00+03:00") == nil)
        #expect(try context.fetch(FetchDescriptor<QiyamNight>()).count == 1 && context.fetch(FetchDescriptor<HifzSession>()).isEmpty)
        #expect(throws: PrayerDomainError.invalidNight) { try apply(.logQiyam(night: GregorianDay("2026-10-08"), rakaat: 2, witr: false), context, at: "2026-10-08T12:00:00+03:00") }
    }
    @Test func taqdimPairHasExactlyTwoRowsAndUndoRemovesBoth() throws {
        let container = try container(); let context = container.mainContext
        try apply(.startTrip(city: "الرياض", country: "SA", place: .riyadh, homeKm: 350), context, at: "2026-10-07T10:00:00+03:00")
        let inverse = try #require(try apply(.logPair(day: GregorianDay("2026-10-07"), pair: .dhuhrAsr, status: .jamaah, shortened: true, mode: .taqdim), context))
        let logs = try context.fetch(FetchDescriptor<PrayerLog>())
        #expect(logs.count == 2 && Set(logs.compactMap(\.pairID)).count == 1 && logs.allSatisfy { $0.shortened == true && $0.tripID != nil })
        try PrayerMutationHandler.undo(inverse, in: context, now: time("2026-10-07T12:01:00+03:00"), writer: "test-device"); try context.save()
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.deletedAt == nil }.isEmpty)
    }
    /// OR-09: Istanbul → Cairo is one journey: the open leg closes at the move, the next leg points to the first. The next test undoes one move.
    @Test func continueTripJoinsLegsOfOneJourney() throws {
        let container = try container(); let context = container.mainContext
        let istanbul = try ActivePlace(latitude: 41.0082, longitude: 28.9784, timeZoneID: "Europe/Istanbul")
        let cairo = try ActivePlace(latitude: 30.0444, longitude: 31.2357, timeZoneID: "Africa/Cairo")
        let amman = try ActivePlace(latitude: 31.9539, longitude: 35.9106, timeZoneID: "Asia/Amman")
        #expect(throws: PrayerDomainError.noActiveTrip) { try apply(.continueTrip(city: "القاهرة", country: "EG", place: cairo, homeKm: nil), context, at: "2026-10-07T09:00:00+03:00") }
        try apply(.startTrip(city: "إسطنبول", country: "TR", place: istanbul, homeKm: 2_100), context, at: "2026-10-07T10:00:00+03:00")
        let first = try #require(context.fetch(FetchDescriptor<Trip>()).first)
        #expect(throws: PrayerDomainError.invalidRecord) { try apply(.continueTrip(city: "إسطنبول", country: "TR", place: istanbul, homeKm: nil), context, at: "2026-10-08T10:00:00+03:00") }
        try apply(.continueTrip(city: "القاهرة", country: "EG", place: cairo, homeKm: nil), context, at: "2026-10-09T10:00:00+03:00")
        try apply(.continueTrip(city: "عمّان", country: "JO", place: amman, homeKm: 1_300), context, at: "2026-10-11T10:00:00+03:00")
        let legs = try context.fetch(FetchDescriptor<Trip>()).sorted { $0.start! < $1.start! }
        #expect(legs.map(\.country) == ["TR", "EG", "JO"])
        #expect(legs[0].journeyID == nil && legs[1].journeyID == first.id && legs[2].journeyID == first.id)
        #expect(legs[0].end == time("2026-10-09T10:00:00+03:00") && legs[1].end == time("2026-10-11T10:00:00+03:00") && legs[2].end == nil)
        #expect(legs[1].homeKm == 2_100 && legs[2].homeKm == 1_300)
        #expect(try PrayerRepository(context: context).activeTrip(at: time("2026-10-11T12:00:00+03:00"))?.city == "عمّان")
        #expect(try PrayerRepository(context: context).activeTrip(at: time("2026-10-10T12:00:00+03:00"))?.city == "القاهرة")
    }
    @Test func undoOfContinueTripReopensTheFirstLeg() throws {
        let container = try container(); let context = container.mainContext
        let istanbul = try ActivePlace(latitude: 41.0082, longitude: 28.9784, timeZoneID: "Europe/Istanbul")
        let cairo = try ActivePlace(latitude: 30.0444, longitude: 31.2357, timeZoneID: "Africa/Cairo")
        try apply(.startTrip(city: "إسطنبول", country: "TR", place: istanbul, homeKm: 2_100), context, at: "2026-10-07T10:00:00+03:00")
        let inverse = try #require(try apply(.continueTrip(city: "القاهرة", country: "EG", place: cairo, homeKm: nil), context, at: "2026-10-09T10:00:00+03:00"))
        try PrayerMutationHandler.undo(inverse, in: context, now: time("2026-10-09T10:05:00+03:00"), writer: "test-device"); try context.save()
        let live = try context.fetch(FetchDescriptor<Trip>()).filter { $0.deletedAt == nil }
        #expect(live.count == 1 && live.first?.country == "TR" && live.first?.end == nil)
        #expect(try PrayerRepository(context: context).activeTrip(at: time("2026-10-09T12:00:00+03:00"))?.city == "إسطنبول")
    }
    @Test func continueTripUndoIsRefusedOnceMoneyPointsToTheNewLeg() throws {
        let container = try container(); let context = container.mainContext
        let istanbul = try ActivePlace(latitude: 41.0082, longitude: 28.9784, timeZoneID: "Europe/Istanbul")
        let cairo = try ActivePlace(latitude: 30.0444, longitude: 31.2357, timeZoneID: "Africa/Cairo")
        try apply(.startTrip(city: "إسطنبول", country: "TR", place: istanbul, homeKm: 2_100), context, at: "2026-10-07T10:00:00+03:00")
        let inverse = try #require(try apply(.continueTrip(city: "القاهرة", country: "EG", place: cairo, homeKm: nil), context, at: "2026-10-09T10:00:00+03:00"))
        let leg = try #require(context.fetch(FetchDescriptor<Trip>()).first { $0.country == "EG" })
        let tx = MoneyTransaction(); tx.tripID = leg.id; context.insert(tx); try context.save()
        #expect(throws: PrayerDomainError.staleUndo) { try PrayerMutationHandler.undo(inverse, in: context, now: time("2026-10-09T10:05:00+03:00"), writer: "test-device") }
        #expect(try context.fetch(FetchDescriptor<Trip>()).filter { $0.deletedAt == nil }.count == 2)
    }
    @Test func editingOnePairedPrayerUnlinksBothAndEndTripPreservesOldClock() throws {
        let container = try container(); let context = container.mainContext
        let jeddah = try ActivePlace(latitude: 21.4858, longitude: 39.1925, timeZoneID: "Asia/Riyadh")
        try apply(.startTrip(city: "جدة", country: "SA", place: jeddah, homeKm: 900), context, at: "2026-10-07T10:00:00+03:00")
        try apply(.logPair(day: GregorianDay("2026-10-07"), pair: .dhuhrAsr, status: .jamaah, shortened: true, mode: .taqdim), context, at: "2026-10-07T12:30:00+03:00")
        let trip = try #require(context.fetch(FetchDescriptor<Trip>()).first)
        try apply(.endTrip(trip.id), context, at: "2026-10-07T13:00:00+03:00")
        let occurrence = try #require(PrayerRepository(context: context).occurrence(ref("2026-10-07", .asr)))
        #expect(occurrence.time == time("2026-10-07T15:03:00+03:00"))
        try apply(.record(ref("2026-10-07", .asr), status: .alone, heart: .present, shortened: false), context, at: "2026-10-07T16:00:00+03:00")
        let logs = try context.fetch(FetchDescriptor<PrayerLog>())
        #expect(logs.allSatisfy { $0.pairID == nil })
        let dhuhr = try #require(logs.first { $0.prayer == "dhuhr" })
        #expect(dhuhr.status == "jamaah" && dhuhr.eventAt == time("2026-10-07T12:11:00+03:00"))
    }
    @Test func activeTripMethodControlsPrayerDayAtTheFajrBoundary() throws {
        let container = try container(start: "2026-03-19T12:00:00+00:00")
        let context = container.mainContext
        let settings = try SettingsStore(context: context)
        try settings.prepare(.string("mwl"), for: "salah.method", now: time("2026-03-19T12:00:00+00:00"))
        try settings.prepare(.string("egyptian"), for: "salah.tripMethod", now: time("2026-03-19T12:00:00+00:00"))
        try settings.prepare(.string("twilightAngle"), for: "salah.highLatitudeRule", now: time("2026-03-19T12:00:00+00:00"))
        let trip = Trip()
        trip.city = "لندن"; trip.lat = 51.5074; trip.lon = -0.1278; trip.tzID = "Europe/London"
        trip.mode = "manual"; trip.start = time("2026-03-20T04:00:00+00:00")
        context.insert(trip); try context.save()

        let repository = try PrayerRepository(context: context)
        let beforeTrip = time("2026-03-20T03:59:00+00:00")
        let nearFajr = time("2026-03-20T04:08:00+00:00")
        let expectedPrayerDay = try GregorianDay("2026-03-20")
        #expect(repository.calculationOptions(at: beforeTrip).method == .mwl)
        #expect(repository.calculationOptions(at: nearFajr).method == .egyptian)
        // Independent MWL fixture in CoreTests pins London Fajr to 04:10 ±3 min; Egypt's 19.5° Fajr is earlier.
        #expect(repository.prayerDay(at: nearFajr) == expectedPrayerDay)
    }
    @Test func aTripStartingAfterHomeDhuhrUsesTheLaterDestinationDhuhr() throws {
        let container = try container(start: "2026-03-28T08:00:00+00:00")
        let context = container.mainContext
        let trip = Trip()
        trip.city = "لندن"; trip.lat = 51.5074; trip.lon = -0.1278; trip.tzID = "Europe/London"
        trip.mode = "manual"; trip.start = time("2026-03-28T09:30:00+00:00"); trip.end = time("2026-03-28T13:00:00+00:00")
        context.insert(trip); try context.save()

        let repository = try PrayerRepository(context: context)
        let occurrence = try #require(repository.occurrence(ref("2026-03-28", .dhuhr)))
        // §9 reference table: London, 28 March 2026, Dhuhr 12:06 (GMT).
        #expect(occurrence.time == time("2026-03-28T12:06:00+00:00"))
        #expect(occurrence.place.timeZoneID == "Europe/London" && occurrence.tripID == trip.id)
    }
    @Test func monthRatioUsesPerformedPrayersAndQadaDoesNotRepairOnTimeStreak() throws {
        // The approved sample has 26 on-time, 2 performed late, and 2 unperformed prayers; only the 28 performed prayers enter the denominator.
        let container = try container(start: "2026-10-01T12:00:00+03:00")
        let context = container.mainContext
        var index = 0
        for day in 1...6 { for prayer in Prayer.allCases {
            if index < 28 {
                let row = PrayerLog()
                row.dayKey = String(format: "2026-10-%02d", day)
                row.prayer = prayer.rawValue
                row.status = index < 26 ? "jamaah" : "qada"
                row.eventAt = index < 26 ? time("2026-10-01T05:00:00+03:00") : time("2026-10-06T20:00:00+03:00")
                row.tzID = "Asia/Riyadh"
                context.insert(row)
            }
            index += 1
        } }
        try context.save()
        let state = try PrayerRepository(context: context).snapshot(now: time("2026-10-07T20:00:00+03:00"))
        #expect(state.statistics.onTime == 26 && state.statistics.denominator == 28 && state.statistics.percentage == 93)
        #expect(state.statistics.madeUp == 2 && state.statistics.owed == 0 && state.statistics.prayerStreak == 0)
        #expect(state.statistics.completionStreak == 5, "The five fully performed days remain complete; the partial latest day stays open.")
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
    }
    @Test func completionStreakCountsLatePerformedPrayerAsCompleted() throws {
        let container = try container(start: "2026-10-01T12:00:00+03:00")
        let context = container.mainContext
        for day in ["2026-10-05", "2026-10-06"] {
            for (index, prayer) in Prayer.allCases.enumerated() {
                let row = PrayerLog()
                row.dayKey = day
                row.prayer = prayer.rawValue
                row.status = day == "2026-10-06" && index == 0 ? "qada" : "jamaah"
                row.eventAt = time(day == "2026-10-06" && index == 0 ? "2026-10-06T06:30:00+03:00" : "\(day)T05:00:00+03:00")
                row.tzID = "Asia/Riyadh"
                context.insert(row)
            }
        }
        try context.save()
        let stats = try PrayerRepository(context: context).snapshot(now: time("2026-10-07T20:00:00+03:00")).statistics
        #expect(stats.completionStreak == 2)
        #expect(stats.prayerStreak == 0, "A late performed prayer does not repair the on-time streak.")
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
    }
    @Test func polarManualLogHasNoFabricatedAdhanOrDerivedPending() throws {
        let container = try container(start: "2026-06-21T12:00:00+02:00"); let context = container.mainContext
        let settings = try SettingsStore(context: context)
        try settings.prepare(.object(["name": .string("Tromso"), "country": .string("NO"), "lat": .number(69.6492), "lon": .number(18.9553), "tz": .string("Europe/Oslo"), "currency": .string("NOK")]), for: "core.homeCity", now: time("2026-06-21T12:00:00+02:00"))
        try context.save()
        try apply(.record(ref("2026-06-21"), status: .alone, heart: nil, shortened: nil), context, at: "2026-06-21T14:00:00+02:00")
        let state = try PrayerRepository(context: context).snapshot(now: time("2026-06-21T14:00:00+02:00"))
        #expect(!state.hasTimes && state.next == nil && state.pending.isEmpty && state.today.cells.allSatisfy { $0.time == nil })
    }
    @Test func polarHomeUsesValidTripTimesAndKeepsFuturePrayerLocked() throws {
        let container = try container(start: "2026-06-21T06:00:00+03:00"); let context = container.mainContext
        let settings = try SettingsStore(context: context)
        try settings.prepare(.object(["name": .string("Tromso"), "country": .string("NO"), "lat": .number(69.6492), "lon": .number(18.9553), "tz": .string("Europe/Oslo"), "currency": .string("NOK")]), for: "core.homeCity", now: time("2026-06-21T06:00:00+03:00"))
        try context.save()
        let riyadh = try ActivePlace(latitude: 24.7136, longitude: 46.6753, timeZoneID: "Asia/Riyadh")
        try apply(.startTrip(city: "الرياض", country: "SA", place: riyadh, homeKm: 350), context, at: "2026-06-21T08:00:00+03:00")

        let repository = try PrayerRepository(context: context)
        let occurrence = try #require(repository.occurrence(ref("2026-06-21", .dhuhr)))
        let tripID = try #require(context.fetch(FetchDescriptor<Trip>()).first?.id)
        #expect(occurrence.tripID == tripID && occurrence.place.timeZoneID == "Asia/Riyadh")

        let state = try repository.snapshot(now: time("2026-06-21T10:00:00+03:00"))
        let dhuhr = try #require(state.today.cells.first { $0.reference.prayer == .dhuhr })
        #expect(state.hasTimes && dhuhr.time != nil && dhuhr.status == .future && !dhuhr.canLog)
    }
}

@Suite struct TravelRuleTests {
    // Riyadh 24.7136, 46.6753. Reference distances are great-circle values (haversine, R = 6371 km) computed by hand from the coordinates.
    private func place(_ lat: Double, _ lon: Double) throws -> ActivePlace { try ActivePlace(latitude: lat, longitude: lon, timeZoneID: "Asia/Riyadh") }
    @Test func eightyKilometresBeyondTheCityEdge() throws {
        let riyadh = try place(24.7136, 46.6753)
        // One degree of latitude is 111.19 km: 0.9 deg = 100 km (inside 25 + 80), 1.0 deg = 111 km (outside).
        #expect(!TravelRule.isAway(home: riyadh, current: try place(24.7136 + 0.9, 46.6753), thresholdKm: 80))
        #expect(TravelRule.isAway(home: riyadh, current: try place(24.7136 + 1.0, 46.6753), thresholdKm: 80))
        // Jeddah is about 845 km away; the old 300 km default is not what decides it any more.
        #expect(TravelRule.isAway(home: riyadh, current: try place(21.4858, 39.1925), thresholdKm: 80))
        #expect(!TravelRule.isAway(home: riyadh, current: riyadh, thresholdKm: 80))
    }
    @Test func localMethodSuggestion() {
        #expect(TravelRule.suggestedMethod(country: "TR") == .turkey)
        #expect(TravelRule.suggestedMethod(country: "GB") == .mwl)
        #expect(TravelRule.suggestedMethod(country: "us") == .isna)
        #expect(TravelRule.suggestedMethod(country: "SA") == .ummAlQura)
    }
}


@Suite(.serialized) @MainActor struct PrayerReadFailureTests {
    private enum ReadFailure: Error { case unavailable }
    private let now = ISO8601DateFormatter().date(from: "2026-10-07T12:00:00+03:00")!

    @Test func placeAndTimesDoNotReadHistory() throws {
        let container = try MadarContainerFactory.makeInMemory()
        var reads = 0
        let repository = try PrayerRepository(context: container.mainContext,
            readLogs: { _ in reads += 1; throw ReadFailure.unavailable },
            readNights: { _ in reads += 1; throw ReadFailure.unavailable })
        _ = repository.place(at: now)
        _ = repository.prayerDay(at: now)
        #expect(repository.occurrence(.init(day: try GregorianDay("2026-10-07"), prayer: .fajr)) != nil)
        #expect(reads == 0)
    }

    @Test func failedDayReadThrowsAndRetryKeepsRecordedPrayer() throws {
        let container = try MadarContainerFactory.makeInMemory()
        let row = PrayerLog(); row.dayKey = "2026-10-07"; row.prayer = "fajr"; row.status = "alone"
        var attempts = 0, nightReads = 0
        let repository = try PrayerRepository(context: container.mainContext,
            readLogs: { _ in attempts += 1; if attempts == 1 { throw ReadFailure.unavailable }; return [row] },
            readNights: { _ in nightReads += 1; return [] })
        let day = try GregorianDay("2026-10-07")
        #expect(throws: ReadFailure.self) { try repository.day(day, now: now) }
        let retry = try repository.day(day, now: now)
        #expect(retry.cells.first { $0.reference.prayer == .fajr }?.status == .alone)
        #expect(attempts == 2)
        #expect(nightReads == 0)
    }

    @Test func failedNightReadThrowsAndRetryRecognizesTombstone() throws {
        let container = try MadarContainerFactory.makeInMemory()
        let row = QiyamNight(); row.nightKey = "2026-10-06"; row.deletedAt = now
        var attempts = 0, prayerReads = 0
        let repository = try PrayerRepository(context: container.mainContext,
            readLogs: { _ in prayerReads += 1; return [] },
            readNights: { _ in attempts += 1; if attempts == 1 { throw ReadFailure.unavailable }; return [row] })
        let night = try GregorianDay("2026-10-06")
        #expect(throws: ReadFailure.self) { try repository.nightRequiresRestore(night) }
        #expect(try repository.nightRequiresRestore(night))
        #expect(attempts == 2)
        #expect(prayerReads == 0)
    }

    @Test func failedDirectReadDoesNotPoisonSnapshot() throws {
        let container = try MadarContainerFactory.makeInMemory()
        let row = PrayerLog(); row.dayKey = "2026-10-07"; row.prayer = "fajr"; row.status = "jamaah"
        var attempts = 0
        let repository = try PrayerRepository(context: container.mainContext,
            readLogs: { _ in attempts += 1; if attempts == 1 { throw ReadFailure.unavailable }; return [row] },
            readNights: { _ in [] })
        let day = try GregorianDay("2026-10-07")
        #expect(throws: ReadFailure.self) { try repository.day(day, now: now) }
        let snapshot = try repository.snapshot(now: now)
        #expect(snapshot.today.cells.first { $0.reference.prayer == .fajr }?.status == .jamaah)
        #expect(attempts == 2)
    }
}
