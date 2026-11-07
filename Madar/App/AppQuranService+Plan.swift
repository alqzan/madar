import Foundation
import MadarCore
import MadarData
import MadarCommands
import MadarQuran

struct QuranUIPlanOverview: Sendable {
    var day: GregorianDay; var input: QuranUIPlanInput?; var forecasts: [String: QuranUIForecast]; var streak: String
    var days: [QuranUIYearDay]; var version: String
    var missPreviews: [String: [QuranUIMissPreviewDay]] = [:]
    var habitualAmount: String = ""
}
struct QuranUIMissPreviewDay: Identifiable, Sendable {
    var day: GregorianDay
    var base: Double
    var extra: Double
    var id: String { day.description }
}
extension AppQuranService {
    func planInput() throws -> QuranUIPlanInput {
        planInput(from: try snapshot())
    }
    func planInput(from v: QuranDataSnapshot) -> QuranUIPlanInput {
        let row = HifzPlan()
        return QuranUIPlanInput(startAyah: v.plan?.plan.startAyah ?? row.startAyah,
            unit: (QuranUIUnit(rawValue: v.plan?.plan.unit.rawValue ?? row.unit) ?? .page), amount: v.plan?.plan.amount ?? row.amount,
            rhythm: (QuranUIRhythm(rawValue: v.plan?.plan.intensity.rawValue ?? row.rhythm) ?? .balanced), restDay: v.restDay.rawValue, missPolicy: v.plan?.missPolicy ?? row.missPolicy)
    }
    func planOverview(at instant: Date? = nil) async throws -> QuranUIPlanOverview {
        let evaluatedAt = instant ?? clock()
        let (snapshots, catalog, preHifzDay) = try await snapshotsOffMain(at: evaluatedAt, hifzLevels: [nil], includePreHifzDaySnapshot: true)
        try Task.checkCancellation()
        guard let v = snapshots.first else { throw DataError.invalidValue("Quran snapshot") }
        let input = planInput(from: v)
        var forecasts: [String: QuranUIForecast] = [:]
        if v.plan != nil {
            for level in QuranDayLevel.allCases {
                try Task.checkCancellation()
                forecasts[level.rawValue] = try forecast(input, snapshot: v, using: level, at: evaluatedAt, preHifzDay: preHifzDay, resourceCatalog: catalog)
            }
        }
        let streak = QuranProgressEngine.streak(activities: v.activities, through: v.day.date, restDay: v.restDay)
        var result = QuranUIPlanOverview(day: v.day.date, input: v.plan == nil ? nil : input, forecasts: forecasts, streak: dayCount(streak.days), days: Array(try yearLog(from: v).days.suffix(28)), version: v.plan.map { "نسخة الخطة " + numerals.string($0.version) } ?? "لا خطة حفظ بعد")
        if v.plan != nil {
            result.missPreviews = try missedDayPreviews(input: input, startingOn: v.day.date, level: v.habitualHifzLevel)
            var habitual = input; habitual.amount *= v.habitualHifzLevel.hifzFactor
            result.habitualAmount = QuranPlanCopy.amount(habitual, digits: numerals)
        }
        return result
    }
    /// Canonical R18-Khitta labels this as an example. No allotment is written or added to a forecast.
    func missedDayPreviews(input: QuranUIPlanInput, startingOn day: GregorianDay, level: QuranDayLevel) throws -> [String: [QuranUIMissPreviewDay]] {
        let rest = QuranRestDay(rawValue: input.restDay) ?? .friday
        let base = input.amount * level.hifzFactor
        var origin = day.adding(days: -1)
        while rest.contains(origin) { origin = origin.adding(days: -1) }
        var dates: [GregorianDay] = [], cursor = day
        while dates.count < 4 {
            if !rest.contains(cursor) { dates.append(cursor) }
            cursor = cursor.adding(days: 1)
        }
        var previews: [String: [QuranUIMissPreviewDay]] = [:]
        for choice in [QuranMissedDayChoice.spread, .double, .skip] {
            let allotments = try QuranDailyPlanEngine.missedDayAllotments(originDay: origin, resolvingOn: day, choice: choice, missedAmount: base, restDay: rest)
            previews[choice.rawValue] = dates.map { target in
                .init(day: target, base: base, extra: allotments.filter { $0.dayKey == target }.reduce(0) { $0 + $1.amount })
            }
        }
        return previews
    }
}

/// Count grammar stays in the room's String Catalog, independent of the stored numeral preference.
enum QuranPlanCopy {
    static func amount(_ p: QuranUIPlanInput, digits: MadarNumberFormatter) -> String {
        if p.unit == .page, p.amount.isFinite, p.amount > 0, p.amount <= 6236,
           (p.amount * 4).rounded() == p.amount * 4, p.amount.rounded() != p.amount {
            let whole = Int(p.amount), quarter = Int((p.amount - Double(whole)) * 4)
            let fraction = ["", "ربع", "نصف", "ثلاثة أرباع"][quarter]
            if whole == 0 { return fraction + " وجه" }
            let pages = whole == 1 ? "وجه" : QuranDayCloseCopy.faces(whole, digits: digits)
            return pages + " و" + fraction
        }
        guard p.amount.rounded() == p.amount, p.amount >= 0, p.amount <= 6236 else {
            return "المقدار " + digits.localized(String(format: "%g", p.amount).replacingOccurrences(of: ".", with: "٫")) + " من وحدة " + p.unit.title
        }
        let count = Int(p.amount), formatted = digits.string(count)
        if p.unit == .page { return QuranDayCloseCopy.faces(count, digits: digits) }
        switch p.unit {
        case .ayah: return String(localized: "quran.planAyahs", defaultValue: "\(count) \(formatted)", table: "Quran", locale: Locale(identifier: "ar"))
        case .quarter: return String(localized: "quran.quarters", defaultValue: "\(count) \(formatted)", table: "Quran", locale: Locale(identifier: "ar"))
        case .half: return String(localized: "quran.halves", defaultValue: "\(count) \(formatted)", table: "Quran", locale: Locale(identifier: "ar"))
        case .page: return QuranDayCloseCopy.faces(count, digits: digits)
        }
    }
}
