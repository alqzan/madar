import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarDesign
import MadarCommands

extension HabitFrequency {
    var arabic: String { switch self { case .daily: "يومية"; case .weekly: "أسبوعية"; case .monthly: "شهرية"; case .yearly: "سنوية" } }
    var periodArabic: String { switch self { case .daily: "أيام"; case .weekly: "أسابيع"; case .monthly: "أشهر"; case .yearly: "سنوات" } }
}
extension HabitReading {
    var statusTitle: String {
        if paused { return "مجمّدة" }
        if summary.atRisk { return summary.consecutiveMisses == 1 ? "فاتتك فترة؛ الحالية تحفظها" : "فاتتك فترتان؛ الحالية تحفظها" }
        switch summary.current?.outcome { case .complete: return "تمّت"; case .minimum: return "أقلّ القليل"; case .excluded: return "إجازتها اليوم"; case .missed: return "فترة بلا تسجيل"; default: return isNow ? "وقتها الآن" : "تنتظر" }
    }
    var sourceTitle: String? { switch source { case "jamaah": "الصلاة"; case "review": "القرآن"; case "diaryLine": "المذكرات"; case "walking": "الصحة"; default: nil } }
    var symbol: String { switch source { case "jamaah": "MadarPrayer"; case "review": "MadarQuran"; case "diaryLine": "MadarDiary"; case "walking": "figure.walk"; default: "checkmark" } }
}
struct HabitEditorIdentity: Identifiable { let id: UUID; var reading: HabitReading? = nil }
struct HabitsRoomView: View {
    @Bindable var session: AppSession
    @State private var readings: [HabitReading] = []
    @State private var liveHealth: [UUID:Int] = [:]
    @State private var detail: HabitReading?
    @State private var editor: HabitEditorIdentity?
    @State private var showArchived = false
    @State private var deletingArchived: HabitReading?
    @State private var pendingEditor: HabitEditorIdentity?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var theme: RoomTheme { .init(room:"bahw",dark:session.string("core.theme") == "dark") }
    private var digits: MadarNumberFormatter { .init(style:session.string("core.numerals") == "western" ? .western : .hindi) }
    private var active: [HabitReading] { readings.filter { !$0.archived } }
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Button { dismiss() } label: { Label("البهو",systemImage:"chevron.right").font(MadarTypography.section()).padding(12).overlay { Capsule().stroke(theme.line) } }
                Spacer()
                VStack(spacing:2) { Text("العادات").font(.custom("thmanyahserifdisplay-Bold",size:26,relativeTo:.title)).accessibilityIdentifier("habits-title"); Text("يومية وأسبوعية وشهرية وسنوية").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                Spacer()
                Button { editor = .init(id:UUID()) } label: { Image(systemName:"plus").frame(width:44,height:44).overlay { Circle().stroke(theme.line) } }.accessibilityLabel("عادة جديدة").accessibilityIdentifier("habit-add")
            }.padding(.horizontal,14).padding(.vertical,8)
            ScrollView {
                VStack(alignment:.leading,spacing:8) {
                    if active.isEmpty { empty }
                    else {
                        summaries
                        suggestion
                        if !dynamicTypeSize.isAccessibilitySize { HabitOrbitView(readings:active,digits:digits,theme:theme) { detail = $0 } }
                        ForEach([HabitFrequency.daily,.weekly,.monthly,.yearly],id:\.self) { frequency in
                            let rows = active.filter { $0.summary.current?.rule.frequency == frequency }.sorted { priority($0) < priority($1) }
                            if !rows.isEmpty {
                                HStack { Text(frequency.arabic).font(MadarTypography.section()); Text(digits.string(rows.filter { $0.summary.current?.met == true }.count) + " من " + digits.string(rows.count)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk); Spacer(); Text("السلسلة: " + frequency.periodArabic).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                                VStack(spacing:0) { ForEach(rows) { row in habitRow(row); if row.id != rows.last?.id { Divider().overlay(theme.line) } } }.background(theme.surface,in:.rect(cornerRadius:24))
                            }
                        }
                    }
                    if readings.contains(where: \.archived) {
                        Button(showArchived ? "أخفِ العادات المحذوفة" : "عادات محذوفة") { showArchived.toggle() }.font(MadarTypography.caption()).frame(minHeight:44).accessibilityIdentifier("habit-archived")
                        if showArchived { ForEach(readings.filter(\.archived)) { row in HStack { Text(row.name); Spacer(); Button("استعد") { perform("habit.archive",["id":.string(row.id.uuidString),"archived":.bool(false)]) };Button("حذف نهائي") { deletingArchived=row }.accessibilityLabel("حذف نهائي "+row.name) }.padding(14).background(theme.surface,in:.rect(cornerRadius:18)) } }
                    }
                    VStack(spacing:5) { Text("«أحبّ الأعمال إلى الله أدومها وإن قلّ»").font(MadarTypography.body()); Text("متفق عليه، من حديث عائشة رضي الله عنها").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }.frame(maxWidth:.infinity).padding(.vertical,24)
                }.padding(.horizontal,14).padding(.vertical,8)
            }.clipped()
        }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.accent)
        .toolbarVisibility(.hidden,for:.navigationBar).environment(\.roomTheme,theme)
        .task(id:session.prayerRevision) { reload() }
        .task { do {liveHealth=try await HabitHealthStore.refresh(session:session);reload()} catch {session.errorMessage="لم تتجدد قراءة الصحة؛ سجلك السابق محفوظ."} }
        .task {
            while !Task.isCancelled {
                do {liveHealth=try await HabitHealthStore.refresh(session:session,closedDays:false);reload()}catch{}
                try? await Task.sleep(for:.seconds(60))
            }
        }
        .confirmationDialog("حذف العادة وسجلها؟",isPresented:Binding(get:{deletingArchived != nil},set:{if !$0{deletingArchived=nil}}),titleVisibility:.visible) {
            Button("احذف نهائيًا",role:.destructive) {if let row=deletingArchived{perform("habit.deleteArchived",["id":.string(row.id.uuidString)])};deletingArchived=nil}
            Button("إلغاء",role:.cancel){deletingArchived=nil}
        } message:{Text("تختفي العادة وسياساتها وتسجيلاتها. يتاح التراجع لعشر دقائق.")}
        .sheet(item:$editor) { value in HabitEditorView(session:session,reading:value.reading,id:value.id) }
        .sheet(item:$detail,onDismiss:{if let pendingEditor {editor=pendingEditor;self.pendingEditor=nil}}) { row in HabitDetailView(session:session,reading:row) { pendingEditor = .init(id:row.id,reading:row); detail=nil } }
    }
    private var empty: some View {
        VStack(spacing:16) { Image(systemName:"sparkles").font(.system(size:42)).foregroundStyle(theme.accent); Text("القليل الذي تدوم عليه").font(MadarTypography.title()); Text("اختر عادة صغيرة تبدأ بها، أو اربطها بما تسجّله في غرف مدار.").font(MadarTypography.body()).multilineTextAlignment(.center).foregroundStyle(theme.secondaryInk); Button("أضف أول عادة") { editor = .init(id:UUID()) }.buttonStyle(.borderedProminent).accessibilityIdentifier("habit-first") }.padding(28).frame(maxWidth:.infinity).background(theme.surface,in:.rect(cornerRadius:24)).padding(.top,25)
    }
    private var summaries: some View {
        HStack(spacing:7) { ForEach([HabitFrequency.daily,.weekly,.monthly,.yearly],id:\.self) { f in
            let rows = active.filter { $0.summary.current?.rule.frequency == f && ($0.summary.current?.target ?? 0) > 0 && !$0.paused }, met = rows.filter { $0.summary.current?.met == true }.count
            HStack(spacing:4) { HabitMiniRing(share:rows.isEmpty ? 0 : Double(met)/Double(rows.count),theme:theme).frame(width:28,height:28); VStack(alignment:.leading,spacing:3) { Text(f == .daily ? "اليوم" : f == .weekly ? "الأسبوع" : f == .monthly ? "الشهر" : "السنة").font(MadarTypography.fine()); Text(rows.isEmpty ? "لا استحقاق" : digits.string(met)+" من "+digits.string(rows.count)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) } }.padding(.vertical,12).frame(maxWidth:.infinity).background(theme.surface,in:.rect(cornerRadius:16))
        } }
    }
    @ViewBuilder private var suggestion: some View {
        let next = active.sorted { priority($0) < priority($1) }.first { $0.summary.current?.met != true && !$0.paused && $0.summary.current?.target != 0 }
        if let next { HStack(spacing:10) { Image(systemName:next.summary.atRisk ? "sparkle" : "circle.dotted").foregroundStyle(theme.accent); Text(next.summary.atRisk ? next.name + ": القليل اليوم يحفظ سلسلتك" : next.name + (next.isNow ? ": وقتها الآن" : ": خطوة صغيرة ليومك")).font(MadarTypography.caption()); Spacer(minLength:0); Button("افتحها") { detail = next }.font(MadarTypography.caption()).padding(.horizontal,12).frame(minHeight:44).background(theme.accentFill,in:.capsule).foregroundStyle(theme.onAccent) }.padding(10).background(theme.surface,in:.rect(cornerRadius:20)).overlay { RoundedRectangle(cornerRadius:20).stroke(theme.line) } }
        else { Text("يومك تمّ، دام القليل الجميل").font(MadarTypography.section()).frame(maxWidth:.infinity,minHeight:56).background(theme.surface,in:.rect(cornerRadius:20)) }
    }
    private func priority(_ r:HabitReading)->Int { (r.summary.current?.met == true ? 100 : 0) + (r.isNow ? 0 : 10) + (r.summary.atRisk ? 0 : 1) }
    private func habitRow(_ row:HabitReading)->some View {
        Button { detail = row } label: {
            HStack(spacing:12) {
                ZStack { HabitMiniRing(share:Double(row.summary.current?.value ?? 0)/Double(max(1,row.summary.current?.target ?? 1)),theme:theme); MadarGlyph(row.symbol,size:18).padding(10) }.frame(width:40,height:40)
                VStack(alignment:.leading,spacing:5) {
                    HStack(spacing:6) { Text(row.name).font(MadarTypography.section()); if let source=row.sourceTitle { Text(source).font(MadarTypography.fine()).padding(.horizontal,6).padding(.vertical,2).background(theme.background,in:.capsule) } }
                    Text(progress(row)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    if row.paused || row.isNow || row.summary.atRisk || row.summary.current?.met == true { Label(row.statusTitle,systemImage:row.paused ? "pause.circle" : row.summary.current?.met == true ? "checkmark.circle" : "circle.lefthalf.filled").font(MadarTypography.fine()).foregroundStyle(theme.accent) }
                }
                Spacer(minLength:0)
                VStack(alignment:.trailing,spacing:4) { Text(habitPeriodCount(row.summary.streak,row.summary.current?.rule.frequency ?? .daily,digits)).font(MadarTypography.caption()).foregroundStyle(theme.accent); HStack(spacing:3) { ForEach(Array(row.summary.periods.suffix(7).enumerated()),id:\.offset) { _,p in Circle().fill(p.met ? theme.accentFill : theme.background).overlay { Circle().stroke(theme.line) }.frame(width:5,height:5) } }.accessibilityHidden(true) }
            }.padding(.horizontal,14).padding(.vertical,15).frame(minHeight:74).contentShape(.rect)
        }.buttonStyle(.plain).accessibilityIdentifier("habit-row-"+row.id.uuidString).accessibilityLabel(row.name+"، "+progress(row)+"، "+row.statusTitle)
    }
    private func progress(_ row:HabitReading)->String { guard let p=row.summary.current else{return "لا فترة بعد"}; return (p.target == 0 ? "سجلك محفوظ" : digits.string(p.value)+" من "+digits.string(p.target)+(p.rule.unit.map { " "+habitUnitName($0) } ?? ""))+(row.sourceTitle.map { "، تُقرأ من "+$0 } ?? "") }
    private func reload() { do { readings=try HabitRepository(context:ModelContext(session.container)).readings(at:session.prayerNow(),includeArchived:true,liveHealth:liveHealth);if let id=session.habitRouteID {if let row=readings.first(where:{$0.id==id}) {if row.archived {showArchived=true}else{detail=row}};session.habitRouteID=nil} } catch { session.errorMessage=error.localizedDescription } }
    private func perform(_ name:String,_ payload:[String:MadarCore.JSONValue]) { Task { do {try await session.executeDiaryCommand(name,payload:payload);reload()}catch{session.errorMessage=error.localizedDescription} } }
}
struct HabitMiniRing:View {
    let share:Double; let theme:RoomTheme
    var body:some View { ZStack { Circle().stroke(theme.line,lineWidth:4); Circle().trim(from:0,to:min(1,max(0,share))).stroke(theme.accentFill,style:.init(lineWidth:4,lineCap:.round)).rotationEffect(.degrees(-90)) }.accessibilityHidden(true) }
}
func habitUnitName(_ unit:String)->String { ["minutes":"دقيقة","exerciseMinutes":"دقيقة حركة","steps":"خطوة","pages":"صفحة"][unit] ?? unit }
func habitPeriodCount(_ count:Int,_ frequency:HabitFrequency,_ digits:MadarNumberFormatter)->String {
    let forms:[String]
    switch frequency {case .daily:forms=["يوم واحد","يومان","أيام","يومًا"];case .weekly:forms=["أسبوع واحد","أسبوعان","أسابيع","أسبوعًا"];case .monthly:forms=["شهر واحد","شهران","أشهر","شهرًا"];case .yearly:forms=["سنة واحدة","سنتان","سنوات","سنة"]}
    return count == 1 ? forms[0] : count == 2 ? forms[1] : digits.string(count)+" "+((0...10).contains(count%100) ? forms[2] : forms[3])
}
func habitBreakExplanation(_ periods:Int)->String {
    let missed=periods == 1 ? "فترة واحدة" : periods == 2 ? "فترتين متتاليتين" : "ثلاث فترات متتالية"
    return "تنكسر السلسلة بفوت "+missed+". الفترات المجمدة مستثناة."
}
