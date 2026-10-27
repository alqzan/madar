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
    @State private var arc:DiaryDayArc?
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
    @State private var travelReturn:DiaryTravelReturn?
    @Environment(\.scenePhase) private var scenePhase
    @State private var stampsOpen=false
    @State private var editing:DiaryLineEdit?
    @State private var deleteConfirmation: UUID?
    @State private var original:DiaryLineEdit?
    @State private var waitingLetter:DiaryLetterCard?
    @State private var openingLetter:DiaryLetterCard?
    @State private var sealedHere=0
    @State private var projectLinks:[String:String]=[:]
    @State private var projectSuggestions:[String:DiaryProjectCard]=[:]
    /// Travel days wear the air-mail paper everywhere on the page and in its sheets (§7.3).
    private var theme:RoomTheme {travel == nil ? roomTheme:RoomTheme(room:"notes.travel",dark:roomTheme.dark)}
    private var friday:Bool {appearance?.friday == true && travel == nil}
    private var shownDay: GregorianDay { selected ?? day }
    private var fridayStyle:DiaryFridayStyle {DiaryFridayStyle(app)}
    /// OR-16: the Friday title wears the look chosen in the diary settings.
    @ViewBuilder private var fridayOrnament:some View {
        switch fridayStyle {
        case .ribbon: DiaryFridayFrame().stroke(theme.accent.opacity(0.65),lineWidth:0.7).padding(.horizontal,12)
        case .mihrab: ZStack(alignment:.top){DiaryMihrabShape().stroke(theme.accent.opacity(0.55),lineWidth:1).padding(.horizontal,56);DiaryStarShape().fill(theme.accent).frame(width:22,height:22).padding(.top,16)}.accessibilityHidden(true).accessibilityIdentifier("diary-friday-mihrab")
        case .medallion: ZStack{Circle().stroke(theme.accent.opacity(0.6),lineWidth:1);DiaryStarShape().fill(theme.accent).frame(width:18,height:18)}.frame(width:36,height:36).frame(maxHeight:.infinity,alignment:.top).accessibilityHidden(true).accessibilityIdentifier("diary-friday-medallion")
        }
    }
    private var service: AppDiaryService { AppDiaryService(app: app) }
    private var today: GregorianDay { (try? service.currentDay()) ?? day }
    private var first: FirstCalendar { FirstCalendar(rawValue: app.string("core.firstCalendar")) ?? .hijri }
    private var eveningPrimary:Bool {shownDay==today && !intentions.isEmpty && service.intentionEvening(shownDay)}
    private var secondInk: Color { switch app.string("notes.secondInk") { case "green": theme.color("ghad"); case "brown": theme.color("autoInkText"); default: theme.color("pencil") } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let appearance,let ramadanDay=appearance.ramadanDay {
                    DiaryRamadanBanner(style:DiaryRamadanStyle(app),dayText:"اليوم "+service.digits.string(ramadanDay)+" من رمضان",headline:appearance.iftarAt.map{"الإفطار بعد "+countdown($0)} ?? (appearance.night ? "ليلة من رمضان":"رمضان")).padding(.horizontal,18).padding(.vertical,6).accessibilityIdentifier("diary-ramadan")
                }

                if let travel {
                    DiaryTravelHeader(page:travel,subtitle:service.bothDates(shownDay,calendar:first),distance:service.kilometres(travel.kilometres),digits:service.digits)
                } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(service.weekday(shownDay) + "، " + (first == .gregorian && appearance?.night == true ? "ليلة " : "") + service.dateTitle(first == .gregorian ? appearance?.hijriDisplayDay ?? shownDay : shownDay, calendar: first == .hijri ? .gregorian : .hijri) + (friday ? "، " + service.dateTitle(shownDay,calendar:first):""))
                        .font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).accessibilityIdentifier("diary-day-secondary-date")
                    // OR-12: the date and its three tabs share one row, as the canonical today page; «حتى الآن» left (lighter header).
                    let title = Text(friday ? "جمعة مباركة" : (first == .hijri && appearance?.night == true ? "ليلة " : "") + service.dateTitle(first == .hijri ? appearance?.hijriDisplayDay ?? shownDay : shownDay, calendar: first)).foregroundStyle(friday ? theme.accent:theme.ink).font(.custom("thmanyahserifdisplay-Bold", size: 32, relativeTo: .largeTitle)).lineLimit(1).minimumScaleFactor(0.7).accessibilityIdentifier("diary-day-title")
                    if friday { title } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .bottom, spacing: 8) { title; Spacer(minLength: 4); tabs }
                            VStack(alignment: .leading, spacing: 8) { title; tabs }
                        }
                    }
                }.padding(.horizontal,18).padding(.vertical,10).frame(maxWidth:.infinity,alignment:friday ? .center:.leading).padding(.top,friday && fridayStyle != .ribbon ? 34:0).background{if friday {fridayOrnament}}
                }
                if let returnDay,!returnDismissed {
                    VStack(alignment:.leading,spacing:8){
                        Text("آخر صفحة كتبتها: "+service.bothDates(returnDay,calendar:first)).font(DiaryType.label)
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
                if let travelReturn {
                    DiaryTravelReturnCard(trip:travelReturn,days:dayCount(travelReturn.days),distance:service.kilometres(travelReturn.kilometres)){stampsOpen=true}.padding(.horizontal,18).padding(.vertical,6)
                }
                if shownDay == today,let waitingLetter {
                    DiaryLetterWaitingCard(letter:waitingLetter,digitsTitle:service.bothDates(waitingLetter.writtenDay)){openingLetter=waitingLetter}.padding(.horizontal,18).padding(.vertical,6)
                }
                if shownDay == today,travel == nil,let arc {DiaryDayArcView(arc:arc).padding(.horizontal,18).padding(.top,2)}
                if eveningPrimary,let first=intentions.first {
                    eveningIntention(first)
                } else if shownDay == today || !intentions.isEmpty {
                    Button {intentionsOpen=true} label:{
                        HStack(alignment:.firstTextBaseline,spacing:10){Text("النيّة").font(DiaryType.label).foregroundStyle(theme.accent);VStack(alignment:.leading,spacing:2){Text(intentions.first?.text ?? "أضف نيّتك لليوم").font(DiaryType.writing).lineLimit(2);if shownDay == today,!intentions.isEmpty {Text("أسألك عنها بعد العشاء").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))}}.frame(maxWidth:.infinity,alignment:.leading);Image(systemName:"chevron.backward").font(.caption)}.padding(.horizontal,18).frame(minHeight:54).contentShape(.rect)
                    }.buttonStyle(.plain).accessibilityIdentifier("diary-niyya-open")
                }
                GeometryReader { geometry in ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let page {
                            ForEach(page.lines.filter{$0.kind != "intention"}) { line in
                                lineRow(line, page: page)
                                let attached = page.media.filter { $0.entryID == line.id }
                                ForEach(attached.filter { $0.kind != "missing" }) { media in DiaryMediaCard(app: app, media: media, transcript: line.text) }
                                // Owner real-data trial, 24 Oct 2026: one line for the entry's missing files, not one per file.
                                if let first = attached.first(where: { $0.kind == "missing" }) {
                                    DiaryMediaCard(app: app, media: first, transcript: line.text, missingCount: attached.filter { $0.kind == "missing" }.count)
                                }
                            }
                            ForEach(0..<sealedHere,id:\.self){_ in
                                HStack(alignment:.center,spacing:12){
                                    DiaryEnvelope(sealed:true).frame(width:38,height:26)
                                    Text("رسالة مختومة تُفتح في وقتها، ولا تُقرأ قبله").font(DiaryType.writing).redacted(reason:.placeholder).blur(radius:2.2).accessibilityHidden(true)
                                }.padding(.leading,6).padding(.trailing,18).padding(.vertical,10).accessibilityElement(children:.ignore).accessibilityLabel("رسالة مختومة").accessibilityIdentifier("diary-sealed-letter-line")
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
                }.overlay(alignment:.topTrailing){if let travel,!typeSize.isAccessibilitySize {DiaryPassportStamp(city:travel.city,date:service.stampDate(travel.arrival)).padding(.top,40).padding(.trailing,4)}}.overlay(alignment:.topTrailing){if friday,!typeSize.isAccessibilitySize {HStack(alignment:.top,spacing:5){if fridayStyle == .ribbon {ribbon("يوم الجمعة",color:theme.accent,height:88)};if appearance?.weekAvailable == true {Button{weekOpen=true}label:{ribbon("صندوق الأسبوع",color:theme.color("ghad"),height:130).frame(width:44).contentShape(.rect)}.buttonStyle(.plain).accessibilityIdentifier("diary-week-open")}}.padding(.trailing,12)}}
                }
            }.background(theme.background).foregroundStyle(theme.ink).environment(\.roomTheme,theme)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 8) {
                    if app.undoToastVisible {
                        UndoToast(message: app.undoMessage, undo: app.undo)
                            .accessibilityIdentifier("diary-day-undo")
                    }
                    HStack(spacing:10){
                        if let travel,shownDay == today {
                            Button { writing = true } label: { Text("اكتب من " + travel.city).font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(theme.color("onButton")).background(theme.color("button"),in:.capsule) }.buttonStyle(.plain).accessibilityIdentifier("diary-day-write")
                        } else {
                        Button { writing = true } label: { Label(shownDay == today ? "اكتب" : "اكتب في هامشها", systemImage: "pencil").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(theme.background).background(theme.dark ? theme.accent:theme.ink,in:.capsule) }.buttonStyle(.plain).accessibilityIdentifier("diary-day-write")

                        }
                        if travel != nil {Button{stampsOpen=true}label:{Text("الأختام").font(DiaryType.label).frame(minHeight:54).padding(.horizontal,18).overlay{Capsule().stroke(theme.line)}}.buttonStyle(.plain).accessibilityIdentifier("diary-stamps-open")}
                    }.padding(.horizontal,18).padding(.vertical,8).background(theme.background)
                    }.background(theme.background)
                }
                .toolbar {
                    ToolbarItemGroup(placement:.topBarTrailing){Button{searchOpen=true}label:{Image(systemName:"magnifyingglass")}.accessibilityLabel("ابحث في مذكراتك");Button{archiveOpen=true}label:{Image(systemName:"book.closed")}.accessibilityLabel("أيامك")}
                    ToolbarItem(placement:.topBarTrailing){if niyyaSaved,app.undoToken != nil{Button("تراجع"){app.undo();niyyaSaved=false}.accessibilityIdentifier("diary-day-niyya-undo")}}
                    ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Label("المذكرات", systemImage: "chevron.backward") }.accessibilityIdentifier("diary-day-close") }
                }
                .toolbarBackground(theme.background, for: .navigationBar).tint(theme.accent)
                .alert("احذف السطر؟", isPresented: Binding(get: { deleteConfirmation != nil }, set: { if !$0 { deleteConfirmation = nil } })) {
                    Button("إلغاء", role: .cancel) { deleteConfirmation = nil }
                    Button("احذف", role: .destructive) {
                        guard let id = deleteConfirmation else { return }
                        deleteConfirmation = nil
                        Task {
                            do { try await app.executeDiaryCommand("diary.deleteEntry", payload: ["entryID": .string(id.uuidString)]) }
                            catch { failure = error.localizedDescription }
                        }
                    }.accessibilityIdentifier("diary-line-delete-confirm")
                } message: {
                    Text("تبقى الهوامش في يوم كتابتها، ويمكنك التراجع عن الحذف خلال عشر دقائق.")
                }
                .fullScreenCover(isPresented:$searchOpen){DiarySearchView(app:app).environment(\.roomTheme,theme)}
                .fullScreenCover(isPresented:$archiveOpen){DiaryHubView(app:app).environment(\.roomTheme,theme)}
                .sheet(item:$openingLetter,onDismiss:{retry+=1}){letter in DiaryLetterMoment(app:app,letter:letter).environment(\.roomTheme,theme)}
                .sheet(item:$editing){edit in DiaryLineEditSheet(app:app,edit:edit){niyyaSaved=true}.environment(\.roomTheme,theme)}
                .sheet(item:$original){first in DiaryOriginalSheet(text:first.text).environment(\.roomTheme,theme).presentationDetents([.medium,.large])}
                .sheet(isPresented:$stampsOpen){DiaryStampsView(app:app).environment(\.roomTheme,theme)}
                .sheet(isPresented:$weekOpen){DiaryWeekView(app:app,day:shownDay).environment(\.roomTheme,theme)}
                .sheet(isPresented:$intentionsOpen){DiaryIntentionsView(app:app,day:shownDay,evening:service.intentionEvening(shownDay)).environment(\.roomTheme,theme)}
                .sheet(isPresented: $writing) { DiaryTextEditor(app: app, margin: shownDay == today ? nil : shownDay).environment(\.roomTheme, theme) }
                // N04: letters are checked when the diary is open and the app comes to the foreground.
                .onChange(of:scenePhase){_,phase in if phase == .active {retry+=1}}
                .task {while !Task.isCancelled {do{try await Task.sleep(for:.seconds(30));displayNow=service.clock();appearance=try service.appearance(shownDay);arc=service.dayArc(shownDay)}catch{break}}}
                .task(id: shownDay.description + ":" + String(app.prayerRevision) + ":" + String(retry)) {
                    do { try await service.prepareClosedDay(shownDay); page = try service.day(shownDay); intentions=try service.intentions(shownDay);arc=service.dayArc(shownDay); appearance=try service.appearance(shownDay);displayNow=service.clock();returnDay=try service.returnAfterAbsence(shownDay);travel=try service.travel(shownDay);travelReturn=travel == nil ? try service.travelReturn(shownDay):nil
                        if shownDay == today {try? await service.refreshLetters()}
                        let letters=try service.letters();waitingLetter=letters.first{$0.state == .eligible};sealedHere=letters.filter{$0.writtenDay==shownDay && $0.state != .opened}.count
                        (projectLinks,projectSuggestions)=try service.projectNotes(shownDay); failure = nil }
                    catch { page = nil; failure = error.localizedDescription }
                }
        }
    }
    /// OR-15: after Isha the morning's intention comes back on the page itself and asks how it went.
    private func eveningIntention(_ row:DiaryIntention)->some View {
        VStack(alignment:.leading,spacing:10){
            HStack{Text("نويت صباحًا").font(DiaryType.label).foregroundStyle(theme.accent);Spacer();if intentions.count>1 {Button("و"+service.digits.string(intentions.count-1)+" غيرها"){intentionsOpen=true}.font(DiaryType.label).frame(minHeight:44).accessibilityIdentifier("diary-niyya-more")}}
            Button{intentionsOpen=true}label:{Text(row.text).font(DiaryType.writing).frame(maxWidth:.infinity,alignment:.leading).lineLimit(3)}.buttonStyle(.plain).accessibilityIdentifier("diary-niyya-open")
            HStack(spacing:6){ForEach([("done","تمّت"),("partial","جزئيًا"),("notEasy","ما تيسّرت")],id:\.0){value,title in
                Button{Task{@MainActor in do{try await service.setIntentionResult(row.id,result:row.result==value ? nil:value);intentions=try service.intentions(shownDay);niyyaSaved=true}catch{failure=error.localizedDescription}}}label:{Text(title).font(DiaryType.label).frame(maxWidth:.infinity,minHeight:44).foregroundStyle(row.result==value ? theme.background:theme.ink).background(row.result==value ? (theme.dark ? theme.accent:theme.ink):.clear,in:.capsule).overlay{Capsule().stroke(theme.line)}}.buttonStyle(.plain).accessibilityIdentifier("diary-niyya-inline-"+value).accessibilityAddTraits(row.result==value ? .isSelected:[])
            }}
        }.padding(14).background(theme.surface,in:.rect(cornerRadius:18)).overlay{RoundedRectangle(cornerRadius:18).stroke(theme.line)}.padding(.horizontal,18).padding(.vertical,6).accessibilityElement(children:.contain).accessibilityIdentifier("diary-niyya-evening")
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
    private var tabs: some View {
        HStack(spacing: 4) {
            dateChoice("اليوم", id: "today", value: today)
            dateChoice("أمس", id: "yesterday", value: today.adding(days: -1))
            dateChoice("قبل سنة", id: "year", value: aYearAgo)
        }.fixedSize()
    }
    private func dateChoice(_ title: String, id: String, value: GregorianDay) -> some View {
        Button { selected = value } label: { Text(title).font(DiaryType.label).frame(minHeight: 44).padding(.horizontal, 10).background(shownDay == value ? theme.surface : .clear, in: .rect(topLeadingRadius: 10, topTrailingRadius: 10)).overlay { UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10).stroke(shownDay == value ? theme.color("ink3Text") : theme.line) } }
            .buttonStyle(.plain).accessibilityIdentifier("diary-day-" + id).accessibilityAddTraits(shownDay == value ? .isSelected : [])
    }
    /// Arabic counted noun: يوم واحد، يومان، ٣–١٠ أيام، ١١–٩٩ يومًا، ١٠٠ يوم.
    private func dayCount(_ n:Int)->String {
        if n == 1 {return "يوم واحد"};if n == 2 {return "يومان"}
        let r=n%100;return service.digits.string(n)+((3...10).contains(r) ? " أيام":r <= 2 ? " يوم":" يومًا")
    }
    private static let rooms = ["salah": "الصلاة", "quran": "القرآن", "mal": "المال", "habits": "العادات", "mihbara": "المحبرة"]
    /// RU1: the joiner picks «، » when the line ends in a digit.
    private func roomSuffix(_ line: DiaryDisplayLine) -> String {
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines), joined = MadarInlineText.joined([text, Self.rooms[line.kind] ?? ""])
        return String(joined.dropFirst(text.count))
    }
    private func lineRow(_ line: DiaryDisplayLine, page: DiaryDisplayDay) -> some View {
        let auto = ["salah", "quran", "mihbara", "mal", "habits"].contains(line.kind)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(service.time(line.at, zone: line.tzID)).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.color("ink3Text")).frame(width: 38, alignment: .center).accessibilityIdentifier("diary-day-line-time")
            VStack(alignment: .leading, spacing: 5) {
                // OR-12: the room's name follows its line, small and in the same light ink («· الصلاة»), as the canonical.
                (Text(line.markdown == true ? ((try? AttributedString(markdown: line.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(line.text)) : AttributedString(line.text))
                    + Text(auto ? roomSuffix(line) : "").font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)))
                    .font(.custom("thmanyahseriftext-Regular", size: auto ? 17 : 19, relativeTo: .body)).lineSpacing(11).italic(auto || line.kind == "margin")
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("diary-day-line")
                if let name = projectLinks[line.id] {Text("مشروع: "+name).font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).accessibilityIdentifier("diary-line-project")}
                else if let project = projectSuggestions[line.id] {
                    Button{Task{do{try await service.link(line.id,to:project.id);niyyaSaved=true}catch{failure=error.localizedDescription}}}label:{Text("يتعلّق بـ«"+project.name+"»؟").font(DiaryType.label).padding(.horizontal,10).frame(minHeight:30).overlay{Capsule().stroke(theme.line)}}.buttonStyle(.plain).accessibilityIdentifier("diary-line-project-suggest")
                }
                if let first = page.originals[line.id] {
                    Button{original = .init(id:line.id,text:first)}label:{Text("عُدّل · الأصل").font(DiaryType.label).frame(minHeight:30)}.buttonStyle(.plain).foregroundStyle(theme.color("ink3Text")).accessibilityIdentifier("diary-line-edited")
                }
                if line.kind == "late" { Text("كُتبت لاحقًا").font(DiaryType.label) }
                if line.kind == "margin" {
                    Text(MadarInlineText.joined(["هامش", page.marginDays[line.id].map { service.bothDates($0) } ?? "تاريخ الكتابة غير متاح"])).font(DiaryType.label)
                }
            }.foregroundStyle(line.kind == "margin" ? secondInk : line.kind == "late" ? theme.color("late") : auto ? theme.color("autoInkText") : theme.ink)
        }.contextMenu {
            if page.editable.contains(line.id) { Button("عدّل السطر", systemImage: "pencil") { editing = .init(id: line.id, text: line.text) } }
            if page.deletable.contains(line.id), let id = UUID(uuidString: line.id) {
                Button(role: .destructive) { deleteConfirmation = id } label: { Label("احذف السطر", systemImage: "trash") }
                    .accessibilityIdentifier("diary-line-delete")
            }
            if shownDay == today, ["normal", "late", "ghad"].contains(line.kind), !line.text.isEmpty {
                Button("اجعلها نيّة اليوم") { Task { do { try await service.saveIntention(line.text, day: shownDay); niyyaSaved = true } catch { failure = error.localizedDescription } } }
            }
        }.padding(.leading, 6).padding(.trailing, travel == nil || typeSize.isAccessibilitySize ? 18 : 92).padding(.vertical, 10).frame(minHeight: 34)
    }
}
