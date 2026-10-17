import SwiftUI
import WidgetKit
import MadarDesign
import MadarSnapshots

/// The same content is rendered by WidgetKit and the in-app previews. No store access or prototype controls.
struct RoomWidgetContent:View {
    let room:BuiltRoomWidget
    let snapshot:RoomWidgetSnapshot?
    var template="summary"
    var family:WidgetFamily = .systemSmall
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var type
    @Environment(\.widgetRenderingMode) private var rendering
    private var theme:RoomTheme{.init(room:"bahw",dark:scheme == .dark)}
    private var accent:Color{rendering == .fullColor ? theme.accent : .primary}
    private var capacity:Int {let n=family == .systemLarge ? 5 : family == .systemMedium ? 3 : 2;return type.isAccessibilitySize ? (n+1)/2 : n}
    private var rows:[RoomWidgetSnapshot.Row] {
        guard let snapshot else{return[]}
        if room == .habits && template == "periods"{return Array(snapshot.periods.prefix(capacity))}
        if room == .year && ["hijri","gregorian"].contains(template){return snapshot.rows.filter{$0.id==template}}
        let values=room == .upcoming && template == "nearest" ? Array(snapshot.rows.prefix(1)) : snapshot.rows
        return Array(values.prefix(capacity))
    }
    private var accessory:Bool{[WidgetFamily.accessoryInline,.accessoryCircular,.accessoryRectangular].contains(family)}
    var body:some View {Group{if room == .money { MoneyWidgetContent(snapshot: snapshot, family: family, template: template) } else if accessory{accessoryContent}else{home}}}
    private var home:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:6) { Image(room.glyph).renderingMode(.template).resizable().scaledToFit().frame(width:16,height:16).widgetAccentable();Text(diaryRow?.title ?? room.title).font(.custom("thmanyahsans-Bold",size:13,relativeTo:.caption));Spacer(minLength:0);if room == .habits && family == .systemMedium {Text(snapshot?.heading ?? "").font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).privacySensitive()} }.foregroundStyle(accent)
            if snapshot?.locked == true {
                Spacer(minLength:0);Label("افتح مدار",systemImage:"lock").font(MadarTypography.section());Text("المحتوى محمي").font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).foregroundStyle(theme.secondaryInk);Spacer(minLength:0)
            } else if let row = diaryRow {
                diaryContent(row)
            } else if room == .diaryWrite {
                dates
                Spacer(minLength:0)
                Text("اكتب سطر اليوم").font(.custom("thmanyahserifdisplay-Bold",size:24,relativeTo:.title2))
                Text("فكرة صغيرة تستحق أن تبقى").font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).foregroundStyle(theme.secondaryInk)
                Spacer(minLength:0)
            } else if rows.isEmpty {
                Spacer(minLength:0);Text(snapshot?.emptyTitle ?? "افتح مدار للتحديث").font(MadarTypography.section());dates;Spacer(minLength:0)
            } else if room == .upcoming && family != .systemLarge {
                HStack(alignment:.top,spacing:8) {ForEach(rows){row in upcoming(row)}}.frame(maxHeight:.infinity)
            } else {
                if room == .habits && template != "periods" && family != .systemMedium && !type.isAccessibilitySize {Text(snapshot?.heading ?? "").font(.custom("thmanyahserifdisplay-Bold",size:22,relativeTo:.title2)).foregroundStyle(accent).privacySensitive()}
                ForEach(rows) { row in
                    Link(destination:URL(string:row.route) ?? URL(string:room.route)!) {
                        HStack(spacing:8) {
                            if room == .year || room == .habits {donut(row.share).frame(width:24,height:24)}
                            VStack(alignment:.leading,spacing:2) {
                                Text(row.title).font(.custom("thmanyahsans-Bold",size:13,relativeTo:.caption)).lineLimit(1)
                                Text(row.value).font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1)
                                if family == .systemLarge && !type.isAccessibilitySize && !row.detail.isEmpty && (room != .habits || row.id == rows.first?.id) {HStack(spacing:6){Text(row.detail).font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1);if !row.secondDate.isEmpty {Text(row.secondDate).font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1)}}}
                            }
                            Spacer(minLength:0)
                            if row.done && room == .habits {Image(systemName:"checkmark").font(.caption).foregroundStyle(accent)}
                        }.contentShape(.rect)
                    }.buttonStyle(.plain).privacySensitive(room == .habits || room == .upcoming)
                }
                if room == .year || family == .systemLarge {Spacer(minLength:0);dates}
                else {Spacer(minLength:0)}
            }
        }.foregroundStyle(theme.ink).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .environment(\.layoutDirection,.rightToLeft)
        .accessibilityElement(children:.contain)
    }
    private var accessoryRow:RoomWidgetSnapshot.Row? {
        room == .habits ? snapshot?.periods.first : rows.first
    }
    private var accessoryValue:String {
        if snapshot?.locked==true{return "افتح مدار"}
        if room == .diaryWrite{return "اكتب سطر اليوم"}
        guard let row=accessoryRow else{return "افتح مدار"}
        return room == .upcoming ? row.title+" "+row.value : row.value
    }
    @ViewBuilder private var accessoryContent:some View {
        if family == .accessoryInline {
            Text(room.title+"، "+accessoryValue).font(.caption).lineLimit(1).privacySensitive(room == .habits || room == .upcoming)
        } else if family == .accessoryCircular {
            ZStack {
                Circle().stroke(.primary.opacity(0.25),lineWidth:3)
                if snapshot?.locked != true {Circle().trim(from:0,to:min(1,max(0,accessoryRow?.share ?? 0))).stroke(.primary,style:.init(lineWidth:3,lineCap:.round)).rotationEffect(.degrees(-90))}
                VStack(spacing:1) {
                    if snapshot?.locked==true{Image(systemName:"lock");Text("افتح").font(.caption2)}
                    else if room == .diaryWrite{Image(room.glyph).renderingMode(.template).resizable().scaledToFit().frame(width:24,height:24);Text("اكتب").font(.caption2)}
                    else {
                        let value=accessoryRow?.value ?? ""
                        Text(value.contains(where:{$0.isNumber}) ? (room == .upcoming ? value.split(separator:" ").first.map(String.init) ?? value : value) : "افتح").font(.custom("thmanyahsans-Bold",size:15,relativeTo:.caption)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(room == .upcoming ? accessoryRow?.title ?? room.title : room == .habits ? "اليوم" : "السنة").font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).lineLimit(1)
                    }
                }.padding(7)
            }.privacySensitive(room == .habits || room == .upcoming).foregroundStyle(.primary).accessibilityElement(children:.combine)
        } else {
            HStack(spacing:8) {
                Image(room.glyph).renderingMode(.template).resizable().scaledToFit().frame(width:20,height:20)
                VStack(alignment:.leading,spacing:3) {
                    Text(room.title).font(.custom("thmanyahsans-Bold",size:11,relativeTo:.caption2))
                    Text(accessoryValue).font(.custom("thmanyahsans-Bold",size:13,relativeTo:.caption)).lineLimit(1)
                    if snapshot?.locked != true {
                        if room == .year,!["hijri","gregorian"].contains(template),let second=snapshot?.rows.first(where:{$0.id != accessoryRow?.id}) {Text((accessoryRow?.title ?? "")+"، "+second.title+" "+second.value).font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).lineLimit(1)}
                        else if room == .habits,let next=(template == "periods" ? rows.dropFirst().first : snapshot?.rows.first) {Text(next.title+"، "+next.value).font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).lineLimit(1)}
                        else if room == .upcoming,let next=rows.dropFirst().first {Text(next.title+"، "+next.value).font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).lineLimit(1)}
                    }
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading).privacySensitive(room == .habits || room == .upcoming).foregroundStyle(.primary)
        }
    }
    /// RD7: the chosen diary template's row, present only when the owner opted in and nothing is locked.
    private var diaryRow:RoomWidgetSnapshot.Row? { room == .diaryWrite && snapshot?.locked != true ? snapshot?.rows.first { $0.id == template } : nil }
    @ViewBuilder private func diaryContent(_ row:RoomWidgetSnapshot.Row)->some View {
        Text(row.value).font(.custom("thmanyahseriftext-Regular",size:family == .systemSmall ? 17 : 19,relativeTo:.body)).lineLimit(family == .systemLarge ? 8 : 4).lineSpacing(3).privacySensitive()
        Spacer(minLength:0)
        if row.id == "intention" {
            Link(destination:URL(string:room.route)!) {Text("اكتب").font(.custom("thmanyahsans-Bold",size:15,relativeTo:.body)).frame(maxWidth:.infinity,minHeight:40).foregroundStyle(theme.surface).background(theme.ink,in:.capsule)}.buttonStyle(.plain)
        } else if !row.detail.isEmpty {
            HStack(spacing:6){Text(row.detail);Text(row.secondDate)}.font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1).privacySensitive()
        }
    }
    private var dates:some View {
        VStack(alignment:.leading,spacing:2){Text(snapshot?.datePrimary ?? "");Text(snapshot?.dateSecondary ?? "")}.font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).foregroundStyle(theme.secondaryInk)
    }
    private func donut(_ share:Double)->some View {ZStack{Circle().stroke(theme.line,lineWidth:3);Circle().trim(from:0,to:min(1,max(0,share))).stroke(accent,style:.init(lineWidth:3,lineCap:.round)).rotationEffect(.degrees(-90))}.accessibilityHidden(true)}
    private func upcoming(_ row:RoomWidgetSnapshot.Row)->some View {
        Link(destination:URL(string:row.route) ?? URL(string:room.route)!) {
            VStack(spacing:5){ZStack{donut(row.share);VStack(spacing:0){Text(row.value.split(separator:" ").first.map(String.init) ?? row.value).font(.custom("thmanyahserifdisplay-Bold",size:26,relativeTo:.title2)).minimumScaleFactor(0.7).lineLimit(1);Text(row.value.split(separator:" ").dropFirst().joined(separator:" ")).font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2))}.multilineTextAlignment(.center).padding(7)}.aspectRatio(1,contentMode:.fit);Text(row.title).font(.custom("thmanyahsans-Bold",size:11,relativeTo:.caption2)).lineLimit(2).multilineTextAlignment(.center)}.frame(maxWidth:.infinity)
        }.buttonStyle(.plain).privacySensitive()
    }
}
