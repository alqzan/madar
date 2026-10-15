import Foundation

public struct DiaryDayAppearance:Sendable {
    public let friday:Bool
    public let weekAvailable:Bool
    public let night:Bool
    public let hijriDisplayDay:GregorianDay
    public let ramadanDay:Int?
    public let iftarAt:Date?
    public init(day:GregorianDay,currentDay:GregorianDay,now:Date,prayers:PrayerDay,source:HijriSource = .ummAlQura,offset:Int=0) {
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=prayers.place.timeZone
        friday=calendar.component(.weekday,from:day.date(in:prayers.place.timeZone).addingTimeInterval(12*3600))==6
        weekAvailable=friday && (day<currentDay || now>=prayers.asr)
        let live=day==currentDay
        night=live && (now>=prayers.maghrib || now<prayers.fajr)
        hijriDisplayDay=live ? prayers.day.adding(days:now>=prayers.maghrib ? 1:0):day
        let hijri=HijriCalendar.date(for:hijriDisplayDay.date(in:prayers.place.timeZone).addingTimeInterval(12*3600),timeZone:prayers.place.timeZone,source:source,sightingOffset:offset)
        ramadanDay=hijri.month==9 ? hijri.day:nil
        iftarAt=live && hijri.month==9 && now<prayers.maghrib ? prayers.maghrib:nil
    }
}
