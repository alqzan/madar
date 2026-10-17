import Foundation
import MadarCore
import MadarData

/// M5-X00 (owner 16 Oct): one reading of a recurring obligation's due days for every consumer (§8: one definition).
public extension Obligation {
    /// Bills and subscriptions repeat; loans and instalments live as InstallmentItem rows.
    var isRecurring: Bool { kind == "bill" || kind == "subscription" }
    /// The free interval and first due day; nil for a row saved before V7 (the monthly bill on `dueDay`).
    var recurrence: Recurrence? { Recurrence(every: repeatEvery, unit: repeatUnit, firstDayKey: firstDueDayKey) }
}

public enum ObligationSchedule {
    /// Due days of a flexible schedule in [start, end) that no linked confirmed movement settled. A movement settles the
    /// due day nearest its own civil day in `zone` (a tie goes to the earlier due day).
    public static func unpaid(_ recurrence: Recurrence, from start: GregorianDay, before end: GregorianDay, payments: [Date], zone: TimeZone) -> [GregorianDay] {
        recurrence.unpaid(from: start, before: end, paidOn: payments.map { GregorianDay.containing($0, in: zone) })
    }
}
