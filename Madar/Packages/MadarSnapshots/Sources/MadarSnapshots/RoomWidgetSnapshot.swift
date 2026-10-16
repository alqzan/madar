import Foundation

public enum BuiltRoomWidget:String,CaseIterable,Codable,Sendable {
    case habits, year, upcoming, diaryWrite
    public var title:String {switch self{case .habits:"العادات";case .year:"السنة";case .upcoming:"الأيام القادمة";case .diaryWrite:"سطر سريع"}}
    public var glyph:String {switch self{case .habits:"MadarHabits";case .year:"MadarYear";case .upcoming:"MadarUpcoming";case .diaryWrite:"MadarDiary"}}
    public var route:String {switch self{case .habits:"madar://bahw/habits";case .year,.upcoming:"madar://bahw/year";case .diaryWrite:"madar://notes/write"}}
}
/// Fixed room templates, never a maker configuration or a store handle. Diary writing carries no diary content.
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
        public init(id:String,title:String,value:String,detail:String="",secondDate:String="",share:Double=0,route:String,done:Bool=false){self.id=id;self.title=title;self.value=value;self.detail=detail;self.secondDate=secondDate;self.share=share;self.route=route;self.done=done}
    }
    public var datePrimary:String
    public var dateSecondary:String
    public var heading:String
    public var emptyTitle:String
    public var rows:[Row]
    public var periods:[Row]
    public var locked:Bool
    public init(datePrimary:String,dateSecondary:String,heading:String,emptyTitle:String,rows:[Row]=[],periods:[Row]=[],locked:Bool=false){self.datePrimary=datePrimary;self.dateSecondary=dateSecondary;self.heading=heading;self.emptyTitle=emptyTitle;self.rows=rows;self.periods=periods;self.locked=locked}
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
