import SwiftUI
import WidgetKit
import MadarDesign
import MadarSnapshots
import MadarCore

/// The same content is rendered by WidgetKit and the in-app previews. No store access or prototype controls.
struct RoomWidgetContent:View {
    let room:BuiltRoomWidget
    let snapshot:RoomWidgetSnapshot?
    var template="summary"
    var family:WidgetFamily = .systemSmall
    var mihbaraSnapshot:MihbaraSnapshot?=nil
    var mihbaraLocked=false
    var numerals="arabicIndic"
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var type
    @Environment(\.widgetRenderingMode) private var rendering
    private var theme:RoomTheme{.init(room:room == .mihbara ? "mihbara" : "bahw",dark:scheme == .dark)}
    private var accent:Color{rendering == .fullColor ? theme.accent : .primary}
    private var extraLargePortrait:Bool {if #available(iOS 27.0, *) {family == .systemExtraLargePortrait} else {false}}
    private var largeHome:Bool {family == .systemLarge || extraLargePortrait}
    private var capacity:Int {let n=extraLargePortrait ? 7 : largeHome ? 5 : family == .systemMedium ? (room == .upcoming ? 4 : 3) : room == .habits ? 3 : 2;return type.isAccessibilitySize ? (n+1)/2 : n}
    private var rows:[RoomWidgetSnapshot.Row] {
        guard let snapshot else{return[]}
        if room == .habits && template == "periods"{return Array(snapshot.periods.prefix(capacity))}
        if room == .year && ["hijri","gregorian"].contains(template){return snapshot.rows.filter{$0.id==template}}
        let values=room == .upcoming && template == "nearest" ? Array(snapshot.rows.prefix(1)) : snapshot.rows
        return Array(values.prefix(capacity))
    }
    private var accessory:Bool{[WidgetFamily.accessoryInline,.accessoryCircular,.accessoryRectangular].contains(family)}
    var body:some View {Group{if room == .mihbara{MihbaraRoomWidgetContent(snapshot:mihbaraSnapshot,locked:mihbaraLocked,family:family,numerals:numerals)}else if room == .money { MoneyWidgetContent(snapshot: snapshot, family: family, template: template) } else if accessory{accessoryContent}else{home}}}
    private var home:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:6) { Image(room.glyph).renderingMode(.template).resizable().scaledToFit().frame(width:16,height:16).widgetAccentable();Text(diaryRow?.title ?? room.title).font(.custom("thmanyahsans-Bold",size:13,relativeTo:.caption));Spacer(minLength:0);if room == .habits && template != "periods" && !largeHome {Text(snapshot?.heading ?? "").font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1).privacySensitive()} else if room == .upcoming && !largeHome && snapshot?.locked != true {Text("كم بقي").font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).foregroundStyle(theme.secondaryInk)} }.foregroundStyle(accent)
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
            } else if room == .upcoming && !largeHome {
                HStack(alignment:.top,spacing:8) {ForEach(rows){row in upcoming(row)}}.frame(maxHeight:.infinity,alignment:.center)
            } else {
                if room == .habits && template != "periods" && largeHome && !type.isAccessibilitySize {Text(snapshot?.heading ?? "").font(.custom("thmanyahserifdisplay-Bold",size:22,relativeTo:.title2)).foregroundStyle(accent).lineLimit(2).minimumScaleFactor(0.7).privacySensitive()}
                ForEach(rows) { row in
                    let isHero = extraLargePortrait && row.id == rows.first?.id
                    Link(destination:URL(string:row.route) ?? URL(string:room.route)!) {
                        HStack(spacing:8) {
                            if room == .year {donut(row.share).frame(width:24,height:24)}
                            VStack(alignment:.leading,spacing:2) {
                                Text(row.title).font(.custom("thmanyahsans-Bold",size:isHero ? 19 : 13,relativeTo:isHero ? .headline : .caption)).lineLimit(1)
                                Text(figure: row.value).font(.custom("thmanyahsans-Regular",size:isHero ? 24 : 11,relativeTo:isHero ? .title3 : .caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1)
                                if largeHome && !type.isAccessibilitySize && !row.detail.isEmpty && (room != .habits || (template != "periods" && row.id == rows.first?.id)) {HStack(spacing:6){Text(row.detail).font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1);if !row.secondDate.isEmpty {Text(row.secondDate).font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1)}}}
                            }
                            Spacer(minLength:0)
                            if room == .habits {
                                // X1: the habit keeps its identity inside its progress ring.
                                ZStack {
                                    donut(row.share, width: 3)
                                    if template != "periods", let glyph = HabitNameGlyph.symbol(for: row.title) {
                                        MadarGlyph(glyph, size: 12).foregroundStyle(accent)
                                    } else if row.done {
                                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(accent)
                                    }
                                }.frame(width: 28, height: 28)
                            }
                        }.contentShape(.rect)
                    }.buttonStyle(.plain).privacySensitive(room == .habits || room == .upcoming)
                }
                if room == .year || largeHome {Spacer(minLength:0);dates}
                else {Spacer(minLength:0)}
            }
        }.foregroundStyle(theme.ink).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .environment(\.layoutDirection,.rightToLeft)
        .accessibilityElement(children:.contain)
    }
    private var accessoryRow:RoomWidgetSnapshot.Row? {
        room == .habits ? (snapshot?.periods.first{!$0.detail.isEmpty} ?? snapshot?.periods.first) : rows.first
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
                        let value=accessoryRow?.value ?? "",remaining=accessoryRow?.detail ?? ""
                        let big=room == .upcoming ? value.split(separator:" ").first.map(String.init) : room == .habits ? (remaining.isEmpty ? nil : remaining) : (value.contains(where:{$0.isNumber}) ? value : nil)
                        Text(big ?? "افتح").font(.custom("thmanyahsans-Bold",size:15,relativeTo:.caption)).lineLimit(1).minimumScaleFactor(0.74)
                        Text(room == .upcoming ? accessoryRow?.title ?? room.title : room == .habits ? (remaining == "تمّ" ? "اليوم" : "متبقية") : "السنة").font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).lineLimit(1)
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
        Text(figure: row.value).font(.custom("thmanyahseriftext-Regular",size:family == .systemSmall ? 17 : 19,relativeTo:.body)).lineLimit(extraLargePortrait ? 12 : largeHome ? 8 : 4).lineSpacing(3).privacySensitive()
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
    private func donut(_ share:Double,width:CGFloat=3,color:Color?=nil)->some View {ZStack{Circle().stroke(theme.line,lineWidth:width);Circle().trim(from:0,to:min(1,max(0,share))).stroke(color ?? accent,style:.init(lineWidth:width,lineCap:.round)).rotationEffect(.degrees(-90))}.accessibilityHidden(true)}
    /// X1: an upcoming ring takes the colour of the room its date comes from (salary in money's ink, a juz in Quran's).
    /// Only the ring, a shape, takes the room's base accent; its text stays in lobby ink (contrast.pairs has no cross-room text pair).
    private func sourceColor(_ route:String)->Color {
        guard rendering == .fullColor,let host=URL(string:route)?.host,["salah","quran","mal","notes","mihbara"].contains(host) else{return accent}
        return RoomTheme(room:host,dark:scheme == .dark).color("accent")
    }
    private func upcoming(_ row:RoomWidgetSnapshot.Row)->some View {
        Link(destination:URL(string:row.route) ?? URL(string:room.route)!) {
            VStack(spacing:6){ZStack{donut(row.share,width:4,color:sourceColor(row.route));VStack(spacing:0){Text(row.value.split(separator:" ").first.map(String.init) ?? row.value).font(.custom("thmanyahserifdisplay-Bold",size:22,relativeTo:.title2)).minimumScaleFactor(0.7).lineLimit(1);Text(row.value.split(separator:" ").dropFirst().joined(separator:" ")).font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2))}.multilineTextAlignment(.center).padding(7)}.frame(width:family == .systemSmall ? 84 : 66,height:family == .systemSmall ? 84 : 66);Text(row.title).font(.custom("thmanyahsans-Bold",size:11,relativeTo:.caption2)).lineLimit(2).multilineTextAlignment(.center)}.frame(maxWidth:.infinity)
        }.buttonStyle(.plain).privacySensitive()
    }
}

private struct MihbaraRoomWidgetContent:View {
    let snapshot:MihbaraSnapshot?
    let locked:Bool
    let family:WidgetFamily
    let numerals:String
    @Environment(\.colorScheme) private var scheme
    private var theme:RoomTheme{.init(room:"mihbara",dark:scheme == .dark)}
    private var digits:MadarNumberFormatter{.init(style:numerals == "western" ? .western : .hindi)}
    private var extraLargePortrait:Bool {if #available(iOS 27.0, *) {family == .systemExtraLargePortrait} else {false}}
    private var largeHome:Bool {family == .systemLarge || extraLargePortrait}
    private var bookTitle:String?{snapshot?.currentBook?.title.trimmingCharacters(in:.whitespacesAndNewlines).nonEmpty}
    private var fallbackTitle:String?{bookTitle ?? snapshot?.hadithToday?.title}
    private var bookProgress:Double? {
        guard let page=snapshot?.currentBook?.currentPage,let pages=snapshot?.currentBook?.pages,pages>0 else{return nil}
        return min(1,max(0,Double(page)/Double(pages)))
    }
    private var pageLine:String? {
        guard let book=snapshot?.currentBook else{return nil}
        if let page=book.currentPage,let pages=book.pages{return digits.string(page)+" من "+WidgetCopy.agree(pages,digits,one:"صفحة واحدة",two:"صفحتين",few:"صفحات",many:"صفحة")}
        if let page=book.currentPage{return "صفحة "+digits.string(page)}
        if let pages=book.pages{return WidgetCopy.agree(pages,digits,one:"صفحة واحدة",two:"صفحتان",few:"صفحات",many:"صفحة")}
        return nil
    }
    /// The title of a Nawawi hadith already says its ordinal («الحديث الثالث عشر»); repeating the number beside it adds nothing.
    private func hadithLabel(_ hadith:MihbaraSnapshot.HadithSummary)->String {
        hadith.title.hasPrefix("الحديث ") ? "حديث اليوم" : "حديث اليوم، "+digits.string(hadith.number)
    }
    var body:some View {
        Group {
            if [WidgetFamily.accessoryInline,.accessoryCircular,.accessoryRectangular].contains(family) { accessory }
            else { home }
        }
        .foregroundStyle(family == .accessoryInline || family == .accessoryCircular || family == .accessoryRectangular ? Color.primary : theme.ink)
        .environment(\.layoutDirection,.rightToLeft)
        .privacySensitive()
    }
    private var home:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:7) {
                Image(systemName:"books.vertical.fill").font(.system(size:15,weight:.semibold)).widgetAccentable()
                Text("المحبرة").font(.custom("thmanyahsans-Bold",size:13,relativeTo:.caption))
                Spacer(minLength:0)
                if let count=snapshot?.shelfCount,count>0 {Text(WidgetCopy.agree(count,digits,one:"كتاب واحد",two:"كتابان",few:"كتب",many:"كتابًا")).font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1)}
            }.foregroundStyle(theme.accent)
            if locked {
                Spacer(minLength:0);Label("افتح مدار",systemImage:"lock").font(MadarTypography.section());Text("المحتوى محمي").font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).foregroundStyle(theme.secondaryInk);Spacer(minLength:0)
            } else if snapshot?.currentBook == nil && snapshot?.hadithToday == nil && snapshot?.lastNotebookLine == nil {
                Spacer(minLength:0);Text("ضع كتابًا على الطاولة").font(.custom("thmanyahserifdisplay-Bold",size:20,relativeTo:.title3));Text("أو اقرأ حديث اليوم").font(.custom("thmanyahsans-Regular",size:12,relativeTo:.caption)).foregroundStyle(theme.secondaryInk);Spacer(minLength:0)
            } else {
                if let book=snapshot?.currentBook {
                    VStack(alignment:.leading,spacing:3) {
                        Text(book.title).font(.custom("thmanyahserifdisplay-Bold",size:family == .systemSmall ? 20 : 22,relativeTo:.title2)).lineLimit(family == .systemSmall ? 2 : 2)
                        if !book.author.isEmpty {Text(book.author).font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1)}
                        if let pageLine {Text(pageLine).font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1)}
                    }
                } else if let hadith=snapshot?.hadithToday {
                    Text("حديث اليوم").font(.custom("thmanyahsans-Bold",size:11,relativeTo:.caption2)).foregroundStyle(theme.accent)
                    Text(hadith.title).font(.custom("thmanyahserifdisplay-Bold",size:20,relativeTo:.title3)).lineLimit(3)
                }
                if family != .systemSmall,let hadith=snapshot?.hadithToday,snapshot?.currentBook != nil {
                    Rectangle().fill(theme.line).frame(height:1)
                    VStack(alignment:.leading,spacing:3){Text(hadithLabel(hadith)).font(.custom("thmanyahsans-Bold",size:11,relativeTo:.caption2)).foregroundStyle(theme.accent);Text(hadith.title).font(.custom("thmanyahsans-Regular",size:12,relativeTo:.caption)).lineLimit(2)}
                }
                if largeHome,let line=snapshot?.lastNotebookLine {
                    Rectangle().fill(theme.line).frame(height:1)
                    Text(line).font(.custom("thmanyahseriftext-Regular",size:15,relativeTo:.body)).lineLimit(family == .systemLarge ? 3 : 5)
                }
                Spacer(minLength:0)
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
    @ViewBuilder private var accessory:some View {
        if family == .accessoryInline {
            Text("المحبرة، "+(locked ? "افتح مدار" : fallbackTitle ?? "رفّك")).font(.caption).lineLimit(1)
        } else if family == .accessoryCircular {
            ZStack {
                Circle().stroke(.primary.opacity(0.25),lineWidth:3)
                if !locked,let page=snapshot?.currentBook?.currentPage {
                    if let bookProgress {Circle().trim(from:0,to:bookProgress).stroke(.primary,style:.init(lineWidth:3,lineCap:.round)).rotationEffect(.degrees(-90))}
                    Text(digits.string(page)).font(.custom("thmanyahsans-Bold",size:14,relativeTo:.caption)).lineLimit(1).minimumScaleFactor(0.79)
                }
                else {Image(systemName:locked ? "lock.fill" : "books.vertical").font(.system(size:17,weight:.medium))}
            }.accessibilityElement(children:.ignore).accessibilityLabel(locked ? "المحبرة مقفلة" : "المحبرة، "+(bookTitle ?? "رفّك")).accessibilityValue(locked ? "" : pageLine ?? "")
        } else {
            HStack(spacing:8) {
                Image(systemName:locked ? "lock.fill" : "books.vertical.fill").font(.system(size:18,weight:.semibold))
                VStack(alignment:.leading,spacing:3) {
                    Text("المحبرة").font(.custom("thmanyahsans-Bold",size:11,relativeTo:.caption2))
                    Text(locked ? "افتح مدار" : fallbackTitle ?? "رفّك ينتظرك").font(.custom("thmanyahsans-Bold",size:13,relativeTo:.caption)).lineLimit(1)
                    if !locked,let pageLine {Text(pageLine).font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).lineLimit(1)}
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading)
        }
    }
}

private extension String {
    var nonEmpty:String? { isEmpty ? nil : self }
}

/// Arabic number agreement for widget copy: «مرة واحدة»، «مرتان»، «٣ مرات»، «١١ مرة». Real amounts, never a bare «٠ من ١».
enum WidgetCopy {
    static func agree(_ n:Int,_ digits:MadarNumberFormatter,one:String,two:String,few:String,many:String,withDigits:Bool=true)->String {
        if n==1{return one};if n==2{return two}
        let word=(3...10).contains(n%100) ? few : many
        return withDigits ? digits.string(n)+" "+word : word
    }
    /// Unit names in Arabic number agreement: one, two, 3–10, 11 and up. Built-in units plus the units people commonly
    /// type themselves, so «٨ كوب» reads «٨ أكواب»; any other unit the owner typed follows the number unchanged.
    static let unitTable:[String:[String]]=["minutes":["دقيقة واحدة","دقيقتان","دقائق","دقيقة"],"exerciseMinutes":["دقيقة حركة واحدة","دقيقتا حركة","دقائق حركة","دقيقة حركة"],
        "steps":["خطوة واحدة","خطوتان","خطوات","خطوة"],"pages":["صفحة واحدة","صفحتان","صفحات","صفحة"],"":["مرة واحدة","مرتان","مرات","مرة"],
        "كوب":["كوب واحد","كوبان","أكواب","كوبًا"],"كأس":["كأس واحدة","كأسان","كؤوس","كأسًا"],"لتر":["لتر واحد","لتران","لترات","لترًا"],
        "صفحة":["صفحة واحدة","صفحتان","صفحات","صفحة"],"دقيقة":["دقيقة واحدة","دقيقتان","دقائق","دقيقة"],"ساعة":["ساعة واحدة","ساعتان","ساعات","ساعة"],
        "ركعة":["ركعة واحدة","ركعتان","ركعات","ركعة"],"مرة":["مرة واحدة","مرتان","مرات","مرة"],"خطوة":["خطوة واحدة","خطوتان","خطوات","خطوة"],
        "آية":["آية واحدة","آيتان","آيات","آية"],"كيلو":["كيلو واحد","كيلوان","كيلوات","كيلو"],"تمرين":["تمرين واحد","تمرينان","تمارين","تمرينًا"]]
    /// After «من» the dual is genitive: «١ من كوبين»، «١ من دقيقتي حركة».
    static func unitCount(_ count:Int,_ unit:String?,_ digits:MadarNumberFormatter,genitive:Bool=false)->String {
        guard let forms=unitTable[(unit ?? "").trimmingCharacters(in:.whitespaces)] else { return digits.string(count)+" "+(unit ?? "") }
        if count==2 && genitive {
            var words=forms[1].split(separator:" ").map(String.init)
            if words[0].hasSuffix("ان") { words[0]=String(words[0].dropLast(2))+"ين" } else if words[0].hasSuffix("تا") { words[0]=String(words[0].dropLast())+"ي" }
            return words.joined(separator:" ")
        }
        return agree(count,digits,one:forms[0],two:forms[1],few:forms[2],many:forms[3])
    }
    /// Before anything is logged, the goal itself («الهدف: ٨ أكواب») rather than «٠ من ٨».
    static func habitProgress(value:Int,target:Int,measure:HabitMeasure,unit:String?,digits:MadarNumberFormatter)->String {
        if target==1 && (measure == .once || unit == nil){return value>=1 ? "تمّت" : "لم تتم بعد"}
        if value==0 { return "الهدف: "+unitCount(target,unit == nil ? "" : unit,digits) }
        return digits.string(value)+" من "+unitCount(target,unit == nil ? "" : unit,digits,genitive:true)
    }
    static func periodProgress(met:Int,total:Int,digits:MadarNumberFormatter)->String {
        if total==0{return "لا استحقاق"}
        if met==total{return total==1 ? "تمّت" : "تمّت كلها"}
        if met==0{
            switch total {case 1:return "عادة واحدة تنتظرك";case 2:return "عادتان تنتظرانك"
            default:return agree(total,digits,one:"",two:"",few:"عادات",many:"عادة")+" تنتظرك"}
        }
        return "تمّت "+digits.string(met)+" من "+digits.string(total)
    }
    static func habitsHeading(met:Int,total:Int,digits:MadarNumberFormatter)->String {
        if total==0{return "لا عادات اليوم"}
        if met==total{return total==1 ? "أتممت عادتك" : "أتممت عاداتك"}
        if met==0{return periodProgress(met:0,total:total,digits:digits)}
        return "تمّت "+digits.string(met)+" من "+digits.string(total)
    }
    static func daysLeft(_ n:Int,digits:MadarNumberFormatter,dayCount:(Int)->String)->String {
        n<=0 ? "اليوم" : n==1 ? "غدًا" : n==2 ? "يومان" : digits.string(n)+" "+dayCount(n)
    }
}
