import Foundation
import MadarCore
import MadarQuran
import MadarCommands

struct QuranUIStrengthFace: Identifiable, Sendable {
    var id: Int; var strength: Int; var reviewed: String; var due: String; var far: Bool
}
struct QuranUIStrengthPart: Identifiable, Sendable {
    var id: Int; var title: String; var strength: Int; var faces: [QuranUIStrengthFace]; var raised: [Int];
    var projected: Int?; var scheduled: Bool
}
struct QuranUIRecoveryOption: Identifiable, Sendable { var id: Int; var title: String; var daily: Int; var end: String }
struct QuranUIStrengthBoard: Sendable {
    var mean: Int?; var parts: [QuranUIStrengthPart]; var far: Int; var options: [QuranUIRecoveryOption];
    var active: String?; var activeShare: Int; var remaining: Int
}
extension AppQuranService {
    func strengthBoard() throws -> QuranUIStrengthBoard {
        let v = try snapshot(), catalog = try QuranResources.catalog(), tomorrow = v.day.date.adding(days: 1)
        let scheduled = Set(v.allotments.filter { $0.origin == .raise && $0.dayKey == tomorrow }.flatMap(\.pages))
        let parts = try catalog.juzCycleSegments().compactMap { segment -> QuranUIStrengthPart? in
            let pages = v.pages.filter { page in
                catalog.ayahs(on: page.page).contains { segment.ayahs.first <= $0.id && $0.id <= segment.ayahs.last }
            }
            guard let mean = QuranProgressEngine.meanStrength(pages) else { return nil }
            let raised = try QuranRecoveryEngine.raise(on: v.day.date, pages: pages).pages
            let projected = try pages.map { p -> QuranPlanningPage in
                if raised.contains(p.page) {
                    let memory = v.memories[p.page]
                    let interval = QuranReviewEngine.nextInterval(
                        previousDays: memory?.intervalDays ?? 1, rating: .good,
                        preset: v.plan?.plan.intensity.preset ?? .balanced, ease: memory?.ease ?? 1,
                        elapsedDays: p.lastReviewed.quranDistance(to: tomorrow))
                    return try QuranPlanningPage(
                        page: p.page, lastReviewed: tomorrow, nextDue: tomorrow.adding(days: interval), grade: .good,
                        today: tomorrow)
                }
                return try QuranPlanningPage(
                    page: p.page, lastReviewed: p.lastReviewed, nextDue: p.nextDue, grade: p.grade, today: tomorrow)
            }
            return QuranUIStrengthPart(
                id: segment.number, title: "الجزء " + numerals.string(segment.number), strength: Int(mean.rounded()),
                faces: pages.map {
                    QuranUIStrengthFace(
                        id: $0.page, strength: $0.strength, reviewed: displayDate($0.lastReviewed),
                        due: displayDate($0.nextDue), far: $0.isFar)
                }, raised: raised,
                projected: raised.isEmpty ? nil : QuranProgressEngine.meanStrength(projected).map { Int($0.rounded()) },
                scheduled: !raised.isEmpty && Set(raised).isSubset(of: scheduled))
        }
        var reviewed: [Int: GregorianDay] = [:]
        for session in v.sessions where [.review, .free, .qiyam].contains(session.kind) {
            for grade in session.grades {
                reviewed[grade.page] = max(reviewed[grade.page] ?? session.dayKey, session.dayKey)
            }
        }
        let far = v.pages.filter(\.isFar).count
        let options = try [5, 7, 14].map { days in
            let plan = try QuranRecoveryPlan.starting(on: v.day.date, days: days, candidates: v.pages)
            return QuranUIRecoveryOption(
                id: days, title: days == 5 ? "خمسة أيام" : days == 7 ? "أسبوع" : "أسبوعان",
                daily: plan.share(on: v.day.date, reviewedOn: reviewed).count,
                end: displayDate(v.day.date.adding(days: days - 1)))
        }
        let remaining =
            v.recovery.map { p in p.pages.filter { reviewed[$0].map { $0 < p.startDayKey } ?? true }.count } ?? 0
        let active = v.recovery.map { p in
            remaining == 0 ? "اكتمل الاسترداد" : "ينتهي في " + displayDate(p.startDayKey.adding(days: p.days - 1))
        }
        return QuranUIStrengthBoard(
            mean: QuranProgressEngine.meanStrength(v.pages).map { Int($0.rounded()) }, parts: parts, far: far,
            options: options, active: active,
            activeShare: v.recovery?.share(on: v.day.date, reviewedOn: reviewed).count ?? 0, remaining: remaining)
    }
}
