import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarPrayer

/// M3-V15 · the diary only reads the shared §8 Trip. Prayer owns the arrival question and its undo (RP7).
struct DiaryTravelPage:Equatable {
    let tripID:UUID
    let city:String
    let homeName:String
    let kilometres:Int
    let arrival:GregorianDay
    let number:Int
    let current:Bool
    let returned:Bool
}
struct DiaryTravelStamp:Identifiable,Equatable {
    let id:UUID
    let city:String
    let arrival:GregorianDay
    let departure:GregorianDay?
}
/// §7.3 «لحظة عودة تطوي الرحلة ظرفًا»: shown on the home page of the return day.
struct DiaryTravelReturn:Equatable {
    let tripID:UUID
    let city:String
    let days:Int
    let kilometres:Int
}

extension AppDiaryService {
    private func travelSpans() throws -> (repository:PrayerRepository,spans:[(Trip,DiaryTravelSpan)]) {
        try authorizeRead()
        let context=ModelContext(app.container),repository=try PrayerRepository(context:context)
        let boundary=DayBoundary(rawValue:app.string("core.dayStart")) ?? .fajr
        let rows=try context.fetch(FetchDescriptor<Trip>(predicate:#Predicate{$0.deletedAt==nil && $0.mergedInto==nil && !$0.dismissed}))
        func key(_ instant:Date,_ place:ActivePlace,_ options:PrayerCalculationOptions) throws -> GregorianDay {
            let civil=GregorianDay.containing(instant,in:place.timeZone)
            let days=[civil.adding(days:-1),civil].compactMap{PrayerTimesEngine.calculate(day:$0,place:place,options:options)}
            return try MadarDay.resolve(instant:instant,place:place,boundary:boundary,prayerDays:days).date
        }
        let spans:[(Trip,DiaryTravelSpan)]=try rows.compactMap{row in
            guard let start=row.start,let place=try? ActivePlace(latitude:row.lat,longitude:row.lon,timeZoneID:row.tzID) else{return nil}
            return (row,.init(id:row.id,city:row.city,arrival:try key(start,place,repository.tripOptions),departure:try row.end.map{try key($0,repository.home,repository.options)}))
        }
        return (repository,spans)
    }
    func travel(_ day:GregorianDay) throws -> DiaryTravelPage? {
        let (repository,spans)=try travelSpans()
        guard let span=DiaryTravelCalendar.span(covering:day,in:spans.map(\.1)),let row=spans.first(where:{$0.1.id==span.id})?.0,
              let place=try? ActivePlace(latitude:row.lat,longitude:row.lon,timeZoneID:row.tzID) else{return nil}
        let km=row.homeKm ?? DiaryTravelCalendar.kilometres(from:repository.home,to:place)
        return .init(tripID:row.id,city:row.city.isEmpty ? "مدينة السفر":row.city,homeName:repository.placeName,kilometres:Int(km.rounded()),arrival:span.arrival,number:span.number(of:day),current:repository.activeTrip(at:clock())?.id==row.id,returned:row.end != nil)
    }
    func travelStamps() throws -> [DiaryTravelStamp] {
        try travelSpans().spans.map{.init(id:$0.1.id,city:$0.1.city.isEmpty ? "مدينة السفر":$0.1.city,arrival:$0.1.arrival,departure:$0.1.departure)}.sorted{$0.arrival>$1.arrival}
    }
    /// Every stored day a trip covers, up to today for an open trip («تقويم السفر»: travel days framed everywhere).
    func travelDays() throws -> Set<GregorianDay> {
        let today=GregorianDay.containing(clock(),in:app.activePlace.timeZone)
        var days:Set<GregorianDay>=[]
        for (_,span) in try travelSpans().spans {
            var day=span.arrival
            while span.covers(day),day<=today,days.count<5000 {days.insert(day);day=day.adding(days:1)}
        }
        return days
    }
    func travelReturn(_ day:GregorianDay) throws -> DiaryTravelReturn? {
        let (repository,spans)=try travelSpans()
        guard let (row,span)=spans.filter({$0.1.departure==day && $0.1.arrival<day}).max(by:{$0.1.arrival<$1.1.arrival}),
              let place=try? ActivePlace(latitude:row.lat,longitude:row.lon,timeZoneID:row.tzID) else{return nil}
        let km=row.homeKm ?? DiaryTravelCalendar.kilometres(from:repository.home,to:place)
        return .init(tripID:row.id,city:row.city.isEmpty ? "مدينة السفر":row.city,days:max(1,span.number(of:day)-1),kilometres:Int(km.rounded()))
    }
}
