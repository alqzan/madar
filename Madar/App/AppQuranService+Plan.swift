import Foundation
import MadarCore
import MadarData
import MadarCommands
import MadarQuran

struct QuranUIPlanOverview: Sendable {
    var input: QuranUIPlanInput?; var forecasts: [String: QuranUIForecast]; var streak: String
    var days: [QuranUIYearDay]; var version: String
}
extension AppQuranService {
    func planInput() throws -> QuranUIPlanInput {
        let v = try snapshot(), row = HifzPlan()
        return QuranUIPlanInput(startAyah: v.plan?.plan.startAyah ?? row.startAyah,
            unit: QuranUIUnit(rawValue: v.plan?.plan.unit.rawValue ?? row.unit)!, amount: v.plan?.plan.amount ?? row.amount,
            rhythm: QuranUIRhythm(rawValue: v.plan?.plan.intensity.rawValue ?? row.rhythm)!, restDay: v.restDay.rawValue, missPolicy: v.plan?.missPolicy ?? row.missPolicy)
    }
    func planOverview() throws -> QuranUIPlanOverview {
        let v = try snapshot(), input = try planInput()
        var forecasts: [String: QuranUIForecast] = [:]
        if v.plan != nil { for level in QuranDayLevel.allCases { forecasts[level.rawValue] = try forecast(input, snapshot: v, using: level) } }
        let streak = QuranProgressEngine.streak(activities: v.activities, through: v.day.date, restDay: v.restDay)
        return QuranUIPlanOverview(input: v.plan == nil ? nil : input, forecasts: forecasts, streak: dayCount(streak.days), days: Array(try yearLog().days.suffix(28)), version: v.plan.map { "نسخة الخطة " + numerals.string($0.version) } ?? "لا خطة حفظ بعد")
    }
}
