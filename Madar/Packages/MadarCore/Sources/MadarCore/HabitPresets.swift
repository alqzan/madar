import Foundation

/// Ready-made rules for the habits room (owner, 17 Nov 2026). Pure: they only fill a `HabitRule`;
/// the editor shows the result and the user saves it like any other habit.
public enum HabitPresets {
    public static let mondayThursdayFastName = "صيام الإثنين والخميس"

    /// Weekly, designated days Monday and Thursday (Foundation weekdays 2 and 5, Sunday = 1).
    /// The question window is anchored at Fajr and opens 8 hours before it, i.e. the evening before the fast,
    /// so the reminder arrives the night before and never inside a prayer sanctity window (the guard still clamps it).
    /// It closes 12 hours after Fajr.
    public static func mondayThursdayFast(from day: GregorianDay) -> HabitRule {
        var rule = HabitRule(effectiveFrom: day)
        rule.frequency = .weekly; rule.measure = .once; rule.unit = nil; rule.target = 1
        rule.weekdays = [2, 5]
        rule.windowAnchor = .fajr; rule.windowStart = -480; rule.windowEnd = 720
        return rule
    }

    // MARK: Ramadan (owner, 17 Nov 2026, idea 16)
    public static let ramadanQiyamName = "قيام رمضان"
    public static let ramadanSuhoorName = "ورد ما قبل السحور"

    /// True on a day of the Hijri month 9 in the given calendar (the room offers its Ramadan presets only then).
    public static func isRamadan(_ day: GregorianDay, days: MadarCalendarDays) -> Bool { days.hijri(day).month == 9 }

    /// Taraweeh and night prayer: daily, a window from 90 minutes after Isha to 6 hours after it, so the question follows Taraweeh.
    public static func ramadanQiyam(from day: GregorianDay) -> HabitRule {
        var rule = HabitRule(effectiveFrom: day)
        rule.frequency = .daily; rule.measure = .once; rule.windowAnchor = .isha; rule.windowStart = 90; rule.windowEnd = 360
        return rule
    }
    /// A reading before the fast begins: daily, the 90 minutes before Fajr (Suhoor).
    public static func ramadanSuhoor(from day: GregorianDay) -> HabitRule {
        var rule = HabitRule(effectiveFrom: day)
        rule.frequency = .daily; rule.measure = .once; rule.windowAnchor = .fajr; rule.windowStart = -90; rule.windowEnd = 0
        return rule
    }

    /// The presets that fill the editor with a name and a rule instead of a linked source, by the room's preset id.
    public static func named(_ id: String, from day: GregorianDay) -> (name: String, rule: HabitRule)? {
        switch id {
        case "preset.fast": (mondayThursdayFastName, mondayThursdayFast(from: day))
        case "preset.ramadanQiyam": (ramadanQiyamName, ramadanQiyam(from: day))
        case "preset.ramadanSuhoor": (ramadanSuhoorName, ramadanSuhoor(from: day))
        default: nil
        }
    }
}
