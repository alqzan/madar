import SwiftUI
import WidgetKit
import AppIntents
import MadarSnapshots
import MadarDesign

protocol FixedRoomConfiguration:WidgetConfigurationIntent {
    static var room:BuiltRoomWidget{get}
    static var defaultTemplate:String{get}
    var templateName:String{get}
}
enum HabitWidgetTemplate:String,AppEnum {
    case today,periods,coming
    static let typeDisplayRepresentation=TypeDisplayRepresentation(name:"قالب العادات")
    static let caseDisplayRepresentations:[Self:DisplayRepresentation]=[.today:"عاداتك التالية",.periods:"الفترات الأربع",.coming:"المواعيد القادمة وآخر إنجاز"]
}
struct HabitWidgetConfiguration:FixedRoomConfiguration {
    static let title:LocalizedStringResource="العادات"
    static let room=BuiltRoomWidget.habits
    static let defaultTemplate="today"
    @Parameter(title:"القالب",default:.today)var template:HabitWidgetTemplate
    var templateName:String{template.rawValue}
}
enum YearWidgetTemplate:String,AppEnum {
    case both,hijri,gregorian
    static let typeDisplayRepresentation=TypeDisplayRepresentation(name:"قالب السنة")
    static let caseDisplayRepresentations:[Self:DisplayRepresentation]=[.both:"السنتان",.hijri:"الهجرية",.gregorian:"الميلادية"]
}
struct YearWidgetConfiguration:FixedRoomConfiguration {
    static let title:LocalizedStringResource="السنة"
    static let room=BuiltRoomWidget.year
    static let defaultTemplate="both"
    @Parameter(title:"القالب",default:.both)var template:YearWidgetTemplate
    var templateName:String{template.rawValue}
}
enum UpcomingWidgetTemplate:String,AppEnum {
    case upcoming,nearest
    static let typeDisplayRepresentation=TypeDisplayRepresentation(name:"قالب الأيام القادمة")
    static let caseDisplayRepresentations:[Self:DisplayRepresentation]=[.upcoming:"الأيام القادمة",.nearest:"أقرب يوم"]
}
struct UpcomingWidgetConfiguration:FixedRoomConfiguration {
    static let title:LocalizedStringResource="الأيام القادمة"
    static let room=BuiltRoomWidget.upcoming
    static let defaultTemplate="upcoming"
    @Parameter(title:"القالب",default:.upcoming)var template:UpcomingWidgetTemplate
    var templateName:String{template.rawValue}
}
enum DiaryWriteTemplate:String,AppEnum {
    case write,intention,thatDay,lastLine
    static let typeDisplayRepresentation=TypeDisplayRepresentation(name:"قالب المذكرات")
    // The three content templates show diary text only when «محتوى المذكرات في الودجات» is on (RD7); otherwise «اكتب».
    static let caseDisplayRepresentations:[Self:DisplayRepresentation]=[.write:"سطر سريع بلا محتوى شخصي",.intention:"النيّة و«اكتب»",.thatDay:"في مثل هذا اليوم",.lastLine:"آخر سطر"]
}
struct DiaryWriteConfiguration:FixedRoomConfiguration {
    static let title:LocalizedStringResource="سطر سريع"
    static let room=BuiltRoomWidget.diaryWrite
    static let defaultTemplate="write"
    @Parameter(title:"القالب",default:.write)var template:DiaryWriteTemplate
    var templateName:String{template.rawValue}
}
enum MihbaraWidgetTemplate:String,AppEnum {
    case summary
    static let typeDisplayRepresentation=TypeDisplayRepresentation(name:"قالب المحبرة")
    static let caseDisplayRepresentations:[Self:DisplayRepresentation]=[.summary:"ملخص رفّك"]
}
struct MihbaraWidgetConfiguration:FixedRoomConfiguration {
    static let title:LocalizedStringResource="المحبرة"
    static let room=BuiltRoomWidget.mihbara
    static let defaultTemplate="summary"
    @Parameter(title:"القالب",default:.summary)var template:MihbaraWidgetTemplate
    var templateName:String{template.rawValue}
}
struct FixedRoomEntry:TimelineEntry {
    let date:Date;let room:BuiltRoomWidget;let value:RoomWidgetSnapshot?;let template:String
    var mihbara:MihbaraSnapshot?=nil
    var mihbaraLocked=false
    var numerals="arabicIndic"
    /// The Mihbara widget opens the book on its face, so a tap lands in the reader and not on the room's door; every other widget opens its room.
    var openURL:URL? {
        if room == .mihbara, !mihbaraLocked, let id=mihbara?.currentBook?.id { return URL(string:room.route+"/book/"+id.uuidString) }
        return URL(string:room.route)
    }
    var relevance:TimelineEntryRelevance?{
        let empty = room == .mihbara
            ? mihbara?.currentBook == nil && mihbara?.hadithToday == nil && mihbara?.lastNotebookLine == nil && (mihbara?.shelfCount ?? 0) == 0
            : value == nil || value?.hasVisibleRows(for: room, template: template) == false
        return .init(score:empty || value?.locked == true || mihbaraLocked ? 0 : 1)
    }
}
struct FixedRoomProvider<Config:FixedRoomConfiguration>:AppIntentTimelineProvider {
    typealias Intent=Config
    func placeholder(in context:Context)->FixedRoomEntry{.init(date:.now,room:Config.room,value:nil,template:Config.defaultTemplate)}
    func snapshot(for configuration:Config,in context:Context) async->FixedRoomEntry{load(configuration)}
    func timeline(for configuration:Config,in context:Context) async->Timeline<FixedRoomEntry>{
        let now=Date(),store=try? SnapshotStore.appGroup("group.com.alqzan.madar2")
        let expiry:Date
        if Config.room == .mihbara {expiry=store?.read(Config.room.rawValue,as:MihbaraSnapshot.self,now:now)?.validUntil ?? now.addingTimeInterval(900)}
        else {expiry=store?.read(Config.room.rawValue,as:RoomWidgetSnapshot.self,now:now)?.validUntil ?? now.addingTimeInterval(900)}
        let fresh=load(configuration,at:now)
        let stale=FixedRoomEntry(date:expiry,room:Config.room,value:nil,template:configuration.templateName,numerals:fresh.numerals)
        return Timeline(entries:[fresh,stale],policy:.after(expiry))
    }
    private func load(_ config:Config,at now:Date = .now)->FixedRoomEntry {
        let store=try? SnapshotStore.appGroup("group.com.alqzan.madar2"),foundation=store?.read("foundation",as:FoundationSnapshot.self,now:now)?.payload
        if Config.room == .mihbara {
            let envelope=store?.read(Config.room.rawValue,as:MihbaraSnapshot.self,now:now)
            return .init(date:now,room:Config.room,value:nil,template:config.templateName,mihbara:envelope?.payload,mihbaraLocked:envelope?.privacy.notesLocked == true,numerals:foundation?.numerals ?? "arabicIndic")
        }
        let envelope=store?.read(Config.room.rawValue,as:RoomWidgetSnapshot.self,now:now)
        return .init(date:now,room:Config.room,value:envelope?.payload,template:config.templateName,numerals:foundation?.numerals ?? "arabicIndic")
    }
}
private struct FixedRoomWidgetView:View {
    let entry:FixedRoomEntry
    @Environment(\.widgetFamily)private var family
    @Environment(\.colorScheme)private var scheme
    var body:some View{RoomWidgetContent(room:entry.room,snapshot:entry.value,template:entry.template,family:family,mihbaraSnapshot:entry.mihbara,mihbaraLocked:entry.mihbaraLocked,numerals:entry.numerals).widgetURL(entry.openURL).containerBackground(for:.widget){if [WidgetFamily.accessoryCircular,.accessoryRectangular,.accessoryInline].contains(family){Color.clear}else if entry.room == .money{MadarToken.colors["widgetIdentity.room.mal.\(scheme == .dark ? "dark" : "light").bg"] ?? .clear}else{RoomTheme(room:entry.room == .mihbara ? "mihbara" : "bahw",dark:scheme == .dark).surface}}}
}
struct FixedRoomWidget<Config:FixedRoomConfiguration>:Widget {
    var body:some WidgetConfiguration {
        AppIntentConfiguration(kind:"MadarRoom-"+Config.room.rawValue,intent:Config.self,provider:FixedRoomProvider<Config>()){FixedRoomWidgetView(entry:$0)}
            .configurationDisplayName(Config.room.title).description("ملخص من غرفتك، وفتح مباشر لها.").supportedFamilies(MadarWidgetFamilies.homeAndAccessories)
    }
}
struct AdditionalRoomWidgets:WidgetBundle {
    var body:some Widget{FixedRoomWidget<HabitWidgetConfiguration>();FixedRoomWidget<YearWidgetConfiguration>();FixedRoomWidget<UpcomingWidgetConfiguration>();FixedRoomWidget<DiaryWriteConfiguration>();FixedRoomWidget<MihbaraWidgetConfiguration>();DiaryWriterControl();HabitsRoomControl();MoneyExpenseControl();MihbaraRoomControl();FixedRoomWidget<MoneyWidgetConfiguration>()}
}

struct MoneyWidgetConfiguration: FixedRoomConfiguration {
    static let title: LocalizedStringResource = "المال"
    static let room = BuiltRoomWidget.money
    static let defaultTemplate = "now"
    @Parameter(title: "القالب", default: .now) var template: MoneyWidgetTemplate
    var templateName: String { template.rawValue }
}
enum MoneyWidgetTemplate: String, AppEnum {
    case now, basis
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "قالب المال")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.now:"لك الآن ويومك", .basis:"لك فعلًا والمحجوز ودخل الدورة"]
}
