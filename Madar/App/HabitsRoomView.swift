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
    @State private var period: HabitFrequency?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        // Owner 20 Oct: one long list blurred the four kinds of habit. The four period cards
                        // are now the way in: each shows only its own habits and how long its window has left,
                        // the next useful step stays on top, and the orbit closes the room as the whole picture.
                        suggestion
                        summaries
                        periodSection(selectedPeriod)
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text("مدارك كله").font(MadarTypography.section()).padding(.top,14)
                            HabitOrbitView(readings:active,digits:digits,theme:theme) { detail = $0 }
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
            let on = f == selectedPeriod, count = active.filter { $0.summary.current?.rule.frequency == f }.count
            Button { withAnimation(reduceMotion ? nil : .snappy) { period = f } } label: {
                VStack(spacing:5) {
                    HabitMiniRing(share:rows.isEmpty ? 0 : Double(met)/Double(rows.count),theme:theme).frame(width:28,height:28)
                    Text(f.arabic).font(MadarTypography.caption())
                    Text(count == 0 ? "لا عادات" : rows.isEmpty ? "لا استحقاق" : digits.string(met)+" من "+digits.string(rows.count)).font(MadarTypography.fine()).foregroundStyle(on ? theme.ink : theme.secondaryInk)
                }
                .padding(.vertical,10).frame(maxWidth:.infinity,minHeight:44)
                .background(on ? theme.accentFill.opacity(0.16) : theme.surface,in:.rect(cornerRadius:16))
                .overlay { RoundedRectangle(cornerRadius:16).stroke(on ? theme.accentFill : .clear,lineWidth:1.5) }
                .contentShape(.rect)
            }
            .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : []).accessibilityIdentifier("habits-period-"+f.rawValue)
        } }
    }
    /// The period shown: the one the user picked, else the first kind with something still open, else the first that has habits.
    private var selectedPeriod: HabitFrequency {
        if let period { return period }
        let kinds:[HabitFrequency] = [.daily,.weekly,.monthly,.yearly]
        return kinds.first { f in active.contains { $0.summary.current?.rule.frequency == f && $0.summary.current?.met != true && !$0.paused && ($0.summary.current?.target ?? 0) > 0 } }
            ?? kinds.first { f in active.contains { $0.summary.current?.rule.frequency == f } } ?? .daily
    }
    @ViewBuilder private func periodSection(_ f:HabitFrequency) -> some View {
        let rows = active.filter { $0.summary.current?.rule.frequency == f }.sorted { priority($0) < priority($1) }
        VStack(alignment:.leading,spacing:4) {
            HStack(alignment:.firstTextBaseline) {
                Text(f == .daily ? "عادات اليوم" : f == .weekly ? "عادات هذا الأسبوع" : f == .monthly ? "عادات هذا الشهر" : "عادات هذه السنة").font(MadarTypography.section())
                Spacer()
                if let left = windowLeft(f, rows) { Text(left).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
            }
            Text(f == .daily ? "تُحسب كل يوم، وتبدأ من جديد مع يومك" : f == .weekly ? "يكفي أن تتمّها في أي يوم من الأسبوع" : f == .monthly ? "يكفي أن تتمّها في أي يوم من الشهر" : "مرة في السنة، في موعدها")
                .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
        }
        .padding(.top,10).accessibilityElement(children:.combine).accessibilityIdentifier("habits-period-title")
        if rows.isEmpty {
            Button { editor = .init(id:UUID()) } label: { Label("لا عادات " + f.arabic + " بعد؛ أضف واحدة", systemImage:"plus").font(MadarTypography.caption()).frame(maxWidth:.infinity,minHeight:56) }
                .buttonStyle(.plain).background(theme.surface,in:.rect(cornerRadius:24)).accessibilityIdentifier("habits-period-add")
        } else {
            VStack(spacing:0) { ForEach(rows) { row in habitRow(row); if row.id != rows.last?.id { Divider().overlay(theme.line) } } }.background(theme.surface,in:.rect(cornerRadius:24))
        }
    }
    /// What is left of the current window («بقي ٣ أيام»); a day's own window needs no countdown.
    private func windowLeft(_ f:HabitFrequency,_ rows:[HabitReading]) -> String? {
        guard f != .daily, let end = rows.compactMap({ $0.summary.current?.end }).first else { return nil }
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = .gmt
        let today = AppBahwService(session:session).today
        let left = (calendar.dateComponents([.day],from:today.date(in:.gmt),to:end.date(in:.gmt)).day ?? 0) + 1
        guard left > 0 else { return nil }
        return left == 1 ? "آخر يوم فيها" : "بقي " + habitPeriodCount(left,.daily,digits)
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
                ZStack { HabitMiniRing(share:Double(row.summary.current?.value ?? 0)/Double(max(1,row.summary.current?.target ?? 1)),theme:theme); if row.source != nil || row.summary.current?.met == true { MadarGlyph(row.symbol,size:18).padding(10) } }.frame(width:40,height:40)
                VStack(alignment:.leading,spacing:5) {
                    HStack(spacing:6) { Text(row.name).font(MadarTypography.section()); if let source=row.sourceTitle { Text(source).font(MadarTypography.fine()).padding(.horizontal,6).padding(.vertical,2).background(theme.background,in:.capsule) } }
                    if !progress(row).isEmpty { Text(progress(row)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                    if row.paused || row.isNow || row.summary.atRisk || row.summary.current?.met == true { Label(row.statusTitle,systemImage:row.paused ? "pause.circle" : row.summary.current?.met == true ? "checkmark.circle" : "circle.lefthalf.filled").font(MadarTypography.fine()).foregroundStyle(theme.accent) }
                }
                Spacer(minLength:0)
                VStack(alignment:.trailing,spacing:4) { Text(habitPeriodCount(row.summary.streak,row.summary.current?.rule.frequency ?? .daily,digits)).font(MadarTypography.caption()).foregroundStyle(theme.accent); HStack(spacing:3) { ForEach(Array(row.summary.periods.suffix(7).enumerated()),id:\.offset) { _,p in Circle().fill(p.met ? theme.accentFill : theme.background).overlay { Circle().stroke(theme.line) }.frame(width:5,height:5) } }.accessibilityHidden(true) }
            }.padding(.horizontal,14).padding(.vertical,15).frame(minHeight:74).contentShape(.rect)
        }.buttonStyle(.plain).accessibilityIdentifier("habit-row-"+row.id.uuidString).accessibilityLabel(row.name+"، "+progress(row)+"، "+row.statusTitle)
    }
    private func progress(_ row:HabitReading)->String { guard let p=row.summary.current else{return "لا فترة بعد"}; return (p.target == 0 ? "سجلك محفوظ" : p.rule.measure == .once && p.target == 1 ? (p.value >= 1 ? "" : "لم تتمّها بعد") : digits.string(p.value)+" من "+digits.string(p.target)+(p.rule.unit.map { " "+habitUnitName($0) } ?? ""))+(row.sourceTitle.map { "، تُقرأ من "+$0 } ?? "") }
    private func reload() { do { readings=try HabitRepository(context:ModelContext(session.container)).readings(at:session.prayerNow(),includeArchived:true,liveHealth:liveHealth);if let id=session.habitRouteID {if let row=readings.first(where:{$0.id==id}) {if row.archived {showArchived=true}else{detail=row}};session.habitRouteID=nil} } catch { session.errorMessage=error.localizedDescription } }
    private func perform(_ name:String,_ payload:[String:MadarCore.JSONValue]) { Task { do {try await session.executeDiaryCommand(name,payload:payload);reload()}catch{session.errorMessage=error.localizedDescription} } }
}
struct HabitMiniRing:View {
    let share:Double; let theme:RoomTheme
    var body:some View { ZStack { Circle().stroke(theme.line,lineWidth:4); Circle().trim(from:0,to:min(1,max(0,share))).stroke(theme.accentFill,style:.init(lineWidth:4,lineCap:.round)).rotationEffect(.degrees(-90)) }.accessibilityHidden(true) }
}
func habitUnitName(_ unit:String)->String { ["minutes":"دقيقة","exerciseMinutes":"دقيقة حركة","steps":"خطوة","pages":"صفحة"][unit] ?? unit }
/// A count with its unit in Arabic number agreement («دقيقتان»، «٨ صفحات»، «١٥ خطوة») for the built-in units;
/// a unit the user typed has no known plural, so it follows the number unchanged. Nominative only.
func habitUnitCount(_ count:Int,_ unit:String?,_ digits:MadarNumberFormatter)->String {
    let known:[String:[String]]=["minutes":["دقيقة واحدة","دقيقتان","دقائق","دقيقة"],"exerciseMinutes":["دقيقة حركة واحدة","دقيقتا حركة","دقائق حركة","دقيقة حركة"],
        "steps":["خطوة واحدة","خطوتان","خطوات","خطوة"],"pages":["صفحة واحدة","صفحتان","صفحات","صفحة"],"":["مرة واحدة","مرتان","مرات","مرة"]]
    guard let forms=known[unit ?? ""] else { return digits.string(count)+" "+(unit ?? "") }
    return arabicCount(count,forms,digits)
}
/// Arabic number agreement from four forms: one, two, plural (٣–١٠), and the singular after ١١ and above.
func arabicCount(_ count:Int,_ forms:[String],_ digits:MadarNumberFormatter)->String {
    count == 1 ? forms[0] : count == 2 ? forms[1] : digits.string(count)+" "+((3...10).contains(count%100) ? forms[2] : forms[3])
}
func habitPeriodCount(_ count:Int,_ frequency:HabitFrequency,_ digits:MadarNumberFormatter)->String {
    let forms:[String]
    switch frequency {case .daily:forms=["يوم واحد","يومان","أيام","يومًا"];case .weekly:forms=["أسبوع واحد","أسبوعان","أسابيع","أسبوعًا"];case .monthly:forms=["شهر واحد","شهران","أشهر","شهرًا"];case .yearly:forms=["سنة واحدة","سنتان","سنوات","سنة"]}
    return count == 1 ? forms[0] : count == 2 ? forms[1] : digits.string(count)+" "+((0...10).contains(count%100) ? forms[2] : forms[3])
}
/// Named in the habit's own period when known: «تنكسر السلسلة بفوت يومين متتاليين. الأيام المجمدة مستثناة.»
func habitBreakExplanation(_ periods:Int,_ frequency:HabitFrequency?=nil)->String {
    let forms:[String], frozen:String
    switch frequency {
    case .daily?: forms=["يوم واحد","يومين متتاليين","ثلاثة أيام متتالية"]; frozen="الأيام"
    case .weekly?: forms=["أسبوع واحد","أسبوعين متتاليين","ثلاثة أسابيع متتالية"]; frozen="الأسابيع"
    case .monthly?: forms=["شهر واحد","شهرين متتاليين","ثلاثة أشهر متتالية"]; frozen="الأشهر"
    case .yearly?: forms=["سنة واحدة","سنتين متتاليتين","ثلاث سنوات متتالية"]; frozen="السنوات"
    case nil: forms=["فترة واحدة","فترتين متتاليتين","ثلاث فترات متتالية"]; frozen="الفترات"
    }
    return "تنكسر السلسلة بفوت "+forms[min(max(periods,1),3)-1]+". "+frozen+" المجمدة مستثناة."
}
