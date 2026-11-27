import Foundation
import Testing
@testable import MadarCore

/// The old app's backup diary → Day One ZIP → `DayOneParser`. Expectations are written by hand from the backup below.
struct LegacyDiaryArchiveTests {
    // 1x1 PNG; its MD5 is not asserted, only that the parser finds the file by the identifier the archive wrote.
    private let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    private func backup() -> Data {
        Data("""
        {"journalEntries":[
         {"id":"e1","date":"2024-03-05","time":"21:30","title":"العنوان","content":"النص","starred":true,"timeZone":"Asia/Riyadh",
          "photos":["data:image/png;base64,\(png)"],"location":{"lat":24.5,"lng":46.25,"place":"الرياض"}},
         {"id":"e2","date":"2024-03-06","capturedAt":"2024-03-06T10:00:00Z","content":"بلا عنوان","photoRefs":["ref-abc"],
          "attachmentRefs":[{"hash":"h1","name":"a.pdf","mime":"application/pdf","localData":"data:application/pdf;base64,JVBERi0xLjQK"}]}
        ]}
        """.utf8)
    }

    @Test func legacyBackupBecomesParsableDayOneArchive() throws {
        let zip = try #require(try LegacyDiaryArchive.zip(fromBackup: backup()))
        let plan = try DayOneParser.plan(ZIPReader(data: zip))
        #expect(plan.entries.map(\.sourceID) == ["e1", "e2"])
        let a = plan.entries[0], b = plan.entries[1]
        #expect(a.text == "# العنوان\n\nالنص" && a.starred && a.legacyDay == "2024-03-05" && a.timeZoneID == "Asia/Riyadh")
        // 21:30 at +03:00 is 18:30 UTC.
        #expect(a.createdAt == ISO8601DateFormatter().date(from: "2024-03-05T18:30:00Z"))
        #expect(a.place == "الرياض" && a.latitude == 24.5 && a.longitude == 46.25)
        #expect(a.media.count == 1 && a.media[0].kind == "photo" && a.media[0].path != nil && a.media[0].path?.hasPrefix("photos/") == true && a.media[0].size == 70)
        #expect(b.text == "بلا عنوان" && b.legacyDay == "2024-03-06" && b.timeZoneID == "Asia/Riyadh")
        // The embedded PDF is found under pdfs/ (9 bytes «%PDF-1.4\n»); the photo reference stays missing.
        #expect(b.media.count == 2)
        #expect(b.media.contains { $0.identifier == "ref-abc" && $0.path == nil && $0.kind == "photo" })
        #expect(b.media.contains { $0.kind == "doc" && $0.path?.hasPrefix("pdfs/") == true && $0.size == 9 })
    }

    @Test func backupWithoutJournalEntriesGivesNoArchive() throws {
        #expect(try LegacyDiaryArchive.zip(fromBackup: Data(#"{"habits":[]}"#.utf8)) == nil)
        #expect(try LegacyDiaryArchive.zip(fromBackup: Data(#"{"journalEntries":[]}"#.utf8)) == nil)
        #expect(LegacyDiaryArchive.entryCount(inBackup: backup()) == 2)
    }
}
