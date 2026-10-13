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
    @Test func makeUpUsesOneNaturalPairOfRowsAndUndoRestoresBoth() throws {
        let container = try container(); let context = container.mainContext; let reference = try ref()
        try apply(.record(reference, status: .missed, heart: nil, shortened: nil), context)
        let inverse = try #require(try apply(.makeUp(reference), context, at: "2026-10-07T12:01:00+03:00"))
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.deletedAt == nil }.map(\.status) == ["qada"])
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).filter { $0.deletedAt == nil }.first?.madeUpAt == time("2026-10-07T12:01:00+03:00"))
        #expect(try apply(.makeUp(reference), context, at: "2026-10-07T12:02:00+03:00") == nil)
        try PrayerMutationHandler.undo(inverse, in: context, now: time("2026-10-07T12:03:00+03:00"), writer: "test-device"); try context.save()
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).first?.status == "missed")
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).first?.madeUpAt == nil)
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).count == 1 && context.fetch(FetchDescriptor<QadaItem>()).count == 1)
    }
    @Test func missedAndMakeUpWaitForEachPrayerWindowEnd() throws {
        let day = try GregorianDay("2026-10-07")
        let place = try ActivePlace(latitude: 24.7136, longitude: 46.6753, timeZoneID: "Asia/Riyadh")
        let dayTimes = try #require(PrayerTimesEngine.calculate(day: day, place: place))
        let nextTimes = try #require(PrayerTimesEngine.calculate(day: day.adding(days: 1), place: place))
        let expectedEnds: [Prayer: Date] = [
            .fajr: dayTimes.sunrise,
            .dhuhr: dayTimes.asr,
            .asr: dayTimes.maghrib,
            .maghrib: dayTimes.isha,
            .isha: nextTimes.fajr
        ]
        let baseline = try container(start: "2026-10-06T04:00:00+03:00")
        let repository = try PrayerRepository(context: baseline.mainContext)

        for prayer in Prayer.allCases {
            let reference = try ref(day.description, prayer)
            let windowEnd = try #require(expectedEnds[prayer])
            #expect(repository.missedWindowEnd(reference) == windowEnd)
            let testContainer = try container(start: "2026-10-06T04:00:00+03:00")
            let context = testContainer.mainContext

            #expect(throws: PrayerDomainError.prayerWindowOpen) {
                try apply(.record(reference, status: .missed, heart: nil, shortened: nil), context, at: iso(windowEnd.addingTimeInterval(-1)))
            }
            context.rollback()
            #expect(try context.fetch(FetchDescriptor<PrayerLog>()).isEmpty)

            try apply(.record(reference, status: .missed, heart: nil, shortened: nil), context, at: iso(windowEnd))
            #expect(throws: PrayerDomainError.prayerWindowOpen) {
                try apply(.makeUp(reference), context, at: iso(windowEnd.addingTimeInterval(-1)))
            }
            context.rollback()
            #expect(try context.fetch(FetchDescriptor<QadaItem>()).first?.madeUpAt == nil)

            try apply(.makeUp(reference), context, at: iso(windowEnd))
            #expect(try context.fetch(FetchDescriptor<PrayerLog>()).first?.status == "qada")
            #expect(try context.fetch(FetchDescriptor<QadaItem>()).first?.madeUpAt == windowEnd)
        }
    }
    @Test func qadaFromArcIsAtomicAndCorrectionTombstonesDebt() throws {
        let container = try container(); let context = container.mainContext; let reference = try ref()
        try apply(.record(reference, status: .qada, heart: .present, shortened: nil), context)
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).first?.heart == "present")
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).first?.madeUpAt != nil)
        try apply(.record(reference, status: .jamaah, heart: nil, shortened: false), context, at: "2026-10-07T12:04:00+03:00")
        let qada = try #require(context.fetch(FetchDescriptor<QadaItem>()).first)
        #expect(qada.deletedAt != nil && qada.deletionBarrierAt != nil)
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
        let container = try container(); let context = container.mainContext
        #expect(throws: PrayerDomainError.futurePrayer) { try apply(.makeUp(ref("2026-10-07", .isha)), context) }
        context.rollback()
        #expect(throws: PrayerDomainError.beforeTrackingStart) { try apply(.makeUp(ref("2026-10-06")), context) }
        context.rollback()
        #expect(throws: PrayerDomainError.invalidShortening) { try apply(.record(ref(), status: .jamaah, heart: nil, shortened: true), context) }
        context.rollback()
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).isEmpty && context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
    }
    @Test func fridayNoonRequiresKindAndMissedJumuahKeepsKindThroughQada() throws {
        let container = try container(start: "2026-10-09T09:00:00+03:00")
        let context = container.mainContext
        let fridayDhuhr = try ref("2026-10-09", .dhuhr)
        #expect(throws: PrayerDomainError.invalidRecord) {
            try apply(.record(fridayDhuhr, status: .jamaah, heart: nil, shortened: nil), context,
                at: "2026-10-09T18:00:00+03:00")
        }
        context.rollback()

        try apply(.record(fridayDhuhr, status: .missed, heart: nil, shortened: nil, fridayKind: .jumuah), context,
            at: "2026-10-09T18:00:00+03:00")
        let missed = try #require(context.fetch(FetchDescriptor<PrayerLog>()).first)
        #expect(missed.status == "missed" && missed.fridayKind == "jumuah")
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).first?.madeUpAt == nil)

        try apply(.record(fridayDhuhr, status: .qada, heart: nil, shortened: nil, fridayKind: .jumuah), context,
            at: "2026-10-09T19:00:00+03:00")
        let madeUp = try #require(context.fetch(FetchDescriptor<PrayerLog>()).first)
        #expect(madeUp.status == "qada" && madeUp.fridayKind == "jumuah")
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).first?.madeUpAt != nil)
    }
    @Test func fridayUnrecordedHistoryStaysUnclassifiedAndCreatesNoDebt() throws {
        let container = try container(start: "2026-10-09T16:00:00+03:00")
        let context = container.mainContext
        let fridayDhuhr = try ref("2026-10-09", .dhuhr)
        try apply(.markUnrecorded([fridayDhuhr]), context, at: "2026-10-09T16:01:00+03:00")

        let row = try #require(context.fetch(FetchDescriptor<PrayerLog>()).first)
        #expect(row.status == "unrecordedHistory" && row.fridayKind == nil)
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).isEmpty)
        let state = try PrayerRepository(context: context).snapshot(now: time("2026-10-09T16:02:00+03:00"))
        #expect(state.statistics.owed == 0 && state.statistics.denominator == 0)
    }
    @Test func oldFridayMissedAndUnclassifiedLegacyQadaRequireExplicitKind() throws {
        let container = try container(start: "2026-10-10T12:00:00+03:00")
        let context = container.mainContext
        let fridayDhuhr = try ref("2026-10-09", .dhuhr)
        #expect(throws: PrayerDomainError.invalidRecord) {
            try apply(.addOldMissed(fridayDhuhr), context, at: "2026-10-10T12:01:00+03:00")
        }
        context.rollback()
        try apply(.addOldMissed(fridayDhuhr, fridayKind: .jumuah), context, at: "2026-10-10T12:02:00+03:00")
        let missed = try #require(context.fetch(FetchDescriptor<PrayerLog>()).first)
        #expect(missed.status == "missed" && missed.fridayKind == "jumuah")

        let legacyDay = try GregorianDay("2026-10-02")
        let legacyLog = PrayerLog(); legacyLog.dayKey = legacyDay.description; legacyLog.prayer = Prayer.dhuhr.rawValue
        legacyLog.status = "missed"; legacyLog.eventAt = time("2026-10-02T12:00:00+03:00"); legacyLog.tzID = "Asia/Riyadh"
        let legacyDebt = QadaItem(); legacyDebt.originalDayKey = legacyDay.description; legacyDebt.prayer = Prayer.dhuhr.rawValue
        context.insert(legacyLog); context.insert(legacyDebt); try context.save()
        let legacyRef = PrayerReference(day: legacyDay, prayer: .dhuhr)
        #expect(throws: PrayerDomainError.invalidRecord) {
            try apply(.makeUp(legacyRef), context, at: "2026-10-10T12:03:00+03:00")
        }
        context.rollback()
        try apply(.makeUp(legacyRef, fridayKind: .dhuhr), context, at: "2026-10-10T12:04:00+03:00")
        let legacyUpdated = try #require(context.fetch(FetchDescriptor<PrayerLog>()).first { $0.dayKey == legacyDay.description })
        #expect(legacyUpdated.status == "qada" && legacyUpdated.fridayKind == "dhuhr")
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).first { $0.originalDayKey == legacyDay.description }?.madeUpAt != nil)
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
    @Test func bulkGapResolutionCreatesOnlyExplicitDebtAndCanUndoAsOneChange() throws {
        let container = try container(start: "2026-10-13T04:00:00+03:00"), context = container.mainContext
        let references = [try ref("2026-10-13"), try ref("2026-10-13", .dhuhr), try ref("2026-10-13", .asr)]
        let resolutions = [
            PrayerGapResolution(reference: references[0], status: .missed),
            PrayerGapResolution(reference: references[1], status: .unrecordedHistory),
            PrayerGapResolution(reference: references[2], status: .excused)
        ]
        let now = "2026-10-20T09:00:00+03:00"
        let inverse = try #require(try apply(.resolveGap(resolutions), context, at: now))
        #expect(try apply(.resolveGap(resolutions), context, at: "2026-10-20T09:01:00+03:00") == nil)
        let state = try PrayerRepository(context: context).snapshot(now: time(now))
        #expect(state.statistics.owed == 1)
        #expect(state.statistics.denominator == 1)
        #expect(state.statistics.onTime == 0)
        #expect(state.qada.count == 1 && state.qada.first?.reference == references[0])
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.deletedAt == nil }.map(\.status).sorted() == ["excused", "missed", "unrecordedHistory"])

        try PrayerMutationHandler.undo(inverse, in: context, now: time("2026-10-20T09:02:00+03:00"), writer: "test-device")
        try context.save()
        let restored = try PrayerRepository(context: context).snapshot(now: time("2026-10-20T09:03:00+03:00"))
        #expect(restored.statistics.owed == 0 && restored.statistics.denominator == 0)
        #expect(references.allSatisfy { restored.unconfirmed.contains($0) })
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).allSatisfy { $0.deletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<QadaItem>()).allSatisfy { $0.deletedAt != nil })
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
    @Test func explicitUnrecordedPeriodCreatesNoDebtOrPercentageAndCanUndo() throws {
        let container = try container(); let context = container.mainContext
        let references = try [ref(), ref("2026-10-07", .dhuhr)]
        let inverse = try #require(try apply(.markUnrecorded(references), context))
        let state = try PrayerRepository(context: context).snapshot(now: time("2026-10-07T12:05:00+03:00"))
        #expect(state.statistics.denominator == 0 && state.statistics.percentage == nil && state.qada.isEmpty)
        try PrayerMutationHandler.undo(inverse, in: context, now: time("2026-10-07T12:06:00+03:00"), writer: "test-device"); try context.save()
        #expect(try PrayerRepository(context: context).snapshot(now: time("2026-10-07T12:07:00+03:00")).pending.count == 2)
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
    @Test func monthRatioGolden26Of30AndStrictStreakNotRepairedByQada() throws {
        // Hand-authored §7.2 example: 26 on time, 2 qada, 2 missed. No code-generated expectations.
        let container = try container(start: "2026-10-01T12:00:00+03:00"); let context = container.mainContext
        var index = 0
        for day in 1...6 { for prayer in Prayer.allCases {
            let row = PrayerLog(); row.dayKey = String(format: "2026-10-%02d", day); row.prayer = prayer.rawValue; row.status = index < 26 ? "jamaah" : (index < 28 ? "qada" : "missed"); row.eventAt = time("2026-10-01T05:00:00+03:00"); row.tzID = "Asia/Riyadh"; context.insert(row)
            if index >= 26 { let qada = QadaItem(); qada.originalDayKey = row.dayKey; qada.prayer = row.prayer; qada.madeUpAt = index < 28 ? time("2026-10-06T20:00:00+03:00") : nil; context.insert(qada) }
            index += 1
        } }; try context.save()
        let state = try PrayerRepository(context: context).snapshot(now: time("2026-10-07T20:00:00+03:00"))
        #expect(state.statistics.onTime == 26 && state.statistics.denominator == 30 && state.statistics.percentage == 87)
        #expect(state.statistics.madeUp == 2 && state.statistics.owed == 2 && state.statistics.prayerStreak == 0)
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
}
