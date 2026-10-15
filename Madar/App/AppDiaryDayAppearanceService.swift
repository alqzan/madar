import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarPrayer

extension AppDiaryService {
    func appearance(_ day:GregorianDay) throws -> DiaryDayAppearance? {
        try authorizeRead()
        let now=clock(),repository=try PrayerRepository(context:ModelContext(app.container)),place=repository.place(at:now),civil=GregorianDay.containing(now,in:place.timeZone)
        guard let prayers=PrayerTimesEngine.calculate(day:civil,place:place,options:repository.options) else{return nil}
        return try .init(day:day,currentDay:currentDay(),now:now,prayers:prayers,source:HijriSource(rawValue:app.string("core.hijriSource")) ?? .ummAlQura,offset:Int(app.number("core.hijriOffset")))
    }
    func returnAfterAbsence(_ day:GregorianDay) throws -> GregorianDay? {
        try authorizeRead();guard day == (try currentDay()) else{return nil}
        let context=ModelContext(app.container)
        let entries=Self.visible(try context.fetch(FetchDescriptor<Entry>(predicate:#Predicate{$0.deletedAt==nil && $0.mergedInto==nil})))
        let intentions=try context.fetch(FetchDescriptor<Niyya>(predicate:#Predicate{$0.deletedAt==nil && $0.mergedInto==nil}))
        let keys=entries.filter{!$0.text.isEmpty || $0.mediaID != nil || !$0.attachmentMediaIDs.isEmpty}.map(\.dayKey)+intentions.map(\.dayKey)
        guard let latest=keys.compactMap({try? GregorianDay($0)}).filter({$0<=day}).max(),latest<day.adding(days:-1) else{return nil}
        return latest
    }
    func weekDays(ending day:GregorianDay) throws -> [DiaryDaySummary] {
        try authorizeRead();var calendar=Calendar(identifier:.gregorian);calendar.timeZone=app.activePlace.timeZone
        let weekday=calendar.component(.weekday,from:day.date(in:calendar.timeZone)),start=day.adding(days:-(weekday-diaryCalendar.weekStart+7)%7)
        return try archive().days.filter{$0.day>=start && $0.day<=day}.sorted{$0.day<$1.day}
    }
}
