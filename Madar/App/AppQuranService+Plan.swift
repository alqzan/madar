import Foundation
import MadarCore
import MadarData
import MadarCommands
import MadarQuran

struct QuranUIPlanOverview: Sendable {
    var day: GregorianDay; var input: QuranUIPlanInput?; var forecasts: [String: QuranUIForecast]; var streak: String
    var days: [QuranUIYearDay]; var version: String
}
extension AppQuranService {
    func planInput() throws -> QuranUIPlanInput {
        planInput(from: try snapshot())
    }
    func planInput(from v: QuranDataSnapshot) -> QuranUIPlanInput {
        let row = HifzPlan()
        return QuranUIPlanInput(startAyah: v.plan?.plan.startAyah ?? row.startAyah,
            unit: QuranUIUnit(rawValue: v.plan?.plan.unit.rawValue ?? row.unit)!, amount: v.plan?.plan.amount ?? row.amount,
            rhythm: QuranUIRhythm(rawValue: v.plan?.plan.intensity.rawValue ?? row.rhythm)!, restDay: v.restDay.rawValue, missPolicy: v.plan?.missPolicy ?? row.missPolicy)
    }
    func planOverview(at instant: Date? = nil) throws -> QuranUIPlanOverview {
        let evaluatedAt = instant ?? clock()
        let v = try repository().snapshot(at: evaluatedAt), input = planInput(from: v)
        var forecasts: [String: QuranUIForecast] = [:]
        if v.plan != nil { for level in QuranDayLevel.allCases { forecasts[level.rawValue] = try forecast(input, snapshot: v, using: level, at: evaluatedAt) } }
        let streak = QuranProgressEngine.streak(activities: v.activities, through: v.day.date, restDay: v.restDay)
        return QuranUIPlanOverview(day: v.day.date, input: v.plan == nil ? nil : input, forecasts: forecasts, streak: dayCount(streak.days), days: Array(try yearLog(at: evaluatedAt).days.suffix(28)), version: v.plan.map { "نسخة الخطة " + numerals.string($0.version) } ?? "لا خطة حفظ بعد")
    }
}

/// Count grammar stays in the room's String Catalog, independent of the stored numeral preference.
enum QuranPlanCopy {
    static func amount(_ p: QuranUIPlanInput, digits: MadarNumberFormatter) -> String {
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
