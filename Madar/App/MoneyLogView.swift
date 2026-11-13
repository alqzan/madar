import SwiftUI
import MadarCore
import MadarDesign
import MadarMoney

struct MoneyLogView: View {
    let app: AppSession
    @Binding var revealed: Bool
    var initialTransactionID: UUID? = nil
    var initialQuery: String? = nil
    var initialRouteRequestID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var isRefreshing = false
    @State private var initialRouteApplied = false
    @State private var initialRouteMissing = false
    @State private var routeRequestTracker = MoneyLogRouteRequestTracker()
    @State private var readingLoadTask: Task<Void, Never>?
    @State private var activeReadingLoadID: UUID?
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var service: AppMoneyService { .init(app: app) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private func amount(_ n: Int) -> String { visible ? service.amount(n) : "•••" }
    private var chosen: MoneyLogDay? { reading?.arcadeDays.first { $0.day == selected } ?? reading?.days.last { $0.day <= reading!.today } ?? reading?.days.first }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle) }.buttonStyle(.madarPlain).accessibilityLabel("إغلاق").accessibilityIdentifier("money-log-close")
                    Text("السجل").font(.custom("thmanyahserifdisplay-Bold", size: 26, relativeTo: .title)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { calendarMode.toggle() } label: { Image(systemName: calendarMode ? "book.pages" : "calendar").frame(width: 44, height: 44).background(calendarMode ? theme.ink : Color.clear, in: Circle()).foregroundStyle(calendarMode ? theme.background : theme.ink).glassEffect(.regular.interactive(), in: .circle) }.buttonStyle(.madarPlain).accessibilityLabel(calendarMode ? "رواق الأيام" : "الشهر أقواسًا").accessibilityIdentifier("money-log-mode")
                }.padding(.top, 8)
                if isRefreshing, reading != nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("نحدّث السجل…").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("money-log-refreshing")
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                if let reading {
                    if initialRouteMissing {
                        Text("هذه الحركة لم تعد موجودة في السجل.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            .accessibilityIdentifier("money-log-route-unavailable")
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(reading.monthStarts, id: \.description) { start in
                                Button { month = start; selected = nil; load() } label: {
                                    let labels = service.logMonthLabels(start)
                                    VStack(alignment: .leading, spacing: 1) { Text(labels.primary).font(.custom("thmanyahserifdisplay-Bold", size: 16, relativeTo: .subheadline)); Text(labels.secondary).font(MadarTypography.fine()).opacity(0.8) }.padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(start == reading.monthStart ? theme.ink : theme.surface, in: UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
                                        .overlay { if start != reading.monthStart { UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14).stroke(theme.line, lineWidth: 1) } }
                                        .foregroundStyle(start == reading.monthStart ? theme.background : theme.ink)
                                }.buttonStyle(.madarPlain).accessibilityIdentifier("money-log-month-" + start.description)
                            }
                        }
                    }.scrollIndicators(.hidden)
                    if searching || !query.isEmpty {
                        HStack(spacing: 8) { Image(systemName: "magnifyingglass"); TextField("التاجر أو المبلغ", text: $query).font(MadarTypography.body()).focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }.autocorrectionDisabled().accessibilityIdentifier("money-log-search"); Button { query = ""; searching = false; searchFocused = false } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }.buttonStyle(.madarPlain).accessibilityLabel("مسح البحث") }.padding(.horizontal, 12).frame(minHeight: 44).background(theme.surface, in: Capsule()).glassEffect(.regular.interactive(), in: .capsule)
                    }
                    HStack(spacing: 7) {
                        Button { searching = true; searchFocused = true } label: { Label("بحث", systemImage: "magnifyingglass").font(MadarTypography.caption()).padding(.horizontal, 12).frame(minHeight: 44).glassEffect(.regular.interactive(), in: .capsule) }.buttonStyle(.madarPlain).accessibilityIdentifier("money-log-search-open")
                        ScrollView(.horizontal) {
                            HStack(spacing: 7) { ForEach(reading.filters) { f in Button { filter = f.id } label: { Text(f.title).font(MadarTypography.caption()).padding(.horizontal, 12).frame(minHeight: 44).background(filter == f.id ? theme.ink : Color.clear, in: Capsule()).foregroundStyle(filter == f.id ? theme.background : theme.ink).glassEffect(.regular.interactive(), in: .capsule) }.buttonStyle(.madarPlain).accessibilityIdentifier("money-log-filter-" + f.id) } }
                        }.scrollIndicators(.hidden)
                    }
                    if !visible { Button { revealed = true } label: { Text("أظهر الأرقام").frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("money-log-reveal") }
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if dynamicType.isAccessibilitySize { dayList(reading.days) }
                        else if calendarMode { monthGrid(reading) }
                        else { arcade(reading) }
                        if let chosen { detail(chosen, reading: reading) }
                    } else {
                        searchResults(reading)
                    }
                    monthSummary(reading)
                } else if let failure { Text(failure).font(MadarTypography.body()); Button { load() } label: { Text("أعِد المحاولة").frame(minHeight: 44).contentShape(Rectangle()) } }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 220) }
            }.padding(.horizontal, 20).padding(.bottom, 30).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
            .task(id: initialRouteRequestID) { load() }
            .onChange(of: app.prayerRevision) { load() }
            .onDisappear { readingLoadTask?.cancel(); readingLoadTask = nil }
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
        let dailies = Set(days.compactMap(\.dailyMinor))
        // One gold line across the whole week when every day shares the same allowance, as in the canonical «خط ٤٠٠».
        let shared = dailies.count == 1 ? dailies.first : nil
        return VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) { ForEach(days) { day in dayButton(day, scale: scale, height: 124, drawsLimit: shared == nil) } }
                .overlay(alignment: .top) {
                    if visible, let daily = shared {
                        let y = 35 + 124 * (1 - min(1, Double(max(0, daily)) / Double(scale)))
                        ZStack(alignment: .bottomTrailing) {
                            Rectangle().fill(theme.color("reserveText")).frame(height: 1)
                            Text(figure: "خط " + amount(daily)).font(MadarTypography.fine()).foregroundStyle(theme.color("reserveText")).padding(.horizontal, 4).background(theme.background).offset(y: -3)
                                .accessibilityIdentifier("money-log-limit-label")
                        }.padding(.horizontal, -6).offset(y: y).allowsHitTesting(false)
                    }
                }
            if visible, shared == nil, let daily = (days.first { $0.day == chosen?.day } ?? days.first)?.dailyMinor { Text(figure: "خط " + amount(daily)).font(MadarTypography.fine()).foregroundStyle(theme.color("reserveText")).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("money-log-limit-label") }
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
            ForEach(r.days) { day in dayButton(day, scale: scale, height: 56, drawsLimit: true) }
        }.padding(.vertical, 10).accessibilityElement(children: .contain).accessibilityIdentifier("money-log-month-grid")
    }
    private func dayButton(_ d: MoneyLogDay, scale: Int, height: CGFloat, drawsLimit: Bool) -> some View {
        let future = d.day > (reading?.today ?? d.day)
        let selected = chosen?.day == d.day
        let over = visible && !future && d.within == .missed
        let pair = DualDate(instant: d.day.date(in: app.activePlace.timeZone).addingTimeInterval(43200), timeZone: app.activePlace.timeZone, source: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(app.number("core.hijriOffset")))
        return Button { self.selected = d.day } label: {
            VStack(spacing: 5) {
                if height > 60 {
                    VStack(spacing: 0) {
                        if over { Text(figure: amount(d.spentMinor)).font(MadarTypography.fine()).foregroundStyle(theme.color("dueText")).lineLimit(1); Rectangle().fill(theme.color("due")).frame(width: 5, height: 14) }
                    }.frame(height: 30, alignment: .bottom).accessibilityHidden(true)
                }
                GeometryReader { proxy in
                    let fill = over ? 1 : visible ? min(1, Double(max(0, d.spentMinor)) / Double(scale)) : 0
                    let arch = UnevenRoundedRectangle(topLeadingRadius: proxy.size.width / 2, topTrailingRadius: proxy.size.width / 2)
                    ZStack(alignment: .bottom) {
                        Rectangle().fill(over ? theme.color("due") : theme.color("surplus").opacity(0.62)).frame(height: height * fill)
                        if visible, drawsLimit, let daily = d.dailyMinor {
                            Rectangle().fill(theme.color("reserveText")).frame(height: 0.7).offset(y: -height * min(1, Double(max(0, daily)) / Double(scale)))
                        }
                        if !future { Text(figure: amount(d.spentMinor)).font(MadarTypography.fine()).foregroundStyle(over ? theme.onAccent : theme.ink).lineLimit(1).padding(.bottom, over ? height - 20 : min(height - 15, height * fill + 2)) }
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
        }.buttonStyle(.madarPlain).accessibilityLabel(app.dateLabels(d.day).combined + "، " + (future ? "يوم قادم" : "صرفت " + amount(d.spentMinor) + " من " + (d.dailyMinor.map(amount) ?? "يومية غير معروفة")) + (d.pending > 0 ? "، يحتاج قرارًا" : ""))
            .accessibilityIdentifier("money-log-day-" + d.id)
    }
    private func dayList(_ days: [MoneyLogDay]) -> some View {
        VStack(spacing: 10) { ForEach(days) { d in Button { selected = d.day } label: { HStack { MadarDateLabel(app.dateLabels(d.day)); Spacer(); Text(figure: amount(d.spentMinor) + " من " + (d.dailyMinor.map(amount) ?? "غير معروف")) }.font(MadarTypography.body()).frame(minHeight: 44).contentShape(.rect) }.buttonStyle(.madarPlain) } }
    }
    private func weekday(_ day: GregorianDay, formatter: DateFormatter) -> String {
        formatter.locale = Locale(identifier: "ar_SA"); formatter.timeZone = app.activePlace.timeZone; formatter.dateFormat = "EEE"
        return formatter.string(from: day.date(in: app.activePlace.timeZone).addingTimeInterval(43200))
    }
    private func detail(_ d: MoneyLogDay, reading r: MoneyLogReading) -> some View {
        let rows = r.movements.filter { row in
            guard row.day == d.day else { return false }
            func normalized(_ s: String) -> String { BankDedupe.normalize(s).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ar")).filter { $0.isLetter || $0.isNumber } }
            return matchesFilter(row) && (query.isEmpty || normalized(row.title + row.category + row.payment + (visible ? service.amount(row.amountMinor) : "")).contains(normalized(query)))
        }
        return VStack(alignment: .leading, spacing: 14) {
            DoubleRule().stroke(theme.color("reserveText"), lineWidth: 0.8).frame(height: 3)
            let title = MadarDateLabel(app.dateLabels(d.day, weekday: true), primaryFont: MadarTypography.cardTitle(), secondaryFont: MadarTypography.caption())
            let tally = visible ? weekTally(d.day, reading: r) : nil
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { title.fixedSize(); Spacer(minLength: 6); if let tally { Text(tally).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).fixedSize() } }
                VStack(alignment: .leading, spacing: 4) { title; if let tally { Text(tally).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) } }
            }.accessibilityElement(children: .combine).accessibilityIdentifier("money-log-week-tally")
            HStack(alignment: .top, spacing: 6) {
                metric("من يومك", value: amount(d.spentMinor), note: d.dailyMinor.map { "من " + amount($0) } ?? "اليومية غير معروفة", tint: theme.color("surplusText"))
                metric("خارج يومك", value: amount(d.otherMinor), note: "مظاريف ومستثنى", tint: theme.color("accentText"))
                metric("نقد خرج فعلًا", value: d.cashOutMinor.map(amount) ?? "غير مكتمل", note: "البطاقة عند السداد", tint: theme.secondaryInk)
            }
            if d.pending > 0 { Button { messagesOpen = true } label: { Label("حركات تحتاج قرارك؛ اليوم معلّق", systemImage: "tray").font(MadarTypography.caption()).frame(minHeight: 44) }.buttonStyle(.madarPlain).accessibilityIdentifier("money-log-pending") }
            if rows.isEmpty {
                // Audit 28 Oct: a narrowed empty day offers the way back to the whole day.
                VStack(alignment: .leading, spacing: 4) {
                    Text(filter == "all" && query.isEmpty ? "لا حركات في هذا اليوم." : "لا حركات تطابق هذا اليوم والفلتر.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-log-empty")
                    if filter != "all" || !query.isEmpty { Button { filter = "all"; query = "" } label: { Text("اعرض كل حركات اليوم").font(MadarTypography.caption()).foregroundStyle(theme.color("accentText")).frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("money-log-clear-filter") }
                }.padding(.vertical, 12)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicType.isAccessibilitySize ? 300 : 150), spacing: 8)], spacing: 8) {
                ForEach(rows) { row in
                    Button { source = row.detail } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Text(row.title).font(MadarTypography.body()).bold(); Spacer(minLength: 2); Text(service.time(row.at)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                            HStack(alignment: .center, spacing: 4) {
                                Text(figure: amount(row.amountMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 25, relativeTo: .title2)).lineLimit(1).minimumScaleFactor(0.7)
                                Spacer(minLength: 2)
                                Text(row.budgetLabel).font(MadarTypography.fine()).foregroundStyle(row.confirmed ? theme.color("surplusText") : theme.secondaryInk).lineLimit(1).padding(.horizontal, 7).padding(.vertical, 3).overlay { Capsule().stroke(row.confirmed ? theme.color("surplusText") : theme.line, lineWidth: 1) }
                            }
                            Text(row.payment + "، " + row.category).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        }.padding(12).frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading).background(theme.surface)
                            .overlay(alignment: .top) { Rectangle().fill(row.confirmed ? theme.color("surplusText") : theme.secondaryInk).frame(height: 3) }.overlay { Rectangle().stroke(theme.line, lineWidth: 1) }
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("money-log-row-" + row.title)
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("money-log-detail")
    }
    /// «٦ من ٧ أيام ضمن اليومية» for the week that holds the chosen day; pending and future days are not counted.
    private func weekTally(_ day: GregorianDay, reading r: MoneyLogReading) -> String? {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = app.activePlace.timeZone
        let firstWeekday = app.string("core.weekStart") == "sunday" ? 1 : 7
        let week = day.adding(days: -((cal.component(.weekday, from: day.date(in: cal.timeZone)) - firstWeekday + 7) % 7))
        let known = r.arcadeDays.filter { $0.day >= week && $0.day < week.adding(days: 7) && $0.day <= r.today && $0.within != nil && $0.within != .pending }
        guard !known.isEmpty else { return nil }
        let met = known.filter { $0.within == .met }.count
        let of = known.count == 1 ? "من يوم واحد" : known.count == 2 ? "من يومين" : "من " + service.digits.string(known.count) + (known.count <= 10 ? " أيام" : " يومًا")
        return service.digits.string(met) + " " + of + " ضمن اليومية"
    }
    private func metric(_ title: String, value: String, note: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk); Text(figure: value).font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title3)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.65); Text(note).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading).padding(9).background(theme.surface).overlay(alignment: .top) { Rectangle().fill(tint).frame(height: 3) }
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
    private func normalizedSearch(_ value: String) -> String {
        BankDedupe.normalize(value).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ar"))
            .filter { $0.isLetter || $0.isNumber }
    }
    private func matchesFilter(_ row: MoneyLogMovement) -> Bool {
        filter == "all" || filter == "cash" && row.cash || filter == "bnpl" && row.bnpl
            || filter == "transfers" && ["transfer", "cardPayment"].contains(row.kind)
            || row.cardID?.uuidString == filter
    }
    private func matchingMovements(_ r: MoneyLogReading) -> [MoneyLogMovement] {
        let needle = normalizedSearch(query)
        guard !needle.isEmpty else { return [] }
        return r.movements.filter { row in
            let searchable = visible ? row.searchIndexWithAmount : row.searchIndex
            return matchesFilter(row) && searchable.contains(needle)
        }
    }
    @ViewBuilder private func searchResults(_ r: MoneyLogReading) -> some View {
        let rows = matchingMovements(r)
        if rows.isEmpty {
            Text("لا حركة تطابق بحثك.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                .accessibilityIdentifier("money-log-search-empty")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("نتائج البحث: " + service.digits.string(rows.count)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                ForEach(rows) { row in
                    Button { source = row.detail } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title).font(MadarTypography.body()).bold()
                                MadarDateLabel(app.dateLabels(row.day, weekday: true)).font(MadarTypography.fine())
                                Text(row.category + "، " + row.payment).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                            }
                            Spacer(minLength: 4)
                            Text(figure: amount(row.amountMinor)).font(MadarTypography.cardTitle()).lineLimit(1).minimumScaleFactor(0.7)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface)
                            .overlay(alignment: .top) { Rectangle().fill(row.confirmed ? theme.color("surplusText") : theme.secondaryInk).frame(height: 3) }
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("money-log-search-result-" + row.id.uuidString)
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("money-log-search-results")
        }
    }
    private func load() {
        readingLoadTask?.cancel()
        let loadID = UUID()
        activeReadingLoadID = loadID
        withAnimation(MadarMotion.quick.animation(reduceMotion: reduceMotion)) { isRefreshing = true }
        routeRequestTracker.stage(initialRouteRequestID)
        let requestID = routeRequestTracker.pendingRequestID
        let appliesNewRoute = routeRequestTracker.hasPendingRequest
        if appliesNewRoute {
            source = nil
            initialRouteMissing = false
            filter = "all"
            query = ""
            searching = false
            month = nil
            selected = nil
        }
        let requestedMonth = appliesNewRoute ? nil : month
        let service = self.service
        readingLoadTask = Task { @MainActor in
            do {
                let loaded = try await service.loadLogOffMain(month: requestedMonth)
                try Task.checkCancellation()
                guard activeReadingLoadID == loadID else { return }
                if appliesNewRoute {
                    month = loaded.monthStart
                    selected = loaded.days.last { $0.day <= loaded.today }?.day ?? loaded.days.first?.day
                }
                let firstTransactionRoute = !initialRouteApplied && initialTransactionID != nil
                if (appliesNewRoute || firstTransactionRoute), let initialTransactionID {
                    if let movement = loaded.movements.first(where: { $0.id == initialTransactionID }) {
                        let targetMonth = service.logMonthStart(movement.day)
                        let routed = targetMonth == loaded.monthStart ? loaded : try await service.loadLogOffMain(month: targetMonth)
                        try Task.checkCancellation()
                        guard activeReadingLoadID == loadID else { return }
                        month = targetMonth
                        selected = movement.day
                        filter = "all"
                        query = ""
                        searching = false
                        reading = routed
                        source = movement.detail
                        initialRouteApplied = true
                    } else {
                        reading = loaded
                        initialRouteMissing = true
                        initialRouteApplied = true
                    }
                } else {
                    reading = loaded
                    if appliesNewRoute {
                        query = initialQuery ?? ""
                        searching = initialQuery != nil
                        initialRouteMissing = false
                        initialRouteApplied = true
                    } else if !initialRouteApplied {
                        if let initialQuery { query = initialQuery; searching = true }
                        initialRouteApplied = true
                    }
                    if selected == nil { selected = loaded.days.last { $0.day <= loaded.today }?.day ?? loaded.days.first?.day }
                }
                if appliesNewRoute { routeRequestTracker.markApplied(requestID) }
                failure = nil
                withAnimation(MadarMotion.quick.animation(reduceMotion: reduceMotion)) { isRefreshing = false }
            } catch {
                guard !Task.isCancelled, activeReadingLoadID == loadID else { return }
                reading = nil
                failure = "لم تكتمل قراءة السجل. حاول مرة أخرى."
                withAnimation(MadarMotion.quick.animation(reduceMotion: reduceMotion)) { isRefreshing = false }
            }
        }
    }
}
