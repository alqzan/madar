import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarDesign
import MadarCommands

extension HabitFrequency {
    var arabic: String { switch self { case .daily: "يومية"; case .interval: "كل عدة أيام"; case .weekly: "أسبوعية"; case .monthly: "شهرية"; case .yearly: "سنوية" } }
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
        if quitting { return summary.current?.outcome == .missed ? "زلّة اليوم" : "تركتها" }
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
    /// The habit whose story the room is telling (canvas `sel`); nil shows every habit.
    @State private var selected: UUID?
    @State private var pastDay: HabitReading?
    /// AU-95: repeated quick taps submit one command while a habit completion is still saving.
    @State private var completionInFlight: Set<UUID> = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("Madar.pad.sidebarHidden") private var sidebarHidden = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var theme: RoomTheme { .init(room:"bahw",dark:colorScheme == .dark) }
    private var digits: MadarNumberFormatter { .init(style:session.string("core.numerals") == "western" ? .western : .hindi) }
    private var active: [HabitReading] { readings.filter { !$0.archived } }
    private var today: GregorianDay { AppBahwService(session:session).today }
    var body: some View {
        VStack(spacing:0) {
            HStack {
                // Owner 17 Nov 2026: habits are a tab root now, so there is no way back to the lobby here; the empty slot keeps the title centred.
                Color.clear.frame(width:44,height:44).accessibilityHidden(true)
                Spacer()
                VStack(spacing:2) { Text("العادات").font(.custom("thmanyahserifdisplay-Bold",size:26,relativeTo:.title)).accessibilityIdentifier("habits-title"); MadarDateLabel(session.dateLabels(today,weekday:true),primaryFont:HabitType.fine(),secondaryFont:HabitType.fine()).foregroundStyle(theme.secondaryInk) }
                Spacer()
                Button { editor = .init(id:UUID()) } label: { Image(systemName:"plus").frame(width:44,height:44).glassEffect(.regular.interactive(), in: .circle) }.buttonStyle(.madarPlain).accessibilityLabel("عادة جديدة").accessibilityIdentifier("habit-add")
            }.padding(.horizontal,14).padding(.vertical,8)
                // iPad with the sidebar folded: its «أظهر القائمة» button sits in this corner, so the add button steps inward.
                .padding(.trailing, sidebarHidden && isPadWide(sizeClass) ? 56 : 0)
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    if !loaded { Color.clear.frame(height: 1) }
                    else if active.isEmpty { empty; roomHabits; archivedBlock }
                    else {
                        periodSummaries
                        VStack(alignment:.leading,spacing:8) { dailySection; longerSection; archivedBlock }
                        if let chosen = selectedReading { story(chosen).id("habit-story") }
                        orbit
                        HabitRoomAnalysis(readings:active.filter { !$0.quitting },selected:selected,session:session,digits:digits,theme:theme)
                        VStack(alignment:.leading,spacing:8) {
                            Button { editor = .init(id:UUID()) } label: { Label("عادة صغيرة جديدة",systemImage:"plus").font(HabitType.caption()).frame(maxWidth:.infinity,minHeight:48).overlay { RoundedRectangle(cornerRadius:16).stroke(theme.line,style:.init(lineWidth:1,dash:[4,4])) }.contentShape(.rect) }
                                .buttonStyle(.madarPlain).accessibilityIdentifier("habits-new")
                            roomHabits
                        }
                    }
                    VStack(spacing:4) { Text("«أحبّ الأعمال إلى الله أدومها وإن قلّ»").font(HabitType.body()); Text("متفق عليه، من حديث عائشة رضي الله عنها").font(HabitType.fine()).foregroundStyle(theme.secondaryInk) }.frame(maxWidth:.infinity).padding(.vertical,24)
                }.padding(.horizontal,14).padding(.vertical,8)
            }.onChange(of:selected) { _,new in
                guard new != nil else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration:0.5)) { proxy.scrollTo("habit-story",anchor:.top) }
            }
            }.madarTopClipped()
        }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.accent)
        .toolbarVisibility(.hidden,for:.navigationBar).environment(\.roomTheme,theme)
        .task(id:session.habitsRevision) { reload() }
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
        // A room left open across midnight shows the new day without waiting for a Health change.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in reload() }
        .task { do {liveHealth=try await HabitHealthStore.refresh(session:session);reload()} catch {session.errorMessage="لم تتجدد قراءة الصحة؛ سجلك السابق محفوظ."} }
        .task {
            while !Task.isCancelled {
                // The tab stays alive behind the others: only poll Health while habits is the room being looked at.
                if session.selectedTab == "habits" { do { let fresh=try await HabitHealthStore.refresh(session:session,closedDays:false); if fresh != liveHealth { liveHealth=fresh;reload() } }catch{} }
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
        ("preset.jamaah", "صليت كل الصلوات بجماعة", "يسألك مدار عنها بعد العشاء بساعة", "MadarPrayer", "salah"),
        ("preset.ramadanQiyam", HabitPresets.ramadanQiyamName, "رمضان: يسألك مدار بعد التراويح", "moon.stars", "bahw"),
        ("preset.ramadanSuhoor", HabitPresets.ramadanSuhoorName, "رمضان: يسألك مدار قبل الفجر", "sunrise", "bahw"),
        ("preset.fast", HabitPresets.mondayThursdayFastName, "يسألك مدار مساء الليلة التي قبل كل يوم", "moon.stars", "bahw"),
        ("walking", "المشي", "تُحسب من خطواتك في تطبيق الصحة", "figure.walk", "bahw")]
    private var roomHabitsLeft: [(source: String, title: String, detail: String, symbol: String, room: String)] {
        var kept = Set(readings.filter { !$0.archived }.compactMap(\.source))
        if readings.contains(where: { !$0.archived && $0.name == HabitJamaahConversion.name }) { kept.insert("preset.jamaah") }
        for (id, name) in [("preset.fast", HabitPresets.mondayThursdayFastName), ("preset.ramadanQiyam", HabitPresets.ramadanQiyamName), ("preset.ramadanSuhoor", HabitPresets.ramadanSuhoorName)]
            where readings.contains(where: { !$0.archived && $0.name == name }) { kept.insert(id) }
        // Ramadan mode: its presets appear only while the Hijri month is Ramadan.
        let ramadan = HabitPresets.isRamadan(AppBahwService(session: session).today, days: MadarCalendarDays(zone: session.activePlace.timeZone, source: HijriSource(rawValue: session.string("core.hijriSource")) ?? .ummAlQura, offset: Int(session.number("core.hijriOffset"))))
        return Self.roomSources.filter { !kept.contains($0.source) && ($0.source != "walking" || HabitHealthStore.available) && (ramadan || !$0.source.hasPrefix("preset.ramadan")) }
    }
    @ViewBuilder private var roomHabits: some View {
        let left = roomHabitsLeft
        if !left.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("من غرف مدار").font(HabitType.section()).accessibilityAddTraits(.isHeader)
                Text("عادات يسجّلها مدار وحده مما تفعله في غرفه؛ أضفها لتظهر هنا مع عاداتك.").font(HabitType.fine()).foregroundStyle(theme.secondaryInk)
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
                                Text(item.title).font(HabitType.section())
                                Text(item.detail).font(HabitType.fine()).foregroundStyle(theme.secondaryInk)
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
        VStack(spacing:16) { HabitRingGlyph(share:0,done:false,symbol:nil,lineWidth:5).frame(width:60,height:60); Text("القليل الذي تدوم عليه").font(HabitType.title()); Text("اختر عادة صغيرة تبدأ بها، أو اربطها بما تسجّله في غرف مدار.").font(HabitType.body()).multilineTextAlignment(.center).foregroundStyle(theme.secondaryInk); Button { editor = .init(id:UUID()) } label: { Text("أضف أول عادة").font(HabitType.section()).padding(.horizontal,22).frame(minHeight:48).background(theme.accentFill,in:.capsule).foregroundStyle(theme.onAccent) }.buttonStyle(.madarPlain).accessibilityIdentifier("habit-first") }.padding(28).frame(maxWidth:.infinity).background(theme.surface,in:.rect(cornerRadius:24)).padding(.top,25)
    }

    @ViewBuilder private var archivedBlock: some View {
        if readings.contains(where: \.archived) {
                        Button { showArchived.toggle() } label: { Text(showArchived ? "أخفِ العادات المحذوفة" : "عادات محذوفة").font(HabitType.caption()).frame(minHeight:44).contentShape(Rectangle()) }.accessibilityIdentifier("habit-archived")
                        if showArchived { ForEach(readings.filter(\.archived)) { row in HStack(spacing:10) { Text(row.name); Spacer(); Button { deletingArchived=row } label: { Text("حذف نهائي").font(HabitType.caption()).foregroundStyle(theme.secondaryInk).frame(minHeight:44).contentShape(Rectangle()) }.accessibilityLabel("حذف نهائي "+row.name); Button("استعدها") { perform("habit.archive",["id":.string(row.id.uuidString),"archived":.bool(false)]) }.buttonStyle(.borderedProminent).frame(minHeight:44) }.padding(14).background(theme.surface,in:.rect(cornerRadius:18)) } }
                    }
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
        guard !r.paused, !r.quitting, let p=r.summary.current, p.target > 0 else { return false }
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

    // MARK: Lists

    /// The four period cards. With a habit chosen they tell that habit's own day, week, month and year.
    private var periodSummaries: some View {
        let cards: [HabitCardModel] = selectedReading.map(selectedCards) ?? [HabitFrequency.daily, .weekly, .monthly, .yearly].map(allCard)
        // From the accessibility sizes the four cards stack, one full-width card per period, instead of squeezing into one row.
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            ForEach(cards, id: \.frequency) { card in
                HabitPeriodSummaryCard(title: card.title, count: card.count, share: card.share, frequency: card.frequency, theme: theme, showsRing: !dynamicTypeSize.isAccessibilitySize)
            }
        }
    }
    private func allCard(_ frequency: HabitFrequency) -> HabitCardModel {
        let group = active.filter { $0.summary.current?.rule.band == frequency }
        let rows = group.filter { !$0.paused && !$0.quitting && ($0.summary.current?.target ?? 0) > 0 }
        let done = rows.filter { $0.summary.current?.met == true }.count
        let count = rows.isEmpty ? (group.isEmpty ? "لا عادات" : "لا شيء مستحق") : digits.string(done) + " من " + digits.string(rows.count)
        return .init(title: periodTitle(frequency), count: count, share: rows.isEmpty ? 0 : Double(done) / Double(rows.count), frequency: frequency)
    }
    private func periodTitle(_ f: HabitFrequency) -> String { f == .daily ? "اليوم" : f == .weekly ? "الأسبوع" : f == .monthly ? "الشهر" : f == .yearly ? "السنة" : "المُدد" }
    private var selectedReading: HabitReading? { selected.flatMap { id in active.first { $0.id == id } } }
    private func rank(_ f: HabitFrequency) -> Int { switch f { case .daily: 0; case .interval, .weekly: 1; case .monthly: 2; case .yearly: 3 } }
    /// The chosen habit across today, the week, the month and the year: its own period shows its progress, a shorter one says it
    /// is not asked, a longer one counts the times it was done in it, and a daily habit counts its kept days.
    private func selectedCards(_ r: HabitReading) -> [HabitCardModel] {
        let service = AppBahwService(session: session), hijriFirst = session.string("core.firstCalendar") == "hijri", days = service.calendarDays
        let starts: [HabitFrequency: GregorianDay] = [
            .daily: today, .weekly: MadarYear.week(today, start: service.weekStart).start,
            .monthly: (hijriFirst ? MadarYear.hijriMonth(today, days) : MadarYear.gregorianMonth(today)).start,
            .yearly: (hijriFirst ? MadarYear.hijriYear(today, days) : MadarYear.gregorianYear(today)).start]
        let band = r.summary.current?.rule.band ?? .daily
        let rates = HabitRoomInsights.dayRates([HabitRoomSeries(id: r.id, periods: r.summary.periods, doneDays: r.times.map(\.day), loggedAt: [])], selected: r.id, today: today)
        return [HabitFrequency.daily, .weekly, .monthly, .yearly].map { f in
            let title = periodTitle(f), start = starts[f] ?? today
            if f == band, let p = r.summary.current {
                let share = p.target == 0 ? 0 : p.met ? 1 : min(1, Double(p.value) / Double(p.target))
                return .init(title: title, count: p.target == 0 ? "إجازتها اليوم" : habitProgressText(p.rule.measure == .once ? min(p.value, p.target) : p.value, p.target, p.rule.unit, digits), share: share, frequency: f)
            }
            if band == .daily {
                let counted = (0...max(0, MadarCalendarDays.distance(from: start, to: today))).compactMap { rates[start.adding(days: $0)] }
                let met = counted.filter { $0 >= 1 }.count
                let share = counted.isEmpty ? 0 : Double(met) / Double(counted.count)
                return .init(title: title, count: counted.isEmpty ? "لا بيانات" : f == .yearly ? digits.percent(Int((share * 100).rounded())) + " من الأيام" : digits.string(met) + " من " + digits.string(counted.count), share: share, frequency: f)
            }
            if rank(f) < rank(band) { return .init(title: title, count: "لا تُسأل " + (f == .daily ? "يوميًا" : f == .weekly ? "أسبوعيًا" : "شهريًا"), share: 0, frequency: f) }
            let n = r.times.filter { $0.day >= start && $0.day <= today }.count
            return .init(title: title, count: n == 0 ? "لم تُتمّها" : arabicCount(n, ["مرة واحدة", "مرتان", "مرات", "مرة"], digits) + (f == .weekly ? " هذا الأسبوع" : f == .monthly ? " هذا الشهر" : " هذه السنة"), share: n > 0 ? 1 : 0, frequency: f)
        }
    }

    // MARK: Lists

    private func choose(_ row: HabitReading) {
        let next = selected == row.id ? nil : row.id
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { selected = next }
    }
    private var dailyRows: [HabitReading] {
        active.enumerated().filter { ($0.element.summary.current?.rule.band ?? .daily) == .daily }
            .sorted { (settled($0.element) ? 1 : 0, $0.offset) < (settled($1.element) ? 1 : 0, $1.offset) }.map(\.element)
    }
    private var longerRows: [HabitReading] {
        active.enumerated().filter { ($0.element.summary.current?.rule.band ?? .daily) != .daily }
            .sorted { (settled($0.element) ? 1 : 0, $0.offset) < (settled($1.element) ? 1 : 0, $1.offset) }.map(\.element)
    }
    /// Done habits sink to the bottom of their list; a frozen one rests there too.
    private func settled(_ r: HabitReading) -> Bool { r.paused || r.summary.current?.met == true }
    @ViewBuilder private var dailySection: some View {
        let rows = dailyRows, due = rows.filter(dueToday), done = due.filter { $0.summary.current?.met == true }.count
        if !rows.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text("يومية").font(HabitType.cardTitle()).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(due.isEmpty ? "لا شيء مستحقّ اليوم" : digits.string(done) + " من " + digits.string(due.count) + "، اضغط الحلقة إذا سويتها").font(HabitType.caption()).foregroundStyle(theme.secondaryInk)
            }.padding(.horizontal, 4).accessibilityIdentifier("habits-daily-header")
            rowsBlock(rows)
        }
    }
    @ViewBuilder private var longerSection: some View {
        let rows = longerRows
        if !rows.isEmpty {
            Text("أسبوعية وشهرية وسنوية").font(HabitType.cardTitle()).padding(.horizontal, 4).padding(.top, 10).accessibilityAddTraits(.isHeader).accessibilityIdentifier("habits-longer-header")
            rowsBlock(rows)
        }
    }
    private func rowsBlock(_ rows: [HabitReading]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(theme.ink.opacity(0.07)) }
                habitRow(row)
            }
        }.background(theme.surface, in: .rect(cornerRadius: 24)).clipShape(.rect(cornerRadius: 24))
    }
    // MARK: Story and orbit

    private func story(_ row: HabitReading) -> some View {
        let service = AppBahwService(session: session)
        let breakAfter = min(3, max(1, Int(session.number("bahw.streakBreakAfter")) == 0 ? 2 : Int(session.number("bahw.streakBreakAfter"))))
        let longest = HabitRoomInsights.longestStreak(row.summary.periods, today: today, breakAfter: breakAfter)
        return HabitStoryCard(reading: row, rule: ruleLine(row), digits: digits, started: session.dateLabels(row.firstEffectiveFrom), longestDate: longest.map { session.dateLabels($0.end) }, today: service.today, breakAfter: breakAfter,
                              clear: { choose(row) }, details: { detail = row })
    }
    /// «٥ كم كل يوم»: what the rule asks, in the habit's own words.
    private func ruleLine(_ row: HabitReading) -> String {
        guard let rule = row.summary.current?.rule ?? row.latestRule else { return "" }
        if rule.measure == .abstain { return "عادة تركتها؛ يُحسب كل يوم بلا زلّة" }
        let every: String = switch rule.frequency { case .daily: "كل يوم"; case .weekly: "كل أسبوع"; case .monthly: "كل شهر"; case .yearly: "كل سنة"; case .interval: "كل " + habitPeriodCount(rule.intervalDays ?? 1, .daily, digits) }
        if row.source != nil { return "تُقرأ من " + (row.sourceTitle ?? "غرفتها") }
        let amount = rule.measure == .once || rule.target == 1 && rule.unit == nil ? "مرة" : rule.unit != nil ? habitUnitCount(rule.target, rule.unit, digits) : arabicCount(rule.target, ["مرة واحدة", "مرتان", "مرات", "مرة"], digits)
        return amount + " " + every
    }
    private var orbit: some View {
        let rows = active.filter { !waitsForItsDate($0) && !$0.quitting }
        var centre = (title: "", caption: "عادات اليوم")
        if let r = selectedReading, let p = r.summary.current {
            centre.title = p.rule.measure == .once && p.target == 1 ? (p.met ? "تمّت" : "لم تتم") : digits.string(p.value)
            centre.caption = p.target > 1 ? "من " + digits.string(p.target) + (p.rule.unit.map { " " + $0 } ?? "") : (p.rule.band == .daily ? "اليوم" : "في فترتها")
        } else {
            let due = dailyRows.filter(dueToday)
            centre.title = due.isEmpty ? "راحة" : digits.string(due.filter { $0.summary.current?.met == true }.count) + " من " + digits.string(due.count)
        }
        return VStack(alignment: .leading, spacing: 10) {
            HabitOrbitView(readings: rows, digits: digits, theme: theme, nowPositions: AppBahwService(session: session).habitOrbitPositions(), selected: selected, select: choose, centre: centre)
                .accessibilityElement(children: .contain).accessibilityIdentifier("habits-orbit")
        }
    }
    /// A habit as the canvas draws it: its ring, its name with the room it is counted in, one line of state, and on the other side
    /// the streak capsule over seven small beads. A tap chooses the habit (its story opens below); the ring and «+» keep logging.
    private func habitRow(_ row:HabitReading)->some View {
        let p = row.summary.current, met = p?.met == true, on = selected == row.id
        let colour = habitRoomColour(row.source,dark:colorScheme == .dark)
        let share = Double(p?.value ?? 0)/Double(max(1,p?.target ?? 1))
        let risky = row.summary.atRisk && !met && !row.paused
        return HStack(spacing:12) {
            leading(row,share:share,met:met,colour:colour)
            Button { choose(row) } label: {
                HStack(spacing:10) {
                    VStack(alignment:.leading,spacing:3) {
                        HStack(spacing:8) {
                            Text(row.name).font(HabitType.section()).fixedSize(horizontal:false,vertical:true)
                            if let tag = row.sourceTitle { Text(tag).font(HabitType.fine()).foregroundStyle(colour).padding(.horizontal,8).padding(.vertical,1).background(colour.opacity(0.1),in:.rect(cornerRadius:8)) }
                        }
                        Text(rowLine(row)).font(HabitType.caption()).foregroundStyle(risky ? theme.risk : theme.secondaryInk).fixedSize(horizontal:false,vertical:true)
                        // Idea 6 (owner, 17 Nov 2026): a quiet milestone on the day a daily streak reaches 30, 100 or 365 — no sound, no pop-up.
                        if met, p?.rule.frequency == .daily, [30,100,365].contains(row.summary.streak) {
                            Text(habitPeriodCount(row.summary.streak,.daily,digits)+" — «أحبّ الأعمال إلى الله أدومها وإن قلّ»").font(HabitType.fine()).foregroundStyle(colour)
                                .accessibilityIdentifier("habit-milestone-"+row.id.uuidString)
                        }
                    }
                    Spacer(minLength:0)
                    VStack(alignment:.trailing,spacing:5) {
                        if row.summary.streak > 0 || row.summary.atRisk { HabitFlame(count:row.summary.streak,frequency:p?.rule.frequency ?? .daily,digits:digits,met:met,atRisk:risky,tint:colour) }
                        HabitRowDots(periods:row.summary.periods,colour:colour)
                    }
                }.frame(minHeight:46).contentShape(.rect)
            }.buttonStyle(.madarPlain).accessibilityIdentifier("habit-row-"+row.id.uuidString).accessibilityLabel(row.name+"، "+rowLine(row)).accessibilityAddTraits(on ? .isSelected : [])
            // A day forgotten is one long-press away (item 26), without opening the habit.
            .contextMenu { if row.source == nil, !row.archived, let p = row.summary.current, p.rule.measure != .health, p.rule.measure != .abstain, (row.summary.periods.first?.start).map({ $0 < today }) == true { Button("فعلتها في يوم سابق",systemImage:"calendar.badge.clock") { pastDay = row } } }
            trailing(row)
        }
        .padding(.horizontal,14).padding(.vertical,12).background(on ? theme.accentFill.opacity(0.16) : .clear)
        .animation(reduceMotion ? nil : .smooth(duration:0.35),value:on)
    }
    /// «٣ من ٥ كم»; a frozen habit says so, a habit that lost a period says what saves it, a quit habit counts its clean days.
    private func rowLine(_ row:HabitReading)->String {
        if row.paused { return row.statusTitle }
        if row.summary.atRisk && row.summary.current?.met != true { return row.statusTitle }
        var line = progress(row)
        if line.isEmpty { line = row.summary.current?.met == true ? "تمّت" : row.summary.current?.rule.band == .daily ? "لم تتمّها بعد" : "تنتظر في فترتها" }
        if row.isNow { line += line.isEmpty ? "وقتها الآن" : "، وقتها الآن" }
        return line
    }
    /// A once-habit's ring is its own checkbox: one circle per row, tapped to finish. Count habits keep the ring as progress and a «+».
    @ViewBuilder private func leading(_ row:HabitReading,share:Double,met:Bool,colour:Color)->some View {
        let ring = HabitRowRing(share:share,done:met,colour:colour,symbol:row.source == nil ? nil : row.symbol,glyph:row.source == nil ? row.nameGlyph : nil)
        if let p=row.summary.current, row.source == nil, !row.paused, p.target > 0, p.rule.measure == .once, !met {
            Button { complete(row, delta: 1) } label: { ring.contentShape(.circle) }
                .buttonStyle(.madarPlain).disabled(completionInFlight.contains(row.id))
                .accessibilityLabel(quickLogLabel(row.name,.once)).accessibilityIdentifier("habit-quick-"+row.id.uuidString)
        } else if !dynamicTypeSize.isAccessibilitySize { ring }
    }
    /// Count and duration habits log from a «+»; a once-habit logs from its ring.
    @ViewBuilder private func trailing(_ row:HabitReading)->some View {
        if row.source == nil, !row.paused, let p=row.summary.current, p.target > 0, p.rule.measure != .once, p.rule.measure != .abstain {
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
    private func progress(_ row:HabitReading)->String { guard let p=row.summary.current else{return "لا فترة بعد"}; if p.rule.measure == .abstain { return row.summary.streak > 0 ? habitPeriodCount(row.summary.streak,.daily,digits)+" بلا زلّة" : "بدأت من جديد اليوم" }; return p.target == 0 ? "سجلك محفوظ" : p.rule.measure == .once && p.target == 1 ? (p.value >= 1 ? "تمّت" : "") : habitProgressText(p.value,p.target,p.rule.unit,digits) }
    /// Owner, 5 Nov 2026 («اضغط العاده يعلق التطبيق»): every table of every habit is read on a background context, and only the
    /// latest request lands, so a tap, a Health refresh and a prayer write in a row never stack reads on the main thread.
    private func reload() {
        reloadTask?.cancel()
        let container = session.container, now = session.prayerNow(), health = liveHealth
        reloadTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try HabitRepository(context: ModelContext(container)).readings(at: now, includeArchived: true, liveHealth: health, includeQuitting: true) }
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
    let frequency: HabitFrequency
    let theme: RoomTheme
    let showsRing: Bool

    var body: some View {
        // Canvas «Habits» (17 Nov): a ring over the period's name and «x من y», centred on a paper card.
        VStack(spacing: 6) {
            if showsRing { HabitMiniRing(share: share, theme: theme).frame(width: 34, height: 34) }
            Text(title).font(HabitType.section()).foregroundStyle(theme.ink).lineLimit(1)
            Text(count).font(.custom("thmanyahseriftext-Regular", size: 12, relativeTo: .caption2))
                .foregroundStyle(theme.secondaryInk).lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 6).padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 58)
        .background(theme.surface, in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(theme.ink.opacity(0.08), lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(frequency.arabic + "، " + count)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        ZStack {
            Circle().fill(done ? theme.accentFill.opacity(0.16) : .clear)
            Circle().stroke(theme.line,lineWidth:lineWidth)
            Circle().trim(from:0,to:done ? 1 : min(1,max(0,share))).stroke(theme.accentFill,style:.init(lineWidth:lineWidth,lineCap:.round)).rotationEffect(.degrees(-90))
            if let symbol { MadarGlyph(symbol,size:14).foregroundStyle(theme.accent) }
            else if done && lineWidth > 2 { PrayerStar().fill(theme.accent).frame(width:11,height:11) }
            else if done { Circle().fill(theme.accentFill).padding(lineWidth*1.5) }
        }.padding(lineWidth/2)
            .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: share)
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: done)
            .orbitCompletionSweep(done: done, lineWidth: lineWidth)
            .accessibilityHidden(true)
    }
}
/// The streak as a flame and its count, no words (owner, 24 Oct: «شعلة وعندها الأيام وبس»).
/// Owner, 17 Nov 2026 (shape «ب»): the streak is one light capsule — flame, number, unit.
/// Done today: the habit's room colour with a lit flame. Waiting: grey with an empty flame.
/// Missed once (`atRisk`): an unlit flame on a red tint with an hourglass in its corner — one more miss and it goes.
struct HabitFlame:View {
    let count:Int; let frequency:HabitFrequency; let digits:MadarNumberFormatter
    var met:Bool = false
    var atRisk:Bool = false
    var tint:Color? = nil
    @Environment(\.roomTheme) private var theme
    private var ink:Color { atRisk ? theme.risk : met ? (tint ?? theme.accent) : theme.secondaryInk }
    private var fill:Color { atRisk ? theme.risk.opacity(0.12) : met ? (tint ?? theme.accent).opacity(0.14) : theme.ink.opacity(0.06) }
    var body:some View {
        HStack(spacing:3) {
            Image(systemName: met && !atRisk ? "flame.fill" : "flame").font(.system(size:11,weight:.semibold))
            Text(habitPeriodCount(count,frequency,digits)).font(.custom("thmanyahseriftext-Bold",size:12,relativeTo:.caption)).monospacedDigit()
        }
        .foregroundStyle(ink).padding(.horizontal,8).frame(minHeight:22).background(fill,in:.capsule)
        .overlay(alignment:.topLeading) {
            if atRisk {
                Image(systemName:"hourglass").font(.system(size:8,weight:.bold)).foregroundStyle(theme.surface)
                    .frame(width:15,height:15).background(theme.risk,in:.circle).overlay(Circle().stroke(theme.surface,lineWidth:1.5))
                    .offset(x:-6,y:-6).accessibilityHidden(true)
            }
        }
        .fixedSize()
        .accessibilityElement().accessibilityLabel("سلسلة "+habitPeriodCount(count,frequency,digits)+(atRisk ? "، فاتتك مرة وستنقطع إن فاتتك الثانية" : ""))
    }
}
/// The colour a habit takes from the room it is counted in (W2 board, owner 17 Nov): Mihbara plum, Quran green,
/// diary sepia, money lapis; a habit of the user's own keeps the lobby's gold.
func habitRoomColour(_ source:String?,dark:Bool)->Color {
    let room:String? = switch source { case "jamaah": "salah"; case "review", "wird": "quran"; case "diaryLine": "notes"; case "reading","hadith": "mihbara"; case "money": "mal"; default: nil }
    return RoomTheme(room:room ?? "bahw",dark:dark).accentFill
}
struct HabitMiniRing:View {
    let share:Double; let theme:RoomTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View { ZStack { Circle().stroke(theme.line,lineWidth:3.5); Circle().trim(from:0,to:min(1,max(0,share))).stroke(theme.accentFill,style:.init(lineWidth:3.5,lineCap:.round)).rotationEffect(.degrees(-90)) }
        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: share)
        .orbitCompletionSweep(done: share >= 1, lineWidth: 3.5).accessibilityHidden(true) }
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
func habitUnitName(_ unit:String)->String { ["minutes":"دقيقة","exerciseMinutes":"دقيقة حركة","sleepMinutes":"دقيقة نوم","workouts":"تمرين","steps":"خطوة","pages":"صفحة"][unit] ?? unit }
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
    // Owner, 17 Nov 2026 (idea 12): a daily habit earns one rest day for every 30 met days in a row.
    return "تنكسر السلسلة بفوت "+forms[min(max(periods,1),3)-1]+". "+frozen+" المجمدة مستثناة."+(frequency == .daily ? " وكل ثلاثين يومًا متتالية تكسبك يوم راحة يحفظ سلسلتك من فوتة واحدة." : "")
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
/// Owner, 17 Nov 2026: the habits room is set in «ثمانية النسخي» — Serif Text for reading, Serif Display Black for titles —
/// at the same sizes as `MadarTypography`, so Dynamic Type scales it the same way.
enum HabitType {
    private static func size(_ key:String)->CGFloat { CGFloat(MadarMetric.values[key] ?? 16) }
    static func title()->Font { .custom("thmanyahserifdisplay-Black",size:size("typeScale.roomTitle.size"),relativeTo:.largeTitle) }
    static func cardTitle()->Font { .custom("thmanyahserifdisplay-Black",size:size("typeScale.cardTitle.size"),relativeTo:.title2) }
    static func body()->Font { .custom("thmanyahseriftext-Regular",size:size("typeScale.body.size"),relativeTo:.body) }
    static func caption()->Font { .custom("thmanyahseriftext-Regular",size:size("typeScale.caption.size"),relativeTo:.subheadline) }
    static func section()->Font { .custom("thmanyahseriftext-Bold",size:size("typeScale.sectionHead.size"),relativeTo:.headline) }
    static func fine()->Font { .custom("thmanyahseriftext-Bold",size:size("typeScale.fine.size"),relativeTo:.caption2) }
}
