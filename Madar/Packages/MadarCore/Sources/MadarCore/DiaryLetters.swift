import Foundation

/// §7.3 N04 letters. A closed trigger list; only an event after the writing counts. State never moves backwards:
/// sealed → eligible → opened, or sealed → orphaned when the named target is gone (it never opens by itself).
public enum DiaryLetterTrigger:String,CaseIterable,Codable,Sendable {
    // bookFinished (M6) and khatma (no stored completion event yet) are not offered in v1.
    case date,hijriDate,tripStart,tripEnd,projectFinished,ramadanStart
}
public enum DiaryLetterState:String,Codable,Sendable {case sealed,eligible,opened,orphaned}

public struct DiaryLetterWorld:Sendable {
    public struct Trip:Sendable {public let id:UUID;public let start:Date;public let end:Date?;public let live:Bool
        public init(id:UUID,start:Date,end:Date?,live:Bool){self.id=id;self.start=start;self.end=end;self.live=live}}
    public struct Project:Sendable {public let id:UUID;public let finishedAt:Date?;public let live:Bool
        public init(id:UUID,finishedAt:Date?,live:Bool){self.id=id;self.finishedAt=finishedAt;self.live=live}}
    public let now:Date
    /// The current Madar day and its Hijri date under the current Hijri settings.
    public let today:GregorianDay
    public let hijriToday:HijriDate
    /// Trips the owner did not dismiss («لست مسافرًا») are `live`; deleted or dismissed ones are not.
    public let trips:[Trip]
    public let projects:[Project]
    public init(now:Date,today:GregorianDay,hijriToday:HijriDate,trips:[Trip],projects:[Project]) {self.now=now;self.today=today;self.hijriToday=hijriToday;self.trips=trips;self.projects=projects}
}

public struct DiaryLetterFacts:Sendable {
    public let writtenAt:Date
    public let trigger:DiaryLetterTrigger
    /// date: the chosen Madar day; hijriDate/ramadanStart: "yyyy-MM-dd" Hijri.
    public let openDay:GregorianDay?
    public let hijriValue:String?
    public let target:UUID?
    public let state:DiaryLetterState
    public init(writtenAt:Date,trigger:DiaryLetterTrigger,openDay:GregorianDay?,hijriValue:String?,target:UUID?,state:DiaryLetterState) {
        self.writtenAt=writtenAt;self.trigger=trigger;self.openDay=openDay;self.hijriValue=hijriValue;self.target=target;self.state=state
    }
}

public enum DiaryLetters {
    public static func hijriKey(_ h:HijriDate)->String {String(format:"%04d-%02d-%02d",h.year,h.month,h.day)}
    /// The first 1 Ramadan after the writing: next year's when written in or after Ramadan.
    public static func nextRamadan(after written:HijriDate)->String {hijriKey(.init(year:written.month>=9 ? written.year+1:written.year,month:9,day:1))}

    /// Evaluates one sealed letter. Any other state is returned unchanged: nothing moves backwards.
    public static func evaluate(_ letter:DiaryLetterFacts,in world:DiaryLetterWorld)->DiaryLetterState {
        guard letter.state == .sealed else {return letter.state}
        func after(_ date:Date?)->Bool {date.map{$0>letter.writtenAt && $0<=world.now} == true}
        switch letter.trigger {
        case .date: return letter.openDay.map{world.today>=$0} == true ? .eligible:.sealed
        case .hijriDate,.ramadanStart: return letter.hijriValue.map{hijriKey(world.hijriToday)>=$0} == true ? .eligible:.sealed
        case .tripStart,.tripEnd:
            if let target=letter.target {
                guard let trip=world.trips.first(where:{$0.id==target}),trip.live else {return .orphaned}
                return after(letter.trigger == .tripStart ? trip.start:trip.end) ? .eligible:.sealed
            }
            return world.trips.contains{$0.live && after(letter.trigger == .tripStart ? $0.start:$0.end)} ? .eligible:.sealed
        case .projectFinished:
            guard let target=letter.target,let project=world.projects.first(where:{$0.id==target}),project.live else {return .orphaned}
            return after(project.finishedAt) ? .eligible:.sealed
        }
    }
}

/// N04 projects: the keyword is a suggestion, never an automatic link. Whole-word match after Arabic normalisation,
/// allowing only the joined conjunction «و» before the word.
public enum DiaryProjectKeyword {
    private static func words(_ value:String)->[String] {
        DiarySearchParser.normalize(value).components(separatedBy:CharacterSet.letters.union(.decimalDigits).inverted).filter{!$0.isEmpty}
    }
    public static func mentions(_ text:String,keyword:String)->Bool {
        let key=words(keyword);guard !key.isEmpty else {return false}
        let found=words(text);guard found.count>=key.count else {return false}
        for start in 0...(found.count-key.count) {
            var slice=Array(found[start..<start+key.count])
            if slice[0] != key[0],slice[0]=="و"+key[0] {slice[0]=key[0]}
            if slice==key {return true}
        }
        return false
    }
}
