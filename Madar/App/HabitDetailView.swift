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
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                HStack { Text(reading.name).font(MadarTypography.title());Spacer();Button("تمّ"){dismiss()}.frame(minHeight:44) }
                if let current=reading.summary.current {
                    Text(current.target == 0 ? "سجلك محفوظ" : digits.string(current.value)+" من "+digits.string(current.target)+(current.rule.unit.map{" "+habitUnitName($0)} ?? "")).font(MadarTypography.cardTitle()).accessibilityIdentifier("habit-progress")
                    Text(reading.statusTitle).font(MadarTypography.section()).foregroundStyle(theme.accent)
                    Text("تُقاس "+measured(current.rule.frequency)+"؛ "+habitBreakExplanation(Int(session.number("bahw.streakBreakAfter")),current.rule.frequency)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    if current.rule.minimum != nil { Text("أقلّ القليل يحفظ السلسلة، ويظهر بعلامة أخفّ.").font(MadarTypography.caption()) }
                    if reading.source == "walking" {
                        if HabitHealthStore.available { Button("حدّث من الصحة") {Task{do{try await HabitHealthStore.authorize(unit:reading.summary.current?.rule.unit ?? "steps");_ = try await HabitHealthStore.refresh(session:session);dismiss()}catch{session.errorMessage=error.localizedDescription}}}.buttonStyle(.borderedProminent).frame(minHeight:44) } else {Text("بيانات الصحة غير متاحة على هذا الجهاز").font(MadarTypography.caption())}
                    } else if let source=reading.source {
                        Button("افتح "+(reading.sourceTitle ?? "غرفتها")) {
                            if source == "jamaah"{session.selectedTab="prayer"}else if source == "review"{session.selectedTab="quran"}else{session.selectedTab="notes"};dismiss()
                        }.buttonStyle(.borderedProminent).frame(minHeight:44).accessibilityIdentifier("habit-owner")
                    } else if !reading.paused && current.target > 0 {
                        Button(current.rule.measure == .duration ? "+١٥ دقيقة" : current.rule.measure == .count ? "+١ "+(current.rule.unit ?? "مرة") : current.met ? "تمّت" : "أتممتها") { perform("habit.complete",["id":.string(reading.id.uuidString),"delta":.number(current.rule.measure == .duration ? 15 : 1)]) }.buttonStyle(.borderedProminent).disabled(busy || current.met && current.rule.measure == .once).accessibilityIdentifier("habit-complete")
                        if let minimum=current.rule.minimum,current.value<minimum { Button("أقلّ القليل: "+digits.string(minimum)) { perform("habit.complete",["id":.string(reading.id.uuidString),"delta":.number(Double(minimum-current.value))]) }.frame(minHeight:44).accessibilityIdentifier("habit-minimum") }
                    }
                }
                HStack {
                    if reading.paused { Button("فكّ التجميد"){perform("habit.resume",["id":.string(reading.id.uuidString)])}.frame(minHeight:44).accessibilityIdentifier("habit-resume") }
                    else {
                        Menu("جمّد") {
                            Button("أسبوعًا"){freeze(week:true)};Button("حتى أفكّه"){freeze(week:false)};Button("من أمس حتى أفكّه"){freeze(week:false,yesterday:true)}
                            if (try? PrayerRepository(context:ModelContext(session.container)).activeTrip(at:session.prayerNow())) != nil { Button("حتى أعود من السفر"){freeze(week:false,trip:true)} }
                        }.frame(minHeight:44).accessibilityIdentifier("habit-freeze")
                    }
                    Spacer();Button("عدّل"){dismiss();edit()}.frame(minHeight:44).accessibilityIdentifier("habit-edit")
                    Spacer();Button("احذف"){perform("habit.archive",["id":.string(reading.id.uuidString),"archived":.bool(true)])}.frame(minHeight:44).accessibilityIdentifier("habit-delete")
                }
                DisclosureGroup(reading.summary.current.map { "آخر "+habitPeriodCount(14,$0.rule.frequency,digits) } ?? "آخر ١٤ فترة") {
                    if reading.summary.current != nil {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:85))],spacing:8) { ForEach(Array(reading.summary.periods.suffix(14).enumerated()),id:\.offset) { _,p in
                        VStack(spacing:4){Image(systemName:p.met ? (p.outcome == .minimum ? "checkmark.circle" : "checkmark.circle.fill") : p.outcome == .excluded ? "pause.circle" : "circle").foregroundStyle(theme.accent);MadarDateLabel(session.dateLabels(p.start,compact:true)).foregroundStyle(theme.secondaryInk)}.frame(minWidth:85,minHeight:74).accessibilityLabel(session.dateLabels(p.start).combined+"، "+(p.met ? "تمّت" : p.outcome == .excluded ? "مستثناة" : "بلا تسجيل"))
                    } }
                    }
                }.font(MadarTypography.section()).padding(.vertical,8)
                Text("الحذف يحفظ سجلك؛ تستعيد العادة من «عادات محذوفة».").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }.padding(22)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.accent)
    }
    private func freeze(week:Bool,trip:Bool=false,yesterday:Bool=false) {
        let today=AppBahwService(session:session).today
        var p:[String:MadarCore.JSONValue]=["id":.string(reading.id.uuidString),"from":.string((yesterday ? today.adding(days:-1) : today).description)]
        if week {p["until"] = .string(today.adding(days:7).description)};if trip{p["trip"] = .bool(true)};perform("habit.pause",p)
    }
    private func perform(_ name:String,_ payload:[String:MadarCore.JSONValue]) { busy=true;Task{do{try await session.executeDiaryCommand(name,payload:payload);dismiss()}catch{session.errorMessage=error.localizedDescription};busy=false} }
}
