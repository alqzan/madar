import SwiftData
import SwiftUI
import MadarCommands
import MadarCore
import MadarData
import MadarDesign
import MadarPrayer

/// Owner, 30 Oct 2026 («الهدف حلو نربطه بالعادات + بالمحبره»): the daily reading goal is the §7.1 linked habit «القراءة»,
/// read from the Mihbara's saved sessions. The room shows today's share of it, the habit's streak, the last seven days
/// and when the reader usually reads. Nothing here is stored: every number is derived from `ReadingSession`.
struct MihbaraReadingGoal {
    struct Day: Identifiable { let day: GregorianDay; let minutes: Int; let pages: Int; var chapters = 0; var id: String { day.description } }
    /// «بهذه الوتيرة تنهي «الكتاب» بعد نحو N يومًا»: the book in hand and the calendar day it is likely to end.
    struct Finish: Equatable { let title: String; let days: Int; let day: GregorianDay }
    /// The live «القراءة» habit, when the reader has one.
    var habit: HabitReading?
    /// The last seven Madar days, oldest first; the last one is today.
    var days: [Day]
    /// «بعد العشاء» and the like, when one stretch of the day clearly holds most of the reading.
    var usual: String?
    /// Seconds a page usually takes this reader (last 30 days), and the pages a chapter of the book in hand holds; nil until the reading says enough.
    var secondsPerPage: Double?
    var pagesPerChapter: Double?
    /// A book is on the stand but has no page count, so neither chapters nor a finish date can be worked out.
    var bookHasNoPageCount = false
    var finish: Finish?
    var unit: String { habit?.summary.current?.rule.unit ?? "minutes" }
    func value(_ day: Day) -> Int { unit == "pages" ? day.pages : unit == "chapters" ? day.chapters : day.minutes }

    /// What `left` of the goal usually costs, in the other unit, from the reader's own pace: a pages or chapters goal says minutes,
    /// a minutes goal says pages. Nil when the pace is not known yet.
    func estimate(left: Int, unit: String) -> (amount: Int, unit: String)? {
        guard left > 0, let secondsPerPage else { return nil }
        switch unit {
        case "pages": return ReadingPace.minutes(forPages: left, secondsPerPage: secondsPerPage).map { ($0, "minutes") }
        case "chapters":
            guard let pagesPerChapter else { return nil }
            return ReadingPace.minutes(forPages: Int((Double(left) * pagesPerChapter).rounded(.up)), secondsPerPage: secondsPerPage).map { ($0, "minutes") }
        default: return ReadingPace.pages(forMinutes: left, secondsPerPage: secondsPerPage).map { ($0, "pages") }
        }
    }

    /// The stretch between two prayers that holds most of the active reading time. At least three sessions, and the
    /// stretch must hold 40٪ of the time, so one long evening never becomes «غالبًا».
    nonisolated static func usualStretch(_ sessions: [(start: Date, seconds: Int)], prayers: (Date) -> PrayerDay?) -> String? {
        guard sessions.count >= 3 else { return nil }
        var share: [String: Int] = [:], total = 0
        for session in sessions where session.seconds > 0 {
            guard let p = prayers(session.start) else { continue }
            let t = session.start
            let name = t < p.fajr || t >= p.isha ? "بعد العشاء"
                : t < p.sunrise ? "بعد الفجر" : t < p.dhuhr ? "في الضحى" : t < p.asr ? "بعد الظهر" : t < p.maghrib ? "بعد العصر" : "بعد المغرب"
            share[name, default: 0] += session.seconds; total += session.seconds
        }
        guard total > 0, let top = share.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }), top.value * 10 >= total * 4 else { return nil }
        return top.key
    }
}

extension AppMihbaraService {
    func readingGoal(today: GregorianDay, at instant: Date? = nil, book: MihbaraBook? = nil) throws -> MihbaraReadingGoal {
        let context = ModelContext(app.container), now = instant ?? app.prayerNow()
        let habit = try HabitRepository(context: context).readings(at: now).first { $0.source == "reading" && !$0.archived }
        let sessions = try context.fetch(FetchDescriptor<ReadingSession>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.activeSeconds >= 60 }
        var seconds: [String: Int] = [:], pages: [String: Int] = [:], chapters: [String: Double] = [:]
        let outlines = Dictionary(try context.fetch(FetchDescriptor<Book>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.map { ($0.id, ($0.pages, ReadingChapters.chapterCount(tocJSON: $0.tocJSON))) }, uniquingKeysWith: { first, _ in first })
        for row in sessions {
            seconds[row.dayKey, default: 0] += row.activeSeconds; pages[row.dayKey, default: 0] += max(0, row.pagesCounted)
            if let id = row.bookID, let outline = outlines[id], let share = ReadingChapters.chapters(pagesRead: row.pagesCounted, bookPages: outline.0, chapterCount: outline.1) { chapters[row.dayKey, default: 0] += share }
        }
        let days = (0..<7).reversed().map { back -> MihbaraReadingGoal.Day in
            let day = today.adding(days: -back), key = day.description
            return .init(day: day, minutes: seconds[key, default: 0] / 60, pages: pages[key, default: 0], chapters: Int(chapters[key, default: 0].rounded(.down)))
        }
        let prayer = try PrayerRepository(context: context), place = prayer.place(at: now), options = prayer.calculationOptions(at: now)
        let recent = sessions.filter { $0.start > now.addingTimeInterval(-30 * 86_400) && $0.start <= now }.map { (start: $0.start, seconds: $0.activeSeconds) }
        // One prayer calculation per calendar day, not one per session: thirty days hold at most thirty.
        var prayerDays: [String: PrayerDay?] = [:]
        let usual = MihbaraReadingGoal.usualStretch(recent) { date in
            let day = GregorianDay.containing(date, in: place.timeZone)
            if let cached = prayerDays[day.description] { return cached }
            let calculated = PrayerTimesEngine.calculate(day: day, place: place, options: options)
            prayerDays[day.description] = .some(calculated)
            return calculated
        }
        // Pace and the finish day come from the last 30 days of counted sessions.
        let samples = sessions.compactMap { row -> ReadingPaceSample? in
            guard row.start > now.addingTimeInterval(-30 * 86_400), let day = try? GregorianDay(row.dayKey) else { return nil }
            return ReadingPaceSample(day: day, seconds: row.activeSeconds, pages: max(0, row.pagesCounted))
        }
        var goal = MihbaraReadingGoal(habit: habit, days: days, usual: usual)
        goal.secondsPerPage = ReadingPace.secondsPerPage(samples)
        if let book, (book.pages ?? 0) <= 0 { goal.bookHasNoPageCount = true }
        if let book, let total = book.pages, total > 0 {
            if let count = ReadingChapters.chapterCount(tocJSON: book.tocJSON) { goal.pagesPerChapter = Double(total) / Double(count) }
            let read = (book.isReadableEPUB || book.isReadablePDF) ? MihbaraCopy.pagesRead(book) : book.page
            if let days = ReadingPace.daysToFinish(remainingPages: total - (read ?? 0), samples: samples, today: today), days > 0 {
                goal.finish = .init(title: MihbaraBookCovers.split(book.title).main, days: days, day: today.adding(days: days))
            }
        }
        return goal
    }
}

/// The reading goal on the Mihbara home: today's share, the streak, seven tappable columns and the usual time.
struct MihbaraReadingGoalCard: View {
    let app: AppSession
    let goal: MihbaraReadingGoal
    let digits: MadarNumberFormatter
    let onCreate: () -> Void
    let onEdit: (HabitReading) -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: String?

    private var current: HabitPeriodResult? { goal.habit?.summary.current }
    private var today: MihbaraReadingGoal.Day? { goal.days.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("وِرد القراءة").font(MadarTypography.section())
                Spacer()
                if let habit = goal.habit {
                    Button("عدّل الهدف") { onEdit(habit) }.font(MadarTypography.caption()).foregroundStyle(theme.accent)
                        .frame(minHeight: 44).buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-goal-edit")
                }
            }
            headline
            // An empty week with no goal is seven blank columns; the offer below says enough.
            if goal.habit != nil || goal.days.contains(where: { $0.minutes > 0 || $0.pages > 0 }) { columns }
            if let selectedDay {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayLine(selectedDay)).font(MadarTypography.caption())
                    MadarDateLabel(app.dateLabels(selectedDay.day, compact: true, weekday: true)).foregroundStyle(theme.secondaryInk)
                }
                .accessibilityElement(children: .combine).accessibilityIdentifier("mihbara-goal-day")
            }
            if let finish = goal.finish {
                VStack(alignment: .leading, spacing: 2) {
                    Label("بهذه الوتيرة تنهي «" + finish.title + "» بعد نحو " + arabicCount(finish.days, ["يوم واحد", "يومين", "أيام", "يومًا"], digits), systemImage: "flag.checkered")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    MadarDateLabel(app.dateLabels(finish.day, compact: true, weekday: false)).foregroundStyle(theme.secondaryInk)
                }
                .accessibilityElement(children: .combine).accessibilityIdentifier("mihbara-goal-finish")
            }
            if let usual = goal.usual {
                Label("تقرأ غالبًا " + usual, systemImage: "clock").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    .accessibilityIdentifier("mihbara-goal-usual")
            }
            if goal.habit == nil {
                Button(action: onCreate) {
                    Text("اجعل للقراءة وِردًا يوميًا").font(MadarTypography.section())
                        .frame(maxWidth: .infinity, minHeight: 48).background(theme.accentFill, in: .capsule).foregroundStyle(theme.onAccent)
                }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-goal-create")
                Text("يُحسب من قراءتك هنا وحدها، ويظهر بين عاداتك في البهو.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .contain).accessibilityIdentifier("mihbara-reading-goal")
    }

    /// The real amount left, «بقي ٧ دقائق»، not a percentage; the streak beside it when there is one.
    @ViewBuilder private var headline: some View {
        if let current, current.target > 0 {
            let left = max(0, current.target - current.value), over = max(0, current.value - current.target)
            VStack(alignment: .leading, spacing: 6) {
                // The goal is a floor, not a ceiling: reading past it is said, and the bar keeps growing beyond the mark.
                Text(over > 0 ? "تجاوزت وِرد اليوم بـ " + habitUnitCount(over, current.rule.unit, digits, genitive: true)
                     : current.met && left == 0 ? "تمّ وِرد اليوم" : "بقي " + habitUnitCount(left, current.rule.unit, digits))
                    .font(.custom("thmanyahserifdisplay-Bold", size: 24, relativeTo: .title2))
                    .contentTransition(.numericText()).accessibilityIdentifier("mihbara-goal-left")
                HStack(spacing: 10) {
                    Text(WidgetCopy.habitProgress(value: current.value, target: current.target, measure: current.rule.measure, unit: current.rule.unit, digits: digits))
                    if let streak = goal.habit?.summary.streak, streak > 0 {
                        Label("سلسلة " + habitPeriodCount(streak, current.rule.frequency, digits), systemImage: "flame").foregroundStyle(theme.accent)
                    }
                }.font(MadarTypography.caption())
                progressBar(value: current.value, target: current.target)
                if let estimate = goal.estimate(left: left, unit: current.rule.unit ?? "minutes") {
                    Label("نحو " + habitUnitCount(estimate.amount, estimate.unit, digits, genitive: true) + " بحسب وتيرتك", systemImage: "hourglass")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("mihbara-goal-estimate")
                }
            }
        } else if goal.habit != nil {
            Text("لا وِرد لهذا اليوم").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
        } else if let today, today.minutes > 0 {
            Text("قرأت اليوم " + habitUnitCount(today.minutes, "minutes", digits, genitive: true)).font(MadarTypography.body())
        } else {
            Text("لم تقرأ هنا اليوم بعد").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
        }
    }

    /// The track fills up to the goal; reading past it adds a second, stronger stretch after a small tick at the goal.
    private func progressBar(value: Int, target: Int) -> some View {
        let scale = Double(max(value, target, 1)), reached = Double(min(value, target)) / scale, tick = Double(target) / scale
        return GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.secondaryInk.opacity(0.15))
                Capsule().fill(theme.accentFill).frame(width: max(6, g.size.width * reached))
                if value > target {
                    Capsule().fill(theme.color("goldUnderstand")).frame(width: max(6, g.size.width * (1 - tick) + 6)).offset(x: g.size.width * tick - 3)
                }
            }
        }
        .frame(height: 6).accessibilityHidden(true)
    }

    private var selectedDay: MihbaraReadingGoal.Day? { selected.flatMap { key in goal.days.first { $0.id == key } } }

    private func dayLine(_ day: MihbaraReadingGoal.Day) -> String {
        guard day.minutes > 0 || day.pages > 0 else { return "لم تقرأ في هذا اليوم" }
        var parts = [habitUnitCount(day.minutes, "minutes", digits, genitive: true)]
        if day.pages > 0 { parts.append(habitUnitCount(day.pages, "pages", digits, genitive: true)) }
        if goal.unit == "chapters", day.chapters > 0 { parts.append(habitUnitCount(day.chapters, "chapters", digits, genitive: true)) }
        return "قرأت " + parts.joined(separator: " و")
    }

    /// Seven columns with the daily target as a quiet line; a tap names the day and its amount.
    private var columns: some View {
        // The quiet line is the daily goal; a weekly or monthly total is not a line a single day can be measured against.
        let target = current.map { $0.rule.frequency == .daily ? $0.target : 0 } ?? 0
        let top = max(1, target, goal.days.map(goal.value).max() ?? 0)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(goal.days) { day in
                let value = goal.value(day), isToday = day.id == goal.days.last?.id, isSelected = selected == day.id
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { selected = isSelected ? nil : day.id }
                } label: {
                    VStack(spacing: 6) {
                        GeometryReader { g in
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(value == 0 ? theme.line : isToday || isSelected ? theme.accentFill : theme.accentFill.opacity(0.45))
                                    .frame(height: value == 0 ? 3 : max(6, g.size.height * CGFloat(value) / CGFloat(top)))
                            }
                        }
                        .frame(height: 64)
                        Text(weekdayInitial(day.day)).font(MadarTypography.fine())
                            .foregroundStyle(isToday || isSelected ? theme.ink : theme.secondaryInk)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.madarPlain)
                .accessibilityLabel(dayLine(day))
                .accessibilityIdentifier("mihbara-goal-column-" + day.id)
            }
        }
        .overlay(alignment: .bottom) {
            if target > 0 {
                GeometryReader { g in
                    let y = 64 - 64 * CGFloat(target) / CGFloat(top)
                    Path { p in p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: g.size.width, y: y)) }
                        .stroke(theme.secondaryInk.opacity(0.5), style: .init(lineWidth: 1, dash: [3, 4]))
                }
                .frame(height: 64).padding(.bottom, 22).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

    private func weekdayInitial(_ day: GregorianDay) -> String {
        ["ح", "ن", "ث", "ر", "خ", "ج", "س"][HabitEngine.weekday(day) - 1]
    }
}
