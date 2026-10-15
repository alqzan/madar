import SwiftUI
import MadarCore
import MadarDesign

struct DiaryDayView: View {
    @Bindable var app: AppSession
    let day: GregorianDay
    @Environment(\.roomTheme) private var roomTheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: GregorianDay?
    @State private var page: DiaryDisplayDay?
    @State private var failure: String?
    @State private var writing = false
    @State private var retry = 0
    @State private var intentions:[DiaryIntention]=[]
    @State private var intentionsOpen=false
    @State private var niyyaSaved=false
    @State private var appearance:DiaryDayAppearance?
    @State private var returnDay:GregorianDay?
    @State private var returnDismissed=false
    @State private var archiveOpen=false
    @State private var weekOpen=false
    @State private var searchOpen=false
    @State private var displayNow=Date()
    @State private var travel:DiaryTravelPage?
    @State private var stampsOpen=false
    @State private var editing:DiaryLineEdit?
    @State private var original:DiaryLineEdit?
    /// Travel days wear the air-mail paper everywhere on the page and in its sheets (§7.3).
    private var theme:RoomTheme {travel == nil ? roomTheme:RoomTheme(room:"notes.travel",dark:roomTheme.dark)}
    private var friday:Bool {appearance?.friday == true && travel == nil}
    private var shownDay: GregorianDay { selected ?? day }
    private var service: AppDiaryService { AppDiaryService(app: app) }
    private var today: GregorianDay { (try? service.currentDay()) ?? day }
    private var first: FirstCalendar { FirstCalendar(rawValue: app.string("core.firstCalendar")) ?? .hijri }
    private var eveningPrimary:Bool {shownDay==today && !intentions.isEmpty && service.intentionEvening(shownDay)}
    private var secondInk: Color { switch app.string("notes.secondInk") { case "green": theme.color("ghad"); case "brown": theme.color("autoInkText"); default: theme.color("pencil") } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let appearance,let ramadanDay=appearance.ramadanDay {
                    HStack{VStack(alignment:.leading,spacing:6){Text("رمضان · اليوم: "+service.digits.string(ramadanDay)).font(DiaryType.label);if let iftar=appearance.iftarAt {Text("الإفطار بعد "+countdown(iftar)).font(DiaryType.heading)}else{Text(appearance.night ? "ليلة من رمضان":"رمضان").font(DiaryType.heading)}};Spacer()}.padding(16).background((MadarToken.colors[theme.dark ? "rooms.notes.ramadan.accentDark":"rooms.notes.ramadan.accent"] ?? theme.accent).opacity(0.12),in:.rect(cornerRadius:16)).padding(.horizontal,18).padding(.vertical,6).accessibilityElement(children:.combine).accessibilityIdentifier("diary-ramadan")
                }

                if let travel {
                    DiaryTravelHeader(page:travel,subtitle:service.weekday(shownDay)+"، "+service.dateTitle(shownDay,calendar:first),distance:service.kilometres(travel.kilometres),digits:service.digits)
                } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(service.weekday(shownDay) + "، " + service.dateTitle(shownDay, calendar: first == .hijri ? .gregorian : .hijri) + (friday ? "، " + service.dateTitle(shownDay,calendar:first):""))
                        .font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                    Text(friday ? "جمعة مباركة" : (first == .hijri && appearance?.night == true ? "ليلة " : "") + service.dateTitle(first == .hijri ? appearance?.hijriDisplayDay ?? shownDay : shownDay, calendar: first)).foregroundStyle(friday ? theme.accent:theme.ink).font(.custom("thmanyahserifdisplay-Bold", size: 32, relativeTo: .largeTitle)).accessibilityIdentifier("diary-day-title")
                    if !friday { HStack(spacing: 6) {
                        dateChoice("اليوم", id: "today", value: today)
                        dateChoice("أمس", id: "yesterday", value: today.adding(days: -1))
                        dateChoice("قبل سنة", id: "year", value: aYearAgo)
                        Spacer(minLength: 0)
                        if shownDay == today { Text("حتى الآن").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
                    }
                    }
                }.padding(.horizontal,18).padding(.vertical,10).frame(maxWidth:.infinity,alignment:friday ? .center:.leading).overlay{if friday {DiaryFridayFrame().stroke(theme.accent.opacity(0.65),lineWidth:0.7).padding(.horizontal,12)}}
                }
                if let returnDay,!returnDismissed {
                    VStack(alignment:.leading,spacing:8){
                        Text("آخر صفحة كتبتها: "+service.dateTitle(returnDay,calendar:first)).font(DiaryType.label)
                        Text("يمكنك أن تبدأ من اليوم أو تفتح يومًا سابقًا. لا تحتاج إلى تعويض شيء.").font(MadarTypography.body())
                        HStack(spacing:8){
                            Button{archiveOpen=true}label:{Text("افتح يومًا سابقًا").frame(maxWidth:.infinity,minHeight:44).overlay{Capsule().stroke(theme.line)}}.accessibilityIdentifier("diary-return-days")
                            Button{returnDismissed=true;writing=true}label:{Text("ابدأ من اليوم").frame(maxWidth:.infinity,minHeight:44).foregroundStyle(theme.background).background(theme.ink,in:.capsule)}.accessibilityIdentifier("diary-return-write")
                        }.font(DiaryType.label).buttonStyle(.plain)
                    }.padding(16).overlay(alignment:.bottom){Rectangle().fill(theme.line).frame(height:1)}.accessibilityElement(children:.contain).accessibilityIdentifier("diary-return")
                }
                if appearance?.weekAvailable == true,typeSize.isAccessibilitySize {
                    HStack{Button("صندوق الأسبوع"){weekOpen=true}.accessibilityIdentifier("diary-week-open");Spacer();Text("يوم الجمعة").foregroundStyle(theme.color("ghad"))}.font(DiaryType.label).frame(minHeight:44).padding(.horizontal,22)
                }
                if shownDay == today || !intentions.isEmpty {
                    Button {intentionsOpen=true} label:{
                        HStack(alignment:.firstTextBaseline,spacing:10){Text("النيّة").font(DiaryType.label).foregroundStyle(theme.accent);Text(intentions.first?.text ?? "أضف نيّتك لليوم").font(DiaryType.writing).frame(maxWidth:.infinity,alignment:.leading).lineLimit(2);Image(systemName:"chevron.backward").font(.caption)}.padding(.horizontal,18).frame(minHeight:54).contentShape(.rect)
                    }.buttonStyle(.plain).accessibilityIdentifier("diary-niyya-open")
                }
                GeometryReader { geometry in ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let page {
                            ForEach(page.lines.filter{$0.kind != "intention"}) { line in
                                lineRow(line, page: page)
                                ForEach(page.media.filter { $0.entryID == line.id }) { media in DiaryMediaCard(app: app, media: media, transcript: line.text) }
                            }
                            if !page.media.contains(where: { $0.id == page.photoID }), let data = page.photo, let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 150).padding(8).background(theme.surface)
                                    .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(width: 48, height: 16).rotationEffect(.degrees(-5)).offset(y: -8) }
                                    .rotationEffect(.degrees(-2)).shadow(color: theme.ink.opacity(0.1), radius: 5, y: 5)
                                    .padding(.vertical, 24).frame(maxWidth: .infinity, alignment: .center).accessibilityLabel("صورة من هذا اليوم")
                            }
                            if page.lines.isEmpty && page.photo == nil { Text(shownDay == today ? "صفحة تنتظر سطرك." : "لم تُكتب سطور في هذا اليوم.").font(DiaryType.writing).foregroundStyle(theme.color("ink3Text")).padding(.vertical, 40).padding(.horizontal, 54) }
                        } else if failure == nil { ProgressView("تُفتح الصفحة…").padding(30) }
                        if let failure {
                            VStack(alignment: .leading, spacing: 10) { Text(failure).font(MadarTypography.body()); Button("حاول مرة أخرى") { retry += 1 }.frame(minHeight: 44) }.padding(20)
                        }
                        Spacer(minLength: 70)
                    }.padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight:geometry.size.height,alignment:.topLeading).background {
                        Canvas { context, size in
                            var rules = Path()
                            for y in stride(from: 14.0, through: size.height, by: 34) { rules.move(to: .init(x: 0, y: y)); rules.addLine(to: .init(x: size.width, y: y)) }
                            context.stroke(rules, with: .color(theme.line), lineWidth: 0.7)
                            var margin = Path(); margin.move(to: .init(x: size.width-50, y: 0)); margin.addLine(to: .init(x: size.width-50, y: size.height))
                            context.stroke(margin, with: .color(theme.color("margin")), lineWidth: 1)
                        }
                    }
                }.overlay(alignment:.topTrailing){if let travel,!typeSize.isAccessibilitySize {DiaryPassportStamp(city:travel.city,date:service.shortDate(travel.arrival)).padding(.top,40).padding(.trailing,4)}}.overlay(alignment:.topTrailing){if friday,!typeSize.isAccessibilitySize {HStack(alignment:.top,spacing:5){ribbon("يوم الجمعة",color:theme.accent,height:88);if appearance?.weekAvailable == true {Button{weekOpen=true}label:{ribbon("صندوق الأسبوع",color:theme.color("ghad"),height:130).frame(width:44).contentShape(.rect)}.buttonStyle(.plain).accessibilityIdentifier("diary-week-open")}}.padding(.trailing,12)}}
                }
            }.background(theme.background).foregroundStyle(theme.ink).environment(\.roomTheme,theme)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    HStack(spacing:10){
                        if let travel,shownDay == today {
                            Button { writing = true } label: { Text("اكتب من " + travel.city).font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(theme.color("onButton")).background(theme.color("button"),in:.capsule) }.buttonStyle(.plain).accessibilityIdentifier("diary-day-write")
                        } else {
                        Button { writing = true } label: { Label(shownDay == today ? "اكتب" : "اكتب في هامشها", systemImage: "pencil").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(eveningPrimary ? theme.ink:theme.background).background(eveningPrimary ? theme.surface:(theme.dark ? theme.accent:theme.ink),in:.capsule) }.buttonStyle(.plain).accessibilityIdentifier("diary-day-write")

                        }
                        if travel != nil {Button{stampsOpen=true}label:{Text("الأختام").font(DiaryType.label).frame(minHeight:54).padding(.horizontal,18).overlay{Capsule().stroke(theme.line)}}.buttonStyle(.plain).accessibilityIdentifier("diary-stamps-open")}
                        if shownDay==today,!intentions.isEmpty {Button{intentionsOpen=true}label:{Text("حصيلة النيّات").font(DiaryType.label).frame(minHeight:54).padding(.horizontal,16).foregroundStyle(service.intentionEvening(shownDay) ? theme.background:theme.ink).background(service.intentionEvening(shownDay) ? (theme.dark ? theme.accent:theme.ink):theme.surface,in:.capsule).overlay{Capsule().stroke(theme.line)}}.buttonStyle(.plain).accessibilityIdentifier("diary-niyya-evening")}
                    }.padding(.horizontal,18).padding(.vertical,8).background(theme.background)
                }
                .toolbar {
                    ToolbarItemGroup(placement:.topBarTrailing){Button{searchOpen=true}label:{Image(systemName:"magnifyingglass")}.accessibilityLabel("ابحث في مذكراتك");Button{archiveOpen=true}label:{Image(systemName:"book.closed")}.accessibilityLabel("أيامك")}
                    ToolbarItem(placement:.topBarTrailing){if niyyaSaved,app.undoToken != nil{Button("تراجع"){app.undo();niyyaSaved=false}.accessibilityIdentifier("diary-day-niyya-undo")}}
                    ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Label("المذكرات", systemImage: "chevron.backward") }.accessibilityIdentifier("diary-day-close") }
                }
                .toolbarBackground(theme.background, for: .navigationBar).tint(theme.accent)
                .fullScreenCover(isPresented:$searchOpen){DiarySearchView(app:app).environment(\.roomTheme,theme)}
                .fullScreenCover(isPresented:$archiveOpen){DiaryHubView(app:app).environment(\.roomTheme,theme)}
                .sheet(item:$editing){edit in DiaryLineEditSheet(app:app,edit:edit){niyyaSaved=true}.environment(\.roomTheme,theme)}
                .sheet(item:$original){first in DiaryOriginalSheet(text:first.text).environment(\.roomTheme,theme).presentationDetents([.medium,.large])}
                .sheet(isPresented:$stampsOpen){DiaryStampsView(app:app).environment(\.roomTheme,theme)}
                .sheet(isPresented:$weekOpen){DiaryWeekView(app:app,day:shownDay).environment(\.roomTheme,theme)}
                .sheet(isPresented:$intentionsOpen){DiaryIntentionsView(app:app,day:shownDay,evening:service.intentionEvening(shownDay)).environment(\.roomTheme,theme)}
                .sheet(isPresented: $writing) { DiaryTextEditor(app: app, margin: shownDay == today ? nil : shownDay).environment(\.roomTheme, theme) }
                .task {while !Task.isCancelled {do{try await Task.sleep(for:.seconds(30));displayNow=service.clock();appearance=try service.appearance(shownDay)}catch{break}}}
                .task(id: shownDay.description + ":" + String(app.prayerRevision) + ":" + String(retry)) {
                    do { try await service.prepareClosedDay(shownDay); page = try service.day(shownDay); intentions=try service.intentions(shownDay); appearance=try service.appearance(shownDay);displayNow=service.clock();returnDay=try service.returnAfterAbsence(shownDay);travel=try service.travel(shownDay); failure = nil }
                    catch { page = nil; failure = error.localizedDescription }
                }
        }
    }
    private func ribbon(_ title:String,color:Color,height:CGFloat)->some View {Text(title).font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).foregroundStyle(theme.background).fixedSize().rotationEffect(.degrees(90)).frame(width:24,height:height-8).frame(height:height,alignment:.top).background(DiaryRibbonShape().fill(color)).accessibilityLabel(title)}
    private func countdown(_ date:Date)->String {
        let formatter=DateComponentsFormatter();formatter.unitsStyle = .full;formatter.allowedUnits=[.hour,.minute];formatter.maximumUnitCount=2
        var calendar=Calendar(identifier:.gregorian);calendar.locale=Locale(identifier:app.string("core.numerals")=="western" ? "ar_SA@numbers=latn":"ar_SA@numbers=arab");formatter.calendar=calendar
        return formatter.string(from:max(0,date.timeIntervalSince(displayNow))) ?? "أقل من دقيقة"
    }

    private var aYearAgo: GregorianDay {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = app.activePlace.timeZone
        return calendar.date(byAdding: .year, value: -1, to: today.date(in: app.activePlace.timeZone)).map { GregorianDay.containing($0, in: app.activePlace.timeZone) } ?? today.adding(days: -365)
    }
    private func dateChoice(_ title: String, id: String, value: GregorianDay) -> some View {
        Button { selected = value } label: { Text(title).font(DiaryType.label).frame(minHeight: 44).padding(.horizontal, 12).background(shownDay == value ? theme.surface : .clear, in: .rect(topLeadingRadius: 10, topTrailingRadius: 10)).overlay { UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10).stroke(shownDay == value ? theme.color("ink3Text") : theme.line) } }
            .buttonStyle(.plain).accessibilityIdentifier("diary-day-" + id).accessibilityAddTraits(shownDay == value ? .isSelected : [])
    }
    private func lineRow(_ line: DiaryDisplayLine, page: DiaryDisplayDay) -> some View {
        let auto = ["salah", "quran"].contains(line.kind)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(service.time(line.at)).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.color("ink3Text")).frame(width: 38, alignment: .center)
            VStack(alignment: .leading, spacing: 5) {
                Text(line.text).font(.custom("thmanyahseriftext-Regular", size: auto ? 17 : 19, relativeTo: .body)).lineSpacing(11).italic(auto || line.kind == "margin")
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu {
                        if page.editable.contains(line.id) {Button("عدّل السطر",systemImage:"pencil"){editing = .init(id:line.id,text:line.text)}}
                        if shownDay==today,["normal","late","ghad"].contains(line.kind),!line.text.isEmpty {Button("اجعلها نيّة اليوم"){Task{do{try await service.saveIntention(line.text,day:shownDay);niyyaSaved=true}catch{failure=error.localizedDescription}}}}
                    }
                if let first = page.originals[line.id] {
                    Button{original = .init(id:line.id,text:first)}label:{Text("عُدّل · الأصل").font(DiaryType.label).frame(minHeight:30)}.buttonStyle(.plain).foregroundStyle(theme.color("ink3Text")).accessibilityIdentifier("diary-line-edited")
                }
                if line.kind == "late" { Text("كُتبت لاحقًا").font(DiaryType.label) }
                if line.kind == "margin" {
                    Text("هامش · " + (page.marginDays[line.id].map { service.dateTitle($0, calendar: .gregorian) } ?? "تاريخ الكتابة غير متاح")).font(DiaryType.label)
                }
                if auto { Text(line.kind == "salah" ? "الصلاة" : "القرآن").font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)) }
            }.foregroundStyle(line.kind == "margin" ? secondInk : line.kind == "late" ? theme.color("late") : auto ? theme.color("autoInkText") : theme.ink)
        }.padding(.leading, 6).padding(.trailing, travel == nil || typeSize.isAccessibilitySize ? 18 : 92).padding(.vertical, 10).frame(minHeight: 34)
    }
}
