import Foundation
import Testing
@testable import MadarCore

struct LegacyPersonalImportTests {
    private let zone = TimeZone(identifier: "Asia/Riyadh")!
    private let day = try! GregorianDay("2026-10-25")
    private func plan(_ raw: String) throws -> LegacyPersonalImport.Plan {
        try LegacyPersonalImport.plan(backup: Data(raw.utf8), observedDay: day, zone: zone, uuid: { _ in UUID(uuidString: "00000000-0000-0000-0000-000000000001")! })
    }
    @Test func sealedLetterRetainsItsExactTextAndGregorianDays() throws {
        let p = try plan(#"{"futureLetters":[{"id":"l","content":"النص الأصلي\nكما هو","title":"عنوان مستقل","writtenDate":"2026-10-01","deliveryDate":"2026-11-19","opened":false,"openedDate":"2026-10-22","unknown":7}]}"#)
        #expect(p.letters[0].text == "النص الأصلي\nكما هو")
        #expect(p.letters[0].writtenDay.description == "2026-10-01" && p.letters[0].deliveryDay.description == "2026-11-19")
        #expect(!p.letters[0].opened && p.letters[0].openedDay == nil)
        #expect(String(data: p.archives[0].json, encoding: .utf8)?.contains("عنوان مستقل") == true)
    }
    @Test func openedWithoutKnownDayDoesNotInventAnOpeningTime() throws {
        let p = try plan(#"{"futureLetters":[{"id":"l","content":"مفتوحة","writtenDate":"2026-10-01","deliveryDate":"2026-10-02","opened":true}]}"#)
        #expect(p.letters[0].opened && p.letters[0].openedDay == nil)
    }
    @Test func deletionRequiresExplicitNewerEditToRestore() throws {
        let p = try plan(#"{"futureLetters":[{"id":"l","content":"محذوفة","writtenDate":"2026-10-01","deliveryDate":"2026-10-02"}],"deleted":{"l":1700000000000}}"#)
        #expect(p.letters[0].provenance.deletedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(p.letters[0].provenance.restoredAt == nil)
        let restored = try plan(#"{"futureLetters":[{"id":"l","content":"مستعادة","writtenDate":"2026-10-01","deliveryDate":"2026-10-02","updatedAt":1700000001000}],"deleted":{"l":1700000000000}}"#)
        #expect(restored.letters[0].provenance.deletedAt == nil)
        #expect(restored.letters[0].provenance.deletionBarrierAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(restored.letters[0].provenance.restoredAt == Date(timeIntervalSince1970: 1_700_000_001))
    }
    @Test func oneOffDayKeepsItsYearAndCountUpMapsToItsOption() throws {
        let p = try plan(#"{"countdownEvents":[{"id":"a","title":"موعد","date":"2026-11-19","emoji":"🌿"},{"id":"b","title":"عد صاعد","date":"2026-11-20","countUpAfter":true},{"id":"c","title":"علم غريب","date":"2026-11-21","countUpAfter":"yes"}]}"#)
        #expect(p.days.map(\.sourceID) == ["a", "b"])
        #expect(p.days[0].day.description == "2026-11-19" && !p.days[0].countUpAfter)
        #expect(p.days[1].day.description == "2026-11-20" && p.days[1].countUpAfter)
        #expect(p.counts["countUpAfter"] == 1 && p.counts["skipped.countUpAfter"] == 1 && p.archives.count == 3)
    }
    @Test func malformedCollectionCannotReportAValidEmptyImport() {
        #expect(throws: CoreError.invalidCommand) { try plan(#"{"futureLetters":{"bad":"shape"}}"#) }
    }
    @Test func invalidDatesStayRawAndNumericBooleansDoNotOpenLetters() throws {
        let p = try plan(#"{"futureLetters":[{"id":"l","content":"سرية","writtenDate":"2026-10-01","deliveryDate":"2026-11-19","opened":1}],"countdownEvents":[{"id":"bad","title":"غير صالح","date":"2026-02-30"}]}"#)
        #expect(p.letters.count == 1 && !p.letters[0].opened)
        #expect(p.days.isEmpty && p.counts["skipped.day"] == 1 && p.archives.count == 2)
    }
}
