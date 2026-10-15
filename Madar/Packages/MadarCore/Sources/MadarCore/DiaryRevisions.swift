import Foundation

/// RD1. An entry freezes 24 hours after its stored day ends; the day ends where the next one starts under the
/// entry's own stored `dayPolicy` and zone, never the current settings.
public enum DiaryFreeze {
    public static func boundary(policy:String)->DayBoundary {DayBoundary(rawValue:String(policy.split(separator:"@").first ?? "")) ?? .midnight}
    /// `nextDay` is the prayer day of the civil day after `day` at the entry's place; midnight needs none.
    public static func dayEnd(day:GregorianDay,boundary:DayBoundary,timeZone:TimeZone,nextDay:PrayerDay?)->Date? {
        switch boundary {
        case .midnight: day.adding(days:1).date(in:timeZone)
        case .fajr: nextDay?.fajr
        case .maghrib: nextDay?.maghrib
        }
    }
    public static func freezesAt(day:GregorianDay,boundary:DayBoundary,timeZone:TimeZone,nextDay:PrayerDay?)->Date? {
        dayEnd(day:day,boundary:boundary,timeZone:timeZone,nextDay:nextDay)?.addingTimeInterval(24*3600)
    }
}

/// RD1 [DEFAULT]: an edit after the freeze is a new row naming the row it replaces; the original is never changed.
public struct DiaryRevisionLink:Sendable,Equatable {
    public let id:UUID
    public let replaces:UUID?
    public init(id:UUID,replaces:UUID?) {self.id=id;self.replaces=replaces}
}
public struct DiaryRevisionChains:Sendable,Equatable {
    /// Rows to show: every live row that no live revision replaces.
    public let heads:Set<UUID>
    /// For an edited head, the first text it grew from.
    public let originals:[UUID:UUID]
    public init(_ live:[DiaryRevisionLink]) {
        let replaced=Set(live.compactMap(\.replaces)),byID=Dictionary(live.map{($0.id,$0)},uniquingKeysWith:{a,_ in a})
        heads=Set(live.map(\.id)).subtracting(replaced)
        var originals:[UUID:UUID]=[:]
        for head in heads {
            var current=head,seen:Set<UUID>=[head]
            while let previous=byID[current]?.replaces,byID[previous] != nil,seen.insert(previous).inserted {current=previous}
            if current != head {originals[head]=current}
        }
        self.originals=originals
    }
}
