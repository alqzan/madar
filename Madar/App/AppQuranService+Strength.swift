import Foundation
import MadarData
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

private struct QuranStrengthProjection: Sendable {
    struct Face: Sendable { var id: Int; var strength: Int; var reviewed: GregorianDay; var due: GregorianDay; var far: Bool }
    struct Part: Sendable {
        var id: Int; var strength: Int; var faces: [Face]; var raised: [Int]; var projected: Int?; var scheduled: Bool
    }
    struct RecoveryOption: Sendable { var days: Int; var daily: Int; var end: GregorianDay }
    var mean: Int?
    var parts: [Part]
    var far: Int
    var options: [RecoveryOption]
    var hasRecovery: Bool
    var activeEnd: GregorianDay?
    var activeShare: Int
    var remaining: Int
}

extension AppQuranService {
    func strengthBoard() async throws -> QuranUIStrengthBoard {
        let container = app.container, generation = app.storeGeneration
        let (snapshots, catalog, _) = try await snapshotsOffMain(at: clock(), hifzLevels: [nil])
        try Task.checkCancellation()
        guard let snapshot = snapshots.first else { throw DataError.invalidValue("Quran strength snapshot") }
        guard !app.maintenanceInProgress, app.storeGeneration == generation, app.container === container else {
            throw CancellationError()
        }
        let projectionTask = Task.detached(priority: .userInitiated) {
            try Self.projectStrengthBoard(snapshot: snapshot, catalog: catalog)
        }
        let projection = try await withTaskCancellationHandler {
            try await projectionTask.value
        } onCancel: {
            projectionTask.cancel()
        }
        try Task.checkCancellation()
        guard !app.maintenanceInProgress, app.storeGeneration == generation, app.container === container else {
            throw CancellationError()
        }

        var dates: [GregorianDay: String] = [:]
        func dateLabel(_ day: GregorianDay) -> String {
            if let label = dates[day] { return label }
            let label = displayDate(day)
            dates[day] = label
            return label
        }
        let parts = projection.parts.map { part in
            QuranUIStrengthPart(
                id: part.id, title: "الجزء " + numerals.string(part.id), strength: part.strength,
                faces: part.faces.map {
                    QuranUIStrengthFace(
                        id: $0.id, strength: $0.strength, reviewed: dateLabel($0.reviewed),
                        due: dateLabel($0.due), far: $0.far)
                }, raised: part.raised, projected: part.projected, scheduled: part.scheduled)
        }
        let options = projection.options.map { option in
            QuranUIRecoveryOption(
                id: option.days, title: option.days == 5 ? "خمسة أيام" : option.days == 7 ? "أسبوع" : "أسبوعان",
                daily: option.daily, end: dateLabel(option.end))
        }
        let active: String?
        if projection.hasRecovery {
            if projection.remaining == 0 { active = "اكتمل الاسترداد" }
            else if let end = projection.activeEnd { active = "ينتهي في " + dateLabel(end) }
            else { active = nil }
        } else {
            active = nil
        }
        return QuranUIStrengthBoard(
            mean: projection.mean, parts: parts, far: projection.far, options: options, active: active,
            activeShare: projection.activeShare, remaining: projection.remaining)
    }

    nonisolated private static func projectStrengthBoard(
        snapshot v: QuranDataSnapshot, catalog: QuranResourceCatalog
    ) throws -> QuranStrengthProjection {
        try Task.checkCancellation()
        let tomorrow = v.day.date.adding(days: 1)
        let scheduled = Set(v.allotments.filter { $0.origin == .raise && $0.dayKey == tomorrow }.flatMap(\.pages))
        let parts = try catalog.juzCycleSegments().compactMap { segment -> QuranStrengthProjection.Part? in
            try Task.checkCancellation()
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
            return QuranStrengthProjection.Part(
                id: segment.number, strength: Int(mean.rounded()),
                faces: pages.map {
                    QuranStrengthProjection.Face(
                        id: $0.page, strength: $0.strength, reviewed: $0.lastReviewed,
                        due: $0.nextDue, far: $0.isFar)
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
        let options = try [5, 7, 14].map { days -> QuranStrengthProjection.RecoveryOption in
            let plan = try QuranRecoveryPlan.starting(on: v.day.date, days: days, candidates: v.pages)
            return QuranStrengthProjection.RecoveryOption(
                days: days, daily: plan.share(on: v.day.date, reviewedOn: reviewed).count,
                end: v.day.date.adding(days: days - 1))
        }
        let remaining =
            v.recovery.map { p in p.pages.filter { reviewed[$0].map { $0 < p.startDayKey } ?? true }.count } ?? 0
        return QuranStrengthProjection(
            mean: QuranProgressEngine.meanStrength(v.pages).map { Int($0.rounded()) }, parts: parts, far: far,
            options: options, hasRecovery: v.recovery != nil,
            activeEnd: v.recovery.map { $0.startDayKey.adding(days: $0.days - 1) },
            activeShare: v.recovery?.share(on: v.day.date, reviewedOn: reviewed).count ?? 0, remaining: remaining)
    }
}
