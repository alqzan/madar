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
    case today,periods
    static let typeDisplayRepresentation=TypeDisplayRepresentation(name:"قالب العادات")
    static let caseDisplayRepresentations:[Self:DisplayRepresentation]=[.today:"عاداتك التالية",.periods:"الفترات الأربع"]
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
struct FixedRoomEntry:TimelineEntry {
    let date:Date;let room:BuiltRoomWidget;let value:RoomWidgetSnapshot?;let template:String
    var relevance:TimelineEntryRelevance?{.init(score:value == nil || value?.locked == true || value?.rows.isEmpty == true ? 0 : 1)}
}
struct FixedRoomProvider<Config:FixedRoomConfiguration>:AppIntentTimelineProvider {
    typealias Intent=Config
    func placeholder(in context:Context)->FixedRoomEntry{.init(date:.now,room:Config.room,value:nil,template:Config.defaultTemplate)}
    func snapshot(for configuration:Config,in context:Context) async->FixedRoomEntry{load(configuration)}
    func timeline(for configuration:Config,in context:Context) async->Timeline<FixedRoomEntry>{
        let now=Date(),envelope=(try? SnapshotStore.appGroup("group.com.alqzan.madar2"))?.read(Config.room.rawValue,as:RoomWidgetSnapshot.self,now:now)
        let expiry=envelope?.validUntil ?? now.addingTimeInterval(900)
        return Timeline(entries:[.init(date:now,room:Config.room,value:envelope?.payload,template:configuration.templateName),.init(date:expiry,room:Config.room,value:nil,template:configuration.templateName)],policy:.after(expiry))
    }
    private func load(_ config:Config)->FixedRoomEntry{.init(date:.now,room:Config.room,value:(try? SnapshotStore.appGroup("group.com.alqzan.madar2"))?.read(Config.room.rawValue,as:RoomWidgetSnapshot.self)?.payload,template:config.templateName)}
}
private struct FixedRoomWidgetView:View {
    let entry:FixedRoomEntry
    @Environment(\.widgetFamily)private var family
    @Environment(\.colorScheme)private var scheme
    var body:some View{RoomWidgetContent(room:entry.room,snapshot:entry.value,template:entry.template,family:family).widgetURL(URL(string:entry.room.route)).containerBackground(for:.widget){if [WidgetFamily.accessoryCircular,.accessoryRectangular,.accessoryInline].contains(family){Color.clear}else{entry.room == .money ? (MadarToken.colors["widgetIdentity.room.mal.\(scheme == .dark ? "dark" : "light").bg"] ?? .clear) : RoomTheme(room:"bahw",dark:scheme == .dark).surface}}}
}
struct FixedRoomWidget<Config:FixedRoomConfiguration>:Widget {
    var body:some WidgetConfiguration {
        AppIntentConfiguration(kind:"MadarRoom-"+Config.room.rawValue,intent:Config.self,provider:FixedRoomProvider<Config>()){FixedRoomWidgetView(entry:$0)}
            .configurationDisplayName(Config.room.title).description("ملخص من غرفتك، وفتح مباشر لها.").supportedFamilies([.systemSmall,.systemMedium,.systemLarge,.accessoryCircular,.accessoryRectangular,.accessoryInline])
    }
}
struct AdditionalRoomWidgets:WidgetBundle {
    var body:some Widget{FixedRoomWidget<HabitWidgetConfiguration>();FixedRoomWidget<YearWidgetConfiguration>();FixedRoomWidget<UpcomingWidgetConfiguration>();FixedRoomWidget<DiaryWriteConfiguration>();DiaryWriterControl();HabitsRoomControl();MoneyExpenseControl();FixedRoomWidget<MoneyWidgetConfiguration>()}
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
