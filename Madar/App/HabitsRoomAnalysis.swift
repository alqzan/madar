import SwiftUI
import MadarCore
import MadarCommands
import MadarDesign

/// The habits room, set as the approved canvas «Habits» (owner order, 17 Nov 2026): the row's ring and its seven beads, the
/// story card of a chosen habit, «ما لاحظه مدار» and the year. Every number is read from the habits' own periods and log times
/// through `HabitRoomInsights`; below AX1 each drawing is replaced by its list.

private let habitWeekdayNames = ["الأحد", "الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"]
private let habitWeekdayLetters = ["ح", "ن", "ث", "ر", "خ", "ج", "س"]

/// A row's ring (canvas: a 46 pt disc that fills with the habit's room colour when done, its own glyph inside).
struct HabitRowRing: View {
    let share: Double; let done: Bool; let colour: Color; let symbol: String?; let glyph: String?
    @Environment(\.roomTheme) private var theme
    var body: some View {
        ZStack {
            Circle().fill(done ? colour : theme.surface)
            Circle().stroke(colour.opacity(0.18), lineWidth: 3)
            Circle().trim(from: 0, to: done ? 1 : min(1, max(0, share))).stroke(colour, style: .init(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90)).scaleEffect(x: -1)
            if let symbol { MadarGlyph(symbol, size: 18).foregroundStyle(done ? theme.surface : colour) }
            else if let glyph { Image(systemName: glyph).font(.system(size: 17, weight: .medium)).foregroundStyle(done ? theme.surface : colour) }
            else if done { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(theme.surface) }
            else { Circle().fill(colour.opacity(0.5)).frame(width: 7, height: 7) }
        }.padding(1.5).frame(width: 46, height: 46).accessibilityHidden(true)
    }
}

/// The last seven periods of a habit as seven small beads, the newest last: kept, started, or empty.
struct HabitRowDots: View {
    let periods: [HabitPeriodResult]; let colour: Color
    @Environment(\.roomTheme) private var theme
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(periods.suffix(7).enumerated()), id: \.offset) { _, p in
                Circle().fill(p.met ? colour : p.value > 0 ? colour.opacity(0.45) : .clear)
                    .overlay { if !p.met && p.value == 0 { Circle().stroke(theme.ink.opacity(0.3), lineWidth: 1.2) } }
                    .frame(width: 6, height: 6)
            }
        }.accessibilityHidden(true)
    }
}

/// The dark card of a chosen habit: when it began, how long it has run, and its longest streak, read from its periods.
struct HabitStoryCard: View {
    let reading: HabitReading; let rule: String; let digits: MadarNumberFormatter
    let started: MadarDateLabels; let longestDate: MadarDateLabels?
    let today: GregorianDay
    var breakAfter = 2
    let clear: () -> Void; let details: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.roomTheme) private var theme
    /// The story card is the room's ink on paper (light) or its raised surface (dark); text takes the opposite role.
    private var ink: Color { colorScheme == .dark ? theme.ink : theme.background }
    private var card: Color { colorScheme == .dark ? theme.surface : theme.ink }
    private var frequency: HabitFrequency { reading.summary.current?.rule.frequency ?? .daily }
    private var longest: (length: Int, end: GregorianDay)? { HabitRoomInsights.longestStreak(reading.summary.periods, today: today, breakAfter: breakAfter) }
    private var kept: Int { HabitRoomInsights.keptPeriods(reading.summary.periods).kept }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("قصة العادة").font(HabitType.fine()).foregroundStyle(ink.opacity(0.64))
                    Text(reading.name).font(HabitType.title()).fixedSize(horizontal: false, vertical: true)
                    if !rule.isEmpty { Text(rule).font(HabitType.caption()).foregroundStyle(ink.opacity(0.72)).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    Button(action: clear) { pill("كل العادات") }.buttonStyle(.madarPlain).accessibilityIdentifier("habit-story-clear")
                    Button(action: details) { pill("التفاصيل") }.buttonStyle(.madarPlain).accessibilityIdentifier("habit-story-details")
                }
            }
            HStack(alignment: .top, spacing: 10) {
                stat("بدأتها", started.primary, started.secondary)
                stat("منذ بدأت", habitPeriodCount(max(1, MadarCalendarDays.distance(from: reading.firstEffectiveFrom, to: today) + 1), .daily, digits),
                     kept == 0 ? "لم تُتمّها بعد" : "أتممتها في " + habitPeriodCount(kept, frequency, digits))
                stat("أطول سلسلة", longest.map { habitPeriodCount($0.length, frequency, digits) } ?? "لا سلسلة بعد", longestDate.map { "حتى " + $0.primary + "، " + $0.secondary } ?? "")
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(card, in: .rect(cornerRadius: 26)).foregroundStyle(ink)
        .accessibilityElement(children: .contain).accessibilityIdentifier("habit-story")
    }
    private func pill(_ title: String) -> some View {
        Text(title).font(HabitType.caption()).padding(.horizontal, 14).frame(minHeight: 44).overlay(Capsule().stroke(ink.opacity(0.24))).contentShape(.capsule)
    }
    private func stat(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(HabitType.fine()).foregroundStyle(ink.opacity(0.64))
            Text(value).font(HabitType.section()).fixedSize(horizontal: false, vertical: true)
            if !sub.isEmpty { Text(sub).font(HabitType.fine()).foregroundStyle(ink.opacity(0.64)).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One period card's text while a habit is chosen.
struct HabitCardModel { let title: String; let count: String; let share: Double; let frequency: HabitFrequency }

/// «ما لاحظه مدار» and the year: everything below the orbit, for all habits or for the chosen one.
struct HabitRoomAnalysis: View {
    let readings: [HabitReading]
    let selected: UUID?
    let session: AppSession
    let digits: MadarNumberFormatter
    let theme: RoomTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var service: AppBahwService { AppBahwService(session: session) }
    private var today: GregorianDay { service.today }
    private var zone: TimeZone { session.activePlace.timeZone }
    private var hijriFirst: Bool { session.string("core.firstCalendar") == "hijri" }
    private var weekStart: MadarWeekStart { service.weekStart }
    private var series: [HabitRoomSeries] { readings.map { .init(id: $0.id, periods: $0.summary.periods, doneDays: $0.times.map(\.day), loggedAt: $0.loggedAt) } }
    private var chosen: HabitReading? { selected.flatMap { id in readings.first { $0.id == id } } }
    private var scope: [HabitRoomSeries] { selected.map { id in series.filter { $0.id == id } } ?? series }
    private var chosenIsLonger: Bool { chosen.map { ($0.summary.current?.rule.band ?? .daily) != .daily } ?? false }
    private func percent(_ v: Double) -> String { digits.percent(Int((v * 100).rounded())) }
    private func hour(_ h: Int) -> String { digits.string(h % 12 == 0 ? 12 : h % 12) + (h % 24 < 12 ? " ص" : " م") }
    private func names(_ weekdays: [Int]) -> String { weekdays.map { habitWeekdayNames[$0 - 1] }.joined(separator: " و") }

    var body: some View {
        let hours = HabitRoomInsights.hourBuckets(scope.flatMap(\.loggedAt), zone: zone)
        let weekly = chosenIsLonger ? HabitRoomInsights.periodRates(chosen?.summary.periods ?? [], today: today) : HabitRoomInsights.weeklyRates(scope, today: today)
        let stats = chosenIsLonger ? HabitRoomInsights.weekdayShares(chosen?.times.map(\.day) ?? []) : HabitRoomInsights.weekdayRates(scope, today: today)
        VStack(alignment: .leading, spacing: 20) {
            noticed(hours: hours, trend: weekly, stats: stats)
            year
        }
    }

    // MARK: ما لاحظه مدار

    @ViewBuilder private func noticed(hours: [Int], trend rates: [Double?], stats: [HabitRoomInsights.WeekdayStat]) -> some View {
        let peak = HabitRoomInsights.peak(hours), trend = HabitRoomInsights.trend(rates)
        let weakest = chosenIsLonger ? nil : HabitRoomInsights.weakestWeekdays(stats), dominant = chosenIsLonger ? HabitRoomInsights.dominantWeekday(stats) : nil
        let weekdaysReady = stats.count == 7 && stats.allSatisfy { $0.rate != nil && (chosenIsLonger ? $0.samples >= 4 : $0.samples >= 3) }
        if peak != nil || trend != nil || weekdaysReady {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle").foregroundStyle(theme.accent)
                    Text("ما لاحظه مدار").font(HabitType.cardTitle())
                }.padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
                if let peak { hoursCard(hours, peak) }
                if let trend { trendCard(rates, trend) }
                if weekdaysReady { weekdaysCard(stats, weakest: weakest, dominant: dominant) }
            }.accessibilityIdentifier("habits-noticed")
        }
    }
    private func card<C: View>(_ label: String, _ text: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label).font(HabitType.fine()).foregroundStyle(theme.secondaryInk)
            Text(text).font(HabitType.section()).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            content()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 24))
    }

    private func hoursCard(_ hours: [Int], _ peak: HabitRoomInsights.Peak) -> some View {
        let morning = HabitRoomInsights.morningShare(hours)
        var text = (chosen == nil ? "تسجّل غالبًا من " : "تسوّيها غالبًا من ") + hour(peak.from) + " إلى " + hour(peak.to) + "."
        if chosen == nil, let morning {
            if morning >= 0.6 { text += " صباحك أقوى: " + percent(morning) + " مما تنجزه قبل الظهر." }
            else if morning <= 0.4 { text += " مساؤك أقوى: " + percent(1 - morning) + " مما تنجزه بعد الظهر." }
        }
        let top = max(1, hours.max() ?? 1)
        return card("متى تسويها", text) {
            if dynamicTypeSize.isAccessibilitySize {
                ForEach(Array(hours.enumerated()).filter { $0.element > 0 }, id: \.offset) { i, n in
                    Text(hour(6 + i) + ": " + arabicCount(n, ["مرة واحدة", "مرتان", "مرات", "مرة"], digits)).font(HabitType.caption())
                }
            } else {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(hours.enumerated()), id: \.offset) { _, n in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(n == top ? theme.accent : Double(n) >= Double(top) / 2 ? theme.accentFill.opacity(0.6) : theme.accentFill.opacity(0.24))
                            .frame(height: max(4, 56 * CGFloat(n) / CGFloat(top)))
                    }
                }.frame(height: 56, alignment: .bottom).accessibilityHidden(true).animation(reduceMotion ? nil : .smooth(duration: 0.4), value: hours)
                HStack { ForEach([6, 12, 18, 23], id: \.self) { h in Text(hour(h)).font(HabitType.fine()).foregroundStyle(theme.secondaryInk); if h != 23 { Spacer() } } }
            }
        }.accessibilityIdentifier("habits-hours")
    }

    private func trendCard(_ rates: [Double?], _ trend: HabitRoomInsights.Trend) -> some View {
        let unit = !chosenIsLonger ? "أسابيع" : { switch chosen?.summary.current?.rule.band ?? .weekly { case .monthly: "أشهر"; case .yearly: "سنوات"; default: "فترات" } }()
        var text: String
        switch trend {
        case .rising(let a, let b): text = "التزامك يرتفع، من " + percent(a) + " إلى " + percent(b) + "."
        case .falling(let a, let b): text = "التزامك ينزل، من " + percent(a) + " إلى " + percent(b) + ". هدف أصغر أو سؤال في وقت آخر قد يعيدك."
        case .steady(let v): text = "التزامك ثابت قرابة " + percent(v) + "."
        }
        if chosen == nil, let m = HabitRoomInsights.mover(series, today: today), let name = readings.first(where: { $0.id == m.id })?.name {
            text += " " + name + (m.rising ? " تتحسّن" : " تتراجع") + ": من " + percent(m.before) + " إلى " + percent(m.now) + " في آخر أسبوعين."
        }
        let falling: Bool = { if case .falling = trend { return true } else { return false } }()
        return card("نسبة التزامك، آخر " + digits.string(8) + " " + unit, text) {
            if dynamicTypeSize.isAccessibilitySize {
                ForEach(Array(rates.enumerated()).compactMap { i, r in r.map { (i, $0) } }, id: \.0) { _, r in Text(percent(r)).font(HabitType.caption()) }
            } else {
                HabitTrendLine(values: rates, colour: falling ? theme.risk : theme.accent, fill: theme.accentFill.opacity(0.14), ring: theme.surface)
                    .frame(height: 70).accessibilityHidden(true)
            }
        }.accessibilityIdentifier("habits-trend")
    }

    private func weekdaysCard(_ stats: [HabitRoomInsights.WeekdayStat], weakest: [Int]?, dominant: Int?) -> some View {
        let order = weekStart == .saturday ? [7, 1, 2, 3, 4, 5, 6] : [1, 2, 3, 4, 5, 6, 7]
        let who = chosen == nil ? "في كل العادات" : ""
        var text: String
        if chosenIsLonger {
            if let dominant, let share = stats.first(where: { $0.weekday == dominant })?.rate { text = "يوم " + habitWeekdayNames[dominant - 1] + " يوم هذه العادة: " + percent(share) + " من مرّاتها فيه." }
            else { text = "لا يوم تفضّله هذه العادة؛ تتوزّع على أيام الأسبوع." }
        } else if let weakest {
            let rate = stats.first { $0.weekday == weakest[0] }?.rate ?? 0
            text = weakest.count == 2 ? names(weakest) + " أضعف أيامك" + (who.isEmpty ? "" : " " + who) + "." : habitWeekdayNames[weakest[0] - 1] + " أضعف أيامك" + (chosen == nil ? " " + who : "") + ": " + (chosen == nil ? "تتمّ فيه " : "تفعلها فيه ") + percent(rate) + " فقط."
        } else { text = "لا يوم ضعيف عندك؛ التزامك متقارب طوال الأسبوع." }
        let rates = order.map { w in stats.first { $0.weekday == w }?.rate ?? 0 }
        let top = max(rates.max() ?? 1, 0.0001), low = rates.min() ?? 0
        return card("أيام الأسبوع", text) {
            if dynamicTypeSize.isAccessibilitySize {
                ForEach(order, id: \.self) { w in Text(habitWeekdayNames[w - 1] + ": " + percent(stats.first { $0.weekday == w }?.rate ?? 0)).font(HabitType.caption()) }
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(order.enumerated()), id: \.offset) { i, w in
                        let v = rates[i]
                        let fill: Color = chosenIsLonger ? (v == top ? theme.accent : theme.accentFill.opacity(0.4))
                            : (weakest?.contains(w) == true && v == low ? theme.risk : theme.accentFill.opacity(0.55))
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 7).fill(fill).frame(height: max(5, 66 * CGFloat(chosenIsLonger ? v / top : v)))
                            Text(habitWeekdayLetters[w - 1]).font(HabitType.fine()).foregroundStyle(theme.secondaryInk)
                        }.frame(maxWidth: .infinity, maxHeight: 84, alignment: .bottom)
                    }
                }.frame(height: 84).accessibilityHidden(true).animation(reduceMotion ? nil : .smooth(duration: 0.4), value: rates)
            }
        }.accessibilityIdentifier("habits-weekdays")
    }

    // MARK: Year

    private var monthNames: [String] { hijriFirst ? AppBahwService.hijriMonths : AppBahwService.gregorianMonths }
    @ViewBuilder private var year: some View {
        let months = HabitRoomInsights.yearMonths(containing: today, calendar: hijriFirst ? .hijri : .gregorian, days: service.calendarDays)
        let rates = HabitRoomInsights.dayRates(series, selected: selected, today: today)
        let counting = chosenIsLonger
        let values = HabitRoomInsights.monthValues(months, rates: rates, counting: counting)
        let extremes = HabitRoomInsights.extremes(values, complete: months.map { $0.end <= today })
        let yearRates = months.flatMap { m in (0..<m.length).compactMap { rates[m.start.adding(days: $0)] } }
        let overall = yearRates.isEmpty ? nil : yearRates.reduce(0, +) / Double(yearRates.count)
        let yearLabel = yearTitle(months)
        if !rates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(yearLabel.primary).font(HabitType.cardTitle()).accessibilityAddTraits(.isHeader)
                        Text(yearLabel.secondary).font(HabitType.fine()).foregroundStyle(theme.secondaryInk)
                    }
                    Spacer()
                    if let overall { Text(counting ? arabicCount(Int(yearRates.reduce(0, +)), ["مرة واحدة", "مرتان", "مرات", "مرة"], digits) : "التزام " + percent(overall)).font(HabitType.caption()).foregroundStyle(theme.secondaryInk) }
                }.padding(.horizontal, 4)
                fabric(months, rates, extremes)
                monthsCard(months, values, extremes, counting: counting)
            }.accessibilityIdentifier("habits-year")
        }
    }
    private func yearTitle(_ months: [HabitRoomInsights.YearMonth]) -> MadarDateLabels {
        guard let first = months.first, let last = months.last else { return .init(primary: "", secondary: "") }
        let lastDay = last.end.adding(days: -1)
        if hijriFirst {
            let g1 = session.dateLabels(first.start, first: .gregorian).primary, g2 = session.dateLabels(lastDay, first: .gregorian).primary
            return .init(primary: "سنة " + digits.string(service.calendarDays.hijri(first.start).year) + " هـ", secondary: g1 + " – " + g2)
        }
        let labels = session.yearLabels(today.year)
        return .init(primary: "سنة " + digits.string(today.year), secondary: labels.primary == digits.string(today.year) + " م" ? labels.secondary : labels.primary)
    }
    private func level(_ rate: Double?) -> Color {
        guard let rate else { return .clear }
        return rate <= 0 ? theme.accentFill.opacity(0.14) : rate < 0.5 ? theme.accentFill.opacity(0.4) : rate < 1 ? theme.accentFill.opacity(0.7) : theme.accent
    }
    @ViewBuilder private func fabric(_ months: [HabitRoomInsights.YearMonth], _ rates: [GregorianDay: Double], _ extremes: HabitRoomInsights.Extremes?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if dynamicTypeSize.isAccessibilitySize {
                ForEach(months, id: \.index) { m in
                    let days = (0..<m.length).compactMap { rates[m.start.adding(days: $0)] }
                    Text(monthNames[m.index - 1] + ": " + (days.isEmpty ? "لا بيانات" : percent(days.reduce(0, +) / Double(days.count)))).font(HabitType.caption())
                }
            } else {
                ForEach(months, id: \.index) { m in
                    let mark = m.index - 1 == extremes?.best ? theme.accent : m.index - 1 == extremes?.worst ? theme.risk : theme.secondaryInk
                    HStack(spacing: 6) {
                        Text(monthNames[m.index - 1]).font(HabitType.fine()).foregroundStyle(mark).lineLimit(1).minimumScaleFactor(0.7).frame(width: 62, alignment: .leading)
                        HabitYearRow(start: m.start, length: m.length, today: today, rates: rates, theme: theme, level: level).frame(height: 8)
                    }
                }
                HStack(spacing: 6) {
                    Text("لم تتم").font(HabitType.fine()).foregroundStyle(theme.secondaryInk)
                    ForEach([theme.accentFill.opacity(0.14), theme.accentFill.opacity(0.4), theme.accentFill.opacity(0.7), theme.accent], id: \.self) { c in RoundedRectangle(cornerRadius: 2.5).fill(c).frame(width: 8, height: 8) }
                    Text("تمّت كاملة").font(HabitType.fine()).foregroundStyle(theme.secondaryInk)
                }.padding(.top, 8)
            }
        }.padding(.horizontal, 12).padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: .rect(cornerRadius: 24)).accessibilityIdentifier("habits-fabric")
    }
    private func monthsCard(_ months: [HabitRoomInsights.YearMonth], _ values: [Double?], _ extremes: HabitRoomInsights.Extremes?, counting: Bool) -> some View {
        let top = max(values.compactMap { $0 }.max() ?? 1, 0.0001)
        func text(_ v: Double) -> String { counting ? arabicCount(Int(v), ["مرة واحدة", "مرتان", "مرات", "مرة"], digits) : percent(v) }
        return VStack(alignment: .leading, spacing: 14) {
            Text(counting ? "مرّاتها كل شهر" : "التزامك كل شهر").font(HabitType.fine()).foregroundStyle(theme.secondaryInk)
            VStack(spacing: 6) {
                ForEach(months, id: \.index) { m in
                    let v = values[m.index - 1], mark = m.index - 1 == extremes?.best ? theme.accent : m.index - 1 == extremes?.worst ? theme.risk : theme.secondaryInk
                    HStack(spacing: 8) {
                        Text(monthNames[m.index - 1]).font(HabitType.fine()).foregroundStyle(mark).lineLimit(1).minimumScaleFactor(0.7).frame(width: 62, alignment: .leading)
                        if !dynamicTypeSize.isAccessibilitySize {
                            Capsule().fill(theme.ink.opacity(0.05)).frame(height: 10).overlay(alignment: .leading) {
                                if let v { Capsule().fill(m.index - 1 == extremes?.best ? theme.accent : m.index - 1 == extremes?.worst ? theme.risk : theme.accentFill.opacity(0.38)).scaleEffect(x: max(0.03, v / top), anchor: .leading) }
                            }
                        } else { Spacer(minLength: 0) }
                        Text(v.map(text) ?? (m.start > today ? "لم يأتِ" : "")).font(HabitType.fine()).foregroundStyle(mark).frame(minWidth: 54, alignment: .trailing)
                    }
                }
            }
            if let extremes {
                HStack(spacing: 10) {
                    extremeBox("أحسن شهر", extremes.best, values, months, tint: theme.accent, text: text)
                    if let worst = extremes.worst { extremeBox("أقل شهر", worst, values, months, tint: theme.risk, text: text) }
                }
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 24)).accessibilityIdentifier("habits-months")
    }
    private func extremeBox(_ title: String, _ index: Int, _ values: [Double?], _ months: [HabitRoomInsights.YearMonth], tint: Color, text: (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(HabitType.fine()).foregroundStyle(tint)
            Text(monthNames[index]).font(HabitType.section())
            Text(values[index].map(text) ?? "").font(HabitType.fine()).foregroundStyle(theme.secondaryInk)
            Text("يبدأ " + session.dateLabels(months[index].start).secondary).font(HabitType.fine()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(tint.opacity(0.08), in: .rect(cornerRadius: 16))
    }
}

/// The trend as a line over a soft area, newest at the leading edge as the canvas draws it (time runs right to left).
private struct HabitTrendLine: View {
    let values: [Double?]; let colour: Color; let fill: Color; let ring: Color
    var body: some View {
        Canvas { context, size in
            let pts: [CGPoint] = values.enumerated().compactMap { i, v in
                guard let v else { return nil }
                let lo = values.compactMap { $0 }.min() ?? 0, hi = values.compactMap { $0 }.max() ?? 1, span = max(hi - lo, 0.0001)
                return CGPoint(x: size.width - 10 - CGFloat(i) * (size.width - 20) / CGFloat(max(1, values.count - 1)), y: hi == lo ? size.height / 2 : size.height - 10 - CGFloat((v - lo) / span) * (size.height - 22))
            }
            guard let first = pts.first, let last = pts.last else { return }
            var line = Path(); line.move(to: first); pts.dropFirst().forEach { line.addLine(to: $0) }
            var area = line; area.addLine(to: CGPoint(x: last.x, y: size.height - 2)); area.addLine(to: CGPoint(x: first.x, y: size.height - 2)); area.closeSubpath()
            context.fill(area, with: .color(fill))
            context.stroke(line, with: .color(colour), style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round))
            let dot = CGRect(x: last.x - 5, y: last.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: dot), with: .color(colour)); context.stroke(Path(ellipseIn: dot), with: .color(ring), lineWidth: 2)
        }
    }
}

/// A month of the year grid: one small square per day, the first day at the reading edge (right in Arabic).
private struct HabitYearRow: View {
    let start: GregorianDay; let length: Int; let today: GregorianDay; let rates: [GregorianDay: Double]; let theme: RoomTheme
    let level: (Double?) -> Color
    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 2, cell = min(9, (size.width - 30 * gap) / 31)
            for d in 0..<length {
                let day = start.adding(days: d)
                let x = size.width - CGFloat(d + 1) * cell - CGFloat(d) * gap, rect = CGRect(x: x, y: (size.height - cell) / 2, width: cell, height: cell)
                let path = Path(roundedRect: rect, cornerRadius: 2)
                if let rate = rates[day], day <= today { context.fill(path, with: .color(level(rate))) }
                else { context.stroke(path, with: .color(theme.ink.opacity(0.09)), lineWidth: 1) }
                if day == today { context.stroke(path, with: .color(theme.ink), lineWidth: 1.5) }
            }
        }.accessibilityHidden(true)
    }
}
