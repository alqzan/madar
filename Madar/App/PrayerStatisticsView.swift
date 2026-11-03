import SwiftUI
import MadarCore
import MadarDesign
import MadarPrayer

struct PrayerStatisticsView: View {
    let session: AppSession
    private let fallback: PrayerSnapshot
    let select: (PrayerCell) -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editing: PrayerDayRoute?

    init(session: AppSession, snapshot: PrayerSnapshot, initialDay: GregorianDay? = nil, select: @escaping (PrayerCell) -> Void) {
        self.session = session; self.fallback = snapshot; self.select = select
        _editing = State(initialValue: initialDay.map { PrayerDayRoute(day: $0) })
    }
    /// Read afresh so an edit in the day sheet shows here at once.
    private var snapshot: PrayerSnapshot { (try? session.prayerSnapshot(at: session.prayerNow())) ?? fallback }

    private var formatter: MadarNumberFormatter { .init(style: session.string("core.numerals") == "western" ? .western : .hindi) }
    private var month: HijriDate { hijri(snapshot.today.day) }
    private var monthDays: [GregorianDay] {
        let start = snapshot.today.day.adding(days: -(month.day - 1))
        return (0..<30).map { start.adding(days: $0) }.filter { let date = hijri($0); return date.month == month.month && date.year == month.year }
    }
    private var monthTitle: String {
        let names = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
        return names[month.month - 1] + " " + formatter.string(month.year) + " هـ"
    }

    @Environment(\.dismiss) private var dismiss

    private var digits: MadarNumberFormatter { formatter }
    private var numeralLocale: Locale { Locale(identifier: session.string("core.numerals") == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab") }
    /// «١٢ سبتمبر – ١١ أكتوبر»: the Gregorian span of the Hijri month shown.
    private var monthSpan: String {
        guard let first = monthDays.first, let last = monthDays.last else { return "" }
        let f = DateFormatter(); f.locale = numeralLocale; f.timeZone = session.activePlace.timeZone
        f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "d MMMM yyyy"
        func text(_ day: GregorianDay) -> String { f.string(from: day.date(in: session.activePlace.timeZone).addingTimeInterval(12 * 3600)) + " م" }
        return text(first) + " – " + text(last)
    }
    /// The Mizan's own count over the last 25 prayers: on time ÷ prayers whose time came (pending and unrecorded stay out).
    private var mizan: (onTime: Int, due: Int, pending: Int) {
        let cells = snapshot.statistics.last25
        let due = cells.filter { [.jamaah, .alone, .qada, .missed].contains($0.status) }
        return (due.filter { $0.status == .jamaah || $0.status == .alone }.count, due.count, cells.filter { $0.status == .pending }.count)
    }
    private func serif(_ size: CGFloat) -> Font { .custom("thmanyahserifdisplay-Bold", size: size, relativeTo: .title) }
    private func summaryCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content().frame(maxWidth: .infinity)
            .background(theme.color("goldSoft"), in: .rect(cornerRadius: 26))
            .overlay { RoundedRectangle(cornerRadius: 26).stroke(theme.line, lineWidth: 1) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 14) {
                    Button { dismiss() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.backward").font(.system(size: 14, weight: .semibold))
                            Text("الصلاة").font(PrayerHomeType.strong)
                        }.frame(minHeight: 44).contentShape(.rect)
                    }
                    .buttonStyle(.madarPlain).accessibilityIdentifier("prayer-hali-back")
                    Text("حالي").font(serif(44)).accessibilityAddTraits(.isHeader)
                }
                if snapshot.statistics.denominator >= 5 {
                    metrics
                    PrayerSummarySection(title: "الميزان", trailing: "آخر " + arabicCount(snapshot.statistics.last25.count, ["فرض", "فرضين", "فروض", "فرضًا"], formatter)) { mizanCard }
                } else {
                    Text("يظهر حالي بعد خمسة فروض مسجّلة؛ المعلّقة لا تدخل في النسبة.")
                        .font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
                }
                PrayerSummarySection(title: "سجلّ الشهر", trailing: "المس يومًا لتعدّله") { monthCard }
                PrayerSummarySection(title: "التزامك بكل صلاة", trailing: "هذا الشهر") { commitmentCard }
                if session.bool("salah.askHeart"), !snapshot.statistics.heartDistribution.isEmpty {
                    PrayerSummarySection(title: "حضور القلب", trailing: "جُمَلٌ لا أرقام") { heartCard }
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .background(theme.background).foregroundStyle(theme.ink)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .sheet(item: $editing) { route in
            PrayerDayEditSheet(session: session, day: route.day, hijriTitle: hijriDayTitle(route.day), gregorianTitle: gregorianDayTitle(route.day),
                firstGregorian: session.string("core.firstCalendar") == "gregorian", digits: formatter, openLog: { cell in editing = nil; select(cell) })
                .environment(\.roomTheme, theme).madarSheetErrorAlert(session)
        }
    }

    private static let monthNames = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
    /// «الثلاثاء ٢٥ ربيع الآخر ١٤٤٨ هـ».
    private func hijriDayTitle(_ day: GregorianDay) -> String {
        let f = DateFormatter(); f.locale = numeralLocale; f.timeZone = session.activePlace.timeZone; f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "EEEE"
        let date = hijri(day)
        let gregorian = f.string(from: day.date(in: session.activePlace.timeZone).addingTimeInterval(12 * 3600))
        return [gregorian, formatter.string(date.day), Self.monthNames[date.month - 1], formatter.string(date.year), "هـ"]
            .joined(separator: " ")
    }
    /// «٦ أكتوبر ٢٠٢٦ م».
    private func gregorianDayTitle(_ day: GregorianDay) -> String {
        let f = DateFormatter(); f.locale = numeralLocale; f.timeZone = session.activePlace.timeZone; f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "d MMMM yyyy"
        return f.string(from: day.date(in: session.activePlace.timeZone).addingTimeInterval(12 * 3600)) + " م"
    }

    // MARK: Three figures

    private var metrics: some View {
        VStack(spacing: 10) {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 10) { metricCards }
            } else {
                HStack(alignment: .top, spacing: 10) { metricCards }
            }
            // AU-24: «قُضيت ٠، عليك ٠» says nothing; the line appears once there is qada.
            if snapshot.statistics.madeUp + snapshot.statistics.owed > 0 {
                Text("قُضيت \(formatter.string(snapshot.statistics.madeUp))، عليك \(formatter.string(snapshot.statistics.owed))")
                    .font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("prayer-stat-qada")
            }
        }
    }
    @ViewBuilder private var metricCards: some View {
        metric("هذا الشهر", value: snapshot.statistics.percentage.map { formatter.percent($0) } ?? "—", id: "prayer-stat-percentage")
        metric("سلسلة في وقتها", value: streakText(snapshot.statistics.prayerStreak), id: "prayer-stat-streak")
        if session.bool("salah.showMosqueStreak") {
            metric("سلسلة الجماعة", value: streakText(snapshot.statistics.congregationStreak), id: "prayer-stat-mosque")
        }
    }
    /// RU3 for the figure cards: «٠ أيام»، «يوم»، «يومان»، «٨ أيام»، «١١ يومًا» (the sentence form «لم تبدأ بعد» is for the home card).
    private func streakText(_ count: Int) -> String {
        switch count {
        case 1: "يوم"
        case 2: "يومان"
        case 0, 3...10: formatter.string(count) + " أيام"
        default: formatter.string(count) + " يومًا"
        }
    }
    private func metric(_ title: String, value: String, id: String) -> some View {
        VStack(spacing: 6) {
            Text(value).font(serif(28)).minimumScaleFactor(0.7).lineLimit(1).accessibilityIdentifier(id)
            Text(title).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 78).padding(.vertical, 8)
        .background(theme.color("goldSoft"), in: .rect(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(theme.line, lineWidth: 1) }
    }

    // MARK: Mizan: the beads on an arc

    private var mizanCard: some View {
        summaryCard {
            VStack(spacing: 10) {
                if typeSize.isAccessibilitySize {
                    DisclosureGroup("آخر " + arabicCount(snapshot.statistics.last25.count, ["فرض", "فرضين", "فروض", "فرضًا"], formatter)) {
                        ForEach(snapshot.statistics.last25) { cell in
                            Text(cellLabel(cell)).font(MadarTypography.caption())
                                .accessibilityIdentifier("prayer-bead-list-\(cell.reference.naturalKey)")
                        }
                    }.accessibilityIdentifier("prayer-beads-list")
                } else {
                    ZStack {
                        PrayerRecentBeads(cells: snapshot.statistics.last25, compact: false)
                        VStack(spacing: 4) {
                            Text(mizan.due == 0 ? "—" : formatter.percent(Int((Double(mizan.onTime) / Double(mizan.due) * 100).rounded())))
                                .font(serif(46))
                            let labels = [mizan.onTime > 0 ? "أوفيت \(formatter.string(mizan.onTime))" : nil,
                                          mizan.pending > 0 ? "معلّقة \(formatter.string(mizan.pending))" : nil]
                            Text(labels.compactMap { $0 }.joined(separator: "، "))
                                .font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                        }.offset(y: 12)
                    }
                    HStack {
                        Text("الأقدم")
                        Spacer(minLength: 6)
                        Text("ميزانٌ يُرى، لا سجلٌّ يُعدّ")
                        Spacer(minLength: 6)
                        Text("الأحدث")
                    }.font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                }
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 18)
        }
    }

    // MARK: Month log

    private var monthCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if session.string("core.firstCalendar") == "gregorian" {
                // The month is still the Hijri one the statistics group by; the Gregorian span leads when it is the first calendar.
                VStack(alignment: .leading, spacing: 2) {
                    Text(monthSpan).font(serif(22)).lineLimit(1).minimumScaleFactor(0.6).accessibilityIdentifier("prayer-history-month-span")
                    Text(monthTitle).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).lineLimit(1).accessibilityIdentifier("prayer-history-month")
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(monthTitle).font(serif(26)).lineLimit(1).minimumScaleFactor(0.7).layoutPriority(1).accessibilityIdentifier("prayer-history-month")
                    Spacer(minLength: 8)
                    Text(monthSpan).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).lineLimit(2).multilineTextAlignment(.trailing).accessibilityIdentifier("prayer-history-month-span")
                }
            }
            if typeSize.isAccessibilitySize {
                ForEach(snapshot.history.filter { hijri($0.day).month == month.month && hijri($0.day).year == month.year }, id: \.day) { day in
                    Button { editing = PrayerDayRoute(day: day.day) } label: {
                        MadarDateLabel(dateTitle(day.day))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                        .accessibilityIdentifier("prayer-history-day-\(day.day)")
                }
            } else { calendarGrid }
        }
        .padding(20).frame(maxWidth: .infinity)
        .overlay { RoundedRectangle(cornerRadius: 26).stroke(theme.ink.opacity(0.1), lineWidth: 1) }
    }

    private var calendarGrid: some View {
        let firstWeekday = session.string("core.weekStart") == "monday" ? 2 : session.string("core.weekStart") == "sunday" ? 1 : 7
        let names = ["أح", "إث", "ثل", "أر", "خم", "جم", "سب"]
        let weekdays = (0..<7).map { names[(firstWeekday - 1 + $0) % 7] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = session.activePlace.timeZone
        let leading = ((calendar.component(.weekday, from: monthDays[0].date(in: calendar.timeZone)) - firstWeekday) + 7) % 7
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
            ForEach(weekdays, id: \.self) { Text($0).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).padding(.bottom, 4) }
            ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 64).accessibilityHidden(true) }
            ForEach(monthDays, id: \.self) { day in
                let isToday = day == snapshot.today.day
                if let summary = snapshot.history.first(where: { $0.day == day }) {
                    Button { editing = PrayerDayRoute(day: day) } label: { dayCell(day, cells: summary.cells, today: isToday) }
                        .buttonStyle(.madarPlain)
                        .accessibilityLabel(dateTitle(day)).accessibilityIdentifier("prayer-history-day-\(day)")
                } else {
                    dayCell(day, cells: [], today: isToday).opacity(0.3).accessibilityHidden(true)
                }
            }
        }
    }

    private func dayCell(_ day: GregorianDay, cells: [PrayerCell], today: Bool) -> some View {
        VStack(spacing: 3) {
            PrayerDayGlyph(cells: cells).frame(width: 28, height: 26).accessibilityHidden(true)
            Text(formatter.string(hijri(day).day)).font(today ? PrayerHomeType.smallBold : PrayerHomeType.small)
                .foregroundStyle(today ? theme.ink : theme.secondaryInk)
            // The Gregorian day beneath, smaller: every date shows both calendars.
            Text(formatter.string(day.day)).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2))
                .foregroundStyle(theme.secondaryInk).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(today ? theme.color("goldSoft") : .clear, in: .rect(cornerRadius: 12))
        .contentShape(.rect)
    }

    // MARK: Commitment per prayer

    private var commitmentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Prayer.allCases, id: \.self) { prayer in
                let value = snapshot.statistics.commitment[prayer]
                let jamaah = value?.jamaah ?? 0, alone = value?.alone ?? 0, due = value?.denominator ?? 0
                HStack(spacing: 12) {
                    Text(prayerTitle(prayer)).font(PrayerHomeType.lead).frame(width: 66, alignment: .leading)
                    if typeSize.isAccessibilitySize {
                        Text("\(formatter.string(jamaah)) جماعة، \(formatter.string(alone)) وحدي").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    } else {
                        GeometryReader { geometry in
                            HStack(spacing: 0) {
                                Rectangle().fill(theme.accent).frame(width: due > 0 ? geometry.size.width * Double(jamaah) / Double(due) : 0)
                                Rectangle().fill(theme.color("goldMid")).frame(width: due > 0 ? geometry.size.width * Double(alone) / Double(due) : 0)
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(height: 11).background(theme.ink.opacity(0.08)).clipShape(.capsule).accessibilityHidden(true)
                    }
                    Text(due > 0 ? formatter.percent(Int((Double(jamaah + alone) / Double(due) * 100).rounded())) : "—")
                        .font(PrayerHomeType.smallBold).frame(width: 44, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(prayerTitle(prayer))، \(formatter.string(jamaah)) جماعة، \(formatter.string(alone)) وحدي")
            }
            HStack(spacing: 18) {
                legend("جماعة", theme.accent)
                legend("وحدي في وقتها", theme.color("goldMid"))
                Spacer(minLength: 0)
            }.padding(.top, 2)
            if let insight = commitmentInsight {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Rectangle().fill(theme.accent).frame(width: 7, height: 7).rotationEffect(.degrees(45)).accessibilityHidden(true)
                    Text(insight).font(PrayerHomeType.lead).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.color("goldSoft"), in: .rect(cornerRadius: 18))
                .accessibilityIdentifier("prayer-commitment-insight")
            }
        }
    }
    /// S3's analysis read as a sentence, not more numbers: which prayer holds best this month and which needs care,
    /// and where congregation is strongest. Only prayers with at least three due days take part.
    private var commitmentInsight: String? {
        let rows: [(Prayer, Double, Double)] = Prayer.allCases.compactMap { prayer in
            guard let value = snapshot.statistics.commitment[prayer], value.denominator >= 3 else { return nil }
            let due = Double(value.denominator)
            return (prayer, Double(value.jamaah + value.alone) / due, Double(value.jamaah) / due)
        }
        guard rows.count >= 2, let best = rows.max(by: { $0.1 < $1.1 }), let weak = rows.min(by: { $0.1 < $1.1 }) else { return nil }
        // Ties are named as a group rather than by whichever prayer comes first.
        let top = rows.filter { best.1 - $0.1 < 0.01 }, low = rows.filter { $0.1 - weak.1 < 0.01 }
        var sentence: String
        if best.1 - weak.1 < 0.05 { sentence = "صلواتك الخمس متقاربة هذا الشهر، فلا واحدة تتأخر عن أخواتها." }
        else if top.count == 1 && low.count == 1 { sentence = "أثبت صلواتك هذا الشهر " + prayerTitle(best.0) + "، وأحوجها إلى عنايتك " + prayerTitle(weak.0) + "." }
        else if top.count == 1 { sentence = "أثبت صلواتك هذا الشهر " + prayerTitle(best.0) + "، والبقية متقاربة دونها." }
        else if low.count == 1 { sentence = "أحوج صلواتك إلى عنايتك هذا الشهر " + prayerTitle(weak.0) + "، والبقية أثبت منها." }
        else { sentence = "صلواتك هذا الشهر على مرتبتين متقاربتين، والفرق بينهما يسير." }
        if let mosque = rows.max(by: { $0.2 < $1.2 }), mosque.2 > 0, rows.contains(where: { $0.2 < mosque.2 - 0.05 }) {
            sentence += " وأكثر ما تدركه في جماعة " + prayerTitle(mosque.0) + "."
        }
        return sentence
    }
    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(title).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
        }
    }

    // MARK: Heart: sentences only, no numbers, no ranking (RP6)

    private var heartCard: some View {
        summaryCard {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(PrayerHeart.allCases, id: \.self) { heart in
                    if snapshot.statistics.heartDistribution[heart, default: 0] > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Rectangle().fill(theme.accent).frame(width: 7, height: 7).rotationEffect(.degrees(45)).accessibilityHidden(true)
                            Text(heartTitle(heart) + "، " + heartSentence(heart)).font(PrayerHomeType.lead)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .accessibilityIdentifier("prayer-heart-reflection")
        }
    }

    private func dayView(_ day: PrayerDaySummary) -> some View {
        List {
            Section { MadarDateLabel(dateTitle(day.day)) }
            ForEach(day.cells) { cell in
                if cell.canLog && (cell.time == nil || cell.status != .future) {
                    Button { select(cell) } label: { Text(prayerTitle(cell.reference.prayer) + "، " + statusTitle(cell.status)).frame(minHeight: 44) }
                        .accessibilityIdentifier("prayer-history-log-\(cell.reference.prayer.rawValue)")
                } else { Text(prayerTitle(cell.reference.prayer) + "، " + statusTitle(cell.status)).frame(minHeight: 44) }
            }
        }.navigationTitle("سجلّ اليوم").navigationBarTitleDisplayMode(.inline)
    }
    private func hijri(_ day: GregorianDay) -> HijriDate {
        HijriCalendar.date(for: day.date(in: session.activePlace.timeZone).addingTimeInterval(12 * 3600), timeZone: session.activePlace.timeZone,
            source: HijriSource(rawValue: session.string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(session.number("core.hijriOffset")))
    }
    private func dateTitle(_ day: GregorianDay) -> String {
        DualDate(instant: day.date(in: session.activePlace.timeZone).addingTimeInterval(12 * 3600), timeZone: session.activePlace.timeZone,
            source: HijriSource(rawValue: session.string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(session.number("core.hijriOffset")))
            .labels(firstCalendar: session.string("core.firstCalendar") == "gregorian" ? .gregorian : .hijri, numerals: formatter.style).combined
    }
    private func cellLabel(_ cell: PrayerCell) -> String { dateTitle(cell.reference.day) + "، " + prayerTitle(cell.reference.prayer) + "، " + statusTitle(cell.status) }
}

private struct PrayerDayRoute: Identifiable { let day: GregorianDay; var id: String { day.description } }

/// S4 · edit a past day, matched to `screens/salah/05-S4-Day.jpg`. One tap on a state records it;
/// what is unrecorded stays pending until the user chooses (RP1, not «ثم تُحسب فائتة»).
/// A stored `dayKey` is read, never recomputed.
private struct PrayerDayEditSheet: View {
    let session: AppSession
    let day: GregorianDay
    let hijriTitle: String
    let gregorianTitle: String
    let firstGregorian: Bool
    let digits: MadarNumberFormatter
    let openLog: (PrayerCell) -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismissDay
    @State private var contentHeight: CGFloat = 560

    private var summary: PrayerDaySummary? {
        (try? session.prayerSnapshot(at: session.prayerNow()))?.history.first { $0.day == day }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let summary {
                header(summary)
                ForEach(summary.cells) { cell in
                    Rectangle().fill(theme.ink.opacity(0.1)).frame(height: 1)
                    row(cell)
                }
                Rectangle().fill(theme.ink.opacity(0.1)).frame(height: 1)
                Text("غير المسجّلة تبقى معلّقة حتى تختار حالها.").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                    .frame(maxWidth: .infinity).padding(.top, 14)
            } else {
                // AU-38: never a blank sheet with only its handle.
                Text("تعذّر تحميل هذا اليوم.").font(PrayerHomeType.lead)
                Button("أغلق") { dismissDay() }.font(PrayerHomeType.strong).frame(minHeight: 44).accessibilityIdentifier("prayer-day-close")
            }
        }
        .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 + 20 }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.background).foregroundStyle(theme.ink)
        .presentationDetents([.height(min(max(contentHeight, 300), 760))])
        .presentationBackground(theme.background)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
    }

    private func header(_ summary: PrayerDaySummary) -> some View {
        let together = summary.cells.filter { $0.status == .jamaah }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(firstGregorian ? gregorianTitle : hijriTitle).font(.custom("thmanyahserifdisplay-Bold", size: 26, relativeTo: .title))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                // AU-24: a day with nothing recorded is not «٠ من ٥ جماعة».
                if summary.cells.contains(where: { [.jamaah, .alone, .qada, .missed, .excused].contains($0.status) }) {
                    Text("\(digits.string(together)) من \(digits.string(summary.cells.count)) جماعة").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                }
            }
            Text(firstGregorian ? hijriTitle : gregorianTitle).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
        }
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("prayer-day-header")
    }

    private func row(_ cell: PrayerCell) -> some View {
        let editable = cell.canLog && (cell.time == nil || cell.status != .future)
        return HStack(spacing: 8) {
            Button { openLog(cell) } label: {
                Text(prayerTitle(cell.reference.prayer)).font(PrayerHomeType.lead).frame(width: 58, alignment: .leading).frame(minHeight: 44)
            }
            .buttonStyle(.madarPlain).accessibilityLabel("تفاصيل \(prayerTitle(cell.reference.prayer))")
            .accessibilityIdentifier("prayer-history-log-\(cell.reference.prayer.rawValue)")
            if editable {
                ForEach(options(cell), id: \.self) { pill($0, cell) }
                Spacer(minLength: 0)
            } else {
                Text(statusTitle(cell.status)).font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: 70)
    }

    private func options(_ cell: PrayerCell) -> [PrayerStoredStatus] {
        [.jamaah, .alone] + (cell.canMakeUp || cell.status == .qada ? [.qada] : []) + (cell.canMarkMissed || cell.status == .missed ? [.missed] : [])
    }

    private func pill(_ option: PrayerStoredStatus, _ cell: PrayerCell) -> some View {
        let on = cell.status.rawValue == option.rawValue
        let tint = statusOutline(option)
        let title: String = switch option { case .jamaah: "جماعة"; case .alone: "وحدي"; case .qada: "قضاء"; default: "فاتتني" }
        return Button {
            guard !session.prayerWriteInProgress, !on else { return }
            // Friday noon carries its kind explicitly (RP5): the full sheet asks for it.
            if cell.isFriday && option != .alone { openLog(cell); return }
            switch option {
            case .qada: session.makeUpPrayer(cell.reference, fridayKind: nil)
            default: session.recordPrayer(cell.reference, status: option, fridayKind: cell.isFriday ? .dhuhr : nil)
            }
        } label: {
            HStack(spacing: 4) {
                statusMark(option)
                    .accessibilityHidden(true)
                Text(title).font(on ? PrayerHomeType.smallBold : PrayerHomeType.small)
                    .foregroundStyle(on ? statusText(option) : theme.secondaryInk)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
                .frame(maxWidth: 76, minHeight: 52)
                .padding(.horizontal, 3)
                .background(on ? statusFill(option) : .clear, in: .rect(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(on ? tint : theme.ink.opacity(0.13), lineWidth: on ? 1.5 : 1) }
                .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.madarPlain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("prayer-day-\(cell.reference.prayer.rawValue)-\(option.rawValue)")
    }

    private func statusOutline(_ option: PrayerStoredStatus) -> Color {
        switch option {
        case .jamaah, .alone: theme.color("accent")
        case .qada: theme.color("ink2")
        case .missed: theme.color("missed")
        default: theme.line
        }
    }

    private func statusText(_ option: PrayerStoredStatus) -> Color {
        switch option {
        case .jamaah, .alone: theme.color("accentText")
        case .qada: theme.color("ink2")
        case .missed: theme.color("missedTextOnSurface")
        default: theme.secondaryInk
        }
    }

    private func statusFill(_ option: PrayerStoredStatus) -> Color {
        switch option {
        case .jamaah: theme.color("goldSoft")
        case .alone: theme.color("goldMid").opacity(0.22)
        case .qada: theme.color("ink2").opacity(0.08)
        case .missed: theme.color("missed").opacity(0.09)
        default: .clear
        }
    }

    @ViewBuilder
    private func statusMark(_ option: PrayerStoredStatus) -> some View {
        switch option {
        case .jamaah:
            PrayerStar().fill(theme.color("accent")).frame(width: 14, height: 14)
        case .alone:
            PrayerStar().fill(theme.color("goldMid"))
                .overlay { PrayerStar().stroke(theme.color("accent"), lineWidth: 1) }
                .frame(width: 14, height: 14)
        case .qada:
            Image(systemName: "hourglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(theme.color("ink2"))
                .frame(width: 16, height: 16)
        case .missed:
            PrayerHorseshoe().stroke(theme.color("missed"), lineWidth: 1.2).frame(width: 14, height: 14)
        default:
            EmptyView()
        }
    }
}

/// The Mizan: 25 beads, 10° apart on a 240° arc, oldest on the right and the newest, larger, on the left.
private struct PrayerRecentBeads: View {
    let cells: [PrayerCell]
    let compact: Bool
    @Environment(\.roomTheme) private var theme
    var body: some View {
        GeometryReader { geometry in arc(in: geometry.size) }
            .frame(height: compact ? 92 : 196).environment(\.layoutDirection, .leftToRight).accessibilityHidden(true)
    }
    private func arc(in size: CGSize) -> some View {
        // S3: the full card opens the arc to 270°, oldest at the lower right, newest at the lower left.
        let radius: CGFloat = compact ? min(size.width * 0.34, (size.height - 24) / 1.5) : min(size.width * 0.36, (size.height - 30) / 1.72)
        let center = CGPoint(x: size.width / 2, y: radius + 14)
        return ZStack {
            Path { path in
                path.addArc(center: center, radius: radius, startAngle: .degrees(start - span), endAngle: .degrees(start), clockwise: false)
            }
            .stroke(theme.color("goldMid").opacity(0.5), lineWidth: 1)
            ForEach(Array(cells.enumerated()), id: \.element.reference) { index, cell in
                bead(cell, last: index == cells.count - 1)
                    .position(position(index, center: center, radius: radius))
            }
        }
    }
    private var start: Double { compact ? 30 : 45 }
    private var span: Double { compact ? 240 : 270 }
    private func position(_ index: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let step = compact || cells.count < 2 ? 10 : span / Double(cells.count - 1)
        let angle = (start - Double(index) * step) * Double.pi / 180
        return CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
    }
    private func bead(_ cell: PrayerCell, last: Bool) -> some View {
        let size: CGFloat = compact ? (last ? 16 : 11) : (last ? 18 : 13)
        let dashed = cell.status == .pending || cell.status == .unconfirmed
        return Circle().fill(fill(cell.status))
            .overlay { Circle().stroke(stroke(cell.status), style: StrokeStyle(lineWidth: 1, dash: dashed ? [2, 2] : [])) }
            .frame(width: size, height: size)
    }
    private func fill(_ status: PrayerDisplayStatus) -> Color {
        switch status { case .jamaah: theme.accent; case .alone: theme.color("goldMid"); case .qada: theme.ink.opacity(0.3); default: .clear }
    }
    private func stroke(_ status: PrayerDisplayStatus) -> Color {
        switch status { case .missed: theme.color("missed"); case .jamaah, .alone, .qada: .clear; default: theme.ink.opacity(0.35) }
    }
}

/// One day of the month as five small beads on an arch, Fajr on the right.
private struct PrayerDayGlyph: View {
    let cells: [PrayerCell]
    @Environment(\.roomTheme) private var theme
    private static let spots: [CGPoint] = [.init(x: 0.9, y: 0.78), .init(x: 0.8, y: 0.34), .init(x: 0.5, y: 0.06), .init(x: 0.2, y: 0.34), .init(x: 0.1, y: 0.78)]
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            ZStack {
                ForEach([0, 4], id: \.self) { i in
                    Rectangle().fill(theme.color("goldMid").opacity(0.55)).frame(width: 1, height: h * 0.26)
                        .position(x: w * Self.spots[i].x, y: h * Self.spots[i].y + h * 0.13)
                }
                ForEach(0..<5, id: \.self) { i in
                    let cell = i < cells.count ? cells[i] : nil
                    Circle().fill(color(cell?.status)).overlay { Circle().stroke(outline(cell?.status), lineWidth: 0.8) }
                        .frame(width: 5, height: 5).position(x: w * Self.spots[i].x, y: h * Self.spots[i].y)
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
    private func color(_ status: PrayerDisplayStatus?) -> Color {
        switch status {
        case .jamaah: theme.accent
        case .alone: theme.color("goldMid")
        case .qada: theme.ink.opacity(0.3)
        case .missed: theme.color("missed")
        default: .clear
        }
    }
    private func outline(_ status: PrayerDisplayStatus?) -> Color {
        switch status { case .jamaah, .alone, .qada, .missed: .clear; default: theme.ink.opacity(0.28) }
    }
}

func prayerTitle(_ prayer: Prayer) -> String {
    switch prayer { case .fajr: "الفجر"; case .dhuhr: "الظهر"; case .asr: "العصر"; case .maghrib: "المغرب"; case .isha: "العشاء" }
}
private func statusTitle(_ status: PrayerDisplayStatus) -> String {
    switch status {
    case .jamaah: "في جماعة"
    case .alone: "وحدي"
    case .qada: "قُضيت"
    case .missed: "فاتتني"
    case .pending: "لم تُسجَّل"
    case .future: "لم يحن"
    case .unconfirmed: "غير محسومة"
    case .excused: "معذورة"
    case .unrecordedHistory: "لم أسجّل"
    }
}

private struct PrayerSummarySection<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Rectangle().fill(theme.accent).frame(width: 7, height: 7).rotationEffect(.degrees(45)).accessibilityHidden(true)
                Text(title).font(PrayerHomeType.strong).foregroundStyle(theme.secondaryInk).accessibilityAddTraits(.isHeader)
                Rectangle().fill(theme.line).frame(height: 1).accessibilityHidden(true)
                if let trailing { Text(trailing).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).fixedSize() }
            }
            content()
        }
    }
}
