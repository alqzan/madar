import Foundation

public struct DiaryMemoryDay: Equatable, Sendable {
    public let day: GregorianDay
    public let hasWriting: Bool
    public let hasPhoto: Bool
    public let dayOne: Bool
    public let hidden: Bool
    public init(day: GregorianDay, hasWriting: Bool, hasPhoto: Bool = false, dayOne: Bool = false, hidden: Bool = false) {
        self.day = day; self.hasWriting = hasWriting; self.hasPhoto = hasPhoto; self.dayOne = dayOne; self.hidden = hidden
    }
}
public enum DiaryMemoryMatch: String, Sendable { case gregorian, hijri, echo, random, firstDay }
public struct DiaryMemorySelection: Equatable, Sendable {
    public let days: [GregorianDay]
    public let match: DiaryMemoryMatch
}

public enum DiaryEchoDistance: String, CaseIterable, Sendable {
    case week = "1w", month = "1m", threeMonths = "3m", sixMonths = "6m", year = "1y", twoYears = "2y", threeYears = "3y"
    public var title: String {
        switch self { case .week: "أسبوع"; case .month: "شهر"; case .threeMonths: "٣ أشهر"; case .sixMonths: "٦ أشهر"; case .year: "سنة"; case .twoYears: "سنتان"; case .threeYears: "٣ سنوات" }
    }
    var component: Calendar.Component { switch self { case .week: .day; case .month, .threeMonths, .sixMonths: .month; default: .year } }
    var amount: Int { switch self { case .week: 7; case .month, .year: 1; case .threeMonths, .threeYears: 3; case .sixMonths: 6; case .twoYears: 2 } }
}
public struct DiaryEcho: Equatable, Sendable {
    public let distance: DiaryEchoDistance
    public let target: GregorianDay
    public let day: GregorianDay?
}

/// N03: selection changes presentation only. Every candidate retains its original stored day.
public enum DiaryMemories {
    /// The seven v1 distances are fixed (RA8). Nearby matches always keep the actual stored date.
    public static func echoes(days: [DiaryMemoryDay], today: GregorianDay, includeDayOne: Bool = true, zone: TimeZone) -> [DiaryEcho] {
        let candidates = Set(days.filter { $0.day < today && !$0.hidden && ($0.hasWriting || $0.hasPhoto) && (includeDayOne || !$0.dayOne) }.map(\.day))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return DiaryEchoDistance.allCases.compactMap { distance in
            guard let date = calendar.date(byAdding: distance.component, value: -distance.amount, to: today.date(in: zone)) else { return nil }
            let target = GregorianDay.containing(date, in: zone)
            let nearest = candidates.compactMap { day -> (GregorianDay, Int)? in
                let gap = abs(calendar.dateComponents([.day], from: target.date(in: zone), to: day.date(in: zone)).day ?? Int.max)
                return gap <= 3 ? (day, gap) : nil
            }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }.first?.0
            return .init(distance: distance, target: target, day: nearest)
        }
    }

    public static func select(days: [DiaryMemoryDay], today: GregorianDay, match: FirstCalendar = .gregorian,
                              includeDayOne: Bool = true, yearsBack: Int? = nil, noMemory: String = "nearestEcho",
                              zone: TimeZone, hijriSource: HijriSource = .ummAlQura, sightingOffset: Int = 0) -> DiaryMemorySelection {
        let eligible = days.filter { $0.day < today && !$0.hidden && ($0.hasWriting || $0.hasPhoto) && (includeDayOne || !$0.dayOne) }
        let candidates = Array(Set(eligible.map(\.day))).sorted(by: >)
        func hijri(_ day: GregorianDay) -> HijriDate {
            HijriCalendar.date(for: day.date(in: zone).addingTimeInterval(12 * 3600), timeZone: zone, source: hijriSource, sightingOffset: sightingOffset)
        }
        let currentHijri = hijri(today)
        func exact(_ calendar: FirstCalendar) -> [GregorianDay] {
            candidates.filter { day in
                switch calendar {
                case .gregorian:
                    let age = today.year - day.year
                    guard age > 0, yearsBack.map({ age <= $0 }) ?? true, day.month == today.month else { return false }
                    let leapMemory = day.month == 2 && day.day == 29 && today.day == 28 && (try? GregorianDay(year: today.year, month: 2, day: 29)) == nil
                    return day.day == today.day || leapMemory
                case .hijri:
                    let old = hijri(day), age = currentHijri.year - old.year
                    guard age > 0, yearsBack.map({ age <= $0 }) ?? true, old.month == currentHijri.month else { return false }
                    var cal = Calendar(identifier: .islamicUmmAlQura); cal.timeZone = zone
                    let offset = hijriSource == .sighting ? min(2, max(-2, sightingOffset)) : 0
                    let instant = today.date(in: zone).addingTimeInterval(Double(12 * 3600 + offset * 86400))
                    let monthDays = cal.range(of: .day, in: .month, for: instant)?.count
                    return old.day == currentHijri.day || old.day == 30 && currentHijri.day == 29 && monthDays == 29
                }
            }
        }
        let primary = exact(match)
        if !primary.isEmpty { return .init(days: primary, match: match == .gregorian ? .gregorian : .hijri) }
        let other: FirstCalendar = match == .gregorian ? .hijri : .gregorian
        let secondary = exact(other)
        if !secondary.isEmpty { return .init(days: secondary, match: other == .gregorian ? .gregorian : .hijri) }
        if noMemory == "todayPhoto" { return .init(days: [], match: .firstDay) }
        if noMemory == "random", !candidates.isEmpty {
            // Stable for this day; opening/relaunching never shuffles the owner's page.
            let index = (today.year * 372 + today.month * 31 + today.day) % candidates.count
            return .init(days: [candidates[index]], match: .random)
        }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        for (unit, count) in [(Calendar.Component.day, 7), (.month, 1), (.month, 6)] {
            guard let target = cal.date(byAdding: unit, value: -count, to: today.date(in: zone)) else { continue }
            let targetDay = GregorianDay.containing(target, in: zone)
            let near = candidates.compactMap { day -> (GregorianDay, Int)? in
                let distance = abs(cal.dateComponents([.day], from: targetDay.date(in: zone), to: day.date(in: zone)).day ?? Int.max)
                return distance <= 3 ? (day, distance) : nil
            }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
            if let first = near.first { return .init(days: [first.0], match: .echo) }
        }
        return .init(days: [], match: .firstDay)
    }
}
