import Foundation
import Testing
@testable import MadarCore

/// §7.3 N04 acceptance: a letter on a trip, date or event is not due before the event and never opens twice;
/// a letter on a deleted target becomes orphaned and never opens by itself.
struct DiaryLetterTests {
    private func at(_ s:String)->Date{ISO8601DateFormatter().date(from:s)!}
    private let written=ISO8601DateFormatter().date(from:"2026-10-15T20:00:00+03:00")!
    private func world(_ now:String,today:String,hijri:HijriDate = .init(year:1448,month:4,day:23),trips:[DiaryLetterWorld.Trip]=[],projects:[DiaryLetterWorld.Project]=[]) throws -> DiaryLetterWorld {
        .init(now:at(now),today:try GregorianDay(today),hijriToday:hijri,trips:trips,projects:projects)
    }
    private func letter(_ trigger:DiaryLetterTrigger,day:String?=nil,hijri:String?=nil,target:UUID?=nil,state:DiaryLetterState = .sealed) throws -> DiaryLetterFacts {
        .init(writtenAt:written,trigger:trigger,openDay:try day.map(GregorianDay.init),hijriValue:hijri,target:target,state:state)
    }
    @Test func dateLetterIsDueOnlyFromItsDay() throws {
        let l=try letter(.date,day:"2027-01-01")
        #expect(DiaryLetters.evaluate(l,in:try world("2026-12-31T23:00:00+03:00",today:"2026-12-31")) == .sealed)
        #expect(DiaryLetters.evaluate(l,in:try world("2027-01-01T06:00:00+03:00",today:"2027-01-01")) == .eligible)
    }
    @Test func tripLetterIgnoresTripsBeforeWritingAndDismissedTrips() throws {
        let old=DiaryLetterWorld.Trip(id:UUID(),start:at("2026-09-29T10:00:00+03:00"),end:nil,live:true)
        let dismissed=DiaryLetterWorld.Trip(id:UUID(),start:at("2026-11-01T10:00:00+03:00"),end:nil,live:false)
        let l=try letter(.tripStart)
        #expect(DiaryLetters.evaluate(l,in:try world("2026-11-02T10:00:00+03:00",today:"2026-11-02",trips:[old,dismissed])) == .sealed)
        let next=DiaryLetterWorld.Trip(id:UUID(),start:at("2026-11-05T10:00:00+03:00"),end:nil,live:true)
        #expect(DiaryLetters.evaluate(l,in:try world("2026-11-04T10:00:00+03:00",today:"2026-11-04",trips:[old,next])) == .sealed)
        #expect(DiaryLetters.evaluate(l,in:try world("2026-11-05T11:00:00+03:00",today:"2026-11-05",trips:[old,next])) == .eligible)
        let returning=try letter(.tripEnd,target:next.id)
        #expect(DiaryLetters.evaluate(returning,in:try world("2026-11-06T10:00:00+03:00",today:"2026-11-06",trips:[next])) == .sealed)
        let ended=DiaryLetterWorld.Trip(id:next.id,start:next.start,end:at("2026-11-09T10:00:00+03:00"),live:true)
        #expect(DiaryLetters.evaluate(returning,in:try world("2026-11-09T11:00:00+03:00",today:"2026-11-09",trips:[ended])) == .eligible)
    }
    @Test func deletedTargetOrphansAndNothingMovesBackwards() throws {
        let project=UUID(),l=try letter(.projectFinished,target:project)
        #expect(DiaryLetters.evaluate(l,in:try world("2026-11-01T10:00:00+03:00",today:"2026-11-01",projects:[.init(id:project,finishedAt:nil,live:true)])) == .orphaned)
        #expect(DiaryLetters.evaluate(l,in:try world("2026-11-01T10:00:00+03:00",today:"2026-11-01",projects:[.init(id:project,finishedAt:nil,live:false)])) == .orphaned)
        #expect(DiaryLetters.evaluate(l,in:try world("2026-11-01T10:00:00+03:00",today:"2026-11-01",projects:[.init(id:project,finishedAt:at("2026-10-20T10:00:00+03:00"),live:true)])) == .eligible)
        for state in [DiaryLetterState.eligible,.opened,.orphaned] {
            #expect(DiaryLetters.evaluate(try letter(.date,day:"2030-01-01",state:state),in:try world("2026-11-01T10:00:00+03:00",today:"2026-11-01")) == state)
        }
        let trip=try letter(.tripStart,target:UUID())
        #expect(DiaryLetters.evaluate(trip,in:try world("2026-11-01T10:00:00+03:00",today:"2026-11-01")) == .orphaned)
    }
    @Test func ramadanAndHijriDates() throws {
        #expect(DiaryLetters.nextRamadan(after:.init(year:1448,month:4,day:23))=="1448-09-01")
        #expect(DiaryLetters.nextRamadan(after:.init(year:1448,month:9,day:3))=="1449-09-01")
        let l=try letter(.ramadanStart,hijri:"1448-09-01")
        #expect(DiaryLetters.evaluate(l,in:try world("2027-02-07T10:00:00+03:00",today:"2027-02-07",hijri:.init(year:1448,month:8,day:29))) == .sealed)
        #expect(DiaryLetters.evaluate(l,in:try world("2027-02-08T10:00:00+03:00",today:"2027-02-08",hijri:.init(year:1448,month:9,day:1))) == .eligible)
    }
}
