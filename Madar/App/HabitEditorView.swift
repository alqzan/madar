import SwiftUI
import MadarCore
import MadarCommands
import MadarDesign

struct HabitEditorView:View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var session:AppSession
    let reading:HabitReading?
    let id:UUID
    @Environment(\.dismiss) private var dismiss
    @State private var name=""
    @State private var source="custom"
    @State private var rule=HabitRule(effectiveFrom:GregorianDay.containing(.now,in:ActivePlace.riyadh.timeZone))
    @State private var monthDays=""
    @State private var minimumOn=false
    @State private var windowOn=false
    @State private var homeOnly=false
    @State private var reminder="dot"
    @State private var busy=false
    @State private var issue:String?
    private var theme:RoomTheme{.init(room:"bahw",dark:colorScheme == .dark)}
    private var digits:MadarNumberFormatter{.init(style:session.string("core.numerals") == "western" ? .western : .hindi)}
    var body:some View {
        VStack(spacing:0) {
            HStack { Button("إلغاء"){dismiss()}.frame(minHeight:44);Spacer();Text(reading == nil ? "عادة جديدة" : "تعديل العادة").font(MadarTypography.cardTitle());Spacer();Button("احفظ"){save()}.font(MadarTypography.section()).frame(minHeight:44).disabled(busy || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("habit-save") }.padding(.horizontal,20).padding(.top,10)
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    section("العادة") {
                        TextField("اسم العادة",text:$name,prompt:Text("ورد قبل النوم")).font(MadarTypography.body()).frame(minHeight:44).accessibilityIdentifier("habit-name")
                        if reading == nil { Picker("تسجيلها",selection:$source) { Text("أسجّلها هنا").tag("custom");Text("الجماعة من الصلاة").tag("jamaah");Text("المراجعة من القرآن").tag("review");Text("سطر اليوم من المذكرات").tag("diaryLine");if HabitHealthStore.available {Text("المشي من الصحة").tag("walking")} }.pickerStyle(.menu).frame(minHeight:44).accessibilityIdentifier("habit-source") }
                        else if let title=reading?.sourceTitle { Text("تُقرأ من "+title).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                    }
                    section("التكرار") {
                        Picker("تكرار العادة",selection:$rule.frequency) { Text("يومية").tag(HabitFrequency.daily);Text("أسبوعية").tag(HabitFrequency.weekly);Text("شهرية").tag(HabitFrequency.monthly);Text("سنوية").tag(HabitFrequency.yearly) }.pickerStyle(.menu).frame(minHeight:44).accessibilityIdentifier("habit-frequency")
                        if reading != nil { Text("تغيير التكرار يبدأ سلسلة جديدة؛ السجل يبقى. بقية التغييرات لا تمسّ الفترات الماضية.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
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
                        if source == "walking" {
                            Picker("وحدة الصحة",selection:Binding(get:{rule.unit ?? "steps"},set:{rule.unit=$0;rule.target=$0 == "steps" ? 6000 : 30})) {Text("خطوات").tag("steps");Text("دقائق حركة").tag("exerciseMinutes")}.pickerStyle(.menu)
                            Text("دقائق الحركة تشمل كل تمرين، وليست المشي وحده. السماح بالصحة باختيارك، ولا يكتب مدار فيها.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        }
                        if rule.measure != .once {
                            Stepper("الهدف: "+habitUnitCount(rule.target,rule.unit,digits),value:$rule.target,in:1...(source == "jamaah" ? 5 : 100000)).frame(minHeight:44).accessibilityIdentifier("habit-target")
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
                        if reminder == "push" {
                            Text(source == "custom" ? "حدّد وقت العادة واسمح بالإشعارات ليصل التذكير." : "الإشعار غير متاح للعادة المرتبطة؛ يمكنك اختيار نقطة البهو.")
                                .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        }
                        Toggle("للبيت فقط، تتوقف في السفر",isOn:$homeOnly).frame(minHeight:44)
                        Text("أيام إجازة").font(MadarTypography.caption());dayButtons($rule.restWeekdays)
                    }
                    if let issue { Text(issue).font(MadarTypography.caption()).foregroundStyle(theme.accent).accessibilityIdentifier("habit-editor-error") }
                    MadarDateLabel(session.dateLabels(AppBahwService(session:session).today)).foregroundStyle(theme.secondaryInk)
                }.padding(20)
            }
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.accent).environment(\.timeZone,session.activePlace.timeZone)
        .onAppear {
            name=reading?.name ?? "";source=reading?.source ?? "custom";rule=reading?.summary.current?.rule ?? HabitRule(effectiveFrom:AppBahwService(session:session).today)
            rule.effectiveFrom=AppBahwService(session:session).today;monthDays=rule.monthDays.map{digits.string($0)}.joined(separator:"، ");minimumOn=rule.minimum != nil;windowOn=rule.windowStart != nil;homeOnly=reading?.homeOnly ?? false
            let defaultReminder = session.string("bahw.reminder")
            reminder=reading?.reminder ?? (["dot", "push", "none"].contains(defaultReminder) ? defaultReminder : "dot")
        }
        .onChange(of:source){old,value in
            if reading == nil && value != "custom" && reminder == "push" { reminder = "dot" }
            if value == "custom",reading == nil {rule.measure = .once;rule.unit=nil;rule.target=1}
            let defaults=["jamaah":"الجماعة","review":"المراجعة","diaryLine":"سطر اليوم","walking":"المشي"]
            if let previous=defaults[old],name==previous {name=defaults[value] ?? ""}
            if value != "custom" && reading == nil { rule.measure = value == "walking" ? .health : .count;rule.unit=["jamaah":"صلاة","review":"وجه","diaryLine":"سطر","walking":"steps"][value];rule.target=value == "walking" ? 6000 : value == "jamaah" ? 5 : 1; if name.isEmpty {name=["jamaah":"الجماعة","review":"المراجعة","diaryLine":"سطر اليوم","walking":"المشي"][value] ?? ""} }
        }
        .onChange(of:rule.measure){_,value in if value == .duration {rule.unit="minutes";rule.target=15}else if value == .once {rule.target=1;rule.minimum=nil;minimumOn=false} }
    }
    private func dayButtons(_ selection:Binding<[Int]>)->some View { HStack(spacing:3) { ForEach(Array(["ح","ن","ث","ر","خ","ج","س"].enumerated()),id:\.offset){i,label in Button {let day=i+1;if selection.wrappedValue.contains(day){selection.wrappedValue.removeAll{$0==day}}else{selection.wrappedValue.append(day)}}label:{Text(label).font(MadarTypography.caption()).frame(maxWidth:.infinity,minHeight:44).background(selection.wrappedValue.contains(i+1) ? theme.accentFill : theme.background,in:.capsule).foregroundStyle(selection.wrappedValue.contains(i+1) ? theme.onAccent : theme.ink)}.buttonStyle(.plain).accessibilityLabel(["الأحد","الاثنين","الثلاثاء","الأربعاء","الخميس","الجمعة","السبت"][i]).accessibilityAddTraits(selection.wrappedValue.contains(i+1) ? .isSelected : []) } } }
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
    private func save(){
        busy=true;issue=nil
        do{
            var saved=rule;saved.effectiveFrom=AppBahwService(session:session).today
            let english=monthDays.map { $0.wholeNumberValue.map(String.init) ?? String($0) }.joined()
            let parts=english.split(whereSeparator:{!$0.isNumber});let parsed=parts.compactMap{Int($0)}
            guard parsed.count==parts.count,parsed.allSatisfy({(1...(saved.hijri ? 30 : 31)).contains($0)}) else{throw CoreError.invalidCommand}
            saved.monthDays=Array(Set(parsed)).sorted();saved.minimum=minimumOn ? min(saved.target,saved.minimum ?? 1) : nil
            if !windowOn{saved.windowStart=nil;saved.windowEnd=nil;saved.windowAnchor=nil}else{saved.windowStart=saved.windowStart ?? 1020;saved.windowEnd=saved.windowEnd ?? 1200}
            try saved.validate()
            let json=try JSONDecoder().decode(MadarCore.JSONValue.self,from:JSONEncoder().encode(saved))
            var p:[String:MadarCore.JSONValue]=["id":.string(id.uuidString),"name":.string(name),"rule":json,"homeOnly":.bool(homeOnly),"reminder":.string(reminder)]
            if source != "custom"{p["source"] = .string(source)}
            Task {do{if source == "walking" {try await HabitHealthStore.authorize(unit:saved.unit ?? "steps")};try await session.executeDiaryCommand("habit.save",payload:p);dismiss()}catch{issue="لم تُحفظ العادة: "+madarUserDetail(error)};busy=false}
        }catch{issue="راجع الهدف وأيام الشهر؛ وقت البداية والنهاية يجب أن يختلفا.";busy=false}
    }
}
