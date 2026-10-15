import Foundation

/// §7.3 travel diary over the shared §8 Trip. `arrival` and `departure` are stored-day keys resolved in the
/// trip's own zone; the return day itself belongs to home unless the trip also began that day.
public struct DiaryTravelSpan:Sendable,Equatable {
    public let id:UUID
    public let city:String
    public let arrival:GregorianDay
    public let departure:GregorianDay?
    public init(id:UUID,city:String,arrival:GregorianDay,departure:GregorianDay?) {self.id=id;self.city=city;self.arrival=arrival;self.departure=departure}
    public func covers(_ day:GregorianDay)->Bool {day==arrival || day>arrival && departure.map{day<$0} != false}
    /// Day one is the arrival day.
    public func number(of day:GregorianDay)->Int {
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone = .gmt
        return (calendar.dateComponents([.day],from:arrival.date(in:.gmt),to:day.date(in:.gmt)).day ?? 0)+1
    }
}

public enum DiaryTravelCalendar {
    /// The latest arrival wins when spans touch (one open Trip invariant, §10).
    public static func span(covering day:GregorianDay,in spans:[DiaryTravelSpan])->DiaryTravelSpan? {
        spans.filter{$0.covers(day)}.max{$0.arrival==$1.arrival ? $0.id.uuidString<$1.id.uuidString:$0.arrival<$1.arrival}
    }
    private static let ordinals=["الأول","الثاني","الثالث","الرابع","الخامس","السادس","السابع","الثامن","التاسع","العاشر"]
    /// «اليوم الثاني» for day 2; past ten the number is written as digits by the caller.
    public static func ordinal(_ number:Int)->String? {(1...ordinals.count).contains(number) ? ordinals[number-1]:nil}
    /// Great-circle distance used only when a trip has no stored homeKm.
    public static func kilometres(from a:ActivePlace,to b:ActivePlace)->Double {
        let r=6371.0,p1=a.latitude * .pi/180,p2=b.latitude * .pi/180,dp=p2-p1,dl=(b.longitude-a.longitude) * .pi/180
        let h=sin(dp/2)*sin(dp/2)+cos(p1)*cos(p2)*sin(dl/2)*sin(dl/2)
        return 2*r*asin(min(1,sqrt(h)))
    }
}
