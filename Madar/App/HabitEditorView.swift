import SwiftUI
import MadarCore
import MadarCommands
import MadarDesign

private struct HabitEditorSnapshot: Equatable {
    let name: String
    let source: String
    let rule: HabitRule
    let monthDays: String
    let minimumOn: Bool
    let windowOn: Bool
    let homeOnly: Bool
    let reminder: String
}

struct HabitEditorView:View {
    /// A habit linked to a room starts with that room's own measure (the same values the source picker sets).
    static let linkedDefaults: [String: (name: String, measure: HabitMeasure, unit: String, target: Int)] = [
        "jamaah": ("الجماعة", .count, "صلاة", 5), "review": ("المراجعة", .count, "وجه", 1), "reading": ("القراءة", .duration, "minutes", 15),
        "diaryLine": ("سطر اليوم", .count, "سطر", 1), "wird": ("ورد الحفظ", .count, "ورد", 1), "walking": ("المشي", .health, "steps", 6000)]
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var session:AppSession
    let reading:HabitReading?
    let id:UUID
    /// A new habit opened from a room starts on that room's source (the Mihbara opens «القراءة»).
    var initialSource="custom"
    @Environment(\.dismiss) private var dismiss
    @State private var name=""
    @State private var source="custom"
    @State private var rule=HabitRule(effectiveFrom:GregorianDay.containing(.now,in:ActivePlace.riyadh.timeZone))
    @State private var monthDays=""
    /// The target the reader typed for each unit, so switching minutes ↔ pages and back keeps it.
    @State private var unitTargets:[String:Int]=[:]
    /// The matching minimum per unit: a 5-minute floor is not 5 pages, so each unit keeps its own and none is converted.
    @State private var unitMinimums:[String:Int]=[:]
    /// The reader's pace, read once when a «القراءة» goal is edited, so the editor can say what the goal costs in minutes or pages.
    @State private var paceGoal:MihbaraReadingGoal?
    private var readingHint:String? {
        let unit=rule.unit ?? "minutes",digits=MadarNumberFormatter(style: session.string("core.numerals") == "western" ? .western : .hindi)
        if unit == "chapters",paceGoal != nil,paceGoal?.pagesPerChapter == nil { return paceGoal?.bookHasNoPageCount == true ? "الفصول تحتاج أن يعرف مدار عدد صفحات الكتاب؛ وهذا الكتاب بلا عدد صفحات." : "الفصول تُحسب للكتب التي لها فهرس: الورقي بعد إضافة فهرسه، وملفات PDF التي فيها فهرس." }
        guard let estimate=paceGoal?.estimate(left:rule.target,unit:unit) else { return "كلما قرأت أكثر عرفتُ كم يأخذ هدفك من وقتك." }
        return "نحو "+habitUnitCount(estimate.amount,estimate.unit,digits,genitive:true)+" في اليوم بحسب وتيرتك الأخيرة."
    }
    @State private var minimumOn=false
    @State private var windowOn=false
    @State private var homeOnly=false
    @State private var reminder="dot"
    @State private var busy=false
    @State private var issue:String?
    @State private var initialSnapshot: HabitEditorSnapshot?
    private var theme:RoomTheme{.init(room:"bahw",dark:colorScheme == .dark)}
    private var digits:MadarNumberFormatter{.init(style:session.string("core.numerals") == "western" ? .western : .hindi)}
    var body:some View {
        VStack(spacing:0) {
            HStack {
                Button("إلغاء"){dismiss()}.frame(minHeight:44).madarWaitsForSave().accessibilityIdentifier("habit-cancel")
#if DEBUG
                if ProcessInfo.processInfo.environment["MADAR_UI_BAHW_ROOT_ROUTE_HARNESS"] == "1" {
                    Button("اختبر رابط البهو") { session.open(URL(string: "madar://bahw")!) }
                        .accessibilityIdentifier("ui-test-open-bahw-root")
                }
#endif
                Spacer();Text(reading == nil ? "عادة جديدة" : "تعديل العادة").font(MadarTypography.cardTitle());Spacer();Button("احفظ"){save()}.font(MadarTypography.section()).frame(minHeight:44).disabled(busy || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("habit-save")
            }.padding(.horizontal,20).padding(.top,10)
            // AU-35: the error sits under «احفظ», not below five sections, and editing clears it.
            if let issue { Text(issue).font(MadarTypography.caption()).foregroundStyle(theme.accent).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,20).padding(.top,6).accessibilityIdentifier("habit-editor-error") }
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    section("العادة") {
                        TextField("اسم العادة",text:$name,prompt:Text("ورد قبل النوم")).font(MadarTypography.body()).frame(minHeight:44).accessibilityIdentifier("habit-name")
                        if reading == nil { Picker("تسجيلها",selection:$source) { Text("أسجّلها هنا").tag("custom");Text("الجماعة من الصلاة").tag("jamaah");Text("ورد الحفظ من القرآن").tag("wird");Text("المراجعة من القرآن").tag("review");Text("القراءة من المحبرة").tag("reading");Text("سطر اليوم من المذكرات").tag("diaryLine");if HabitHealthStore.available {Text("المشي من الصحة").tag("walking")} }.pickerStyle(.menu).frame(minHeight:44).accessibilityIdentifier("habit-source") }
                        else if let title=reading?.sourceTitle { Text("تُقرأ من "+title).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                    }
                    section("التكرار") {
                        Picker("تكرار العادة",selection:Binding(get:{rule.frequency},set:{rule.frequency=$0;rule.intervalDays = $0 == .interval ? (rule.intervalDays ?? 3) : nil})) { Text("يومية").tag(HabitFrequency.daily);Text("كل عدد من الأيام").tag(HabitFrequency.interval);Text("أسبوعية").tag(HabitFrequency.weekly);Text("شهرية").tag(HabitFrequency.monthly);Text("سنوية").tag(HabitFrequency.yearly) }.pickerStyle(.menu).frame(minHeight:44).accessibilityIdentifier("habit-frequency")
                        if reading != nil { Text("تغيير التكرار يبدأ سلسلة جديدة؛ السجل يبقى. بقية التغييرات لا تمسّ الفترات الماضية.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                        // FB-39 (owner, 6 Nov): «كل ٣ أيام»، «كل ٤٠ يومًا» — any day inside each block counts.
                        if rule.frequency == .interval {
                            Stepper(value:Binding(get:{rule.intervalDays ?? 3},set:{rule.intervalDays=$0}),in:2...3660) {
                                Text("كل "+WidgetCopy.agree(rule.intervalDays ?? 3,digits,one:"يوم",two:"يومين",few:"أيام",many:"يومًا"))
                            }.frame(minHeight:44).accessibilityIdentifier("habit-interval")
                            Text("أي يوم داخل كل مدة يكفي؛ تبدأ المدة الأولى من تاريخ البداية.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        }
                        // FB-39: a new habit may begin on a free date. A past date opens its days for logging; a later one waits.
                        if reading == nil {
                            DatePicker("تبدأ من",selection:Binding(get:{rule.effectiveFrom.date(in:session.activePlace.timeZone).addingTimeInterval(43200)},set:{rule.effectiveFrom=GregorianDay.containing($0,in:session.activePlace.timeZone)}),in:firstDayRange,displayedComponents:.date)
                                .environment(\.timeZone,session.activePlace.timeZone).frame(minHeight:44).accessibilityIdentifier("habit-first-day")
                            MadarDateLabel(session.dateLabels(rule.effectiveFrom),primaryFont:MadarTypography.caption(),secondaryFont:MadarTypography.fine())
                            if rule.effectiveFrom < AppBahwService(session:session).today { Text("تستطيع أن تسجّل الأيام الماضية من صفحة العادة بعد حفظها.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                        }
                        if rule.frequency == .weekly { Text("أيام محددة، أو اتركها لِأي يوم").font(MadarTypography.caption());dayButtons($rule.weekdays) }
                        if rule.frequency == .monthly || rule.frequency == .yearly {
                            Picker("التقويم",selection:$rule.hijri){Text("هجري").tag(true);Text("ميلادي").tag(false)}.pickerStyle(.segmented)
                            if rule.frequency == .monthly { TextField("أيام الشهر، مثل ١٣، ١٤، ١٥",text:$monthDays).keyboardType(.numbersAndPunctuation).frame(minHeight:44).accessibilityIdentifier("habit-month-days") }
                            else { Stepper("الشهر: "+digits.string(rule.yearMonth),value:$rule.yearMonth,in:1...12).frame(minHeight:44);Stepper("اليوم: "+digits.string(rule.yearDay),value:$rule.yearDay,in:1...(rule.hijri ? 30 : 31)).frame(minHeight:44) }
                            Text("إذا نقص اليوم عن طول الشهر يقع في آخر يوم، ولا يسقط الاستحقاق.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        }
                    }
                    section("قدر يسهل أن تدوم عليه") {
                        if source == "custom" {
                            Picker("الحساب",selection:$rule.measure){Text("مرة").tag(HabitMeasure.once);Text("بالعدد").tag(HabitMeasure.count);Text("بالوقت").tag(HabitMeasure.duration)}.pickerStyle(.menu).frame(minHeight:44).accessibilityIdentifier("habit-measure")
                            if rule.measure == .count { TextField("الوحدة، مثل كوب أو صفحة",text:Binding(get:{rule.unit ?? ""},set:{rule.unit=$0})).frame(minHeight:44).accessibilityIdentifier("habit-unit") }
                        }
                        if source == "reading" {
                            Picker("تُقاس",selection:Binding(get:{rule.unit ?? "minutes"},set:{unit in
                                unitTargets[rule.unit ?? "minutes"]=rule.target;unitMinimums[rule.unit ?? "minutes"]=rule.minimum
                                rule.measure = unit == "minutes" ? .duration : .count;rule.unit=unit;rule.target=unitTargets[unit] ?? (unit == "pages" ? 10 : unit == "chapters" ? 1 : 15);rule.minimum=unitMinimums[unit].map{min($0,rule.target)}
                            })) {Text("بالدقائق").tag("minutes");Text("بالصفحات").tag("pages");Text("بالفصول").tag("chapters")}.pickerStyle(.segmented).accessibilityIdentifier("habit-reading-unit")
                            if let hint=readingHint { Text(hint).font(MadarTypography.caption()).foregroundStyle(theme.accent).accessibilityIdentifier("habit-reading-hint") }
                            Text("تُحسب من جلسات القراءة في المحبرة: الوقت وأنت تقرأ فعلًا، والصفحات الجديدة فقط. الجلسة الأقصر من دقيقة لا تُحسب.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        }
                        if source == "walking" {
                            Picker("وحدة الصحة",selection:Binding(get:{rule.unit ?? "steps"},set:{unitTargets[rule.unit ?? "steps"]=rule.target;rule.unit=$0;rule.target=unitTargets[$0] ?? ($0 == "steps" ? 6000 : 30)})) {Text("خطوات").tag("steps");Text("دقائق حركة").tag("exerciseMinutes")}.pickerStyle(.menu)
                            Text("دقائق الحركة تشمل كل تمرين، وليست المشي وحده. السماح بالصحة باختيارك، ولا يكتب مدار فيها.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        }
                        if rule.measure != .once {
                            // FB-39: a step of one up to 100000 meant 2000 taps to move a walking goal from 6000 to 8000 steps; type it, or step by a sensible amount.
                            HStack(spacing:10) {
                                Stepper("الهدف: "+habitUnitCount(rule.target,rule.unit,digits),value:$rule.target,in:1...targetLimit,step:targetStep).frame(minHeight:44).accessibilityIdentifier("habit-target")
                                if source != "jamaah" {
                                    TextField("الهدف",value:Binding(get:{rule.target},set:{rule.target=min(targetLimit,max(1,$0))}),format:.number)
                                        .keyboardType(.numberPad).multilineTextAlignment(.center).frame(width:76,height:40)
                                        .background(theme.surface,in:.rect(cornerRadius:10)).accessibilityIdentifier("habit-target-field")
                                }
                            }
                            if !rule.weekdays.isEmpty && rule.frequency == .weekly || !monthDays.isEmpty && rule.frequency == .monthly { Text("الأيام المحددة تحدد هدف الفترة؛ ما زاد مكافأة.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                            Toggle("أقلّ القليل يحفظ السلسلة",isOn:$minimumOn).frame(minHeight:44).accessibilityIdentifier("habit-minimum-toggle")
                            if minimumOn { Stepper("أقلّ القليل: "+habitUnitCount(min(rule.target,rule.minimum ?? 1),rule.unit,digits),value:Binding(get:{min(rule.target,rule.minimum ?? 1)},set:{rule.minimum=$0}),in:1...max(1,rule.target)).frame(minHeight:44) }
                        }
                    }
                    section("وقت اختياري") {
                        Toggle("له وقت في اليوم",isOn:$windowOn).frame(minHeight:44)
                        if windowOn {
                            Picker("البداية من",selection:Binding(get:{rule.windowAnchor?.rawValue ?? "clock"},set:{rule.windowAnchor=Prayer(rawValue:$0)})) { Text("الساعة المحلية").tag("clock");ForEach(Prayer.allCases,id:\.self){p in Text(prayerName(p)).tag(p.rawValue)} }.pickerStyle(.menu)
                            if rule.windowAnchor == nil {
                                DatePicker("من",selection:timeBinding(start:true),displayedComponents:.hourAndMinute)
                                DatePicker("إلى",selection:timeBinding(start:false),displayedComponents:.hourAndMinute)
                            } else {
                                Stepper("البداية: "+digits.string(rule.windowStart ?? 0)+" دقيقة من الأذان",value:Binding(get:{rule.windowStart ?? 0},set:{rule.windowStart=$0}),in:0...720,step:15)
                                Stepper("النهاية: "+digits.string(rule.windowEnd ?? 90)+" دقيقة من الأذان",value:Binding(get:{rule.windowEnd ?? 90},set:{rule.windowEnd=$0}),in:15...1440,step:15)
                            }
                            Text("الوقت يتبع مدينتك النشطة؛ ونافذة الليل تتبع يوم مدار الذي بدأت فيه.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        }
                        Picker("التذكير",selection:$reminder){
                            Text("نقطة في البهو").tag("dot")
                            if source == "custom" || (reading != nil && reminder == "push") { Text("إشعار لطيف").tag("push") }
                            Text("بلا تذكير").tag("none")
                        }.pickerStyle(.menu).accessibilityIdentifier("habit-reminder")
                            .onChange(of:reminder){ _,new in if new == "push" && source == "custom" { windowOn = true } }
                        if reminder == "push" {
                            Text(source == "custom" ? "يصلك الإشعار في بداية وقت العادة، فوقتها مطلوب." : "الإشعار غير متاح للعادة المرتبطة؛ يمكنك اختيار نقطة البهو.")
                                .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        }
                        Toggle("للبيت فقط، تتوقف في السفر",isOn:$homeOnly).frame(minHeight:44)
                        Text("أيام إجازة").font(MadarTypography.caption());dayButtons($rule.restWeekdays)
                    }
                    MadarDateLabel(session.dateLabels(AppBahwService(session:session).today)).foregroundStyle(theme.secondaryInk)
                }.padding(20)
            }
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.accent).environment(\.timeZone,session.activePlace.timeZone)
        .task(id:source) {
            guard source == "reading" else { return }
            let service=AppMihbaraService(app:session)
            if let loaded=try? service.load() { paceGoal=try? service.readingGoal(today:loaded.day,book:MihbaraStand.pick(from:loaded.books)) }
        }
        .onAppear {
            let initialName = reading?.name ?? HabitEditorView.linkedDefaults[self.initialSource]?.name ?? ""
            let initialSource = reading?.source ?? self.initialSource
            var initialRule = reading?.summary.current?.rule ?? HabitRule(effectiveFrom:AppBahwService(session:session).today)
            if reading == nil, let linked = HabitEditorView.linkedDefaults[initialSource] { initialRule.measure = linked.measure;initialRule.unit=linked.unit;initialRule.target=linked.target }
            initialRule.effectiveFrom=AppBahwService(session:session).today
            let initialMonthDays = initialRule.monthDays.map{digits.string($0)}.joined(separator:"، ")
            let initialMinimumOn = initialRule.minimum != nil
            let initialWindowOn = initialRule.windowStart != nil
            let initialHomeOnly = reading?.homeOnly ?? false
            let defaultReminder = session.string("bahw.reminder")
            let initialReminder = reading?.reminder ?? (["dot", "push", "none"].contains(defaultReminder) ? defaultReminder : "dot")
            name=initialName;source=initialSource;rule=initialRule;monthDays=initialMonthDays;minimumOn=initialMinimumOn;windowOn=initialWindowOn;homeOnly=initialHomeOnly;reminder=initialReminder
            initialSnapshot = .init(name:initialName,source:initialSource,rule:initialRule,monthDays:initialMonthDays,minimumOn:initialMinimumOn,windowOn:initialWindowOn,homeOnly:initialHomeOnly,reminder:initialReminder)
        }
        .onChange(of:name){issue=nil}.onChange(of:monthDays){issue=nil}.onChange(of:windowOn){issue=nil}
        .onChange(of:source){old,value in
            if reading == nil && value != "custom" && reminder == "push" { reminder = "dot" }
            if value == "custom",reading == nil {rule.measure = .once;rule.unit=nil;rule.target=1}
            let defaults=["jamaah":"الجماعة","review":"المراجعة","reading":"القراءة","diaryLine":"سطر اليوم","walking":"المشي","wird":"ورد الحفظ"]
            if let previous=defaults[old],name==previous {name=defaults[value] ?? ""}
            if value != "custom" && reading == nil { rule.measure = value == "walking" ? .health : value == "reading" ? .duration : .count;rule.unit=["jamaah":"صلاة","review":"وجه","reading":"minutes","diaryLine":"سطر","walking":"steps","wird":"ورد"][value];rule.target=value == "walking" ? 6000 : value == "jamaah" ? 5 : value == "reading" ? 15 : 1; if name.isEmpty {name=["jamaah":"الجماعة","review":"المراجعة","reading":"القراءة","diaryLine":"سطر اليوم","walking":"المشي","wird":"ورد الحفظ"][value] ?? ""} }
        }
        .onChange(of:rule.measure){old,value in measureChanged(from:old,to:value)}
        .madarSheetLock(saving: busy, draft: hasUnsavedChanges)
    }
    /// Switching back from minutes to a count drops the «minutes» unit, so a count habit never reads as time.
    private func measureChanged(from old:HabitMeasure,to value:HabitMeasure) {
        if source == "reading" { return } // the minutes/pages picker sets measure, unit and target together
        if value == .duration {rule.unit="minutes";rule.target=15}
        else if value == .once {rule.target=1;rule.minimum=nil;minimumOn=false}
        else if value == .count, old == .duration {rule.unit=nil}
    }
    private var hasUnsavedChanges: Bool {
        guard let initialSnapshot else { return false }
        return initialSnapshot != .init(name:name,source:source,rule:rule,monthDays:monthDays,minimumOn:minimumOn,windowOn:windowOn,homeOnly:homeOnly,reminder:reminder)
    }
    private func dayButtons(_ selection:Binding<[Int]>)->some View { HStack(spacing:3) { ForEach(Array(["ح","ن","ث","ر","خ","ج","س"].enumerated()),id:\.offset){i,label in Button {let day=i+1;if selection.wrappedValue.contains(day){selection.wrappedValue.removeAll{$0==day}}else{selection.wrappedValue.append(day)}}label:{Text(label).font(MadarTypography.caption()).frame(maxWidth:.infinity,minHeight:44).background(selection.wrappedValue.contains(i+1) ? theme.accentFill : theme.background,in:.capsule).foregroundStyle(selection.wrappedValue.contains(i+1) ? theme.onAccent : theme.ink)}.buttonStyle(.madarPlain).accessibilityLabel(["الأحد","الاثنين","الثلاثاء","الأربعاء","الخميس","الجمعة","السبت"][i]).accessibilityAddTraits(selection.wrappedValue.contains(i+1) ? .isSelected : []) } } }
    private func section<Content:View>(_ title:String,@ViewBuilder content:()->Content)->some View { VStack(alignment:.leading,spacing:12){Text(title).font(MadarTypography.section());content()}.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(theme.surface,in:.rect(cornerRadius:22)) }
    private func prayerName(_ p:Prayer)->String{switch p{case .fajr:"الفجر";case .dhuhr:"الظهر";case .asr:"العصر";case .maghrib:"المغرب";case .isha:"العشاء"}}
    private func timeBinding(start:Bool)->Binding<Date>{
        Binding(get:{
            var calendar=Calendar(identifier:.gregorian);calendar.timeZone=session.activePlace.timeZone
            let m=(start ? rule.windowStart : rule.windowEnd) ?? (start ? 1020 : 1200)
            var parts=calendar.dateComponents([.year,.month,.day],from:session.prayerNow());parts.hour=m/60;parts.minute=m%60
            return calendar.date(from:parts) ?? session.prayerNow()
        },set:{date in
            var calendar=Calendar(identifier:.gregorian);calendar.timeZone=session.activePlace.timeZone
            let c=calendar.dateComponents([.hour,.minute],from:date)
            if start{rule.windowStart=(c.hour ?? 0)*60+(c.minute ?? 0)}else{rule.windowEnd=(c.hour ?? 0)*60+(c.minute ?? 0)}
        })
    }
    private var firstDayRange:ClosedRange<Date> {
        let today=AppBahwService(session:session).today,zone=session.activePlace.timeZone
        return today.adding(days:-3660).date(in:zone)...today.adding(days:366).date(in:zone).addingTimeInterval(86399)
    }
    private var targetLimit:Int { source == "jamaah" ? 5 : 100000 }
    private var targetStep:Int { switch rule.unit { case "steps": 500; case "minutes","exerciseMinutes": 5; default: 1 } }
    private func save(){
        busy=true;issue=nil
        do{
            var saved=rule;if reading != nil { saved.effectiveFrom=AppBahwService(session:session).today }
            if saved.frequency != .interval { saved.intervalDays=nil }
            let english=monthDays.map { $0.wholeNumberValue.map(String.init) ?? String($0) }.joined()
            let parts=english.split(whereSeparator:{!$0.isNumber});let parsed=parts.compactMap{Int($0)}
            // Days of the month count only for a monthly habit; a hidden field never blocks another rhythm.
            if saved.frequency != .monthly { saved.monthDays=[] }
            else { guard parsed.count==parts.count,parsed.allSatisfy({(1...(saved.hijri ? 30 : 31)).contains($0)}) else{issue=saved.hijri ? "أيام الشهر الهجري من ١ إلى ٣٠، تفصلها فاصلة." : "أيام الشهر من ١ إلى ٣١، تفصلها فاصلة.";busy=false;return}
            saved.monthDays=Array(Set(parsed)).sorted() }
            saved.minimum=minimumOn ? min(saved.target,saved.minimum ?? 1) : nil
            if !windowOn{saved.windowStart=nil;saved.windowEnd=nil;saved.windowAnchor=nil}else{saved.windowStart=saved.windowStart ?? 1020;saved.windowEnd=saved.windowEnd ?? 1200}
            // Name the one thing to fix instead of one sentence for every refusal.
            if saved.target <= 0 {issue="اجعل الهدف أكبر من صفر.";busy=false;return}
            if let low=saved.minimum, low <= 0 || low > saved.target {issue="الحد الأدنى بين ١ والهدف.";busy=false;return}
            if let a=saved.windowStart, let b=saved.windowEnd, a == b {issue="وقت البداية والنهاية يجب أن يختلفا.";busy=false;return}
            // FB-39: a «إشعار لطيف» without a time never fires (RoomReminders.habit needs the window), so it is not saved silently.
            if reminder == "push" && source == "custom" && !windowOn {issue="الإشعار يحتاج وقتًا للعادة: فعّل «له وقت في اليوم».";busy=false;return}
            try saved.validate()
            let json=try JSONDecoder().decode(MadarCore.JSONValue.self,from:JSONEncoder().encode(saved))
            var p:[String:MadarCore.JSONValue]=["id":.string(id.uuidString),"name":.string(name),"rule":json,"homeOnly":.bool(homeOnly),"reminder":.string(reminder)]
            if source != "custom"{p["source"] = .string(source)}
            Task {do{if source == "walking" {try await HabitHealthStore.authorize(unit:saved.unit ?? "steps")};try await session.executeDiaryCommand("habit.save",payload:p);dismiss()}catch{issue="لم تُحفظ العادة: "+madarUserDetail(error)};busy=false}
        }catch{issue="راجع العادة: "+madarUserDetail(error);busy=false}
    }
}
