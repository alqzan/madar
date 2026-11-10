import XCTest
import SwiftData
import MadarData
import MadarCore
import MadarSnapshots
@testable import Madar

@MainActor final class QuranOutsideIntegrationTests: XCTestCase {
    private func fixture() throws -> (AppSession, AppQuranService, URL, Date) {
        let root = FileManager.default.temporaryDirectory.appending(path: "MadarQuranOutside-\(UUID())")
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let context = ModelContext(container), settings = try SettingsStore(context: context)
        _ = try settings.stage(["core.dayStart": .string("midnight"), "quran.restDay": .string("friday"), "quran.wirdReminder": .string("afterFajr"), "quran.lateReminder": .bool(true)])
        let now = ISO8601DateFormatter().date(from: "2026-10-15T02:00:00+03:00")!
        let plan = HifzPlan(); plan.activeFrom = now.addingTimeInterval(-3 * 86400); context.insert(plan)
        let hifz = HifzSession(); hifz.kind = "hifz"; hifz.fromAyah = 1; hifz.toAyah = 7; hifz.pages = [1]
        hifz.dayKey = "2026-10-12"; hifz.endedAt = now.addingTimeInterval(-3 * 86400); context.insert(hifz)
        let grade = PageGrade(); grade.sessionID = hifz.id; grade.page = 1; grade.grade = "mastered"; context.insert(grade)
        try context.save()
        let app = try AppSession(container: container, groupDirectory: root)
        return (app, AppQuranService(session: app, clock: { now }), root, now)
    }
    func testReminderCandidatesRespectSanctityBudgetQuietAndOff() async throws {
        let (app, service, root, now) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let day = try XCTUnwrap(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-15"), place: .riyadh))
        let candidates = try service.notificationCandidates(prayerDays: [day], now: now)
        let wird = try XCTUnwrap(candidates.first { $0.id.hasSuffix(".wird") })
        let late = try XCTUnwrap(candidates.first { $0.id.hasSuffix(".late") })
        XCTAssertEqual(wird.dueAt, day.fajr.addingTimeInterval(30 * 60))
        XCTAssertEqual(late.dueAt, day.asr.addingTimeInterval(30 * 60))
        let budget = NotificationArbiter.plan(candidates: candidates, prayerDays: [day], now: now, timeZone: .init(identifier: "Asia/Riyadh")!, policy: .init(dailyBudget: 1, digestEnabled: false, staleNudgeEnabled: false, dayBoundary: .midnight))
        XCTAssertEqual(budget.scheduled.map(\.id), [wird.id]); XCTAssertEqual(budget.droppedIDs, [late.id])
        let quiet = NotificationArbiter.plan(candidates: candidates, prayerDays: [day], now: now, timeZone: .init(identifier: "Asia/Riyadh")!, policy: .init(quietFromMinutes: 12 * 60, staleNudgeEnabled: false))
        XCTAssertTrue(quiet.droppedIDs.contains(late.id))
        try await app.applySettingsAndWait(["quran.wirdReminder": .string("off"), "quran.lateReminder": .bool(false)])
        XCTAssertTrue(try service.notificationCandidates(prayerDays: [day], now: now).isEmpty)
    }
    func testWidgetJSONExpiresAtMadarBoundaryAndRoutesOnlyBuiltScreens() throws {
        let (app, service, root, now) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let envelope = try service.widgetSnapshot(), store = SnapshotStore(directory: root.appending(path: "QuranSnapshots"))
        XCTAssertEqual(envelope.payload.fraction, 1.0 / 604); XCTAssertEqual(envelope.payload.coverage, "وجه واحد")
        XCTAssertEqual(envelope.payload.route, "madar://quran/session/hifz")
        XCTAssertEqual(envelope.payload.days.count, 7)
        try store.write(envelope)
        XCTAssertEqual(store.read("quran", as: QuranWidgetSnapshot.self, now: now)?.payload, envelope.payload)
        XCTAssertNil(store.read("quran", as: QuranWidgetSnapshot.self, now: envelope.validUntil))
        let context = ModelContext(app.container), settings = try SettingsStore(context: context)
        _ = try settings.stage(["core.dayStart": .string("fajr")]); try context.save()
        let prayerDay = try XCTUnwrap(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-15"), place: .riyadh))
        let nearBoundary = AppQuranService(session: app, clock: { prayerDay.fajr.addingTimeInterval(-300) })
        let finalMinutes = try nearBoundary.widgetSnapshot()
        XCTAssertEqual(finalMinutes.dayKey, "2026-10-14")
        XCTAssertEqual(finalMinutes.validUntil, prayerDay.fajr, "yesterday's widget expires exactly at the new Madar day")
        app.open(URL(string: "madar://quran/page/285")!)
        XCTAssertEqual(app.selectedTab, "quran"); XCTAssertEqual(app.quranRoute?.path, ["page", "285"])
        app.quranRoute = nil; app.errorMessage = nil
        app.open(URL(string: "madar://quran/fihris")!)
        XCTAssertEqual(app.quranRoute?.path, ["fihris"]); XCTAssertNil(app.errorMessage); XCTAssertEqual(app.selectedTab, "quran")
        app.quranRoute = nil; app.errorMessage = nil
        app.open(URL(string: "madar://quran/juz/30")!)
        XCTAssertEqual(app.quranRoute?.path, ["juz", "30"]); XCTAssertNil(app.errorMessage); XCTAssertEqual(app.selectedTab, "quran")
        XCTAssertEqual(try ModelContext(app.container).fetchCount(FetchDescriptor<HifzSession>()), 1)
    }
    func testQuranWidgetSnapshotIsPublishedWithItsRoute() async throws {
        let (app, _, root, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try app.publishSnapshot()
        let visible = try XCTUnwrap(app.snapshotStore.read("quran", as: QuranWidgetSnapshot.self))
        XCTAssertEqual(visible.payload.route, "madar://quran/session/hifz")
        XCTAssertFalse(visible.payload.nextDetail.isEmpty)
    }
    func testWidgetReviewProgressCountsDistinctFacesAndDecodesOlderJSON() throws {
        let (app, service, root, now) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let initial = try service.widgetSnapshot().payload
        XCTAssertEqual(initial.reviewProgress, "٠ من ١")
        let context = ModelContext(app.container)
        for kind in ["free", "qiyam"] {
            let session = HifzSession(); session.kind = kind; session.fromAyah = 1; session.toAyah = 7; session.pages = [1]
            session.dayKey = "2026-10-15"; session.endedAt = now.addingTimeInterval(-60); context.insert(session)
            let grade = PageGrade(); grade.sessionID = session.id; grade.page = 1; grade.grade = "mastered"; context.insert(grade)
        }
        try context.save()
        let completed = try service.widgetSnapshot().payload
        XCTAssertEqual(completed.reviewProgress, "١ من ١", "Free review and qiyam on the same face count once.")
        var oldJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(completed)) as? [String: Any])
        oldJSON.removeValue(forKey: "reviewProgress")
        let legacy = try JSONDecoder().decode(QuranWidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        XCTAssertNil(legacy.reviewProgress); XCTAssertEqual(legacy.nextTitle, completed.nextTitle)
    }
}
