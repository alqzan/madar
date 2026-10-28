import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands
import MadarDesign

struct MoneyGoalView: View {
    let app: AppSession
    @Binding var revealed: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var size
    @State private var reading: MoneyGoalReading?
    @State private var name = ""
    @State private var amount = ""
    @State private var upfront = ""
    @State private var daily = ""
    @State private var source = "surplus"
    @State private var selected = 0
    @State private var paid: Set<UUID> = []
    @State private var edit = false
    @State private var paidOpen = false
    @State private var preview = false
    @State private var saving = false
    @State private var failure: String?
    private var service: AppMoneyService { .init(app: app) }
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private func minor(_ raw: String) -> Int { MoneyAmountInput.minor(raw, exponent: CurrencyExponents.specified.exponent(app.string("core.currency")) ?? 2) ?? 0 }
    private var already: Int { reading?.paid.filter { paid.contains($0.id) }.reduce(0) { $0 + $1.amountMinor } ?? 0 }
    private var target: Int { max(0, minor(amount) - already) }
    private var rest: Int { max(0, target - minor(upfront)) }
    private var days: Int? { GoalPreparation.days(remainingMinor: rest, dailyMinor: minor(daily)) }
    private var finish: GregorianDay? { days.flatMap { reading?.today.adding(days: $0) } }
    private var valid: Bool { visible && name.count <= 80 && [amount, upfront, daily].allSatisfy { MoneyAmountInput.minor($0, exponent: CurrencyExponents.specified.exponent(app.string("core.currency")) ?? 2).map { $0 >= 0 } == true } && target > 0 && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && minor(upfront) <= target && minor(upfront) <= max(0, source == "surplus" ? reading?.surplusMinor ?? 0 : reading?.reserveMinor ?? 0) && minor(daily) <= (reading?.dailyMinor ?? 0) && days != nil }
    private func shown(_ n: Int) -> String { visible ? service.amount(n) : "•••" }
    var body: some View {
        ScrollView { VStack(spacing: 18) {
            HStack { Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).overlay { Circle().stroke(theme.color("reserveText")) } }.accessibilityIdentifier("money-goal-close"); Text("جهّز لشيء قادم").font(MadarTypography.title()); Spacer() }
            if let reading {
                if !visible { Button("المس لإظهار الأرقام") { revealed = true }.frame(minHeight: 44).accessibilityIdentifier("money-goal-reveal") }
                ScrollView(.horizontal) { HStack { ForEach(["هدية", "دراسة", "سفرة", "أثاث", "سيارة"], id: \.self) { title in Button(title) { name = title }.font(MadarTypography.caption()).padding(.horizontal, 18).frame(minHeight: 42).background(name == title ? theme.ink : .clear, in: Capsule()).foregroundStyle(name == title ? theme.background : theme.ink).overlay { Capsule().stroke(theme.color("reserveText").opacity(0.25)) } } } }.scrollIndicators(.hidden)
                Button { edit = true } label: { HStack { VStack(alignment: .leading) { Text(name.isEmpty ? "ما الذي تستعد له؟" : name).font(MadarTypography.cardTitle()).foregroundStyle(theme.color("reserveText")); Text(shown(minor(amount))).font(.custom("thmanyahserifdisplay-Bold", size: 40, relativeTo: .largeTitle)) }; Spacer(); Image(systemName: "pencil").frame(width: 44, height: 44).overlay { Circle().stroke(theme.color("reserveText")) } }.frame(maxWidth: .infinity).contentShape(.rect) }.accessibilityIdentifier("money-goal-edit")
                Text(reading.dailyMinor > 0 ? "حجمه بمخصّصك اليومي: " + service.days(target / max(1, reading.dailyMinor)) + "؛ اختر ما يناسبك" : "يمكنك تمويله من الفائض أو الاحتياطي؛ اليومية غير متاحة الآن")
                    .font(MadarTypography.caption()).padding(12).frame(maxWidth: .infinity).background(theme.surface, in: RoundedRectangle(cornerRadius: 12)).accessibilityHidden(!visible).redacted(reason: visible ? [] : .placeholder)
                HStack(spacing: 8) { ForEach(0..<3, id: \.self) { index in
                    Button { choose(index) } label: { VStack(spacing: 7) { Text(["خفيف", "متوازن", "سريع"][index]).font(MadarTypography.cardTitle()); Text(shown(suggestions[index].dailyMinor) + "/ يوم").font(MadarTypography.body()); Text(!visible ? "•••" : suggestions[index].days.map { $0 == 0 ? "جاهز من الفائض" : service.days($0) } ?? "عدّل اليومية").font(MadarTypography.fine()) }.frame(maxWidth: .infinity, minHeight: 96).padding(4).background(selected == index ? theme.ink : .clear, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(selected == index ? theme.background : theme.ink).overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.color("reserveText").opacity(0.25)) } }.accessibilityIdentifier("money-goal-plan-\(index)")
                } }
                VStack(spacing: 4) { Text("يكتمل تقريبًا").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    if let finish, visible { MadarDateLabel(app.dateLabels(finish), primaryFont: MadarTypography.cardTitle(), secondaryFont: MadarTypography.caption()).foregroundStyle(theme.color("reserveText")) }
                    else { Text(visible ? "اختر مبلغًا وخطة" : "•••").font(MadarTypography.cardTitle()) }
                    Text(service.days(days ?? 0) + "؛ يبقى ليومك " + shown(max(0, reading.dailyMinor - minor(daily)))).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).redacted(reason: visible ? [] : .placeholder)
                }.accessibilityIdentifier("money-goal-completion")
                if !size.isAccessibilitySize && visible { chart.frame(height: 120).accessibilityHidden(true) }
                VStack(spacing: 8) {
                    GeometryReader { proxy in HStack(spacing: 2) { Rectangle().fill(theme.color("reserveText")).frame(width: proxy.size.width * (!visible || target == 0 ? 0 : min(1, Double(minor(upfront)) / Double(target)))); Rectangle().fill(theme.color("surplusText")) } }.frame(height: 9).clipShape(Capsule())
                    HStack { Text("من " + (source == "surplus" ? "الفائض " : "الاحتياطي ") + shown(minor(upfront))); Spacer(); Text("من يومك " + shown(rest)) }.font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    HStack { Text("يومك"); Text(shown(reading.dailyMinor - minor(daily))).frame(maxWidth: .infinity); Text("+ " + shown(minor(daily))).foregroundStyle(theme.color("surplusText")) }.font(MadarTypography.body()).padding(8).overlay { Capsule().stroke(theme.color("reserveText").opacity(0.25)) }
                }
                Button("عدّل المبلغ والاقتطاع والمصدر") { edit = true }.font(MadarTypography.caption()).frame(minHeight: 44).accessibilityIdentifier("money-goal-adjust")
                Button("خطة سنة من الاحتياطي واليومية") { yearPlan() }.font(MadarTypography.caption()).frame(minHeight: 44).disabled(!visible).accessibilityIdentifier("money-goal-year")
                Button("دفعت منه شيء قبل؟ " + (paid.isEmpty ? "اختر من مصروفاتك" : shown(already))) { paidOpen = true }.font(MadarTypography.caption()).frame(minHeight: 44).disabled(!visible).accessibilityIdentifier("money-goal-paid")
                if let failure { Text(failure).font(MadarTypography.caption()) }
                Button { preview = true } label: { Text("أنشئ المظروف").font(MadarTypography.cardTitle()).frame(maxWidth: .infinity, minHeight: 54).background(theme.ink, in: Capsule()).foregroundStyle(theme.background) }.disabled(!valid).accessibilityIdentifier("money-goal-create")
            } else { ProgressView() }
        }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity) }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).environment(\.roomTheme, theme).buttonStyle(.plain).toolbarVisibility(.hidden, for: .navigationBar)
        .sheet(isPresented: $edit) { editor }
        .sheet(isPresented: $paidOpen) { payments }
        .sheet(isPresented: $preview) { confirmation }
        .task { load(); if ProcessInfo.processInfo.environment["MADAR_UI_MONEY_FIXTURE"] == "goal" { name = "سفرة الصيف"; amount = "15000"; choose(0) } }
    }
    private var suggestions: [GoalPreparation.Suggestion] { GoalPreparation.suggestions(targetMinor: target, availableDailyMinor: reading?.dailyMinor ?? 0, surplusMinor: reading?.surplusMinor ?? 0) }
    private func choose(_ index: Int) { selected = index; source = "surplus"; upfront = service.moneyInput(suggestions[index].upfrontMinor); daily = service.moneyInput(suggestions[index].dailyMinor) }
    private func yearPlan() {
        guard let reading, let end = SalaryRecurrence(every: 1, unit: .year, first: reading.today, hijri: app.string("mal.cycleCalendar") == "hijri")?.occurrence(1) else { return }
        source = "reserve"; selected = -1; let share = reading.dailyMinor / 4
        upfront = service.moneyInput(GoalPreparation.yearReserve(targetMinor: target, balancedDailyMinor: share, daysInYear: MadarCalendarDays.distance(from: reading.today, to: end), reserveMinor: reading.reserveMinor)); daily = service.moneyInput(min(rest, share))
    }
    private var chart: some View { GeometryReader { proxy in
        let horizon = max(1, days ?? 0, suggestions.compactMap(\.days).max() ?? 0)
        let height = proxy.size.height - 24
        let top = 6 + height * min(1, Double(minor(upfront)) / Double(max(1, target)))
        let end = proxy.size.width * (1 - Double(days ?? 0) / Double(horizon))
        Path { path in
            path.move(to: .init(x: proxy.size.width, y: top)); path.addLine(to: .init(x: end, y: height)); path.addLine(to: .init(x: proxy.size.width, y: height)); path.closeSubpath()
        }.fill(theme.color("surplusText").opacity(0.2))
        ForEach(0..<3, id: \.self) { index in
            let plan = suggestions[index]
            let x = proxy.size.width * (1 - Double(plan.days ?? horizon) / Double(horizon))
            let y = 6 + height * min(1, Double(plan.upfrontMinor) / Double(max(1, target)))
            Path { path in path.move(to: .init(x: proxy.size.width, y: y)); path.addLine(to: .init(x: x, y: height)) }.stroke(theme.secondaryInk.opacity(0.4), style: .init(lineWidth: 1, dash: [3, 4]))
        }
        Path { path in path.move(to: .init(x: proxy.size.width, y: top)); path.addLine(to: .init(x: end, y: height)) }.stroke(theme.color("surplusText"), lineWidth: 2)
        HStack { Text("الآن"); Spacer(); Text("بعد " + service.days(horizon)) }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).frame(maxHeight: .infinity, alignment: .bottom)
    } }
    private var editor: some View { NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 16) {
        Text("على قدر يومك").font(MadarTypography.title())
        TextField("اسم الشيء", text: $name).accessibilityIdentifier("money-goal-name")
        field("المبلغ الكامل", raw: $amount, id: "money-goal-amount")
        Picker("من أين تبدأ؟", selection: $source) { Text("الفائض").tag("surplus"); Text("الاحتياطي").tag("reserve") }.pickerStyle(.segmented)
        field("تنقل الآن", raw: $upfront, id: "money-goal-upfront")
        Text("المتاح " + shown(source == "surplus" ? reading?.surplusMinor ?? 0 : reading?.reserveMinor ?? 0)).font(MadarTypography.caption())
        field("اقتطاع كل يوم، من الغد", raw: $daily, id: "money-goal-daily")
        Text("يمكنك تعديل كل مبلغ. اليومية لا تتجاوز المتاح بعد خططك الحالية؛ تتوقف القطرات عند اكتمال الهدف، وتتوقف أيام إيقاف اليومية في السفر.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
        Button("تمّ") { selected = -1; edit = false }.frame(maxWidth: .infinity, minHeight: 48).background(theme.ink).foregroundStyle(theme.background).accessibilityIdentifier("money-goal-editor-done")
    }.textFieldStyle(.roundedBorder).padding(22) }.scrollDismissesKeyboard(.interactively).background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).disabled(!visible) } }
    private func field(_ title: String, raw: Binding<String>, id: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(MadarTypography.caption()); TextField(title, text: raw).keyboardType(.decimalPad).accessibilityIdentifier(id) } }
    private var payments: some View { ScrollView { VStack(alignment: .leading, spacing: 12) {
        Text("دفعات مسجلة لهذا الشيء").font(MadarTypography.cardTitle()); Text("اختر ما دفعته نقدًا أو بالبطاقة أو التقسيط. يبقى المصروف كما سجلته؛ المظروف الجديد للمتبقي فقط.").font(MadarTypography.caption())
        ForEach(reading?.paid ?? []) { item in Button { if paid.contains(item.id) { paid.remove(item.id) } else { paid.insert(item.id) } } label: { HStack { Image(systemName: paid.contains(item.id) ? "checkmark.circle.fill" : "circle"); VStack(alignment: .leading) { Text(item.title); if let day = try? GregorianDay(item.dayKey) { MadarDateLabel(app.dateLabels(day), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()) } }; Spacer(); Text(shown(item.amountMinor)) }.frame(minHeight: 50).contentShape(.rect) }.accessibilityIdentifier("money-goal-paid-" + item.id.uuidString) }
        Button("تمّ") { upfront = service.moneyInput(min(target, minor(upfront))); daily = service.moneyInput(min(rest, minor(daily))); selected = -1; paidOpen = false }.frame(minHeight: 44).accessibilityIdentifier("money-goal-paid-done")
    }.padding(22) }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).buttonStyle(.plain) }
    private var confirmation: some View { VStack(alignment: .leading, spacing: 18) {
        Text("قبل إنشاء المظروف").font(MadarTypography.cardTitle()); Text(name).font(MadarTypography.body()); Text("المتبقي " + shown(target) + "؛ تنقل الآن " + shown(minor(upfront)) + " من " + (source == "surplus" ? "الفائض" : "الاحتياطي") + "، ومن الغد " + shown(minor(daily)) + " يوميًا.").font(MadarTypography.body())
        if let finish { MadarDateLabel(app.dateLabels(finish), primaryFont: MadarTypography.body(), secondaryFont: MadarTypography.caption()) }
        Text("الموعد تقديري إذا بقيت اليومية كما هي. لا تعاد كتابة مصروفاتك السابقة.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
        Button(saving ? "جارٍ الإنشاء…" : "اعتمد الخطة") { save() }.frame(maxWidth: .infinity, minHeight: 50).background(theme.ink).foregroundStyle(theme.background).disabled(saving || !valid).accessibilityIdentifier("money-goal-confirm")
        Button("ارجع للتعديل") { preview = false }.frame(minHeight: 44)
    }.padding(24).background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).buttonStyle(.plain).presentationDetents([.medium, .large]) }
    private func load() { do { _ = try service.load(); reading = try MoneyRepository(context: ModelContext(app.container)).goalPreparation(at: app.prayerNow()) } catch { failure = "تعذّرت قراءة المال. أعد فتح الصفحة." } }
    private func save() {
        guard let reading, valid, let finish else { return }; saving = true
        let due = max(app.prayerNow(), finish.date(in: app.activePlace.timeZone).addingTimeInterval(12 * 3600))
        Task { do { try await app.executeMoneyCommand("money.prepareGoal", payload: ["name": .string(name), "totalMinor": .string(String(minor(amount))), "paidIDs": .array(paid.map { .string($0.uuidString) }), "upfrontMinor": .string(String(minor(upfront))), "dailyMinor": .string(String(minor(daily))), "source": .string(source), "due": .string(ISO8601DateFormatter().string(from: due)), "signature": .string(reading.signature)]); preview = false; dismiss() } catch { preview = false; saving = false; failure = "تغيّر المال منذ المعاينة. راجع الأرقام ثم اعتمدها من جديد."; load() } }
    }
}
