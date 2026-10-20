import SwiftUI
import MadarCore
import MadarDesign
import MadarMoney

/// «التحليل» (`mal/22-Z-R18-ana-1`, `23-Z-R18-ana-1x`): the cycle or the week as a written report — the days as columns
/// against «يومك», where the spending went against each limit, the pace, the days kept within «يومك», and the merchants.
/// Reads the same ledger as «السجل» and V10's category definition; writes nothing.
struct MoneyAnalysisView: View {
    let app: AppSession
    @Binding var revealed: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var period: MoneyAnalysisPeriod?
    @State private var offset = 0
    @State private var reading: MoneyAnalysisReading?
    @State private var empty = false
    @State private var failure: String?
    @State private var selected: GregorianDay?
    @State private var grown = false
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var service: AppMoneyService { .init(app: app) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private func amount(_ n: Int) -> String { visible ? service.amount(n) : "•••" }
    /// Averages and «نحو» projections read in whole currency units; the halalas would claim a precision they lack.
    private func approx(_ n: Int) -> String {
        var scale = 1; for _ in 0..<(CurrencyExponents.specified.exponent(app.string("core.currency")) ?? 2) { scale *= 10 }
        return amount(AnalysisEngine.roundedDivision(n, by: scale) * scale)
    }
    private var current: MoneyAnalysisPeriod { period ?? (app.string("mal.analysisDefault") == "week" ? .week : .cycle) }
    private var gregorianFirst: Bool { app.string("core.firstCalendar") == "gregorian" }
    /// The binding colours of «التصنيفات والحدود», in category order, so a category looks the same on both screens.
    private func tint(_ index: Int?) -> Color {
        guard let index else { return theme.color("rod") }
        return [theme.color("reserveText"), theme.color("surplus"), theme.color("accent"), theme.color("bills"), theme.secondaryInk][index % 5]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if !empty { periodPicker }
                if let reading {
                    summary(reading)
                    if !visible { Button("أظهر الأرقام") { revealed = true }.font(MadarTypography.caption()).frame(minHeight: 44).accessibilityIdentifier("money-analysis-reveal") }
                    chart(reading)
                    DoubleRule().stroke(theme.color("reserveText"), lineWidth: 0.8).frame(height: 3).padding(.vertical, 4)
                    categories(reading)
                    cards(reading)
                    merchants(reading)
                } else if empty { emptyPage }
                else if let failure { Text(failure).font(MadarTypography.body()); Button("أعِد المحاولة", action: load).frame(minHeight: 44) }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 240) }
            }.padding(.horizontal, 16).padding(.bottom, 30).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
            .task { load() }.onChange(of: app.prayerRevision) { load() }
            .accessibilityIdentifier("money-analysis")
    }

    // MARK: Header, period

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3).frame(width: 52, height: 52).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1.2) } }
                .buttonStyle(.plain).accessibilityLabel("إغلاق").accessibilityIdentifier("money-analysis-close")
            Text("التحليل").font(.custom("thmanyahserifdisplay-Bold", size: 28, relativeTo: .title)).accessibilityAddTraits(.isHeader)
            Spacer()
        }.padding(.top, 8)
    }
    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach([MoneyAnalysisPeriod.week, .cycle]) { p in
                Button { guard p != current else { return }; period = p; offset = 0; selected = nil; load() } label: {
                    Text(p == .week ? "الأسبوع" : "الدورة").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 44)
                        .background(p == current ? theme.ink : Color.clear, in: Capsule()).foregroundStyle(p == current ? theme.background : theme.ink)
                }.buttonStyle(.plain).accessibilityAddTraits(p == current ? .isSelected : []).accessibilityIdentifier("money-analysis-period-" + p.rawValue)
            }
        }.padding(4).background(theme.color("glass"), in: Capsule())
    }

    // MARK: The headline

    private func rangeLabels(_ r: MoneyAnalysisReading) -> MadarDateLabels {
        let a = app.dateLabels(r.first, compact: true), b = app.dateLabels(r.last, compact: true)
        return .init(primary: a.primary + " ← " + b.primary, secondary: a.secondary + " ← " + b.secondary)
    }
    private func summary(_ r: MoneyAnalysisReading) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                let range = rangeLabels(r)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title + "، " + range.primary).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    Text(range.secondary).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("money-analysis-range")
                Spacer(minLength: 4)
                Button { offset -= 1; selected = nil; load() } label: { Image(systemName: "chevron.backward").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain).disabled(!r.canGoBack).opacity(r.canGoBack ? 1 : 0.3).accessibilityLabel(r.period == .week ? "الأسبوع السابق" : "الدورة السابقة").accessibilityIdentifier("money-analysis-previous")
                Button { offset = min(0, offset + 1); selected = nil; load() } label: { Image(systemName: "chevron.forward").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain).disabled(r.offset >= 0).opacity(r.offset < 0 ? 1 : 0.3).accessibilityLabel(r.period == .week ? "الأسبوع التالي" : "الدورة التالية").accessibilityIdentifier("money-analysis-next")
            }
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(figure: amount(r.spentMinor)).font(.custom("thmanyahserifdisplay-Black", size: 62, relativeTo: .largeTitle)).lineLimit(1).minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                    VStack(alignment: .leading, spacing: 0) {
                        Text("من " + amount(r.allowanceMinor)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        if r.running { Text("حتى اليوم").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                    }.fixedSize()
                }.accessibilityElement(children: .combine).accessibilityLabel("صرفت من يومك " + amount(r.spentMinor) + " من " + amount(r.allowanceMinor) + (r.running ? " حتى اليوم" : "")).accessibilityIdentifier("money-analysis-spent")
                Spacer(minLength: 6)
                if let c = r.comparison { comparisonBox(c) }
            }
        }
    }
    private func comparisonBox(_ c: MoneyAnalysisComparison) -> some View {
        let tone = !visible ? theme.line : c.percent < 0 ? theme.color("surplusText") : c.percent > 0 ? theme.color("dueText") : theme.ink
        let value = c.percent == 0 ? "كما هو" : (c.percent < 0 ? "−" : "+") + service.digits.string(abs(c.percent)) + "٪"
        return VStack(spacing: 2) {
            Text(visible ? value : "•••").font(.custom("thmanyahserifdisplay-Bold", size: 26, relativeTo: .title2)).foregroundStyle(visible ? tone : theme.secondaryInk).environment(\.layoutDirection, .leftToRight)
            Text(c.label).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: 150)
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(tone.opacity(0.85), lineWidth: 1.2) }
            .accessibilityElement(children: .combine).accessibilityIdentifier("money-analysis-compare")
    }

    // MARK: Days against «يومك»

    private func chosen(_ r: MoneyAnalysisReading) -> MoneyLogDay? {
        r.days.first { $0.day == selected } ?? r.days.last { $0.day <= r.today } ?? r.days.first
    }
    @ViewBuilder private func chart(_ r: MoneyAnalysisReading) -> some View {
        if dynamicType.isAccessibilitySize {
            VStack(spacing: 8) {
                ForEach(r.days.filter { $0.day <= r.today }) { d in
                    HStack { MadarDateLabel(app.dateLabels(d.day, weekday: true)); Spacer(); Text(figure: amount(d.spentMinor) + " من " + (d.dailyMinor.map(amount) ?? "غير معروف")) }.font(MadarTypography.body())
                }
            }.accessibilityIdentifier("money-analysis-days")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                bars(r).frame(height: r.period == .week ? 178 : 196)
                if let d = chosen(r) { dayLine(d, r) }
            }
        }
    }
    private func bars(_ r: MoneyAnalysisReading) -> some View {
        let line = r.dailyLineMinor
        let peak = max(r.days.map(\.spentMinor).max() ?? 0, line ?? 0, 1)
        let scale = Double(peak) * 1.12
        let week = r.period == .week
        return GeometryReader { proxy in
            let labelBand: CGFloat = 22, axis: CGFloat = week ? 22 : 34
            let plot = proxy.size.height - labelBand - axis - 4
            let gap: CGFloat = week ? 10 : 3, count = CGFloat(max(1, r.days.count))
            // Every column the same width; labels may overflow their column without widening it.
            let column = max(2, (proxy.size.width - gap * (count - 1)) / count)
            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(Array(r.days.enumerated()), id: \.element.id) { index, d in
                        bar(d, index: index, r: r, scale: scale, plot: plot, labelBand: labelBand, axis: axis, line: line).frame(width: column)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if let line, visible {
                    let y = labelBand + plot - plot * CGFloat(Double(line) / scale)
                    DashLine().stroke(theme.color("reserveText"), style: .init(lineWidth: 1, dash: [4, 3])).frame(height: 1).offset(y: y).allowsHitTesting(false)
                    Text(figure: amount(line) + " يوميًا").font(MadarTypography.fine()).foregroundStyle(theme.color("reserveText"))
                        .padding(.horizontal, 3).background(theme.background.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .trailing).offset(y: y - 18).allowsHitTesting(false).accessibilityIdentifier("money-analysis-line")
                }
                Rectangle().fill(theme.ink).frame(height: 1.5).offset(y: labelBand + plot).allowsHitTesting(false)
            }
        }.onAppear { if reduceMotion { grown = true } else { withAnimation(.easeOut(duration: 0.55)) { grown = true } } }
            .accessibilityElement(children: .contain).accessibilityIdentifier("money-analysis-chart")
    }
    private func bar(_ d: MoneyLogDay, index: Int, r: MoneyAnalysisReading, scale: Double, plot: CGFloat, labelBand: CGFloat, axis: CGFloat, line: Int?) -> some View {
        let week = r.period == .week
        let future = d.day > r.today
        let over = !future && d.within == .missed
        let isSelected = chosen(r)?.day == d.day
        let height = visible && !future ? max(d.spentMinor > 0 ? 3 : 0, plot * CGFloat(Double(max(0, d.spentMinor)) / scale)) : 0
        let fill = over ? theme.color("due") : d.within == .pending ? theme.secondaryInk.opacity(0.45) : theme.color("surplus")
        let showLabel = visible && !future && (week || over || isSelected)
        let pair = DualDate(instant: d.day.date(in: app.activePlace.timeZone).addingTimeInterval(43200), timeZone: app.activePlace.timeZone,
                            source: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(app.number("core.hijriOffset")))
        let primaryDay = gregorianFirst ? pair.gregorian.day : pair.hijri.day, secondaryDay = gregorianFirst ? pair.hijri.day : pair.gregorian.day
        return Button { selected = d.day } label: {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(showLabel ? amount(d.spentMinor) : " ").font(week ? MadarTypography.section() : .custom("thmanyahsans-Bold", size: 11, relativeTo: .caption2))
                    .foregroundStyle(over ? theme.color("dueText") : theme.ink).lineLimit(1).fixedSize().frame(height: 18).padding(.bottom, 3)
                ZStack(alignment: .bottom) {
                    if future, let line, visible {
                        UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3).stroke(theme.line, style: .init(lineWidth: 1, dash: [3, 3]))
                            .frame(height: plot * CGFloat(Double(line) / scale))
                    }
                    UnevenRoundedRectangle(topLeadingRadius: week ? 4 : 2, topTrailingRadius: week ? 4 : 2).fill(fill)
                        .frame(height: grown ? height : 0)
                        .overlay { if isSelected && !future { UnevenRoundedRectangle(topLeadingRadius: week ? 4 : 2, topTrailingRadius: week ? 4 : 2).stroke(theme.color("reserve"), lineWidth: week ? 2.5 : 1.5) } }
                }.frame(height: min(plot, max(height, future && visible ? plot * CGFloat(Double(line ?? 0) / scale) : 0, 1)), alignment: .bottom)
                VStack(spacing: 0) {
                    if week { Text(weekday(d.day)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.7) }
                    else if index % 5 == 0 || d.day == r.last {
                        Text(service.digits.string(primaryDay)).font(MadarTypography.fine()).fixedSize()
                        Text(service.digits.string(secondaryDay)).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.secondaryInk).fixedSize()
                    }
                }.frame(height: axis, alignment: .top).padding(.top, 4)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(app.dateLabels(d.day, weekday: true).combined + "، " + (future ? "يوم قادم" : "صرفت " + amount(d.spentMinor) + " من " + (d.dailyMinor.map(amount) ?? "يومية غير معروفة")) + (d.pending > 0 ? "، يحتاج قرارًا" : ""))
            .accessibilityAddTraits(isSelected ? .isSelected : []).accessibilityIdentifier("money-analysis-day-" + d.id)
    }
    private func dayLine(_ d: MoneyLogDay, _ r: MoneyAnalysisReading) -> some View {
        let labels = app.dateLabels(d.day, compact: true, weekday: true)
        let judgement: (String, Color) = {
            guard d.day <= r.today else { return ("لم يأتِ بعد", theme.secondaryInk) }
            guard let daily = d.dailyMinor else { return ("لا يومية معروفة لهذا اليوم", theme.secondaryInk) }
            if d.pending > 0 { return ("معلّق حتى تقرّر في رسائله", theme.secondaryInk) }
            guard visible else { return ("من " + amount(daily), theme.secondaryInk) }
            let gap = d.spentMinor - daily
            return gap > 0 ? ("فوق يومك بـ" + amount(gap), theme.color("dueText")) : gap == 0 ? ("على يومك تمامًا", theme.color("surplusText")) : ("دون يومك بـ" + amount(-gap), theme.color("surplusText"))
        }()
        return HStack(alignment: .center, spacing: 10) {
            Rectangle().fill(theme.color("reserve")).frame(width: 3).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(labels.primary).font(MadarTypography.section())
                Text(labels.secondary).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                if d.day <= r.today { Text(figure: amount(d.spentMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title3)) }
                Text(judgement.0).font(MadarTypography.fine()).foregroundStyle(judgement.1)
            }
        }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 2)
            .accessibilityElement(children: .combine).accessibilityIdentifier("money-analysis-selected")
    }
    private func weekday(_ day: GregorianDay) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ar_SA"); f.timeZone = app.activePlace.timeZone; f.dateFormat = "EEEE"
        return f.string(from: day.date(in: app.activePlace.timeZone).addingTimeInterval(43200)).replacingOccurrences(of: "ال", with: "", options: .anchored)
    }

    // MARK: Where the spending went

    private func categories(_ r: MoneyAnalysisReading) -> some View {
        let rows = r.categories, positive = rows.filter { $0.spentMinor > 0 }
        let total = max(1, positive.reduce(0) { $0 + $1.spentMinor })
        let scale = max(1, rows.map { max($0.spentMinor, $0.capMinor ?? 0) }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text("أين راح صرفك؟").font(.custom("Amiri-Bold", size: 27, relativeTo: .title2)).accessibilityAddTraits(.isHeader)
                Spacer()
                if rows.contains(where: { $0.capMinor != nil }) {
                    HStack(spacing: 4) { Rectangle().fill(theme.ink).frame(width: 2, height: 12); Text(r.period == .week ? "الخط = حصة الأسبوع من الحد" : "الخط = الحد") }
                        .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }
            }
            if rows.isEmpty {
                Text(r.running ? "لا مصروف مسجّل في هذه الفترة بعد." : "لا مصروف مسجّل في هذه الفترة.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-analysis-categories-empty")
            } else {
                if visible {
                    GeometryReader { proxy in
                        HStack(spacing: 2) {
                            ForEach(positive) { c in Rectangle().fill(tint(c.tint)).frame(width: max(2, (proxy.size.width - CGFloat(positive.count - 1) * 2) * CGFloat(c.spentMinor) / CGFloat(total))) }
                        }
                    }.frame(height: 20).accessibilityHidden(true)
                }
                ForEach(rows) { c in categoryRow(c, scale: scale) }
                if r.categoriesTotalMinor != r.spentMinor {
                    Text("المجموع " + amount(r.categoriesTotalMinor) + "، ويشمل ما صُرف من المظاريف لا من يومك وحده.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("money-analysis-categories")
    }
    private func categoryRow(_ c: MoneyAnalysisCategory, scale: Int) -> some View {
        let gap = c.capMinor.map { c.spentMinor - $0 }
        return HStack(spacing: 10) {
            Text(c.name).font(.custom("thmanyahsans-Bold", size: 17, relativeTo: .body)).lineLimit(1).minimumScaleFactor(0.75).frame(width: 92, alignment: .leading)
            GeometryReader { proxy in
                let w = proxy.size.width
                // Drawn left-to-right with trailing alignment, so the bar grows from the right edge as Arabic reads.
                ZStack(alignment: .trailing) {
                    Rectangle().fill(theme.color("glass")).frame(height: 18)
                    Rectangle().fill(tint(c.tint)).frame(width: visible ? max(2, w * CGFloat(max(0, c.spentMinor)) / CGFloat(scale)) : 0, height: 18)
                    if let cap = c.capMinor, visible {
                        Rectangle().fill(theme.ink).frame(width: 2, height: 26).offset(x: -max(0, min(w - 2, w * CGFloat(cap) / CGFloat(scale) - 1)))
                    }
                }.frame(width: w, height: 26).environment(\.layoutDirection, .leftToRight)
            }.frame(height: 26)
            Text(figure: amount(c.spentMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .body)).lineLimit(1).minimumScaleFactor(0.7).frame(width: 66, alignment: .trailing)
            Group {
                if let gap, visible { Text((gap > 0 ? "+" : gap < 0 ? "−" : "") + approx(abs(gap))).foregroundStyle(gap > 0 ? theme.color("dueText") : theme.color("surplusText")).environment(\.layoutDirection, .leftToRight) }
                else if gap == nil { Text("بلا حد").foregroundStyle(theme.secondaryInk) }
                else { Text("•••") }
            }.font(.custom("thmanyahsans-Bold", size: 13, relativeTo: .caption)).lineLimit(1).minimumScaleFactor(0.7).frame(width: 50, alignment: .trailing)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(c.name + "، " + amount(c.spentMinor) + (c.capMinor.map { "، الحد " + amount($0) } ?? "، بلا حد") + (gap.map { visible ? ($0 > 0 ? "، فوقه بـ" + service.amount($0) : "، دونه بـ" + service.amount(-$0)) : "" } ?? ""))
            .accessibilityIdentifier("money-analysis-category-" + c.name)
    }

    // MARK: Pace and days within «يومك»

    private func cards(_ r: MoneyAnalysisReading) -> some View {
        Group {
            if dynamicType.isAccessibilitySize { VStack(spacing: 12) { paceCard(r); withinCard(r) } }
            else { HStack(alignment: .top, spacing: 12) { paceCard(r).frame(maxWidth: .infinity); withinCard(r).frame(maxWidth: .infinity) }.fixedSize(horizontal: false, vertical: true) }
        }
    }
    private func card<Content: View>(_ title: String, id: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(MadarTypography.section())
            content()
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(theme.color("surface2"))
            .overlay { RoundedRectangle(cornerRadius: 3).stroke(theme.line, lineWidth: 1.2) }
            .accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }
    private func paceCard(_ r: MoneyAnalysisReading) -> some View {
        card("وتيرتك", id: "money-analysis-pace") {
            if let pace = r.pace {
                if !dynamicType.isAccessibilitySize {
                    PaceGauge(ratio: visible && pace.averageDailyMinor > 0 ? Double(pace.averageSpentMinor) / Double(pace.averageDailyMinor) : 1, under: theme.color("surplus"), over: theme.color("due"),
                              needle: theme.ink, track: theme.color("glass"), animate: !reduceMotion)
                        .frame(height: 82).frame(maxWidth: .infinity).accessibilityHidden(true)
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(approx(pace.averageSpentMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 20, relativeTo: .title3))
                        Text("متوسط صرفك").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(approx(pace.averageDailyMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 20, relativeTo: .title3)).foregroundStyle(theme.color("reserveText"))
                        Text("يومك").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    }
                }
                if let left = pace.projectedLeftMinor {
                    Text(left >= 0 ? "على هذه الوتيرة يبقى من يومياتك نحو " + approx(left) + " عند الراتب" : "على هذه الوتيرة تتجاوز يومياتك بنحو " + approx(-left) + " عند الراتب")
                        .font(MadarTypography.fine()).foregroundStyle(left >= 0 ? theme.color("surplusText") : theme.color("dueText")).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("money-analysis-projection")
                }
            } else {
                Text("تظهر الوتيرة بعد " + service.dayCount(AnalysisEngine.minimumPaceDays) + " معروفة النتيجة.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func withinCard(_ r: MoneyAnalysisReading) -> some View {
        card("ضمن يومك", id: "money-analysis-within") {
            if r.judgedDays > 0 {
                HStack {
                    Spacer()
                    ZStack {
                        Circle().stroke(theme.color("glass"), lineWidth: 9)
                        Circle().trim(from: 0, to: visible ? CGFloat(r.metDays) / CGFloat(r.judgedDays) : 0).stroke(theme.color("reserve"), style: .init(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                            .overlay { Circle().trim(from: 0, to: visible ? CGFloat(r.metDays) / CGFloat(r.judgedDays) : 0).stroke(theme.color("reserveText"), lineWidth: 0.6).rotationEffect(.degrees(-90)) }
                        VStack(spacing: 0) {
                            Text(visible ? service.digits.string(r.metDays) : "•••").font(.custom("thmanyahserifdisplay-Black", size: 32, relativeTo: .title))
                            Text("من " + (visible ? service.dayCount(r.judgedDays) : "•••")).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        }
                    }.frame(width: 104, height: 104)
                    Spacer()
                }
                Text(r.pendingDays > 0 ? "معلّق حتى تقرّر: " + service.dayCount(r.pendingDays) : r.running ? "من الأيام المنقضية" : "من أيام الفترة")
                    .font(MadarTypography.fine()).foregroundStyle(r.pendingDays > 0 ? theme.secondaryInk : theme.color("surplusText")).frame(maxWidth: .infinity)
            } else {
                Text("لا يوم مكتمل الحكم في هذه الفترة بعد.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Merchants

    private func merchants(_ r: MoneyAnalysisReading) -> some View {
        let top = r.merchants, peak = max(1, top.first?.amountMinor ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("أكثر من صرفت عندهم").font(MadarTypography.section()).foregroundStyle(theme.secondaryInk).accessibilityAddTraits(.isHeader)
            if top.isEmpty {
                Text("لا متجر في هذه الفترة بعد.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, m in
                        VStack(spacing: 4) {
                            Text(figure: amount(m.amountMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .body)).lineLimit(1).minimumScaleFactor(0.6)
                            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                                .fill(index == 0 ? theme.color("reserve") : theme.color("glass").mix(with: theme.color("reserve"), by: 0.18))
                                .overlay { if index == 0 { UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16).stroke(theme.color("reserveText"), lineWidth: 1) } }
                                .frame(height: visible ? 22 + 32 * CGFloat(m.amountMinor) / CGFloat(peak) : 36)
                            Text(m.name).font(.custom("thmanyahsans-Bold", size: 13, relativeTo: .caption)).lineLimit(1).minimumScaleFactor(0.7)
                            Text(visible ? service.times(m.count) : "•••").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(1)
                        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine).accessibilityIdentifier("money-analysis-merchant-" + m.name)
                    }
                    ForEach(top.count..<5, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                }
            }
        }.padding(.top, 6)
    }

    private var emptyPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "chart.bar.xaxis").font(.title2).foregroundStyle(theme.color("reserveText"))
            Text("يبدأ التحليل مع دورتك الأولى").font(MadarTypography.cardTitle())
            Text("حين ينزل الراتب ويُضبط يومك، تظهر هنا أيامك أمام يومك، وأين ذهب صرفك، ومن صرفت عندهم أكثر. لا أرقام قبل أن تكون لها بيانات.")
                .font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface).accessibilityIdentifier("money-analysis-empty")
    }

    private func load() {
        do {
            let next = try service.loadAnalysis(period: current, offset: offset)
            reading = next; empty = next == nil; failure = nil
            if let next { offset = next.offset }
        } catch { reading = nil; empty = false; failure = "لم تكتمل قراءة التحليل. حاول مرة أخرى." }
    }
}

/// «وتيرتك»: a half dial from «لا شيء» to twice «يومك»; the needle stands upright when the average equals «يومك».
private struct PaceGauge: View {
    var ratio: Double
    var under: Color
    var over: Color
    var needle: Color
    var track: Color
    var animate: Bool
    @State private var shown = false
    var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width / 2, proxy.size.height) - 8
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height - 4)
            let clamped = min(2, max(0, shown ? ratio : 1))
            ZStack {
                Arc(from: 180, to: 360, center: center, radius: radius).stroke(track, style: .init(lineWidth: 14))
                // Read right to left like the page: «دون يومك» on the right, «فوقه» on the left.
                Arc(from: 270, to: 360, center: center, radius: radius).stroke(under, style: .init(lineWidth: 14))
                Arc(from: 180, to: 270, center: center, radius: radius).stroke(over.opacity(0.55), style: .init(lineWidth: 14))
                Path { p in
                    let angle = Angle.degrees(360 - 90 * clamped).radians
                    p.move(to: center); p.addLine(to: CGPoint(x: center.x + cos(angle) * (radius - 4), y: center.y + sin(angle) * (radius - 4)))
                }.stroke(needle, style: .init(lineWidth: 2.5, lineCap: .round))
                Circle().fill(needle).frame(width: 11, height: 11).position(center)
            }.environment(\.layoutDirection, .leftToRight)
        }.onAppear { if animate { withAnimation(.spring(duration: 0.8, bounce: 0.25)) { shown = true } } else { shown = true } }
    }
    private struct Arc: Shape {
        var from: Double, to: Double, center: CGPoint, radius: CGFloat
        func path(in rect: CGRect) -> Path { Path { p in p.addArc(center: center, radius: radius, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false) } }
    }
}
