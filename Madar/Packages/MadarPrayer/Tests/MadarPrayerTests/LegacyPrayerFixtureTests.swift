import Foundation
import Testing
import MadarCore
import MadarPrayer

private struct LegacyPrayerFixture: Decodable {
    let fixtureVersion: Int
    let sourceCommit: String
    let sourceFile: String
    let sourceSHA256: String
    let synthetic: Bool
    let state: State

    struct State: Decodable {
        let prayerLogs: [PrayerLog]
        let qadaBacklog: Int
    }

    struct PrayerLog: Decodable {
        let date: String
        let prayers: [String: String]
        let khushu: [String: Int]
        let khushuUpdatedAt: [String: Double]
        let prayerUpdatedAt: [String: Double]
        let sunan: Int
        let sunanUpdatedAt: Double
        let qiyam: QiyamNight
        let qiyamUpdatedAt: Double
    }

    struct QiyamNight: Decodable {
        let rakaat: Int
        let witr: Bool
    }
}

@Test("synthetic legacy prayer fixture covers the pinned source fields")
func test_M1F05SyntheticPrayerFixtureCapturesSourceShape() throws {
    let url = try #require(Bundle.module.url(forResource: "legacy-prayer-history-synthetic-v1", withExtension: "json", subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    let fixture = try JSONDecoder().decode(LegacyPrayerFixture.self, from: data)

    #expect(fixture.fixtureVersion == 1)
    #expect(fixture.sourceCommit == "aba0c1b18a3bf3fc070395a40595e939c3b73aa3")
    #expect(fixture.sourceFile == "src/lib/types.ts")
    #expect(fixture.sourceSHA256 == "4eee0ee64c6014f949b24c096d9c80497fce12620f59dd614e912644e2161ed7")
    #expect(fixture.synthetic)
    #expect(fixture.state.qadaBacklog == 2)
    #expect(fixture.state.prayerLogs.count == 1)

    let log = try #require(fixture.state.prayerLogs.first)
    #expect(log.date == "2026-10-05")
    #expect(Set(log.prayers.keys) == ["الفجر", "الظهر", "العصر", "المغرب", "العشاء"])
    #expect(Set(log.prayers.values) == ["لم", "منفردة", "جماعة", "فائتة", "قضاء"])
    #expect(Set(log.khushu.values) == [1, 2, 3])
    #expect(log.sunan == 8)
    #expect(log.qiyam.rakaat == 11 && log.qiyam.witr)

    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let state = try #require(object["state"] as? [String: Any])
    let rows = try #require(state["prayerLogs"] as? [[String: Any]])
    let sourceFields = try #require(rows.first.map { Set($0.keys) })
    #expect(sourceFields == [
        "date", "prayers", "khushu", "khushuUpdatedAt", "prayerUpdatedAt",
        "sunan", "sunanUpdatedAt", "qiyam", "qiyamUpdatedAt"
    ])
    #expect(!sourceFields.contains("eventAt"))
    #expect(!sourceFields.contains("tzID"))
    #expect(!sourceFields.contains("place"))
}

@Test("legacy prayer status preview preserves approved meanings and reports missing facts")
func test_M1F05LegacyPrayerStatusPreview() throws {
    let fixtureDay = try GregorianDay("2026-10-05")
    let trackingStart = try GregorianDay("2026-10-06")
    let activeDay = try GregorianDay("2026-10-06")
    let jamaah = LegacyPrayerStatusPreview.preview("جماعة", legacyDay: activeDay, trackingStart: trackingStart)
    #expect(jamaah.status == .jamaah)
    #expect(jamaah.disposition == .mapped)
    #expect(jamaah.requiredFacts == [.adhanInstant, .timeZoneID])

    let alone = LegacyPrayerStatusPreview.preview("منفردة", legacyDay: activeDay, trackingStart: trackingStart)
    #expect(alone.status == .alone)

    let missed = LegacyPrayerStatusPreview.preview("فائتة", legacyDay: activeDay, trackingStart: trackingStart)
    #expect(missed.status == .missed)

    let qada = LegacyPrayerStatusPreview.preview("قضاء", legacyDay: activeDay, trackingStart: trackingStart)
    #expect(qada.status == .qada)
    #expect(qada.requiredFacts == [.adhanInstant, .timeZoneID, .qadaMadeUpAt])

    let explicitLegacyLog = LegacyPrayerStatusPreview.preview("جماعة", legacyDay: fixtureDay, trackingStart: trackingStart)
    #expect(explicitLegacyLog.status == .jamaah)

    let unloggedBeforeTracking = LegacyPrayerStatusPreview.preview("لم", legacyDay: fixtureDay, trackingStart: trackingStart)
    #expect(unloggedBeforeTracking.status == .unrecordedHistory)
    #expect(unloggedBeforeTracking.requiredFacts == [.adhanInstant, .timeZoneID])

    let withinTracking = LegacyPrayerStatusPreview.preview("لم", legacyDay: activeDay, trackingStart: trackingStart)
    #expect(withinTracking.status == nil)
    #expect(withinTracking.disposition == .omittedUnloggedPrayer)
    #expect(withinTracking.requiredFacts.isEmpty)

    let unsupported = LegacyPrayerStatusPreview.preview("قيمة غير معروفة", legacyDay: activeDay, trackingStart: trackingStart)
    #expect(unsupported.status == nil)
    #expect(unsupported.rawValue == "قيمة غير معروفة")
    #expect(unsupported.disposition == .preserveRawUnsupportedStatus)
}
