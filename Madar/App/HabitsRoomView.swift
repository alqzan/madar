import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarDesign
import MadarCommands

extension HabitFrequency {
    var arabic: String { switch self { case .daily: "يومية"; case .interval: "كل عدة أيام"; case .weekly: "أسبوعية"; case .monthly: "شهرية"; case .yearly: "سنوية" } }
    var periodArabic: String { switch self { case .daily: "أيام"; case .interval: "مُدد"; case .weekly: "أسابيع"; case .monthly: "أشهر"; case .yearly: "سنوات" } }
}
extension HabitReading {
    /// What was missed in the habit's own unit (audit 28 Oct: «فاتتك فترة» meant nothing for a daily habit):
    /// «فاتك يوم»، «فاتك أسبوعان»، «فاتتك ٣ أشهر».
    func missedPhrase(_ digits: MadarNumberFormatter) -> String {
        let n = max(1, summary.consecutiveMisses)
        let forms: (verb: String, one: String, two: String, few: String, many: String) = switch summary.current?.rule.frequency {
        case .daily?: (n > 2 ? "فاتتك" : "فاتك", "يوم", "يومان", "أيام", "يومًا")
        case .interval?: (n > 2 ? "فاتتك" : "فاتك", "مدة", "مدتان", "مُدد", "مدة")
        case .weekly?: (n > 2 ? "فاتتك" : "فاتك", "أسبوع", "أسبوعان", "أسابيع", "أسبوعًا")
        case .monthly?: (n > 2 ? "فاتتك" : "فاتك", "شهر", "شهران", "أشهر", "شهرًا")
        case .yearly?: ("فاتتك", "سنة", "سنتان", "سنوات", "سنة")
        case nil: ("فاتتك", "فترة", "فترتان", "فترات", "فترة")
        }
        return forms.verb + " " + WidgetCopy.agree(n, digits, one: forms.one, two: forms.two, few: forms.few, many: forms.many)
    }
    var statusTitle: String {
        if paused { return "مجمّدة" }
        if summary.atRisk { return missedPhrase(MadarNumberFormatter(style: .hindi)) + "؛ الحالية تحفظها" }
        switch summary.current?.outcome { case .complete: return "تمّت"; case .minimum: return "أقلّ القليل"; case .excluded: return "إجازتها اليوم"; case .missed: return "فترة بلا تسجيل"; default: return isNow ? "وقتها الآن" : "تنتظر" }
    }
    var sourceTitle: String? { switch source { case "jamaah": "الصلاة"; case "review", "wird": "القرآن"; case "diaryLine": "المذكرات"; case "reading", "hadith": "المحبرة"; case "walking": "الصحة"; default: nil } }
    var symbol: String { switch source { case "jamaah": "MadarPrayer"; case "review", "wird": "MadarQuran"; case "diaryLine": "MadarDiary"; case "reading", "hadith": "books.vertical"; case "walking": "figure.walk"; default: nameGlyph ?? "checkmark" } }
    /// DA-05: a hand-made habit has no stored icon; its own words choose one for display only (nil when none fits).
    var nameGlyph: String? {
        HabitNameGlyph.symbol(for: name)
    }
}
struct HabitEditorIdentity: Identifiable { let id: UUID; var reading: HabitReading? = nil; var source = "custom" }
struct HabitsRoomView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var session: AppSession
    @State private var readings: [HabitReading] = []
    /// FB-38: the readings are computed off the main thread; until the first arrives nothing (not the empty state) is drawn.
    @State private var loaded = false
    @State private var reloadTask: Task<Void, Never>?
    @State private var liveHealth: [UUID:Int] = [:]
    @State private var detail: HabitReading?
    @State private var editor: HabitEditorIdentity?
    @State private var pendingBahwRootRequestID: UUID?
    @State private var detailPastDayDraftPresented = false
    @State private var showArchived = false
    @State private var deletingArchived: HabitReading?
    @State private var pendingEditor: HabitEditorIdentity?
    @State private var showAll = false
    @State private var selectedPeriod: HabitFrequency?
    @State private var pastDay: HabitReading?
    /// AU-95: repeated quick taps submit one command while a habit completion is still saving.
    @State private var completionInFlight: Set<UUID> = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var viewLens
    private var theme: RoomTheme { .init(room:"bahw",dark:colorScheme == .dark) }
    private var digits: MadarNumberFormatter { .init(style:session.string("core.numerals") == "western" ? .western : .hindi) }
    private var active: [HabitReading] { readings.filter { !$0.archived } }
    private var today: GregorianDay { AppBahwService(session:session).today }
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Button { dismiss() } label: { Label("البهو",systemImage:"chevron.right").font(MadarTypography.section()).padding(12).glassEffect(.regular.interactive(), in: .capsule) }.buttonStyle(.madarPlain)
                Spacer()
                VStack(spacing:2) { Text("العادات").font(.custom("thmanyahserifdisplay-Bold",size:26,relativeTo:.title)).accessibilityIdentifier("habits-title"); MadarDateLabel(session.dateLabels(today,weekday:true),primaryFont:MadarTypography.fine(),secondaryFont:MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                Spacer()
                Button { editor = .init(id:UUID()) } label: { Image(systemName:"plus").frame(width:44,height:44).glassEffect(.regular.interactive(), in: .circle) }.buttonStyle(.madarPlain).accessibilityLabel("عادة جديدة").accessibilityIdentifier("habit-add")
            }.padding(.horizontal,14).padding(.vertical,8)
            ScrollView {
                VStack(alignment:.leading,spacing:8) {
                    if !loaded { Color.clear.frame(height: 1) }
                    else if active.isEmpty { empty; roomHabits }
                    else {
                        periodSummaries
                        if active.count > 1 && !dynamicTypeSize.isAccessibilitySize {
                            nextStep
                            HabitOrbitView(readings: active.filter { !waitsForItsDate($0) }, digits: digits, theme: theme, nowPositions: AppBahwService(session: session).habitOrbitPositions()) { detail = $0 }
                                .accessibilityElement(children: .contain).accessibilityIdentifier("habits-orbit")
                        } else {
                            hero
                        }
                        viewSwitch
                        if showAll { allList } else { todayList }
                        Button { editor = .init(id:UUID()) } label: { Label("عادة صغيرة جديدة",systemImage:"plus").font(MadarTypography.caption()).frame(maxWidth:.infinity,minHeight:48).overlay { RoundedRectangle(cornerRadius:16).stroke(theme.line,style:.init(lineWidth:1,dash:[4,4])) }.contentShape(.rect) }
                            .buttonStyle(.madarPlain).padding(.top,10).accessibilityIdentifier("habits-new")
                        roomHabits
                    }
                    if readings.contains(where: \.archived) {
                        Button { showArchived.toggle() } label: { Text(showArchived ? "أخفِ العادات المحذوفة" : "عادات محذوفة").font(MadarTypography.caption()).frame(minHeight:44).contentShape(Rectangle()) }.accessibilityIdentifier("habit-archived")
                        if showArchived { ForEach(readings.filter(\.archived)) { row in HStack(spacing:10) { Text(row.name); Spacer(); Button { deletingArchived=row } label: { Text("حذف نهائي").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).frame(minHeight:44).contentShape(Rectangle()) }.accessibilityLabel("حذف نهائي "+row.name); Button("استعدها") { perform("habit.archive",["id":.string(row.id.uuidString),"archived":.bool(false)]) }.buttonStyle(.borderedProminent).frame(minHeight:44) }.padding(14).background(theme.surface,in:.rect(cornerRadius:18)) } }
                    }
                    VStack(spacing:5) { Text("«أحبّ الأعمال إلى الله أدومها وإن قلّ»").font(MadarTypography.body()); Text("متفق عليه، من حديث عائشة رضي الله عنها").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }.frame(maxWidth:.infinity).padding(.vertical,24)
                }.padding(.horizontal,14).padding(.vertical,8)
            }.madarTopClipped()
        }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.accent)
        .toolbarVisibility(.hidden,for:.navigationBar).environment(\.roomTheme,theme)
        .task(id:session.prayerRevision) { reload() }
        .onChange(of: session.habitRouteID) { _, routeID in
            guard routeID != nil else { return }
            reload()
        }
        .onChange(of: session.bahwRootRequestID, initial: true) { _, requestID in
            guard let requestID else { pendingBahwRootRequestID = nil; return }
            if editor != nil || pastDay != nil || detailPastDayDraftPresented {
                pendingBahwRootRequestID = requestID
            } else {
                session.bahwRootRequestID = nil
                session.habitsOpen = false
            }
        }
        .onChange(of: detailPastDayDraftPresented) { _, _ in applyPendingBahwRootIfReady() }
        .task { do {liveHealth=try await HabitHealthStore.refresh(session:session);reload()} catch {session.errorMessage="لم تتجدد قراءة الصحة؛ سجلك السابق محفوظ."} }
        .task {
            while !Task.isCancelled {
                do { let fresh=try await HabitHealthStore.refresh(session:session,closedDays:false); if fresh != liveHealth { liveHealth=fresh;reload() } }catch{}
                try? await Task.sleep(for:.seconds(60))
            }
        }
        .confirmationDialog("حذف العادة وسجلها؟",isPresented:Binding(get:{deletingArchived != nil},set:{if !$0{deletingArchived=nil}}),titleVisibility:.visible) {
            Button("احذف",role:.destructive) {if let row=deletingArchived{perform("habit.deleteArchived",["id":.string(row.id.uuidString)])};deletingArchived=nil}
            Button("إلغاء",role:.cancel){deletingArchived=nil}
        } message:{Text("تختفي العادة وسياساتها وتسجيلاتها، ويمكنك التراجع فورًا من زر «تراجع» أسفل الشاشة.")}
        .sheet(item:$editor, onDismiss: { applyPendingBahwRootIfReady() }) { value in HabitEditorView(session:session,reading:value.reading,id:value.id,initialSource:value.source).madarSheetErrorAlert(session) }
        .sheet(item:$pastDay, onDismiss: { applyPendingBahwRootIfReady() }) { row in HabitPastDaySheet(session:session,reading:row) { reload() }.madarSheetErrorAlert(session) }
        .sheet(item:$detail,onDismiss:{
            detailPastDayDraftPresented = false
            if let pendingEditor { editor=pendingEditor;self.pendingEditor=nil }
            applyPendingBahwRootIfReady()
        }) { row in HabitDetailView(session:session,reading:row,pastDayDraftPresented:$detailPastDayDraftPresented) { pendingEditor = .init(id:row.id,reading:row); detail=nil }.madarSheetErrorAlert(session) }
    }
    private func applyPendingBahwRootIfReady() {
        guard pendingBahwRootRequestID != nil, editor == nil, pastDay == nil, !detailPastDayDraftPresented else { return }
        pendingBahwRootRequestID = nil
        session.bahwRootRequestID = nil
        session.habitsOpen = false
    }
    /// FB-35 (owner, 5 Nov 2026): «سكشن العادات ابي فيه عادات التطبيق موجوده فيه مثل المذكرات والقرآن والورد».
    /// The habits Madar already measures in its rooms wait here, each one tap from being tracked; one already kept is not offered.
    private static let roomSources: [(source: String, title: String, detail: String, symbol: String, room: String)] = [
        ("diaryLine", "سطر اليوم", "تُحسب حين تكتب في المذكرات", "MadarDiary", "notes"),
        ("wird", "ورد الحفظ", "يُحسب يوم تسجّل وردك الجديد في القرآن", "MadarQuran", "quran"),
        ("review", "المراجعة", "تُحسب من وجوه مراجعتك في القرآن", "MadarQuran", "quran"),
        ("reading", "القراءة", "تُحسب من دقائق قراءتك في المحبرة", "books.vertical", "mihbara"),
        ("jamaah", "الجماعة", "تُحسب من صلواتك في جماعة", "MadarPrayer", "salah"),
        ("walking", "المشي", "تُحسب من خطواتك في تطبيق الصحة", "figure.walk", "bahw")]
    private var roomHabitsLeft: [(source: String, title: String, detail: String, symbol: String, room: String)] {
        let kept = Set(readings.filter { !$0.archived }.compactMap(\.source))
        return Self.roomSources.filter { !kept.contains($0.source) && ($0.source != "walking" || HabitHealthStore.available) }
    }
    @ViewBuilder private var roomHabits: some View {
        let left = roomHabitsLeft
        if !left.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("من غرف مدار").font(MadarTypography.section()).accessibilityAddTraits(.isHeader)
                Text("عادات يسجّلها مدار وحده مما تفعله في غرفه؛ أضفها لتظهر هنا مع عاداتك.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                ForEach(left, id: \.source) { item in
                    Button { editor = .init(id: UUID(), source: item.source) } label: {
                        HStack(spacing: 12) {
                            let roomTheme = RoomTheme(room: item.room, dark: colorScheme == .dark)
                            Group {
                                if item.symbol.hasPrefix("Madar") { Image(item.symbol).resizable().scaledToFit() } else { Image(systemName: item.symbol).resizable().scaledToFit() }
                            }
                            .frame(width: 20, height: 20).foregroundStyle(roomTheme.accent)
                            .frame(width: 40, height: 40).background(roomTheme.accent.opacity(0.12), in: .circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(MadarTypography.section())
                                Text(item.detail).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "plus").font(.system(size: 14, weight: .semibold)).frame(width: 34, height: 34)
                                .glassEffect(.regular.interactive(), in: .circle).accessibilityHidden(true)
                        }
                        .padding(12).contentShape(.rect)
                    }
                    .buttonStyle(.madarPlain)
                    .background(theme.surface, in: .rect(cornerRadius: 18))
                    .accessibilityLabel("أضف عادة " + item.title + "، " + item.detail)
                    .accessibilityIdentifier("habits-room-" + item.source)
                }
            }
            .padding(.top, 18)
            .accessibilityElement(children: .contain).accessibilityIdentifier("habits-room-habits")
        }
    }

    private var empty: some View {
        VStack(spacing:16) { HabitRingGlyph(share:0,done:false,symbol:nil,lineWidth:5).frame(width:60,height:60); Text("القليل الذي تدوم عليه").font(MadarTypography.title()); Text("اختر عادة صغيرة تبدأ بها، أو اربطها بما تسجّله في غرف مدار.").font(MadarTypography.body()).multilineTextAlignment(.center).foregroundStyle(theme.secondaryInk); Button { editor = .init(id:UUID()) } label: { Text("أضف أول عادة").font(MadarTypography.section()).padding(.horizontal,22).frame(minHeight:48).background(theme.accentFill,in:.capsule).foregroundStyle(theme.onAccent) }.buttonStyle(.madarPlain).accessibilityIdentifier("habit-first") }.padding(28).frame(maxWidth:.infinity).background(theme.surface,in:.rect(cornerRadius:24)).padding(.top,25)
    }

    // MARK: What «اليوم» holds

    /// Due now: every daily habit and longer habits on their scheduled days, with the existing weekly and
    /// flexible-monthly closing windows.
    /// A fixed-date habit before its date stays out of the orbit as it stays out of today's list
    /// (it used to show «فاتتك فترة» on a monthly charity days before its day).
    private func waitsForItsDate(_ r:HabitReading)->Bool {
        guard !r.paused, let p=r.summary.current, !p.met else { return false }
        let fixed = p.rule.frequency == .yearly || (p.rule.frequency == .monthly && !p.rule.monthDays.isEmpty)
        return fixed && !p.dueDays.contains(today)
    }
    private func dueToday(_ r:HabitReading)->Bool {
        guard !r.paused, let p=r.summary.current, p.target > 0 else { return false }
        if p.rule.frequency == .daily { return true }
        if p.met { return false }
        if p.rule.frequency == .yearly || (p.rule.frequency == .monthly && !p.rule.monthDays.isEmpty) {
            return p.dueDays.contains(today)
        }
        if r.isNow || r.summary.atRisk { return true }
        let left = daysLeft(p)
        switch p.rule.frequency {
        case .weekly: return p.dueDays.contains(today) || left <= 2
        case .interval: return left <= 2
        case .monthly: return left <= 7
        case .yearly: return false
        case .daily: return true
        }
    }
    private func daysLeft(_ p:HabitPeriodResult)->Int {
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = .gmt
        // `end` is the next period's first day, so today counts and `end` does not.
        return calendar.dateComponents([.day],from:today.date(in:.gmt),to:p.end.date(in:.gmt)).day ?? 0
    }
    private var todayRows: [HabitReading] { active.filter(dueToday).sorted { priority($0) < priority($1) } }
    private var openToday: [HabitReading] { todayRows.filter { $0.summary.current?.met != true } }
    private func priority(_ r:HabitReading)->Int { (r.summary.current?.met == true ? 100 : 0) + (r.isNow ? 0 : 10) + (r.summary.atRisk ? 0 : 1) }

    // MARK: Hero

    /// The next useful step, from what the room already knows: a streak at risk, a habit whose time is now, or the hour of the day.
    private var headline: (title:String,detail:String?) {
        let rows = todayRows, open = openToday
        if rows.isEmpty { return ("لا شيء مستحقّ اليوم","عاداتك الأخرى لها وقتها في أسبوعها وشهرها") }
        guard let next = open.first else { return ("يومك تمّ، دام القليل الجميل",nil) }
        // Owner 24 Oct: few words. The ring already shows «٠ من ٣», so the title stands alone.
        let left:String? = nil
        if next.summary.atRisk { return (next.name+": القليل اليوم يحفظ سلسلتك",left) }
        if next.isNow { return (next.name+": وقتها الآن",left) }
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = session.activePlace.timeZone
        let hour = calendar.component(.hour,from:session.prayerNow())
        return (hour < 12 ? "صباحك بخطوة صغيرة" : hour < 17 ? "خطوة صغيرة تكفي" : "ما زال في يومك متّسع",left)
    }
    private func heroAction(_ r:HabitReading)->String {
        guard r.source == nil, let p = r.summary.current else { return "تفاصيل "+r.name }
        switch p.rule.measure {
        case .once: return "أتممتُ "+r.name
        case .duration: return r.name+": أضف "+digits.string(15)+" دقيقة"
        default: return r.name+": سجّل "+habitOneMore(p.rule.unit)
        }
    }
    /// W2's short invitation leaves the full orbit as the room's focal point.
    private var nextStep: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle").foregroundStyle(theme.accent)
            Text(headline.title).font(MadarTypography.caption())
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let next = openToday.first {
                Button {
                    if next.source == nil, let period = next.summary.current {
                        complete(next, delta: period.rule.measure == .duration ? 15 : 1)
                    } else { detail = next }
                } label: {
                    // FB-39: the button names the habit it logs; a bare «سجّل» logged a habit the card never showed.
                    Text((next.source == nil ? "سجّل " : "افتح ") + next.name).font(MadarTypography.caption())
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(theme.accentFill, in: .capsule).foregroundStyle(theme.onAccent)
                }
                .buttonStyle(.madarPlain).disabled(completionInFlight.contains(next.id))
                .accessibilityLabel(heroAction(next)).accessibilityIdentifier("habits-next")
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line) }
    }

    private var hero: some View {
        let rows = todayRows, done = rows.count - openToday.count
        let share = rows.isEmpty ? 0 : Double(done)/Double(rows.count), line = headline
        return HStack(alignment:.center,spacing:16) {
            VStack(alignment:.leading,spacing:6) {
                Text(line.title).font(MadarTypography.cardTitle()).fixedSize(horizontal:false,vertical:true)
                if let detail = line.detail { Text(detail).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                if let next = openToday.first {
                    // The next step is one tap from the top: it logs, as the row's own button does; a linked habit opens its sheet.
                    Button {
                        if next.source == nil, let p = next.summary.current { complete(next, delta: p.rule.measure == .duration ? 15 : 1) } else { detail = next }
                    } label: { Text(heroAction(next)).font(MadarTypography.caption()).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true).padding(.horizontal,14).frame(minHeight:44).background(theme.accentFill,in:.capsule).foregroundStyle(theme.onAccent) }
                        .buttonStyle(.madarPlain).disabled(completionInFlight.contains(next.id)).padding(.top,4).accessibilityIdentifier("habits-next")
                }
            }
            Spacer(minLength:0)
            if !dynamicTypeSize.isAccessibilitySize {
                HabitHeroOrbit(share:share,done:!rows.isEmpty && done == rows.count,moving:!reduceMotion && !openToday.isEmpty,count:rows.isEmpty ? nil : digits.string(done)+" من "+digits.string(rows.count))
            }
        }
        .padding(.horizontal,18).padding(.vertical,14).frame(maxWidth:.infinity,alignment:.leading)
        .background(theme.surface,in:.rect(cornerRadius:24))
        .animation(reduceMotion ? nil : .smooth(duration:0.6),value:done)
        .sensoryFeedback(.success,trigger:done) { old,new in new > old }
        .accessibilityElement(children:.contain).accessibilityIdentifier("habits-hero")
    }

    // MARK: Lists

    /// A compact overview of the four frequencies. Choosing one opens its own grouped list;
    /// the Today/All switch remains available to return to either complete view.
    private var periodSummaries: some View {
        HStack(spacing: 6) {
            ForEach([HabitFrequency.daily, .weekly, .monthly, .yearly], id: \.self) { frequency in
                periodSummary(frequency)
            }
        }
    }

    private func periodSummary(_ frequency: HabitFrequency) -> some View {
        let group = active.filter { $0.summary.current?.rule.band == frequency }
        let rows = group.filter { !$0.paused && ($0.summary.current?.target ?? 0) > 0 }
        let done = rows.filter { $0.summary.current?.met == true }.count
        let count = rows.isEmpty ? (group.isEmpty ? "لا عادات" : "لا شيء مستحق") : digits.string(done) + " من " + digits.string(rows.count)
        let title: String = switch frequency {
        case .daily: "اليوم"
        case .interval: "المُدد"
        case .weekly: "الأسبوع"
        case .monthly: "الشهر"
        case .yearly: "السنة"
        }
        return HabitPeriodSummaryCard(title: title, count: count,
                                      share: rows.isEmpty ? 0 : Double(done) / Double(rows.count),
                                      selected: showAll && selectedPeriod == frequency, enabled: !group.isEmpty,
                                      frequency: frequency, theme: theme, showsRing: !dynamicTypeSize.isAccessibilitySize) {
            withAnimation(reduceMotion ? nil : .snappy) { showAll = true; selectedPeriod = frequency }
        }
    }

    private var viewSwitch: some View {
        HStack(spacing:6) {
            ForEach([false,true],id:\.self) { all in
                let on = showAll == all && (!all || selectedPeriod == nil)
                Button { withAnimation(reduceMotion ? nil : .snappy) { showAll = all; selectedPeriod = nil } } label: {
                    Text(all ? "كل عاداتي" : "اليوم").font(MadarTypography.caption()).frame(maxWidth:.infinity,minHeight:40)
                        .background { if on { Capsule().fill(theme.accentFill.opacity(0.14)).glassEffect(.regular.interactive(), in: .capsule).matchedGeometryEffect(id:"lens",in:viewLens) } }
                        .foregroundStyle(on ? theme.ink : theme.secondaryInk).contentShape(.capsule)
                }
                .buttonStyle(.madarPlain).accessibilityAddTraits(on ? .isSelected : []).accessibilityIdentifier(all ? "habits-view-all" : "habits-view-today")
            }
        }
        // FB-35: one glass track with a lens that slides between «اليوم» and «كل عاداتي», like the tab bar.
        .padding(4).background(theme.line.opacity(0.35),in:.capsule).padding(.top,6)
    }
    @ViewBuilder private var todayList: some View {
        let rows = todayRows, open = rows.filter { $0.summary.current?.met != true }, done = rows.filter { $0.summary.current?.met == true }
        let frozen = active.filter { $0.paused && $0.summary.current?.rule.frequency == .daily }
        let laterRows = active.filter { r in !rows.contains { $0.id == r.id } && !frozen.contains { $0.id == r.id } }
        let later = laterRows.count, laterOpen = laterRows.filter { $0.summary.current?.met != true && !$0.paused }.count
        let laterPaused = laterRows.filter(\.paused).count
        let settledLater = laterPaused == later ? "عاداتك الأخرى مجمّدة" : laterPaused > 0 ? "عادات مكتملة وأخرى مجمّدة" : "عاداتك الأخرى تمّت في فتراتها"
        if rows.isEmpty && frozen.isEmpty {
            Button { withAnimation(reduceMotion ? nil : .snappy) { showAll = true } } label: { Label("لا شيء مستحقّ اليوم؛ اعرض كل عاداتك",systemImage:"list.bullet").font(MadarTypography.caption()).frame(maxWidth:.infinity,minHeight:56) }
                .buttonStyle(.madarPlain).background(theme.surface,in:.rect(cornerRadius:20)).accessibilityIdentifier("habits-today-empty")
        } else {
            ForEach([HabitFrequency.daily, .weekly, .monthly, .yearly], id: \.self) { frequency in
                let group = open.filter { $0.summary.current?.rule.band == frequency }
                if !group.isEmpty {
                    Text(frequency.arabic).font(MadarTypography.section()).padding(.top, 4)
                        .accessibilityIdentifier("habits-today-group-" + frequency.rawValue)
                    rowsBlock(group)
                }
            }
            if !done.isEmpty {
                Text("تمّت اليوم").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).padding(.top,open.isEmpty ? 0 : 10)
                rowsBlock(done)
            }
            if !frozen.isEmpty {
                Text("مجمّدة حتى تفكّها").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).padding(.top,10)
                rowsBlock(frozen)
            }
        }
        if later > 0 {
            Button { withAnimation(reduceMotion ? nil : .snappy) { showAll = true } } label: {
                HStack { Text(laterOpen == 0 ? settledLater : laterOpen == 1 ? "عادة أخرى تنتظر في فترتها" : laterOpen == 2 ? "عادتان أخريان في فترتيهما" : arabicCount(laterOpen,["","","عادات","عادة"],digits)+" أخرى في فتراتها").font(MadarTypography.fine()); Image(systemName:"chevron.left").font(.caption) }
                    .foregroundStyle(theme.accent).frame(minHeight:44)
            }.buttonStyle(.madarPlain).accessibilityIdentifier("habits-later")
        }
    }
    @ViewBuilder private var allList: some View {
        ForEach([HabitFrequency.daily,.weekly,.monthly,.yearly],id:\.self) { f in
            let rows = active.filter { ($0.summary.current?.rule.band ?? .daily) == f }.sorted { priority($0) < priority($1) }
            if !rows.isEmpty && (selectedPeriod == nil || selectedPeriod == f) {
                HStack(alignment:.firstTextBaseline) {
                    Text(f == .daily ? "كل يوم" : f == .weekly ? "كل أسبوع" : f == .monthly ? "كل شهر" : "كل سنة").font(MadarTypography.section())
                    Spacer()
                    if let left = windowLeft(f,rows) { Text(left).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                }.padding(.top,10).accessibilityElement(children:.combine).accessibilityIdentifier("habits-group-"+f.rawValue)
                if !dynamicTypeSize.isAccessibilitySize { HabitRhythmBand(frequency:f,rows:rows,today:today,digits:digits) }
                rowsBlock(rows)
            }
        }
    }
    private func rowsBlock(_ rows:[HabitReading])->some View {
        VStack(spacing:0) { ForEach(rows) { row in habitRow(row); if row.id != rows.last?.id { Divider().overlay(theme.line).padding(.leading,58) } } }
            .background(theme.surface,in:.rect(cornerRadius:22))
    }
    /// What is left of the current window («بقي ٣ أيام»); a day's own window needs no countdown.
    private func windowLeft(_ f:HabitFrequency,_ rows:[HabitReading]) -> String? {
        guard f != .daily, let p = rows.compactMap({ $0.summary.current }).first else { return nil }
        let left = daysLeft(p)
        guard left > 0 else { return nil }
        return left == 1 ? "آخر يوم فيها" : "بقي " + habitPeriodCount(left,.daily,digits)
    }
    private func habitRow(_ row:HabitReading)->some View {
        let p = row.summary.current, met = p?.met == true
        let share = Double(p?.value ?? 0)/Double(max(1,p?.target ?? 1))
        return HStack(spacing:0) {
            leading(row,share:share,met:met).padding(.leading,10)
            Button { detail = row } label: {
                HStack(spacing:12) {
                    VStack(alignment:.leading,spacing:4) {
                        HStack(spacing:6) { Text(row.name).font(MadarTypography.section()); if row.summary.streak > 1 { HabitFlame(count:row.summary.streak,frequency:p?.rule.frequency ?? .daily,digits:digits) }; if let source=row.sourceTitle { Text(source).font(MadarTypography.fine()).padding(.horizontal,6).padding(.vertical,2).background(theme.background,in:.capsule) } }
                        if !progress(row).isEmpty { Text(progress(row)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                        if row.paused || row.isNow || row.summary.atRisk { Label(row.statusTitle,systemImage:row.paused ? "pause.circle" : "circle.lefthalf.filled").font(MadarTypography.fine()).foregroundStyle(theme.accent) }
                    }
                    Spacer(minLength:0)
                }.padding(.leading,10).padding(.vertical,13).frame(minHeight:70).contentShape(.rect)
            }.buttonStyle(.madarPlain).accessibilityIdentifier("habit-row-"+row.id.uuidString).accessibilityLabel(row.name+"، "+progress(row)+"، "+row.statusTitle)
            // A day forgotten is one long-press away (item 26), without opening the habit.
            .contextMenu { if row.source == nil, !row.archived, let p = row.summary.current, p.rule.measure != .health, (row.summary.periods.first?.start).map({ $0 < today }) == true { Button("فعلتها في يوم سابق",systemImage:"calendar.badge.clock") { pastDay = row } } }
            trailing(row).padding(.trailing,10)
        }
    }
    /// A once-habit's ring is its own checkbox: one circle per row, tapped to finish (tour 25 Oct: the ring
    /// beside an empty tap circle read as two of the same). Count habits keep the ring as progress and a «+».
    @ViewBuilder private func leading(_ row:HabitReading,share:Double,met:Bool)->some View {
        if let p=row.summary.current, row.source == nil, !row.paused, p.target > 0, p.rule.measure == .once, !met {
            Button {
                complete(row, delta: 1)
            } label: {
                Circle().stroke(theme.accent,lineWidth:2).frame(width:32,height:32).frame(width:44,height:44).contentShape(.circle)
            }.buttonStyle(.madarPlain).disabled(completionInFlight.contains(row.id))
            .accessibilityLabel(quickLogLabel(row.name,.once))
            .accessibilityIdentifier("habit-quick-"+row.id.uuidString)
        } else if !dynamicTypeSize.isAccessibilitySize {
            HabitRingGlyph(share:share,done:met,symbol:row.source == nil ? row.nameGlyph : row.symbol).frame(width:36,height:36).frame(width:44,height:44)
        }
    }
    /// Count and duration habits log from a «+»; a once-habit logs from its ring.
    @ViewBuilder private func trailing(_ row:HabitReading)->some View {
        if row.source == nil, !row.paused, let p=row.summary.current, p.target > 0, p.rule.measure != .once {
            Button { complete(row, delta: p.rule.measure == .duration ? 15 : 1) } label: {
                Image(systemName:"plus").font(.system(size:16,weight:.semibold)).foregroundStyle(p.met ? theme.accent : theme.onAccent).frame(width:38,height:38).background(p.met ? theme.accentFill.opacity(0.14) : theme.accentFill,in:.circle)
                    .frame(width:44,height:44).contentShape(.circle)
            }.buttonStyle(.madarPlain).disabled(completionInFlight.contains(row.id))
            .accessibilityLabel(quickLogLabel(row.name,p.rule.measure))
            .accessibilityIdentifier("habit-quick-"+row.id.uuidString)
        }
    }
    private func quickLogLabel(_ name:String,_ measure:HabitMeasure)->String {
        switch measure {
        case .once: return "أتممت " + name
        case .duration: return "أضف " + digits.string(15) + " دقيقة إلى " + name
        default: return "أضف واحدًا إلى " + name
        }
    }
    private func progress(_ row:HabitReading)->String { guard let p=row.summary.current else{return "لا فترة بعد"}; return p.target == 0 ? "سجلك محفوظ" : p.rule.measure == .once && p.target == 1 ? (p.value >= 1 ? "تمّت" : "") : habitProgressText(p.value,p.target,p.rule.unit,digits) }
    /// Owner, 5 Nov 2026 («اضغط العاده يعلق التطبيق»): every table of every habit is read on a background context, and only the
    /// latest request lands, so a tap, a Health refresh and a prayer write in a row never stack reads on the main thread.
    private func reload() {
        reloadTask?.cancel()
        let container = session.container, now = session.prayerNow(), health = liveHealth
        reloadTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try HabitRepository(context: ModelContext(container)).readings(at: now, includeArchived: true, liveHealth: health) }
            }.value
            guard !Task.isCancelled else { return }
            apply(result)
        }
    }
    private func apply(_ result: Result<[HabitReading], Error>) {
        do {
            let fresh = try result.get()
            readings = fresh; loaded = true
            if let selected = detail, let updated = selected.refreshed(in: fresh) { detail = updated }
            if let id = session.habitRouteID {
                if let row = fresh.first(where: { $0.id == id }) {
                    if row.archived { showArchived = true } else { detail = row }
                }
                session.habitRouteID = nil
            }
        } catch { loaded = true; session.errorMessage = madarUserMessage(error) }
    }
    private func complete(_ row: HabitReading, delta: Int) {
        guard !completionInFlight.contains(row.id) else { return }
        completionInFlight.insert(row.id)
        perform("habit.complete", ["id": .string(row.id.uuidString), "delta": .number(Double(delta))]) {
            completionInFlight.remove(row.id)
        }
    }
    private func perform(_ name:String,_ payload:[String:MadarCore.JSONValue],done:@escaping () -> Void = {}) { Task { defer{done()}; do {try await session.executeDiaryCommand(name,payload:payload);reload()}catch{session.errorMessage=madarUserMessage(error)} } }
}

private struct HabitPeriodSummaryCard: View {
    let title: String
    let count: String
    let share: Double
    let selected: Bool
    let enabled: Bool
    let frequency: HabitFrequency
    let theme: RoomTheme
    let showsRing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(MadarTypography.fine()).lineLimit(1)
                    Text(count).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2))
                        .foregroundStyle(theme.secondaryInk).lineLimit(1)
                }
                Spacer(minLength: 0)
                if showsRing { HabitMiniRing(share: share, theme: theme).frame(width: 22, height: 22) }
            }
            .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 58)
            .background(theme.surface, in: .rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(selected ? theme.accentFill : theme.line, lineWidth: selected ? 1.5 : 1) }
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.madarPlain).disabled(!enabled)
        .accessibilityLabel(frequency.arabic + "، " + count)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("habits-period-" + frequency.rawValue)
    }
}
/// A habit as its own small orbit: the ring closes as the period's progress grows; a finished habit
/// fills softly and takes a star. Linked habits carry their room's glyph. (Owner 24 Oct: arches are the
/// prayer room's mark, not the habits'.)
struct HabitRingGlyph:View {
    let share:Double; let done:Bool; let symbol:String?
    var lineWidth:CGFloat = 3.5
    @Environment(\.roomTheme) private var theme
    var body:some View {
        ZStack {
            Circle().fill(done ? theme.accentFill.opacity(0.16) : .clear)
            Circle().stroke(theme.line,lineWidth:lineWidth)
            Circle().trim(from:0,to:done ? 1 : min(1,max(0,share))).stroke(theme.accentFill,style:.init(lineWidth:lineWidth,lineCap:.round)).rotationEffect(.degrees(-90))
            if let symbol { MadarGlyph(symbol,size:14).foregroundStyle(theme.accent) }
            else if done && lineWidth > 2 { PrayerStar().fill(theme.accent).frame(width:11,height:11) }
            else if done { Circle().fill(theme.accentFill).padding(lineWidth*1.5) }
        }.padding(lineWidth/2).accessibilityHidden(true)
    }
}
/// The day as a small «مدار»: today's ring closes as habits finish, two faint outer orbits stand for the
/// week and the month, and one bead travels the outer orbit slowly while something is still open.
private struct HabitHeroOrbit:View {
    let share:Double; let done:Bool; let moving:Bool; var count:String?
    @Environment(\.roomTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        ZStack {
            Circle().stroke(theme.line.opacity(0.6),lineWidth:1)
            Circle().stroke(theme.line,lineWidth:1).padding(9)
            TimelineView(.animation(minimumInterval:1/12,paused:!moving || reduceMotion)) { context in
                let angle = moving && !reduceMotion ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:40)/40*360 : 210
                Circle().fill(theme.accentFill).frame(width:7,height:7).offset(y:-44).rotationEffect(.degrees(angle))
            }
            HabitRingGlyph(share:share,done:done,symbol:nil,lineWidth:5).padding(19)
            if let count, !done { Text(count).font(MadarTypography.fine()).foregroundStyle(theme.ink).lineLimit(1).minimumScaleFactor(0.7) }
        }.frame(width:92,height:92).accessibilityHidden(true)
    }
}
/// The streak as a flame and its count, no words (owner, 24 Oct: «شعلة وعندها الأيام وبس»).
struct HabitFlame:View {
    let count:Int; let frequency:HabitFrequency; let digits:MadarNumberFormatter
    @Environment(\.roomTheme) private var theme
    var body:some View {
        HStack(spacing:2) { Image(systemName:"flame.fill").font(.system(size:12,weight:.semibold)); Text(digits.string(count)).font(MadarTypography.caption()) }
            .foregroundStyle(theme.accent).accessibilityElement().accessibilityLabel("سلسلة "+habitPeriodCount(count,frequency,digits))
    }
}
struct HabitMiniRing:View {
    let share:Double; let theme:RoomTheme
    var body:some View { ZStack { Circle().stroke(theme.line,lineWidth:4); Circle().trim(from:0,to:min(1,max(0,share))).stroke(theme.accentFill,style:.init(lineWidth:4,lineCap:.round)).rotationEffect(.degrees(-90)) }.accessibilityHidden(true) }
}
/// «٣ من ٨ أكواب»; before anything is logged, the goal alone («الهدف: ٨ أكواب») rather than «٠ من ٨».
func habitProgressText(_ value:Int,_ target:Int,_ unit:String?,_ digits:MadarNumberFormatter)->String {
    guard let unit, !unit.isEmpty else {
        if value > 0 { return digits.string(value)+" من "+(target == 2 ? "مرتين" : digits.string(target)) }
        return target == 1 ? "لم تتمّها بعد" : "الهدف: "+arabicCount(target,["مرة واحدة","مرتان","مرات","مرة"],digits)
    }
    return value == 0 ? "الهدف: "+habitUnitCount(target,unit,digits) : digits.string(value)+" من "+habitUnitCount(target,unit,digits,genitive:true)
}
/// One more of a unit, as the object of «سجّل/أضف»: «كوبًا»، «صفحة»، «مرة».
func habitOneMore(_ unit:String?)->String {
    guard let unit, !unit.isEmpty else { return "مرة" }
    return ["كوب":"كوبًا","كأس":"كأسًا","pages":"صفحة","صفحة":"صفحة","ركعة":"ركعة","مرة":"مرة","فنجان":"فنجانًا"][unit] ?? "واحدًا"
}
func habitUnitName(_ unit:String)->String { ["minutes":"دقيقة","exerciseMinutes":"دقيقة حركة","steps":"خطوة","pages":"صفحة"][unit] ?? unit }
/// A count with its unit in Arabic number agreement; the table lives in `WidgetCopy` so the widget says the same.
func habitUnitCount(_ count:Int,_ unit:String?,_ digits:MadarNumberFormatter,genitive:Bool=false)->String {
    WidgetCopy.unitCount(count,unit,digits,genitive:genitive)
}
/// Arabic number agreement from four forms: one, two, plural (٣–١٠), and the singular after ١١ and above.
func arabicCount(_ count:Int,_ forms:[String],_ digits:MadarNumberFormatter)->String {
    count == 1 ? forms[0] : count == 2 ? forms[1] : digits.string(count)+" "+((3...10).contains(count%100) ? forms[2] : forms[3])
}
func habitPeriodCount(_ count:Int,_ frequency:HabitFrequency,_ digits:MadarNumberFormatter)->String {
    let forms:[String]
    switch frequency {case .daily:forms=["يوم واحد","يومان","أيام","يومًا"];case .interval:forms=["مدة واحدة","مدتان","مُدد","مدة"];case .weekly:forms=["أسبوع واحد","أسبوعان","أسابيع","أسبوعًا"];case .monthly:forms=["شهر واحد","شهران","أشهر","شهرًا"];case .yearly:forms=["سنة واحدة","سنتان","سنوات","سنة"]}
    return count == 1 ? forms[0] : count == 2 ? forms[1] : digits.string(count)+" "+(count == 0 || (3...10).contains(count%100) ? forms[2] : forms[3])
}
/// Named in the habit's own period when known: «تنكسر السلسلة بفوت يومين متتاليين. الأيام المجمدة مستثناة.»
func habitBreakExplanation(_ periods:Int,_ frequency:HabitFrequency?=nil)->String {
    let forms:[String], frozen:String
    switch frequency {
    case .daily?: forms=["يوم واحد","يومين متتاليين","ثلاثة أيام متتالية"]; frozen="الأيام"
    case .interval?: forms=["مدة واحدة","مدتين متتاليتين","ثلاث مدد متتالية"]; frozen="المُدد"
    case .weekly?: forms=["أسبوع واحد","أسبوعين متتاليين","ثلاثة أسابيع متتالية"]; frozen="الأسابيع"
    case .monthly?: forms=["شهر واحد","شهرين متتاليين","ثلاثة أشهر متتالية"]; frozen="الأشهر"
    case .yearly?: forms=["سنة واحدة","سنتين متتاليتين","ثلاث سنوات متتالية"]; frozen="السنوات"
    case nil: forms=["فترة واحدة","فترتين متتاليتين","ثلاث فترات متتالية"]; frozen="الفترات"
    }
    return "تنكسر السلسلة بفوت "+forms[min(max(periods,1),3)-1]+". "+frozen+" المجمدة مستثناة."
}

/// FB-39: an «every N days» habit sits in the band nearest its length — up to a week with the weekly habits,
/// up to a month with the monthly ones, longer with the yearly ones — so every grouped view shows it.
extension HabitRule {
    var band: HabitFrequency {
        guard frequency == .interval else { return frequency }
        let days = intervalDays ?? 3
        return days <= 7 ? .weekly : days <= 31 ? .monthly : .yearly
    }
}
