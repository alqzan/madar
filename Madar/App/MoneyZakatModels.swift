import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

@MainActor struct MoneyHawl {
    var chosen: GregorianDay
    var anniversary: GregorianDay
    var followingAnniversary: GregorianDay
    var fraction: Double
    var daysLeft: Int
    static func read(_ key: String, at now: Date? = nil, app: AppSession) -> MoneyHawl? {
        guard key.hasPrefix("h:") else { return nil }
        let parts = key.dropFirst(2).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let instant = now ?? app.prayerNow()
        var calendar = Calendar(identifier: .islamicUmmAlQura); calendar.timeZone = app.activePlace.timeZone
        let offset = app.string("core.hijriSource") == "sighting" ? Int(app.number("core.hijriOffset")) : 0
        func day(_ year: Int) -> GregorianDay? {
            guard let month = calendar.date(from: DateComponents(year: year, month: parts[1], day: 1, hour: 12)), let range = calendar.range(of: .day, in: .month, for: month),
                  let date = calendar.date(from: DateComponents(year: year, month: parts[1], day: min(parts[2], range.count), hour: 12)) else { return nil }
            return GregorianDay.containing(date, in: app.activePlace.timeZone).adding(days: -offset)
        }
        let today = GregorianDay.containing(instant, in: app.activePlace.timeZone)
        guard let chosen = day(parts[0]) else { return nil }
        let thisYear = HijriCalendar.date(for: instant, timeZone: app.activePlace.timeZone, source: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura, sightingOffset: offset).year
        var year = max(parts[0] + 1, thisYear)
        guard var anniversary = day(year) else { return nil }
        if anniversary < today { year += 1; guard let next = day(year) else { return nil }; anniversary = next }
        guard let followingAnniversary = day(year + 1) else { return nil }
        let start = day(year-1) ?? chosen
        let total = max(1, MadarCalendarDays.distance(from: start, to: anniversary)), elapsed = MadarCalendarDays.distance(from: start, to: today)
        return .init(chosen: chosen, anniversary: anniversary, followingAnniversary: followingAnniversary,
                     fraction: min(1, max(0, Double(elapsed) / Double(total))), daysLeft: max(0, MadarCalendarDays.distance(from: today, to: anniversary)))
    }
}
extension AppMoneyService {
    func loadZakat(at now: Date? = nil) throws -> MoneyZakatReading {
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        return try MoneyRepository(context: ModelContext(app.container)).zakat(at: now ?? app.prayerNow())
    }
    func moneyInput(_ n: Int, exponent: Int? = nil) -> String {
        let exp = exponent ?? CurrencyExponents.specified.exponent(app.string("core.currency")) ?? 2
        var scale = 1; for _ in 0..<exp { scale *= 10 }
        let fraction = String(abs(n) % scale)
        return localizedRate(String(n / scale) + (exp > 0 ? "." + String(repeating: "0", count: max(0, exp - fraction.count)) + fraction : ""))
    }
}
