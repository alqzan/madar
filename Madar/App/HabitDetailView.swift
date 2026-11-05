import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import MadarPrayer
import MadarDesign

struct HabitDetailView:View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var session:AppSession
    let reading:HabitReading
    @Binding var pastDayDraftPresented: Bool
    let edit:()->Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy=false
    @State private var pastDay=false
    /// Read once when the page opens; it was rebuilt from every prayer log on each redraw of the «جمّد» menu.
    @State private var onTrip=false
    /// A month or a year apart, the habit is kept by «آخر مرة» (item 26 «ج»): that leads the page.
    private var keptBySince:Bool { reading.source == nil && [.monthly,.yearly].contains(reading.summary.current?.rule.frequency) }
    private var theme:RoomTheme{.init(room:"bahw",dark:colorScheme == .dark)}
    /// «تُقاس يوميًا»: the adverb, not the adjective «يومية».
    private func measured(_ f:HabitFrequency)->String { switch f {case .daily:"يوميًا";case .weekly:"أسبوعيًا";case .monthly:"شهريًا";case .yearly:"سنويًا"} }
    private var digits:MadarNumberFormatter{.init(style:session.string("core.numerals") == "western" ? .western : .hindi)}
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                HStack { Text(reading.name).font(MadarTypography.title());Spacer();Button("تمّ"){dismiss()}.frame(minHeight:44) }
                if keptBySince { HabitSinceSection(session:session,reading:reading) }
                if let current=reading.summary.current { hero(current) }
                actions
                if let current=reading.summary.current { history(current) }
                Text("الحذف يحفظ سجلك؛ تستعيد العادة من «عادات محذوفة».").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }.padding(22)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.accent).environment(\.roomTheme,theme)
        .sheet(isPresented:$pastDay, onDismiss: { pastDayDraftPresented = false }) { HabitPastDaySheet(session:session,reading:reading) { dismiss() }.madarSheetErrorAlert(session) }
        .task { onTrip = (try? PrayerRepository(context:ModelContext(session.container)).activeTrip(at:session.prayerNow())) != nil }
    }
    /// The period at a glance: its arch filling with progress, what is left, and the one action that moves it.
    private func hero(_ current:HabitPeriodResult)->some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.center,spacing:16) {
                VStack(alignment:.leading,spacing:6) {
                    Text(current.target == 0 ? "سجلك محفوظ" : habitProgressText(current.rule.measure == .once ? min(current.value,current.target) : current.value,current.target,current.rule.unit,digits)).font(MadarTypography.cardTitle()).accessibilityIdentifier("habit-progress")
                    if let state = stateLine(current) { Text(state).font(MadarTypography.section()).foregroundStyle(theme.accent) }
                    if reading.summary.streak > 1 { HabitFlame(count:reading.summary.streak,frequency:current.rule.frequency,digits:digits).scaleEffect(1.25,anchor:.leading) }
                }
                Spacer(minLength:0)
                if !dynamicTypeSize.isAccessibilitySize { HabitRingGlyph(share:Double(current.value)/Double(max(1,current.target)),done:current.met,symbol:reading.source == nil ? nil : reading.symbol,lineWidth:5).frame(width:64,height:64) }
            }
            primary(current)
            Text("تُقاس "+measured(current.rule.frequency)+"؛ "+habitBreakExplanation(Int(session.number("bahw.streakBreakAfter")),current.rule.frequency)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            if current.rule.minimum != nil { Text("أقلّ القليل يحفظ السلسلة، ويظهر بعلامة أخفّ.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
        }
        .padding(18).frame(maxWidth:.infinity,alignment:.leading).background(theme.surface,in:.rect(cornerRadius:24))
    }
    private func stateLine(_ p:HabitPeriodResult)->String? {
        if reading.paused || reading.summary.atRisk || p.met || p.target == 0 { return reading.statusTitle }
        if reading.isNow { return "وقتها الآن" }
        guard p.rule.measure != .once, p.value > 0, p.target > p.value else { return nil }
        return "بقي "+habitUnitCount(p.target-p.value,p.rule.unit,digits)
    }
    private func filled(_ title:String)->some View { Text(title).font(MadarTypography.section()).frame(maxWidth:.infinity,minHeight:48).background(theme.accentFill,in:.capsule).foregroundStyle(theme.onAccent) }
    @ViewBuilder private func primary(_ current:HabitPeriodResult)->some View {
        if reading.source == "walking" {
            if HabitHealthStore.available { Button {Task{do{try await HabitHealthStore.authorize(unit:reading.summary.current?.rule.unit ?? "steps");_ = try await HabitHealthStore.refresh(session:session);dismiss()}catch{session.errorMessage=madarUserMessage(error)}}} label: { filled("حدّث من الصحة") }.buttonStyle(.madarPlain) } else {Text("بيانات الصحة غير متاحة على هذا الجهاز").font(MadarTypography.caption())}
        } else if let source=reading.source {
            Button {
                switch source {
                case "jamaah": session.selectedTab = "prayer"
                case "review", "wird": session.selectedTab = "quran"
                case "diaryLine": session.selectedTab = "notes"
                case "reading", "hadith": session.selectedTab = "mihbara"
                default: session.errorMessage = "لا توجد غرفة مرتبطة بهذا المصدر."
                }
                dismiss()
            } label: { filled("افتح "+(reading.sourceTitle ?? "غرفتها")) }.buttonStyle(.madarPlain).accessibilityIdentifier("habit-owner")
        } else if !reading.paused && current.target > 0 {
            let doneOnce = current.met && current.rule.measure == .once
            // A once-a-period habit done in its period needs no greyed «تمّت»: the ring and the state line already say it (AU-35).
            if !doneOnce { Button { perform("habit.complete",["id":.string(reading.id.uuidString),"delta":.number(current.rule.measure == .duration ? 15 : 1)]) } label: {
                filled(current.rule.measure == .duration ? "أضف "+digits.string(15)+" دقيقة" : current.rule.measure == .count ? "أضف "+habitOneMore(current.rule.unit) : doneOnce ? "تمّت" : "أتممتها").opacity(doneOnce ? 0.55 : 1)
            }.buttonStyle(.madarPlain).disabled(busy || doneOnce).accessibilityIdentifier("habit-complete") }
            if current.rule.measure != .health, let start = reading.summary.periods.first?.start, start < AppBahwService(session:session).today { Button { pastDayDraftPresented = true; pastDay = true } label: { outline(Label("فعلتها في يوم سابق",systemImage:"calendar.badge.clock")) }.buttonStyle(.madarPlain).accessibilityIdentifier("habit-past-day") }
            if let minimum=current.rule.minimum,current.value<minimum { Button { perform("habit.complete",["id":.string(reading.id.uuidString),"delta":.number(Double(minimum-current.value))]) } label: { outline(Text("سجّل أقلّ القليل: "+habitUnitCount(minimum,current.rule.unit,digits))) }.buttonStyle(.madarPlain).disabled(busy).accessibilityIdentifier("habit-minimum") }
        }
    }
    private func outline<L:View>(_ label:L)->some View { label.font(MadarTypography.caption()).frame(maxWidth:.infinity,minHeight:44).overlay { Capsule().stroke(theme.line) }.contentShape(.capsule) }
    private var actions:some View {
        HStack(spacing:8) {
            if reading.paused { Button { perform("habit.resume",["id":.string(reading.id.uuidString)]) } label: { outline(Label("فكّ التجميد",systemImage:"play")) }.buttonStyle(.madarPlain).accessibilityIdentifier("habit-resume") }
            else {
                Menu {
                    Button("جمّد أسبوعًا"){freeze(week:true)};Button("جمّد حتى أفكّه"){freeze(week:false)};Button("جمّد من أمس حتى أفكّه"){freeze(week:false,yesterday:true)}
                    if onTrip { Button("حتى أعود من السفر"){freeze(week:false,trip:true)} }
                } label: { outline(Label("جمّد",systemImage:"snowflake")) }.accessibilityIdentifier("habit-freeze")
            }
            Button { dismiss();edit() } label: { outline(Label("عدّل",systemImage:"pencil")) }.buttonStyle(.madarPlain).accessibilityIdentifier("habit-edit")
            Button { perform("habit.archive",["id":.string(reading.id.uuidString),"archived":.bool(true)]) } label: { outline(Label("احذف",systemImage:"archivebox")) }.buttonStyle(.madarPlain).accessibilityIdentifier("habit-delete")
        }
    }
    /// The last fourteen periods as a row of small rings, oldest on the right as in the prayer footprint.
    @ViewBuilder private func history(_ current:HabitPeriodResult)->some View {
        let periods = Array(reading.summary.periods.suffix(14))
        VStack(alignment:.leading,spacing:10) {
            let closed = periods.filter { $0.outcome != .waiting && $0.outcome != .excluded }
            HStack { Text("آخر "+habitPeriodCount(14,current.rule.frequency,digits)).font(MadarTypography.section()); Spacer(); if !closed.isEmpty { Text(digits.string(closed.filter(\.met).count)+" من "+digits.string(closed.count)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) } }
            if dynamicTypeSize.isAccessibilitySize {
                ForEach(Array(periods.enumerated()),id:\.offset) { _,p in HStack { MadarDateLabel(session.dateLabels(p.start,compact:true)); Spacer(); Text(outcome(p)).font(MadarTypography.caption()) } }
            } else {
                HStack(alignment:.bottom,spacing:4) { ForEach(Array(periods.enumerated()),id:\.offset) { _,p in
                    Group {
                        if p.outcome == .waiting { Circle().stroke(theme.accent,style:.init(lineWidth:1.5,dash:[2.5,2.5])).padding(1) }
                        else if p.outcome == .excluded { Circle().stroke(theme.line,lineWidth:2).overlay { Capsule().fill(theme.line).frame(width:8,height:2) }.padding(1) }
                        else { HabitRingGlyph(share:p.outcome == .minimum ? 0.5 : 0,done:p.outcome == .complete,symbol:nil,lineWidth:2) }
                    }.frame(width:18,height:18)
                        .frame(maxWidth:22).accessibilityElement().accessibilityLabel(session.dateLabels(p.start).combined+"، "+outcome(p))
                } }.frame(maxWidth:.infinity,alignment:.leading)
                if let first=periods.first, let last=periods.last {
                    HStack(alignment:.top) { MadarDateLabel(session.dateLabels(first.start,compact:true)); Spacer(); if periods.count > 1 { MadarDateLabel(session.dateLabels(last.start,compact:true)) } }.foregroundStyle(theme.secondaryInk)
                }
            }
        }.padding(18).background(theme.surface,in:.rect(cornerRadius:24))
    }
    private func outcome(_ p:HabitPeriodResult)->String { p.outcome == .complete ? "تمّت" : p.outcome == .minimum ? "أقلّ القليل" : p.outcome == .excluded ? "مستثناة" : p.outcome == .missed ? "بلا تسجيل" : "جارية" }
    private func freeze(week:Bool,trip:Bool=false,yesterday:Bool=false) {
        let today=AppBahwService(session:session).today
        var p:[String:MadarCore.JSONValue]=["id":.string(reading.id.uuidString),"from":.string((yesterday ? today.adding(days:-1) : today).description)]
        if week {p["until"] = .string(today.adding(days:7).description)};if trip{p["trip"] = .bool(true)};perform("habit.pause",p)
    }
    private func perform(_ name:String,_ payload:[String:MadarCore.JSONValue]) { guard !busy else { return }; busy=true;Task{do{try await session.executeDiaryCommand(name,payload:payload);dismiss()}catch{session.errorMessage=madarUserMessage(error)};busy=false} }
}
