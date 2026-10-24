import Foundation
import Testing
@testable import MadarCore

/// M3-V09 / N01 / RD8 against the synthetic Day One export built by `scripts/make-dayone-fixture.py`.
/// Expected values are worked out from the fixture's own inputs and the spec rules, never from parser output.
struct DayOneImportTests {
    private func fixture() throws -> ZIPReader {
        let url = try #require(Bundle.module.url(forResource: "dayone-synthetic", withExtension: "zip", subdirectory: "Fixtures"))
        return try ZIPReader(url: url)
    }
    private func plan() throws -> DayOnePlan { try DayOneParser.plan(fixture()) }
    private func entry(_ id: String) throws -> DayOneEntryPlan { try #require(try plan().entries.first { $0.sourceID == id }) }
    private func iso(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func readsDeflatedMembersWithDataDescriptorsAndVerifiesCRC() throws {
        let zip = try fixture()
        #expect(Set(zip.members.map(\.path)) == ["Journal.json", "رحلات.json", "photos/1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f.jpeg",
                                                "audios/2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a.m4a", "pdfs/4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d.pdf", "__MACOSX/._Journal.json"])
        let journal = try zip.read(try #require(zip.member("Journal.json")))
        #expect(try JSONSerialization.jsonObject(with: journal) is [String: Any])
        let jpeg = try zip.read(try #require(zip.member("photos/1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f.jpeg")))
        #expect(jpeg.prefix(2) == Data([0xFF, 0xD8]))
        // One flipped byte inside a deflated member must fail (corrupt stream or CRC), never return a partial file.
        let url = try #require(Bundle.module.url(forResource: "dayone-synthetic", withExtension: "zip", subdirectory: "Fixtures"))
        var bytes = try Data(contentsOf: url); bytes[60] ^= 0xFF
        let damaged = try ZIPReader(data: bytes)
        #expect(throws: ZIPReaderError.self) { try damaged.read(damaged.members[0]) }
        #expect(throws: ZIPReaderError.notZIP) { try ZIPReader(data: Data("not a zip at all, just text".utf8)) }
    }

    @Test func entriesSkipsJournalsAndMedia() throws {
        let plan = try plan()
        #expect(plan.journals.map(\.name) == ["Journal", "رحلات"])
        #expect(plan.entries.map(\.sourceID) == ["A1000000000000000000000000000001", "B2000000000000000000000000000002", "C3000000000000000000000000000003",
                                                 "D4000000000000000000000000000004", "F6000000000000000000000000000006"])
        #expect(plan.skipped.map(\.reason) == [.empty, .noIdentity, .duplicateInFile])
        #expect(plan.skipped.last?.journal == "رحلات" && plan.skipped.last?.sourceID == "B2000000000000000000000000000002")
        // Four distinct files: the London photo serves two entries (same md5) and stays one Media.
        #expect(plan.media.map(\.key) == ["1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f", "2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a", "3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c", "4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d"])
        #expect(plan.media.filter { !$0.found }.map(\.kind) == ["video"])
    }

    @Test func londonEntryKeepsMarkdownTagsPlaceZoneAndInlineMediaOrder() throws {
        let e = try entry("A1000000000000000000000000000001")
        #expect(e.text == "# مساء في لندن\n\nمشينا **طويلًا** حتى النهر\\.\n\n![](dayone-moment://P1)\n\nصوت المطر:\n\n![](dayone-moment:/audio/AU1)")
        #expect(e.tags == ["سفر", "عائلة"])
        #expect(e.starred && e.journal == "Journal" && e.timeZoneID == "Europe/London" && !e.dateOnly)
        #expect(e.createdAt == iso("2025-07-14T22:30:00Z") && e.modifiedAt == iso("2025-07-20T09:00:00Z"))
        #expect(e.place == "Hyde Park" && e.latitude == 51.5073 && e.longitude == -0.1657)
        #expect(e.media.map(\.identifier) == ["P1", "AU1"] && e.media.allSatisfy(\.inline))
        #expect(e.media.map(\.contentType) == ["image/jpeg", "audio/mp4"] && e.media[1].durationS == 1)
        #expect(e.media[0].path == "photos/1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f.jpeg")
    }

    @Test func addressPlaceNamesGiveWayToTheLocality() {
        #expect(DayOneParser.placeName(["6339 الرين، 19433 - 4090", "الرياض", "منطقة الرياض"]) == "الرياض")
        #expect(DayOneParser.placeName(["١٢ شارع", nil, "منطقة الرياض"]) == "منطقة الرياض")
        #expect(DayOneParser.placeName(["Hyde Park", "London", nil]) == "Hyde Park")
        // Only an address: its words stay, building and postal numbers go; numbers alone give no place.
        #expect(DayOneParser.placeName(["6339 الرين، 19433 - 4090", nil, " "]) == "الرين")
        #expect(DayOneParser.placeName(["٤٢١٠ شارع نهر النيل، حي الملز، 12629", nil, nil]) == "شارع نهر النيل، حي الملز")
        #expect(DayOneParser.placeName(["7702 2788", nil, nil]) == nil)
        #expect(DayOneParser.placeName([nil, nil, nil]) == nil)
    }

    @Test func missingVideoAndPDFFoundInPdfsFolder() throws {
        let e = try entry("B2000000000000000000000000000002")
        #expect(e.media.map(\.kind) == ["video", "doc"])
        #expect(e.media[0].path == nil && e.media[0].contentType == "video/quicktime" && e.media[0].durationS == 4)
        #expect(e.media[1].path == "pdfs/4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d.pdf" && e.media[1].contentType == "application/pdf")
        #expect(try entry("C3000000000000000000000000000003").dateOnly)
    }

    @Test func dayKeyUsesOriginalZoneAndCurrentDayStart() throws {
        let p = try plan(), home = ActivePlace.riyadh
        func key(_ id: String, _ boundary: DayBoundary) throws -> DayOneDayKey.Resolved {
            DayOneDayKey.resolve(try #require(p.entries.first { $0.sourceID == id }), boundary: boundary, home: home) { PrayerTimesEngine.calculate(day: $1, place: $0) }
        }
        // 22:30Z = 23:30 BST on 14 July in London; in Riyadh it would already be 15 July.
        #expect(try key("A1000000000000000000000000000001", .fajr) == .init(day: try GregorianDay("2025-07-14"), timeZoneID: "Europe/London", policy: "fajr@1"))
        // 01:10Z = 04:10 in Riyadh on 2 March, before Fajr (≈05:00): the prayer day is 1 March; by midnight it is 2 March.
        #expect(try key("B2000000000000000000000000000002", .fajr) == .init(day: try GregorianDay("2025-03-01"), timeZoneID: "Asia/Riyadh", policy: "fajr@1"))
        #expect(try key("B2000000000000000000000000000002", .midnight) == .init(day: try GregorianDay("2025-03-02"), timeZoneID: "Asia/Riyadh", policy: "midnight@1"))
        // All-day entry: 21:00Z on 10 Jan = 00:00 on 11 Jan in Riyadh; keeps 11 Jan even under fajr.
        #expect(try key("C3000000000000000000000000000003", .fajr) == .init(day: try GregorianDay("2025-01-11"), timeZoneID: "Asia/Riyadh", policy: "midnight@1"))
        // 20:00Z on 1 May = 05:00 on 2 May in Tokyo; no coordinates outside the home zone → civil date there.
        #expect(try key("D4000000000000000000000000000004", .fajr) == .init(day: try GregorianDay("2025-05-02"), timeZoneID: "Asia/Tokyo", policy: "midnight@1"))
    }

    @Test func oldMadarDayIsKeptOverTheDayBoundary() throws {
        // MIGRATION.md: the old app's stored date is never recomputed. B is 04:10 in Riyadh on 2 March, before Fajr, so
        // the fajr boundary alone gives 1 March; an old Madar row stored on 2 March stays on 2 March.
        var legacy = try entry("B2000000000000000000000000000002")
        #expect(legacy.legacyDay == nil)
        legacy.legacyDay = "2025-03-02"
        let resolved = DayOneDayKey.resolve(legacy, boundary: .fajr, home: .riyadh) { PrayerTimesEngine.calculate(day: $1, place: $0) }
        #expect(resolved == .init(day: try GregorianDay("2025-03-02"), timeZoneID: "Asia/Riyadh", policy: "legacy@0"))
        let parsed = DayOneParser.entry(["uuid": "L1", "creationDate": "2025-03-02T01:10:00Z", "timeZone": "Asia/Riyadh", "text": "سطر", "madarLegacyDay": "2025-03-02"], journal: "Journal", byStem: [:])
        #expect((try? parsed.get())?.legacyDay == "2025-03-02")
    }

    @Test func hashIgnoresKeyOrderAndChangesWithContent() {
        let a: [String: Any] = ["uuid": "X", "text": "سطر", "tags": ["أ"], "creationDate": "2025-01-01T00:00:00Z"]
        let reordered: [String: Any] = ["creationDate": "2025-01-01T00:00:00Z", "tags": ["أ"], "text": "سطر", "uuid": "X"]
        var text = a; text["text"] = "سطر آخر"
        var tags = a; tags["tags"] = ["أ", "ب"]
        var media = a; media["photos"] = [["md5": "ff"]]
        #expect(DayOneParser.hash(a) == DayOneParser.hash(reordered))
        #expect(Set([DayOneParser.hash(a), DayOneParser.hash(text), DayOneParser.hash(tags), DayOneParser.hash(media)]).count == 4)
        #expect(DayOneParser.hash(a).count == 64)
    }

    @Test func reimportRule() {
        let mine = DayOneMerge.Existing(hash: "h1", editedInMadar: true), clean = DayOneMerge.Existing(hash: "h1", editedInMadar: false)
        #expect(DayOneMerge.action(hash: "h1", existing: nil) == .add)
        #expect(DayOneMerge.action(hash: "h1", existing: clean) == .same)
        #expect(DayOneMerge.action(hash: "h1", existing: mine) == .same)
        #expect(DayOneMerge.action(hash: "h1", existing: .init(hash: "h1", editedInMadar: true, tags: nil), incomingTags: ["سفر"]) == .backfillTags)
        #expect(DayOneMerge.action(hash: "h1", existing: .init(hash: "h1", editedInMadar: false, tags: []), incomingTags: ["سفر"]) == .same)
        #expect(DayOneMerge.action(hash: "h2", existing: clean) == .update)
        #expect(DayOneMerge.action(hash: "h2", existing: mine) == .keepBoth)
        #expect(DayOneMerge.action(hash: "h2", existing: clean, choice: .keepMine) == .keepMine)
        #expect(DayOneMerge.action(hash: "h2", existing: mine, choice: .update) == .update)
    }

    @Test func markdownForDisplayAndSearch() {
        let text = "# مساء في لندن\n\nمشينا **طويلًا** حتى النهر\\.\n\n![](dayone-moment://P1)\n\nصوت المطر:\n\n![](dayone-moment:/audio/AU1)"
        #expect(DayOneMarkdown.inlineIdentifiers(text) == ["P1", "AU1"])
        #expect(DayOneMarkdown.readable(text) == "مساء في لندن\n\nمشينا **طويلًا** حتى النهر\\.\n\nصوت المطر:")
        #expect(DayOneMarkdown.plain(text) == "مساء في لندن\n\nمشينا طويلًا حتى النهر.\n\nصوت المطر:")
    }
}
