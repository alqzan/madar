import Foundation
import Testing
@testable import MadarCore

struct LegacyHabitImportTests {
    let observed = try! GregorianDay("2026-10-25")
    let zone = TimeZone(identifier: "Asia/Riyadh")!
    func plan(_ raw: String) throws -> LegacyHabitImport.Plan {
        try LegacyHabitImport.plan(backup: Data(raw.utf8), observedDay: observed, zone: zone, uuid: { text in
            // Stable, deliberately simple test identity; golden dates/values below
            // come from the pinned legacy daily checkbox contract, not the engine.
            var bytes = Array(repeating: UInt8(0), count: 16)
            for (i, byte) in text.utf8.enumerated() { bytes[i % 16] &+= byte }
            return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
        })
    }
    @Test func datesUnionOnceAndUnknownFieldsAreArchived() throws {
        let raw = #"{"habits":[{"id":"a","name":"قديم","icon":"x","color":"blue","logs":["2026-10-21","2026-10-21","bad"],"updatedAt":1000,"future":7},{"id":"a","name":"جديد","logs":["2026-10-22"],"updatedAt":2000}]}"#
        let p = try plan(raw)
        #expect(p.habits.count == 1 && p.habits[0].name == "جديد")
        #expect(p.habits[0].start.description == "2026-10-21")
        #expect(p.events.map { $0.day.description } == ["2026-10-21", "2026-10-22"])
        #expect(p.counts["skipped.logDay"] == 1 && p.counts["deduped.logDay"] == 1)
        #expect(String(data: p.archives[0].json, encoding: .utf8)?.contains("future") == true)
        #expect(try plan(raw) == p)
    }
    @Test func explicitUncheckWinsAndMissingDeletedDatesAreRetained() throws {
        let p = try plan(#"{"habits":[{"id":"a","name":"عادة","logs":["2026-10-21","2026-10-22"]}],"deleted":{"habitlog:a:2026-10-22":100000,"habitlog:a:2026-10-23":200000}}"#)
        #expect(p.events.count == 3)
        #expect(p.events.filter { $0.deletedAt == nil }.map { $0.day.description } == ["2026-10-21"])
        #expect(p.events.last?.deletedAt == Date(timeIntervalSince1970: 200))
    }
    @Test func freezeIsObservedWithoutInventingItsStartOrLinkingByName() throws {
        let p = try plan(#"{"habits":[{"id":"a","name":"قرآن","logs":["2026-10-01"]}],"frozenHabits":["a","core:reading"]}"#)
        #expect(p.pauses.count == 1 && p.pauses[0].observedFrom == observed)
        #expect(p.counts["pause.startUnknown"] == 1 && p.counts["archived.freezeKey"] == 1)
        #expect(p.habits.count == 1 && p.events.count == 1)
    }
    @Test func itemTombstoneKeepsHistoryAndNewerMetadataCanRestoreIt() throws {
        let deleted = try plan(#"{"habits":[{"id":"a","name":"عادة","logs":["2026-10-01"],"updatedAt":1000}],"deleted":{"a":2000}}"#)
        #expect(deleted.habits[0].deletedAt == Date(timeIntervalSince1970: 2))
        let restored = try plan(#"{"habits":[{"id":"a","name":"عادة","logs":[],"updatedAt":3000}],"deleted":{"a":2000}}"#)
        #expect(restored.habits[0].deletedAt == nil)
        #expect(restored.habits[0].deletionBarrierAt == Date(timeIntervalSince1970: 2))
        #expect(restored.habits[0].restoredAt == Date(timeIntervalSince1970: 3))
    }
    @Test func missingEditTimestampCannotOverrideDeletionWithAnInferredDate() throws {
        for logs in ["[]", "[\"2026-10-21\"]"] {
            let p = try plan("{\"habits\":[{\"id\":\"gone\",\"name\":\"قديمة\",\"logs\":\(logs)}],\"deleted\":{\"gone\":1700000000000}}")
            #expect(p.habits[0].deletedAt == Date(timeIntervalSince1970: 1_700_000_000))
            #expect(p.habits[0].restoredAt == nil)
        }
    }
    @Test func malformedDeletionEvidenceIsArchivedWithoutRevivingAnything() throws {
        let p = try plan(#"{"habits":[{"id":"a","name":"عادة","logs":["2026-10-21"]},{"id":"b","name":"محذوفة","logs":[]}],"deleted":{"habitlog:a:2026-10-21":"unknown","b":false}}"#)
        #expect(p.habits.map(\.sourceID) == ["a"] && p.events.isEmpty)
        #expect(p.counts["skipped.logDeletion"] == 1 && p.counts["skipped.itemDeletion"] == 1)
        #expect(String(data: p.archives.last!.json, encoding: .utf8)?.contains("unknown") == true)
    }
    @Test func invalidRowsStayArchivedAndEmptyHabitStartsAtObservation() throws {
        let p = try plan(#"{"habits":[{"name":"بلا معرّف"},{"id":"b","name":"","logs":[]},{"id":"c","name":"جديد","logs":[]}] }"#)
        #expect(p.habits.count == 1 && p.habits[0].start == observed)
        #expect(p.archives.count == 4 && p.events.isEmpty)
    }
}
