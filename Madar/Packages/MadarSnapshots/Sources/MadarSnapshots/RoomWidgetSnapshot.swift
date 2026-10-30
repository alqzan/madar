import Foundation

public enum BuiltRoomWidget:String,CaseIterable,Codable,Sendable {
    case habits, year, upcoming, diaryWrite, money, mihbara
    public var title:String {switch self{case .money:"المال";case .habits:"العادات";case .year:"السنة";case .upcoming:"الأيام القادمة";case .diaryWrite:"سطر سريع";case .mihbara:"المحبرة"}}
    public var glyph:String {switch self{case .money:"MadarMoney";case .habits:"MadarHabits";case .year:"MadarYear";case .upcoming:"MadarUpcoming";case .diaryWrite:"MadarDiary";case .mihbara:"books.vertical"}}
    public var route:String {switch self{case .money:"madar://mal";case .habits:"madar://bahw/habits";case .year,.upcoming:"madar://bahw/year";case .diaryWrite:"madar://notes/write";case .mihbara:"madar://mihbara"}}
}
/// Fixed room templates, never a maker configuration or a store handle. Diary rows exist only with the RD7 opt-in.
public struct RoomWidgetSnapshot:Codable,Sendable,Equatable {
    public struct Row:Codable,Sendable,Equatable,Identifiable {
        public var id:String
        public var title:String
        public var value:String
        public var detail:String
        public var secondDate:String
        public var share:Double
        public var route:String
        public var done:Bool
        /// Optional read projections for period circles; older payloads retain their prose fallback.
        public var completedCount:Int?
        public var targetCount:Int?
        public init(id:String,title:String,value:String,detail:String="",secondDate:String="",share:Double=0,route:String,done:Bool=false,completedCount:Int?=nil,targetCount:Int?=nil){self.id=id;self.title=title;self.value=value;self.detail=detail;self.secondDate=secondDate;self.share=share;self.route=route;self.done=done;self.completedCount=completedCount;self.targetCount=targetCount}
    }
    public var datePrimary:String
    public var dateSecondary:String
    public var heading:String
    public var emptyTitle:String
    public var rows:[Row]
    public var periods:[Row]
    public var locked:Bool
    public init(datePrimary:String,dateSecondary:String,heading:String,emptyTitle:String,rows:[Row]=[],periods:[Row]=[],locked:Bool=false){self.datePrimary=datePrimary;self.dateSecondary=dateSecondary;self.heading=heading;self.emptyTitle=emptyTitle;self.rows=rows;self.periods=periods;self.locked=locked}
    public func hasVisibleRows(for room:BuiltRoomWidget, template:String) -> Bool {
        if room == .habits && template == "periods" { return !periods.isEmpty }
        if room == .year && ["hijri", "gregorian"].contains(template) { return rows.contains { $0.id == template } }
        return !rows.isEmpty
    }
}
/// Mihbara's outside-room payload follows data-dictionary.json. It contains only facts owned by
/// Mihbara; private notes and diary-linked notes are filtered by the app before the JSON is written.
public struct MihbaraSnapshot:Codable,Sendable,Equatable {
    public struct BookSummary:Codable,Sendable,Equatable {
        public var id:UUID
        public var title:String
        public var author:String
        public var currentPage:Int?
        public var pages:Int?
        public var pagesToChapterEnd:Int?
        public init(id:UUID,title:String,author:String,currentPage:Int?=nil,pages:Int?=nil,pagesToChapterEnd:Int?=nil){self.id=id;self.title=title;self.author=author;self.currentPage=currentPage;self.pages=pages;self.pagesToChapterEnd=pagesToChapterEnd}
    }
    public struct HadithSummary:Codable,Sendable,Equatable {
        public var collectionID:String
        public var number:Int
        public var title:String
        public init(collectionID:String,number:Int,title:String){self.collectionID=collectionID;self.number=number;self.title=title}
    }
    public var currentBook:BookSummary?
    public var hadithToday:HadithSummary?
    public var shelfCount:Int
    public var lastNotebookLine:String?
    public init(currentBook:BookSummary?=nil,hadithToday:HadithSummary?=nil,shelfCount:Int=0,lastNotebookLine:String?=nil){self.currentBook=currentBook;self.hadithToday=hadithToday;self.shelfCount=shelfCount;self.lastNotebookLine=lastNotebookLine.map{String($0.prefix(80))}}
}
/// Habits a Shortcut or Siri may complete blindly (§16): custom habits only, never a linked or Health habit,
/// with the in-app step and the period the completion belongs to. Empty under whole-app protection.
public struct HabitShortcutSnapshot:Codable,Sendable,Equatable {
    public static let name="habitShortcuts"
    public struct Item:Codable,Sendable,Equatable,Identifiable {
        public var id:UUID
        public var title:String
        /// What one tap adds, written as the user would say it («+١ كوب»، «+١٥ دقيقة»، «أتممتها»).
        public var stepTitle:String
        public var step:Int
        public var periodKey:String
        public var done:Bool
        public init(id:UUID,title:String,stepTitle:String,step:Int,periodKey:String,done:Bool){self.id=id;self.title=title;self.stepTitle=stepTitle;self.step=step;self.periodKey=periodKey;self.done=done}
    }
    public var items:[Item]
    /// Period keys hold until the current Madar day ends; after that only the app can resolve the period.
    public var periodsValidUntil:Date
    public init(items:[Item],periodsValidUntil:Date){self.items=items;self.periodsValidUntil=periodsValidUntil}
}
