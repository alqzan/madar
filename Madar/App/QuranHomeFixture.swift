#if DEBUG
import Foundation
import SwiftData
import MadarData
import MadarCore
import MadarCommands
import MadarQuran

extension AppSession {
    func prepareQuranHomeFixture(group: URL) throws {
        let env = ProcessInfo.processInfo.environment
        guard env["MADAR_UI_QURAN_FIXTURE"] == "home", let id = env["MADAR_UI_STORE_ID"],
              group.lastPathComponent == id, group.deletingLastPathComponent().lastPathComponent == "UITestStores" else { return }
        let context = ModelContext(container)
        selectedTab = "quran"
        guard try context.fetchCount(FetchDescriptor<HifzSession>()) == 0 else { return }
        let now = prayerUITestClock(.now), catalog = try QuranResources.catalog()
        let today = GregorianDay.containing(now, in: .riyadhZone)
        let settings = try SettingsStore(context: context)
        _ = try settings.stage(["core.dayStart": .string("midnight"), "quran.restDay": .string("friday"), "quran.reviewSchedule": .string("spaced")], now: now)
        let plan = HifzPlan(); plan.startAyah = 1; plan.amount = 1; plan.activeFrom = now.addingTimeInterval(-100 * 86400); plan.createdAt = plan.activeFrom
        plan.missPolicy = "ask"; context.insert(plan)
        func append(kind: String, first: Int, last: Int, pages: [Int], offset: Int) {
            let row = HifzSession(); row.planID = plan.id; row.kind = kind; row.fromAyah = first; row.toAyah = last; row.pages = pages
            row.dayKey = today.adding(days: offset).description; row.endedAt = today.adding(days: offset).date(in: .riyadhZone).addingTimeInterval(12 * 3600)
            row.tzID = "Asia/Riyadh"; row.dayPolicy = "midnight@1"; context.insert(row)
            for page in pages { let grade = PageGrade(); grade.sessionID = row.id; grade.page = page; grade.grade = "mastered"; context.insert(grade) }
        }
        let baseEnd = catalog.ayahs(on: 270).last!.id
        append(kind: "hifz", first: 1, last: baseEnd, pages: Array(1...270), offset: -70)
        for offset in [-63, -49, -19, -1] { append(kind: "review", first: 1, last: baseEnd, pages: Array(1...270), offset: offset) }
        for index in 0..<14 {
            let page = 271 + index
            append(kind: "hifz", first: catalog.ayahs(on: page).first!.id, last: catalog.ayahs(on: page).last!.id, pages: [page], offset: index - 14)
        }
        let done = DeviceSetting(); done.key = "sys.onboardingCompleted"; done.valueJSON = Data("true".utf8); context.insert(done)
        try context.save()
    }
}
private extension TimeZone { static var riyadhZone: TimeZone { TimeZone(identifier: "Asia/Riyadh")! } }
#endif
