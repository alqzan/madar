import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import MadarPrayer
import MadarDesign

struct HabitDetailView:View {
    @Bindable var session:AppSession
    let reading:HabitReading
    let edit:()->Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy=false
    private var theme:RoomTheme{.init(room:"bahw",dark:session.string("core.theme") == "dark")}
    /// «تُقاس يوميًا»: the adverb, not the adjective «يومية».
    private func measured(_ f:HabitFrequency)->String { switch f {case .daily:"يوميًا";case .weekly:"أسبوعيًا";case .monthly:"شهريًا";case .yearly:"سنويًا"} }
    private var digits:MadarNumberFormatter{.init(style:session.string("core.numerals") == "western" ? .western : .hindi)}
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                HStack { Text(reading.name).font(MadarTypography.title());Spacer();Button("تمّ"){dismiss()}.frame(minHeight:44) }
                if let current=reading.summary.current { hero(current) }
                actions
                if let current=reading.summary.current { history(current) }
                Text("الحذف يحفظ سجلك؛ تستعيد العادة من «عادات محذوفة».").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }.padding(22)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.accent).environment(\.roomTheme,theme)
    }
    /// The period at a glance: its arch filling with progress, what is left, and the one action that moves it.
    private func hero(_ current:HabitPeriodResult)->some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.center,spacing:16) {
                VStack(alignment:.leading,spacing:6) {
                    Text(current.target == 0 ? "سجلك محفوظ" : habitProgressText(current.value,current.target,current.rule.unit,digits)).font(MadarTypography.cardTitle()).accessibilityIdentifier("habit-progress")
                    Text(reading.statusTitle).font(MadarTypography.section()).foregroundStyle(theme.accent)
                    if reading.summary.streak > 1 { Text("متّصلة منذ "+habitPeriodCount(reading.summary.streak,current.rule.frequency,digits)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
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
    private func filled(_ title:String)->some View { Text(title).font(MadarTypography.section()).frame(maxWidth:.infinity,minHeight:48).background(theme.accentFill,in:.capsule).foregroundStyle(theme.onAccent) }
    @ViewBuilder private func primary(_ current:HabitPeriodResult)->some View {
        if reading.source == "walking" {
            if HabitHealthStore.available { Button {Task{do{try await HabitHealthStore.authorize(unit:reading.summary.current?.rule.unit ?? "steps");_ = try await HabitHealthStore.refresh(session:session);dismiss()}catch{session.errorMessage=error.localizedDescription}}} label: { filled("حدّث من الصحة") }.buttonStyle(.plain) } else {Text("بيانات الصحة غير متاحة على هذا الجهاز").font(MadarTypography.caption())}
        } else if let source=reading.source {
            Button {
                if source == "jamaah"{session.selectedTab="prayer"}else if source == "review"{session.selectedTab="quran"}else{session.selectedTab="notes"};dismiss()
            } label: { filled("افتح "+(reading.sourceTitle ?? "غرفتها")) }.buttonStyle(.plain).accessibilityIdentifier("habit-owner")
        } else if !reading.paused && current.target > 0 {
            let doneOnce = current.met && current.rule.measure == .once
            Button { perform("habit.complete",["id":.string(reading.id.uuidString),"delta":.number(current.rule.measure == .duration ? 15 : 1)]) } label: {
                filled(current.rule.measure == .duration ? "أضف "+digits.string(15)+" دقيقة" : current.rule.measure == .count ? "أضف "+digits.string(1)+" "+habitUnitName(current.rule.unit ?? "مرة") : doneOnce ? "تمّت" : "أتممتها").opacity(doneOnce ? 0.55 : 1)
            }.buttonStyle(.plain).disabled(busy || doneOnce).accessibilityIdentifier("habit-complete")
            if let minimum=current.rule.minimum,current.value<minimum { Button("أقلّ القليل: "+digits.string(minimum)) { perform("habit.complete",["id":.string(reading.id.uuidString),"delta":.number(Double(minimum-current.value))]) }.font(MadarTypography.caption()).frame(maxWidth:.infinity,minHeight:44).accessibilityIdentifier("habit-minimum") }
        }
    }
    private func outline<L:View>(_ label:L)->some View { label.font(MadarTypography.caption()).frame(maxWidth:.infinity,minHeight:44).overlay { Capsule().stroke(theme.line) }.contentShape(.capsule) }
    private var actions:some View {
        HStack(spacing:8) {
            if reading.paused { Button { perform("habit.resume",["id":.string(reading.id.uuidString)]) } label: { outline(Label("فكّ التجميد",systemImage:"play")) }.buttonStyle(.plain).accessibilityIdentifier("habit-resume") }
            else {
                Menu {
                    Button("أسبوعًا"){freeze(week:true)};Button("حتى أفكّه"){freeze(week:false)};Button("من أمس حتى أفكّه"){freeze(week:false,yesterday:true)}
                    if (try? PrayerRepository(context:ModelContext(session.container)).activeTrip(at:session.prayerNow())) != nil { Button("حتى أعود من السفر"){freeze(week:false,trip:true)} }
                } label: { outline(Label("جمّد",systemImage:"snowflake")) }.accessibilityIdentifier("habit-freeze")
            }
            Button { dismiss();edit() } label: { outline(Label("عدّل",systemImage:"pencil")) }.buttonStyle(.plain).accessibilityIdentifier("habit-edit")
            Button { perform("habit.archive",["id":.string(reading.id.uuidString),"archived":.bool(true)]) } label: { outline(Label("احذف",systemImage:"archivebox")) }.buttonStyle(.plain).accessibilityIdentifier("habit-delete")
        }
    }
    /// The last fourteen periods as a row of small rings, oldest on the right as in the prayer footprint.
    @ViewBuilder private func history(_ current:HabitPeriodResult)->some View {
        let periods = Array(reading.summary.periods.suffix(14))
        VStack(alignment:.leading,spacing:10) {
            HStack { Text("آخر "+habitPeriodCount(14,current.rule.frequency,digits)).font(MadarTypography.section()); Spacer(); Text(digits.string(periods.filter(\.met).count)+" من "+digits.string(periods.count)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
            if dynamicTypeSize.isAccessibilitySize {
                ForEach(Array(periods.enumerated()),id:\.offset) { _,p in HStack { MadarDateLabel(session.dateLabels(p.start,compact:true)); Spacer(); Text(outcome(p)).font(MadarTypography.caption()) } }
            } else {
                HStack(alignment:.bottom,spacing:4) { ForEach(Array(periods.enumerated()),id:\.offset) { _,p in
                    HabitRingGlyph(share:p.outcome == .minimum ? 0.5 : 0,done:p.outcome == .complete,symbol:nil,lineWidth:2).frame(width:18,height:18).opacity(p.outcome == .excluded ? 0.35 : 1)
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
    private func perform(_ name:String,_ payload:[String:MadarCore.JSONValue]) { busy=true;Task{do{try await session.executeDiaryCommand(name,payload:payload);dismiss()}catch{session.errorMessage=error.localizedDescription};busy=false} }
}
