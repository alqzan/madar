import SwiftUI
import WidgetKit
import AppIntents
import MadarSnapshots

enum MadarWidgetFamilies {
    static var homeAndAccessories: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
        if #available(iOS 27.0, *) { families.append(.systemExtraLargePortrait) }
        families += [.accessoryCircular, .accessoryRectangular, .accessoryInline]
        return families
    }
}

/// «الصلاة القادمة»: the next prayer and its time, nothing else (RP9, RU2). It reads the `prayerNext`
/// snapshot only and carries one timeline entry per minute, so the countdown is exact without refreshes.
enum PrayerWidgetTemplate:String,AppEnum {
    case next,countdown
    static let typeDisplayRepresentation=TypeDisplayRepresentation(name:"قالب الصلاة")
    static let caseDisplayRepresentations:[Self:DisplayRepresentation]=[.next:"القادمة ووقتها",.countdown:"كم بقي"]
}
struct PrayerWidgetConfiguration:WidgetConfigurationIntent {
    static let title:LocalizedStringResource="الصلاة القادمة"
    @Parameter(title:"القالب",default:.next)var template:PrayerWidgetTemplate
}
struct NextPrayerEntry: TimelineEntry {
    let date: Date
    let snapshot: PrayerNextSnapshot?
    let tzID: String
    var template:PrayerWidgetTemplate = .next
}

struct NextPrayerProvider: TimelineProvider {
    private func load(now: Date) -> (PrayerNextSnapshot, String)? {
        guard let store = try? SnapshotStore.appGroup("group.com.alqzan.madar2"),
              let envelope = store.read("prayerNext", as: PrayerNextSnapshot.self, now: now) else { return nil }
        return (envelope.payload, envelope.tzID)
    }
    func placeholder(in context: Context) -> NextPrayerEntry {
        let now = Date()
        return .init(date: now, snapshot: PrayerNextSnapshot(items: [.init(prayer: "maghrib", name: "المغرب", at: now.addingTimeInterval(74 * 60))], numerals: "hindi"), tzID: TimeZone.current.identifier)
    }
    func getSnapshot(in context: Context, completion: @escaping (NextPrayerEntry) -> Void) {
        let now = Date()
        if let (snapshot, tz) = load(now: now) { completion(.init(date: now, snapshot: snapshot, tzID: tz)) }
        else { completion(context.isPreview ? placeholder(in: context) : .init(date: now, snapshot: nil, tzID: TimeZone.current.identifier)) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextPrayerEntry>) -> Void) {
        let now = Date()
        guard let (snapshot, tz) = load(now: now) else {
            completion(Timeline(entries: [.init(date: now, snapshot: nil, tzID: TimeZone.current.identifier)], policy: .after(now.addingTimeInterval(900))))
            return
        }
        let entries = snapshot.timelineDates(from: now).map { NextPrayerEntry(date: $0, snapshot: snapshot, tzID: tz) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

private enum Salah {
    static func color(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    static let ink = color(light: 0x241D16, dark: 0xF0E6D3)
    static let accent = color(light: 0x87551D, dark: 0xD3A24D)
    static let paper = color(light: 0xFBF7EE, dark: 0x15110D)
}
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

struct NextPrayerView: View {
    let entry: NextPrayerEntry
    @Environment(\.widgetFamily) private var environmentFamily
    var previewFamily:WidgetFamily? = nil
    private var family:WidgetFamily {previewFamily ?? environmentFamily}
    private var extraLargePortrait:Bool {if #available(iOS 27.0, *) {family == .systemExtraLargePortrait} else {false}}
    @Environment(\.widgetRenderingMode) private var rendering

    private var state: PrayerNextSnapshot.State? { entry.snapshot?.state(at: entry.date) }
    private func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: entry.snapshot?.numerals == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab")
        formatter.timeZone = TimeZone(identifier: entry.tzID) ?? .current
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    private var countdown: String { state.map { "بعد " + (entry.snapshot?.countdown(minutes: $0.minutes) ?? "") } ?? "" }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            case .accessoryRectangular: rectangular
            default: home
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .widgetURL(URL(string: "madar://salah"))
        .background(previewFamily == nil ? Color.clear : Salah.paper)
        .containerBackground(for: .widget) {if [.accessoryCircular,.accessoryRectangular,.accessoryInline].contains(family){Color.clear}else{Salah.paper}}
    }

    private var circular:some View {
        VStack(spacing:3) {
            Image("MadarPrayer").renderingMode(.template).resizable().scaledToFit().frame(width:16,height:16)
            if let state {Text(entry.snapshot?.countdown(minutes:state.minutes) ?? "").font(.system(size:15,weight:.semibold)).monospacedDigit().minimumScaleFactor(0.74).lineLimit(1);Text(state.item.name).font(.system(size:11)).lineLimit(1)}
            else{Text("افتح مدار").font(.system(size:11))}
        }.foregroundStyle(.primary).frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    private var inline: some View {
        Text(state.map { $0.item.name + " " + clock($0.item.at) } ?? "افتح مدار")
    }
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("الصلاة القادمة").font(.caption2).foregroundStyle(.secondary)
            if let state {
                Text(state.item.name + " " + clock(state.item.at)).font(.headline)
                Text(countdown).font(.caption).monospacedDigit()
            } else { Text("افتح مدار").font(.headline) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var home: some View {
        VStack(alignment: .leading, spacing: extraLargePortrait ? 18 : 4) {
            Text("الصلاة القادمة").font(extraLargePortrait ? .title2 : .caption).foregroundStyle(.secondary)
            if let state {
                Text(entry.template == .countdown ? countdown : state.item.name).font(.system(size: extraLargePortrait ? 72 : family == .systemSmall ? 34 : 40, weight: .bold, design: .serif))
                    .minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(Salah.ink)
                Text(clock(state.item.at)).font(.system(size: extraLargePortrait ? 52 : 22, weight: .semibold, design: .rounded)).foregroundStyle(Salah.accent).widgetAccentable()
                Spacer(minLength: 0)
                Text(entry.template == .countdown ? state.item.name : countdown).font(.system(size: extraLargePortrait ? 32 : 16, weight: .regular)).monospacedDigit().foregroundStyle(.secondary)
            } else {
                Spacer(minLength: 0)
                Text("افتح مدار").font(.title3.weight(.semibold)).foregroundStyle(Salah.ink)
                Text("لتحديث مواقيت الصلاة").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct ConfiguredPrayerProvider:AppIntentTimelineProvider {
    func placeholder(in context:Context)->NextPrayerEntry{.init(date:.now,snapshot:nil,tzID:TimeZone.current.identifier)}
    func snapshot(for configuration:PrayerWidgetConfiguration,in context:Context) async->NextPrayerEntry{load(configuration)}
    func timeline(for configuration:PrayerWidgetConfiguration,in context:Context) async->Timeline<NextPrayerEntry>{
        let now=Date(),envelope=(try? SnapshotStore.appGroup("group.com.alqzan.madar2"))?.read("prayerNext",as:PrayerNextSnapshot.self,now:now)
        let expiry=envelope?.validUntil ?? now.addingTimeInterval(900),zone=envelope?.tzID ?? TimeZone.current.identifier
        let window=envelope?.payload.minuteWindow(from:now,validUntil:expiry)
        let dates=window?.dates ?? [now],refresh=window?.refreshAt ?? expiry
        var entries=dates.map{NextPrayerEntry(date:$0,snapshot:envelope?.payload,tzID:zone,template:configuration.template)}
        entries.append(.init(date:refresh,snapshot:nil,tzID:zone,template:configuration.template))
        return Timeline(entries:entries,policy:.after(refresh))
    }
    private func load(_ config:PrayerWidgetConfiguration)->NextPrayerEntry{
        let envelope=(try? SnapshotStore.appGroup("group.com.alqzan.madar2"))?.read("prayerNext",as:PrayerNextSnapshot.self)
        return .init(date:.now,snapshot:envelope?.payload,tzID:envelope?.tzID ?? TimeZone.current.identifier,template:config.template)
    }
}
struct NextPrayerWidget: Widget {
    let kind = "MadarNextPrayer"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: PrayerWidgetConfiguration.self, provider: ConfiguredPrayerProvider()) { entry in NextPrayerView(entry: entry) }
            .configurationDisplayName("الصلاة القادمة")
            .description("اسم الصلاة القادمة ووقتها وكم بقي.")
            .supportedFamilies(MadarWidgetFamilies.homeAndAccessories)
    }
}
