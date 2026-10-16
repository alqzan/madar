import SwiftUI
import MadarCore
import MadarDesign
import MadarMoney

struct MoneyLogView: View {
    let app: AppSession
    @Binding var revealed: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var reading: MoneyLogReading?
    @State private var selected: GregorianDay?
    @State private var month: GregorianDay?
    @State private var calendarMode = false
    @State private var filter = "all"
    @State private var query = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    @State private var source: MoneySourceDetail?
    @State private var messagesOpen = false
    @State private var failure: String?
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var service: AppMoneyService { .init(app: app) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private func amount(_ n: Int) -> String { visible ? service.amount(n) : "•••" }
    private var chosen: MoneyLogDay? { reading?.arcadeDays.first { $0.day == selected } ?? reading?.days.last { $0.day <= reading!.today } ?? reading?.days.first }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1) } }.buttonStyle(.plain).accessibilityLabel("إغلاق").accessibilityIdentifier("money-log-close")
                    Text("السجل").font(.custom("thmanyahserifdisplay-Bold", size: 26, relativeTo: .title)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { calendarMode.toggle() } label: { Image(systemName: calendarMode ? "book.pages" : "calendar").frame(width: 44, height: 44).background(calendarMode ? theme.ink : Color.clear, in: Circle()).foregroundStyle(calendarMode ? theme.background : theme.ink).overlay { Circle().stroke(theme.line, lineWidth: 1) } }.buttonStyle(.plain).accessibilityLabel(calendarMode ? "رواق الأيام" : "الشهر أقواسًا").accessibilityIdentifier("money-log-mode")
                }.padding(.top, 8)
                if let reading {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(reading.monthStarts, id: \.description) { start in
                                Button { month = start; selected = nil; load() } label: {
                                    let labels = service.logMonthLabels(start)
                                    VStack(alignment: .leading, spacing: 3) { Text(labels.primary).font(MadarTypography.caption()); Text(labels.secondary).font(MadarTypography.fine()) }.padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(start == reading.monthStart ? theme.ink : theme.surface, in: UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
                                        .foregroundStyle(start == reading.monthStart ? theme.background : theme.ink)
                                }.buttonStyle(.plain).accessibilityIdentifier("money-log-month-" + start.description)
                            }
                        }
                    }.scrollIndicators(.hidden)
                    if searching || !query.isEmpty {
                        HStack(spacing: 8) { Image(systemName: "magnifyingglass"); TextField("التاجر أو المبلغ", text: $query).font(MadarTypography.body()).focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }.autocorrectionDisabled().accessibilityIdentifier("money-log-search"); Button { query = ""; searching = false; searchFocused = false } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel("مسح البحث") }.padding(.horizontal, 12).frame(minHeight: 44).background(theme.surface, in: Capsule()).overlay { Capsule().stroke(theme.line, lineWidth: 1) }
                    }
                    HStack(spacing: 7) {
                        Button { searching = true; searchFocused = true } label: { Label("بحث", systemImage: "magnifyingglass").font(MadarTypography.caption()).padding(.horizontal, 12).frame(minHeight: 44).overlay { Capsule().stroke(theme.color("reserveText"), lineWidth: 1) } }.buttonStyle(.plain).accessibilityIdentifier("money-log-search-open")
                        ScrollView(.horizontal) {
                            HStack(spacing: 7) { ForEach(reading.filters) { f in Button { filter = f.id } label: { Text(f.title).font(MadarTypography.caption()).padding(.horizontal, 12).frame(minHeight: 44).background(filter == f.id ? theme.ink : Color.clear, in: Capsule()).foregroundStyle(filter == f.id ? theme.background : theme.ink).overlay { Capsule().stroke(theme.line, lineWidth: 1) } }.buttonStyle(.plain).accessibilityIdentifier("money-log-filter-" + f.id) } }
                        }.scrollIndicators(.hidden)
                    }
                    if !visible { Button("أظهر الأرقام") { revealed = true }.frame(minHeight: 44).accessibilityIdentifier("money-log-reveal") }
                    if dynamicType.isAccessibilitySize { dayList(reading.days) }
                    else if calendarMode { monthGrid(reading) }
                    else { arcade(reading) }
                    if let chosen { detail(chosen, reading: reading) }
                    monthSummary(reading)
                } else if let failure { Text(failure).font(MadarTypography.body()); Button("أعِد المحاولة", action: load).frame(minHeight: 44) }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 220) }
            }.padding(.horizontal, 20).padding(.bottom, 30).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
            .task { load() }.onChange(of: app.prayerRevision) { load() }
            .sheet(item: $source) { MoneySourceView(app: app, detail: $0, visible: visible).environment(\.roomTheme, theme) }
            .navigationDestination(isPresented: $messagesOpen) { MoneyMessagesView(app: app, revealed: $revealed) }.accessibilityIdentifier("money-log")
    }
    private func arcade(_ r: MoneyLogReading) -> some View {
        let center = chosen?.day ?? r.today
        var cal = Calendar(identifier: .gregorian); cal.timeZone = app.activePlace.timeZone
        let firstWeekday = app.string("core.weekStart") == "sunday" ? 1 : 7
        let leading = (cal.component(.weekday, from: center.date(in: cal.timeZone)) - firstWeekday + 7) % 7
        let week = center.adding(days: -leading)
        let days = r.arcadeDays.filter { $0.day >= week && $0.day < week.adding(days: 7) }
        let maximum = days.map { max($0.dailyMinor ?? 0, $0.spentMinor) }.max() ?? 1
        let scale = max(1, maximum + maximum / 2)
        return VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) { ForEach(days) { day in dayButton(day, scale: scale, height: 124) } }
            if visible, let daily = (days.first { $0.day == chosen?.day } ?? days.first)?.dailyMinor { Text("خط " + amount(daily)).font(MadarTypography.fine()).foregroundStyle(theme.color("reserveText")).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("money-log-limit-label") }
            Text("الخط الذهبي يومك الفعلي؛ الرسم ليومك كاملًا، والتصفية للحركات أدناه.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
        }.padding(.top, 10).padding(.bottom, 6).accessibilityElement(children: .contain).accessibilityIdentifier("money-log-arcade")
    }
    private func monthGrid(_ r: MoneyLogReading) -> some View {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = app.activePlace.timeZone
        let firstWeekday = app.string("core.weekStart") == "sunday" ? 1 : 7
        let leading = (cal.component(.weekday, from: r.monthStart.date(in: cal.timeZone)) - firstWeekday + 7) % 7
        let maximum = r.days.map { max($0.dailyMinor ?? 0, $0.spentMinor) }.max() ?? 1
        let scale = max(1, maximum + maximum / 2)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 12) {
            ForEach(0..<7, id: \.self) { index in Text(["أحد", "اثنين", "ثلاثاء", "أربعاء", "خميس", "جمعة", "سبت"][(firstWeekday - 1 + index) % 7]).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
            ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 70) }
            ForEach(r.days) { day in dayButton(day, scale: scale, height: 56) }
        }.padding(.vertical, 10).accessibilityElement(children: .contain).accessibilityIdentifier("money-log-month-grid")
    }
    private func dayButton(_ d: MoneyLogDay, scale: Int, height: CGFloat) -> some View {
        let future = d.day > (reading?.today ?? d.day)
        let selected = chosen?.day == d.day
        let over = visible && !future && d.within == .missed
        let pair = DualDate(instant: d.day.date(in: app.activePlace.timeZone).addingTimeInterval(43200), timeZone: app.activePlace.timeZone, source: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(app.number("core.hijriOffset")))
        return Button { self.selected = d.day } label: {
            VStack(spacing: 5) {
                if height > 60 {
                    VStack(spacing: 0) {
                        if over { Text(amount(d.spentMinor)).font(MadarTypography.fine()).foregroundStyle(theme.color("dueText")).lineLimit(1).minimumScaleFactor(0.7); Rectangle().fill(theme.color("due")).frame(width: 5, height: 14) }
                    }.frame(height: 30, alignment: .bottom).accessibilityHidden(true)
                }
                GeometryReader { proxy in
                    let fill = over ? 1 : visible ? min(1, Double(max(0, d.spentMinor)) / Double(scale)) : 0
                    let arch = UnevenRoundedRectangle(topLeadingRadius: proxy.size.width / 2, topTrailingRadius: proxy.size.width / 2)
                    ZStack(alignment: .bottom) {
                        Rectangle().fill(over ? theme.color("due") : theme.color("surplus").opacity(0.62)).frame(height: height * fill)
                        if visible, let daily = d.dailyMinor {
                            Rectangle().fill(theme.color("reserveText")).frame(height: 0.7).offset(y: -height * min(1, Double(max(0, daily)) / Double(scale)))
                        }
                        if !future { Text(amount(d.spentMinor)).font(MadarTypography.fine()).foregroundStyle(over ? theme.onAccent : theme.ink).lineLimit(1).minimumScaleFactor(0.85).padding(.bottom, over ? height - 20 : min(height - 15, height * fill + 2)) }
                        if d.pending > 0 { Circle().stroke(theme.ink, lineWidth: 1.5).frame(width: 7, height: 7).padding(.bottom, 4) }
                    }.frame(width: proxy.size.width, height: height, alignment: .bottom).clipShape(arch).overlay { arch.stroke(selected ? theme.ink : theme.color("reserveText"), style: .init(lineWidth: selected ? 2 : 1, dash: future ? [3, 3] : [])) }
                }.frame(height: height)
                Text(service.digits.string(app.string("core.firstCalendar") == "gregorian" ? pair.gregorian.day : pair.hijri.day)).font(MadarTypography.caption())
                Text(service.digits.string(app.string("core.firstCalendar") == "gregorian" ? pair.hijri.day : pair.gregorian.day)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                if height > 60 {
                    let formatter = DateFormatter()
                    Text(weekday(d.day, formatter: formatter)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain).accessibilityLabel(app.dateLabels(d.day).combined + "، " + (future ? "يوم قادم" : "صرفت " + amount(d.spentMinor) + " من " + (d.dailyMinor.map(amount) ?? "يومية غير معروفة")) + (d.pending > 0 ? "، يحتاج قرارًا" : ""))
            .accessibilityIdentifier("money-log-day-" + d.id)
    }
    private func dayList(_ days: [MoneyLogDay]) -> some View {
        VStack(spacing: 10) { ForEach(days) { d in Button { selected = d.day } label: { HStack { MadarDateLabel(app.dateLabels(d.day)); Spacer(); Text(amount(d.spentMinor) + " من " + (d.dailyMinor.map(amount) ?? "غير معروف")) }.font(MadarTypography.body()).frame(minHeight: 44) }.buttonStyle(.plain) } }
    }
    private func weekday(_ day: GregorianDay, formatter: DateFormatter) -> String {
        formatter.locale = Locale(identifier: "ar_SA"); formatter.timeZone = app.activePlace.timeZone; formatter.dateFormat = "EEE"
        return formatter.string(from: day.date(in: app.activePlace.timeZone).addingTimeInterval(43200))
    }
    private func detail(_ d: MoneyLogDay, reading r: MoneyLogReading) -> some View {
        let rows = r.movements.filter { row in
            guard row.day == d.day else { return false }
            let matches = filter == "all" || filter == "cash" && row.cash || filter == "bnpl" && row.bnpl || filter == "transfers" && ["transfer", "cardPayment"].contains(row.kind) || row.cardID?.uuidString == filter
            func normalized(_ s: String) -> String { BankDedupe.normalize(s).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ar")).filter { $0.isLetter || $0.isNumber } }
            return matches && (query.isEmpty || normalized(row.title + row.category + row.payment + service.amount(row.amountMinor)).contains(normalized(query)))
        }
        return VStack(alignment: .leading, spacing: 14) {
            DoubleRule().stroke(theme.color("reserveText"), lineWidth: 0.8).frame(height: 3)
            MadarDateLabel(app.dateLabels(d.day, weekday: true), primaryFont: MadarTypography.cardTitle(), secondaryFont: MadarTypography.caption())
            HStack(alignment: .top, spacing: 6) {
                metric("من يومك", value: amount(d.spentMinor), note: d.dailyMinor.map { "من " + amount($0) } ?? "اليومية غير معروفة", tint: theme.color("surplusText"))
                metric("خارج يومك", value: amount(d.otherMinor), note: "مظاريف ومستثنى", tint: theme.color("accentText"))
                metric("نقد خرج فعلًا", value: d.cashOutMinor.map(amount) ?? "غير مكتمل", note: "البطاقة عند السداد", tint: theme.secondaryInk)
            }
            if d.pending > 0 { Button { messagesOpen = true } label: { Label("حركات تحتاج قرارك؛ اليوم معلّق", systemImage: "tray").font(MadarTypography.caption()).frame(minHeight: 44) }.buttonStyle(.plain).accessibilityIdentifier("money-log-pending") }
            if rows.isEmpty { Text("لا حركات تطابق هذا اليوم والفلتر.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).padding(.vertical, 16).accessibilityIdentifier("money-log-empty") }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicType.isAccessibilitySize ? 300 : 150), spacing: 8)], spacing: 8) {
                ForEach(rows) { row in
                    Button { source = row.detail } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Text(row.title).font(MadarTypography.body()).bold(); Spacer(minLength: 2); Text(service.time(row.at)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                            Text(row.budgetLabel).font(MadarTypography.fine()).foregroundStyle(row.confirmed ? theme.color("surplusText") : theme.secondaryInk).padding(.horizontal, 7).padding(.vertical, 3).overlay { Capsule().stroke(theme.line, lineWidth: 1) }
                            Text(amount(row.amountMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 25, relativeTo: .title2))
                            Text(row.payment + "، " + row.category).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        }.padding(12).frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading).background(theme.surface)
                            .overlay(alignment: .top) { Rectangle().fill(row.confirmed ? theme.color("surplusText") : theme.secondaryInk).frame(height: 3) }.overlay { Rectangle().stroke(theme.line, lineWidth: 1) }
                    }.buttonStyle(.plain).accessibilityIdentifier("money-log-row-" + row.title)
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("money-log-detail")
    }
    private func metric(_ title: String, value: String, note: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk); Text(value).font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title3)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.65); Text(note).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading).padding(9).background(theme.surface).overlay(alignment: .top) { Rectangle().fill(tint).frame(height: 3) }
    }
    private func monthSummary(_ r: MoneyLogReading) -> some View {
        let known = r.days.filter { $0.day <= r.today && $0.within != nil && $0.within != .pending }
        let met = known.filter { $0.within == .met }.count
        return HStack(spacing: 7) {
            metric("ضمن اليومية حتى الآن", value: visible ? service.digits.string(met) + " / " + service.digits.string(known.count) : "•••", note: "المعلّق لا يدخل العدد", tint: theme.color("surplusText"))
            metric("صرف من يومك", value: amount(r.days.reduce(0) { $0 + $1.spentMinor }), note: "بعد الردود على يوم الأصل", tint: theme.ink)
            metric("تحويلات محايدة", value: amount(r.neutralTransfersMinor), note: "لا تُخصم من اليومية", tint: theme.secondaryInk)
        }.padding(.top, 10)
    }
    private func load() {
        do { reading = try service.loadLog(month: month); if selected == nil { selected = reading?.days.last { $0.day <= reading!.today }?.day ?? reading?.days.first?.day }; failure = nil }
        catch { reading = nil; failure = "لم تكتمل قراءة السجل. حاول مرة أخرى." }
    }
}
