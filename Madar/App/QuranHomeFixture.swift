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
        guard let variant = env["MADAR_UI_QURAN_FIXTURE"], ["home", "drill", "dayClose", "dayCloseStart", "khatmaStart", "widgetReview", "historyRoute", "reference", "referencePartial", "referenceBoundary", "referenceFatiha", "referenceFatihaOpening", "referenceKursi", "referenceSadi183", "referenceAalImran", "referenceBaqara178186", "referenceBaqara189", "referenceBaqara190"].contains(variant), let id = env["MADAR_UI_STORE_ID"],
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
        var historyRouteSessionID: UUID?
        @discardableResult func append(kind: String, first: Int, last: Int, pages: [Int], offset: Int, id: UUID? = nil) -> HifzSession {
            let row = HifzSession(); if let id { row.id = id }; row.planID = plan.id; row.kind = kind; row.fromAyah = first; row.toAyah = last; row.pages = pages
            row.dayKey = today.adding(days: offset).description; row.endedAt = today.adding(days: offset).date(in: .riyadhZone).addingTimeInterval(12 * 3600)
            row.tzID = "Asia/Riyadh"; row.dayPolicy = "midnight@1"; context.insert(row)
            for page in pages { let grade = PageGrade(); grade.sessionID = row.id; grade.page = page; grade.grade = "mastered"; context.insert(grade) }
            return row
        }
        if variant == "referenceFatiha" {
            let target = catalog.ayahs.first { $0.surahID == 1 && $0.ayahNumber == 5 }!
            plan.startAyah = target.id; plan.unit = "ayah"; plan.amount = 1; plan.rhythm = "light"; plan.activeFrom = now
        } else if variant == "referenceFatihaOpening" {
            let target = catalog.ayahs.first { $0.surahID == 1 && $0.ayahNumber == 2 }!
            plan.startAyah = target.id; plan.unit = "ayah"; plan.amount = 4; plan.rhythm = "light"; plan.activeFrom = now
        } else if variant == "referenceKursi" {
            let target = catalog.ayahs.first { $0.surahID == 2 && $0.ayahNumber == 255 }!
            plan.startAyah = target.id; plan.unit = "ayah"; plan.amount = 1; plan.rhythm = "light"; plan.activeFrom = now
        } else if variant == "referenceSadi183" {
            let target = catalog.ayahs.first { $0.surahID == 2 && $0.ayahNumber == 183 }!
            plan.startAyah = target.id; plan.unit = "ayah"; plan.amount = 1; plan.rhythm = "light"; plan.activeFrom = now
        } else if variant == "referenceAalImran" {
            let target = catalog.ayahs.first { $0.surahID == 3 && $0.ayahNumber == 190 }!
            plan.startAyah = target.id; plan.unit = "ayah"; plan.amount = 1; plan.rhythm = "light"; plan.activeFrom = now
        } else if variant == "referenceBaqara178186" {
            let target = catalog.ayahs.first { $0.surahID == 2 && $0.ayahNumber == 178 }!
            plan.startAyah = target.id; plan.unit = "ayah"; plan.amount = 9; plan.rhythm = "light"; plan.activeFrom = now
        } else if variant == "referenceBaqara189" {
            let target = catalog.ayahs.first { $0.surahID == 2 && $0.ayahNumber == 189 }!
            plan.startAyah = target.id; plan.unit = "ayah"; plan.amount = 1; plan.rhythm = "light"; plan.activeFrom = now
        } else if variant == "referenceBaqara190" {
            let target = catalog.ayahs.first { $0.surahID == 2 && $0.ayahNumber == 190 }!
            plan.startAyah = target.id; plan.unit = "ayah"; plan.amount = 1; plan.rhythm = "light"; plan.activeFrom = now
        } else if variant == "reference" {
            let target = catalog.ayahs.first { $0.surahID == 2 && $0.ayahNumber == 187 }!
            plan.startAyah = target.id; plan.unit = "ayah"; plan.amount = 2; plan.rhythm = "light"; plan.activeFrom = now
        } else if variant == "referencePartial" {
            let target = catalog.ayahs.first { $0.surahID == 2 && $0.ayahNumber == 177 }!
            plan.startAyah = target.id; plan.unit = "ayah"; plan.amount = 8; plan.rhythm = "light"; plan.activeFrom = now
        } else if variant == "referenceBoundary" {
            let target = catalog.ayahs.first { $0.surahID == 2 && $0.ayahNumber == 286 }!
            plan.startAyah = target.id; plan.unit = "ayah"; plan.amount = 2; plan.rhythm = "light"; plan.activeFrom = now
        } else if variant == "historyRoute" {
            let row = append(kind: "review", first: 1, last: 7, pages: [1], offset: -1, id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
            let mistake = MistakeEvent(); mistake.sessionID = row.id; mistake.ayahId = 2; mistake.wordIndex = 1; mistake.kind = "mistake"; mistake.at = row.endedAt; context.insert(mistake)
            let next = append(kind: "hifz", first: 8, last: 14, pages: [2], offset: -2, id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
            let nextMistake = MistakeEvent(); nextMistake.sessionID = next.id; nextMistake.ayahId = 10; nextMistake.wordIndex = 2; nextMistake.kind = "mistake"; nextMistake.at = next.endedAt; context.insert(nextMistake)
            historyRouteSessionID = row.id
        } else if variant == "dayCloseStart" {
            plan.unit = "ayah"; plan.amount = 7; plan.rhythm = "light"; plan.activeFrom = now
        } else if variant == "khatmaStart" {
            let finalAyah = catalog.ayahs(on: 604).last!.id
            plan.startAyah = finalAyah; plan.unit = "ayah"; plan.amount = 1; plan.rhythm = "light"; plan.activeFrom = now
            append(kind: "hifz", first: 1, last: finalAyah - 1, pages: Array(1...603), offset: -1)
        } else {
            let baseEnd = catalog.ayahs(on: 270).last!.id
            append(kind: "hifz", first: 1, last: baseEnd, pages: Array(1...270), offset: -70)
            for offset in [-63, -49, -19, -1] { append(kind: "review", first: 1, last: baseEnd, pages: Array(1...270), offset: offset) }
            for index in 0..<14 {
                let page = 271 + index
                append(kind: "hifz", first: catalog.ayahs(on: page).first!.id, last: catalog.ayahs(on: page).last!.id, pages: [page], offset: index - 14)
            }
        }
        if variant == "dayClose" || variant == "widgetReview" {
            let page = 285
            let hifz = append(kind: "hifz", first: catalog.ayahs(on: page).first!.id, last: catalog.ayahs(on: page).last!.id, pages: [page], offset: 0)
            hifz.endedAt = now.addingTimeInterval(-3600)
            try context.save()
            let snapshot = try QuranRepository(context: context, catalog: catalog).snapshot(at: now)
            let pages = snapshot.review.allPages
            let dayState = QuranDayState(); dayState.dayKey = today.description; dayState.testPages = snapshot.review.testPages; context.insert(dayState)
            if variant == "dayClose", let first = pages.min(), let last = pages.max() {
                let review = append(kind: "review", first: catalog.ayahs(on: first).first!.id, last: catalog.ayahs(on: last).last!.id, pages: pages, offset: 0)
                review.endedAt = now.addingTimeInterval(-1800)
            }
        }
        if variant == "drill" {
            // M2-V04: a word spot (Al-An'am 114, «مفصّلا») slipped before and today, a whole-ayah spot today, and an older spot one success from closing.
            plan.rhythm = "light"
            let anam114 = 789 + 114, kursi = 7 + 255, older = 7 + 20
            func event(_ ayah: Int, _ word: Int?, _ kind: String, _ session: HifzSession, hour: Double) {
                let row = MistakeEvent(); row.sessionID = session.id; row.ayahId = ayah; row.wordIndex = word; row.kind = kind
                row.at = session.endedAt.addingTimeInterval(hour * 60); context.insert(row)
            }
            let free = append(kind: "free", first: catalog.ayahs(on: 142).first!.id, last: catalog.ayahs(on: 142).last!.id, pages: [142], offset: 0)
            free.endedAt = now.addingTimeInterval(-3600)
            let sessions = try context.fetch(FetchDescriptor<HifzSession>())
            let longAgo = sessions.first { $0.dayKey == today.adding(days: -19).description }!, yesterday = sessions.first { $0.dayKey == today.adding(days: -1).description }!
            event(anam114, 9, "mistake", longAgo, hour: 1)
            event(anam114, 9, "mistake", free, hour: 1)
            event(kursi, nil, "mistake", free, hour: 2)
            event(older, 3, "mistake", longAgo, hour: 2)
            event(older, 3, "drillPass", yesterday, hour: 1)
        }
        let done = DeviceSetting(); done.key = "sys.onboardingCompleted"; done.valueJSON = Data("true".utf8); context.insert(done)
        try context.save()
        if let historyRouteSessionID { open(URL(string: "madar://quran/history/\(historyRouteSessionID.uuidString)")!) }
        else if let raw = env["MADAR_UI_QURAN_ROUTE"], let url = URL(string: raw) { open(url) }
    }
}
private extension TimeZone { static var riyadhZone: TimeZone { TimeZone(identifier: "Asia/Riyadh")! } }
#endif
