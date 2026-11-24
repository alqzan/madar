import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarDesign
import MadarCommands

/// Item 26, owner's pick «ج»: a habit kept by «آخر مرة». How long since, on both calendars; every time as a mark on
/// one line to today; and the diary lines of those days, so the habit carries its memories.
struct HabitSinceSection:View {
    @Bindable var session:AppSession
    let reading:HabitReading
    @Environment(\.roomTheme) private var theme
    private var digits:MadarNumberFormatter{.init(style:session.string("core.numerals") == "western" ? .western : .hindi)}
    private var today:GregorianDay { AppBahwService(session:session).today }
    @State private var memory: (request: MemoryRequest, lines: [Memory])?
    private struct MemoryRequest: Equatable {
        let access: HabitDiaryLines.Access
        let times: [HabitTime]
    }
    var body:some View {
        let request = MemoryRequest(access: .init(session), times: Array(reading.times.prefix(3)))
        VStack(alignment:.leading,spacing:16) {
            if let last = reading.lastTime {
                VStack(alignment:.leading,spacing:6) {
                    Text("آخر مرة").font(HabitType.caption()).foregroundStyle(theme.secondaryInk)
                    Text(habitSince(last.day,today,digits)).font(.custom("thmanyahserifdisplay-Bold",size:34,relativeTo:.largeTitle)).accessibilityIdentifier("habit-since")
                    MadarDateLabel(session.dateLabels(last.day,weekday:true))
                    if let rhythm { Text(rhythm).font(HabitType.caption()).foregroundStyle(theme.accent).padding(.top,2) }
                }
                if reading.times.count > 1 { timeline }
                if request.access.allowed, let memory, memory.request == request {
                    memories(memory.lines)
                }
            } else {
                Text("لم تسجّلها بعد؛ سجّل أول مرة اليوم أو في يوم مضى، وتظهر هنا مع سطر مذكراتك يومها.").font(HabitType.caption()).foregroundStyle(theme.secondaryInk)
            }
        }
        .task(id: request) {
            memory = nil
            guard request.access.allowed, !request.times.isEmpty,
                  let lines = try? await HabitDiaryLines.read(Set(request.times.map(\.day)), session: session),
                  !Task.isCancelled else { return }
            let excerpts = request.times.compactMap { time -> Memory? in
                let candidates = lines[time.day] ?? []
                let linked = candidates.first { $0.id == time.entryID }
                return (linked ?? candidates.first).map { Memory(id: $0.id, text: $0.text, day: time.day) }
            }
            memory = (request, excerpts)
        }
        .padding(18).frame(maxWidth:.infinity,alignment:.leading).background(theme.surface,in:.rect(cornerRadius:24))
        .accessibilityElement(children:.contain).accessibilityIdentifier("habit-since-card")
    }
    /// Where the rhythm stands: «إيقاعها سنة، بقي نحو ٤ أشهر» from the current period's end.
    private var rhythm:String? {
        guard let p = reading.summary.current, p.target > 0, p.rule.frequency == .monthly || p.rule.frequency == .yearly else { return nil }
        if p.met { return "تمّت في فترتها؛ "+(p.rule.frequency == .yearly ? "تعود في سنتها القادمة" : "تعود في شهرها القادم") }
        // The gentle nudge the owner asked for: a whole rhythm has passed since the last time.
        if let last = reading.lastTime, HabitRhythmMath.days(last.day,today) >= (p.rule.frequency == .yearly ? 365 : 30) {
            return p.rule.frequency == .yearly ? "مرّت سنة ولم تفعلها؛ لعلّ هذا وقتها" : "مرّ شهر ولم تفعلها؛ لعلّ هذا وقتها"
        }
        let left = HabitRhythmMath.days(today,p.end) // `end` is the next period's first day
        let ahead = left < 14 ? arabicCount(left,["يوم","يومان","أيام","يومًا"],digits) : left < 60 ? arabicCount(left/7,["أسبوع","أسبوعان","أسابيع","أسبوعًا"],digits) : arabicCount(left/30,["شهر","شهران","أشهر","شهرًا"],digits)
        return "إيقاعها "+(p.rule.frequency == .yearly ? "سنة" : "شهر")+"، بقي "+(left < 14 ? "" : "نحو ")+ahead
    }
    /// Every time on one line from the first to today; years mark the line where they turn.
    private var timeline:some View {
        let first = reading.times.last!.day, total = max(1,HabitRhythmMath.days(first,today))
        let years = Array(Set(reading.times.map(\.day.year))).sorted()
        return VStack(alignment:.leading,spacing:8) {
            Text("مراتك").font(HabitType.section())
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment:.topLeading) {
                    Capsule().fill(theme.line).frame(height:2).offset(y:25)
                    ForEach(reading.times,id:\.day) { time in
                        let x = CGFloat(HabitRhythmMath.days(first,time.day))/CGFloat(total)*(w-12)
                        Circle().fill(time.entryID == nil ? theme.accent : theme.accentFill).frame(width:12,height:12)
                            .overlay { if time.entryID != nil { Circle().stroke(theme.surface,lineWidth:2).padding(-2) } }
                            .offset(x:x,y:20)
                    }
                    // Today sits above the same date axis. Even a time logged today remains a separate filled mark.
                    Capsule().fill(theme.accent.opacity(0.5)).frame(width:1,height:17).offset(x:w-6,y:8)
                    Circle().fill(theme.surface).frame(width:14,height:14)
                        .glassEffect(.regular.interactive(), in: .circle).offset(x:w-13,y:0)
                }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).environment(\.layoutDirection,.leftToRight).scaleEffect(x:-1)
            }.frame(height:34)
            HStack {
                timelineYearLabel(first.year)
                Spacer()
                if years.count > 2 { timelineYearLabel(years[years.count/2]); Spacer() }
                Text("اليوم").font(HabitType.fine())
            }.foregroundStyle(theme.secondaryInk)
            Text(arabicCount(reading.times.count,["مرة واحدة","مرتان","مرات","مرة"],digits)+" منذ أول تسجيل").font(HabitType.caption()).foregroundStyle(theme.secondaryInk)
        }.accessibilityElement(children:.combine)
    }
    private func timelineYearLabel(_ year: Int) -> some View {
        MadarDateLabel(session.yearLabels(year), primaryFont: HabitType.caption(), secondaryFont: HabitType.fine())
    }
    /// The diary line linked to each of the last times, or that day's first line when none was linked.
    @ViewBuilder private func memories(_ lines: [Memory]) -> some View {
        if !lines.isEmpty {
            VStack(alignment:.leading,spacing:10) {
                Text("من مذكراتك يومها").font(HabitType.section())
                ForEach(lines,id:\.id) { line in
                    VStack(alignment:.leading,spacing:4) {
                        Text(line.text).font(HabitType.body()).lineLimit(4)
                        Text(session.dateLabels(line.day).combined).font(HabitType.fine()).foregroundStyle(theme.secondaryInk)
                    }
                    .padding(.leading,12).overlay(alignment:.leading) { Capsule().fill(theme.accentFill.opacity(0.5)).frame(width:3) }
                }
            }.accessibilityIdentifier("habit-memories")
        }
    }
    private struct Memory { let id:UUID; let text:String; let day:GregorianDay }
}

enum HabitRhythmMath {
    static func days(_ a:GregorianDay,_ b:GregorianDay)->Int {
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = .gmt
        return calendar.dateComponents([.day],from:a.date(in:.gmt),to:b.date(in:.gmt)).day ?? 0
    }
}
@MainActor enum HabitDiaryLines {
    struct Access: Equatable {
        let allowed: Bool
        private let container: ObjectIdentifier
        private let revision: Int

        @MainActor init(_ session: AppSession) {
            allowed = (try? AppDiaryService(app: session).authorizeRead()) != nil
            container = ObjectIdentifier(session.container)
            revision = session.prayerRevision
        }
    }

    struct Line: Identifiable, Sendable {
        let id: UUID
        let text: String
    }

    static func read(_ days: Set<GregorianDay>, session: AppSession) async throws -> [GregorianDay: [Line]] {
        let diary = AppDiaryService(app: session)
        try diary.authorizeRead()
        let container = session.container, generation = session.storeGeneration
        let lines = try await readDays(days, container: container)
        try Task.checkCancellation()
        try diary.authorizeRead()
        guard session.storeGeneration == generation, session.container === container else { throw CancellationError() }
        return lines
    }

    @concurrent private static func readDays(_ days: Set<GregorianDay>, container: ModelContainer) async throws -> [GregorianDay: [Line]] {
        let context = ModelContext(container)
        var result: [GregorianDay: [Line]] = [:]
        for day in days {
            try Task.checkCancellation()
            let key = day.description
            // Diary edits keep the original dayKey, including the whole live revision chain in this fetch.
            let entries = try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate {
                $0.dayKey == key && $0.deletedAt == nil && $0.mergedInto == nil && $0.source != "autoPinned"
            }, sortBy: [SortDescriptor(\.createdAt)])).filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            result[day] = AppDiaryService.visible(entries).map { Line(id: $0.id, text: $0.text) }
        }
        return result
    }
}

/// «فعلتها في يوم سابق»: pick the day, optionally the diary line it belongs to, and log it in that day's period.
struct HabitPastDaySheet:View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var session:AppSession
    let reading:HabitReading
    let done:()->Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var entry:UUID?
    @State private var busy = false
    @State private var loadedLines: (request: LineRequest, lines: [HabitDiaryLines.Line])?
    private struct LineRequest: Equatable {
        let access: HabitDiaryLines.Access
        let day: GregorianDay
    }
    private var theme:RoomTheme{.init(room:"bahw",dark:colorScheme == .dark)}
    private var today:GregorianDay { AppBahwService(session:session).today }
    private var first:GregorianDay { reading.firstEffectiveFrom }
    private var defaultDay:GregorianDay { max(first,today.adding(days:-1)) }
    private var day:GregorianDay { GregorianDay.containing(date,in:.gmt) }
    private var selectedPeriod: HabitPeriodResult? { reading.summary.periods.last { $0.start <= day && day < $0.end } }
    private var selectedRule: HabitRule? { selectedPeriod?.rule }
    private var hasSelectedTarget: Bool { day >= reading.firstEffectiveFrom && (selectedPeriod?.target ?? 0) > 0 && !reading.breaks.contains { $0.contains(day) } }
    private var delta: Int { selectedRule?.measure == .duration ? 15 : 1 }
    private var saveTitle: String {
        guard let rule = selectedRule, rule.measure != .once else { return "سجّلها في يومها" }
        return "أضف " + habitUnitCount(delta, rule.unit, AppBahwService(session: session).digits) + " في يومها"
    }
    private func gmt(_ d:GregorianDay)->Date { d.date(in:.gmt) }
    private var lineRequest: LineRequest? {
        let access = HabitDiaryLines.Access(session)
        guard access.allowed, day >= first, day < today else { return nil }
        return LineRequest(access: access, day: day)
    }
    var body:some View {
        let request = lineRequest
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                HStack {
                    Text("فعلتها في يوم سابق").font(HabitType.title())
#if DEBUG
                    if ProcessInfo.processInfo.environment["MADAR_UI_BAHW_ROOT_ROUTE_HARNESS"] == "1" {
                        Button("اختبر رابط البهو") { session.open(URL(string: "madar://bahw")!) }
                            .accessibilityIdentifier("ui-test-open-bahw-root")
                    }
#endif
                    Spacer(); Button {dismiss()} label: { Text("إلغاء").frame(minHeight:44).contentShape(Rectangle()) }.madarWaitsForSave()
                }
                Text(reading.name).font(HabitType.section()).foregroundStyle(theme.secondaryInk)
                if first < today {
                    DatePicker("اليوم",selection:$date,in:gmt(first)...gmt(today.adding(days:-1)),displayedComponents:.date)
                        .datePickerStyle(.graphical).environment(\.timeZone,.gmt).padding(8).background(theme.surface,in:.rect(cornerRadius:20)).accessibilityIdentifier("habit-past-date")
                    MadarDateLabel(session.dateLabels(day,weekday:true))
                    if !hasSelectedTarget {
                        Text("هذا اليوم ليس من أيام العادة، اختر يومًا آخر.").font(HabitType.caption()).foregroundStyle(theme.secondaryInk)
                            .accessibilityIdentifier("habit-past-unavailable")
                    }
                    let lines = request == loadedLines?.request ? loadedLines?.lines ?? [] : []
                    if !lines.isEmpty {
                        VStack(alignment:.leading,spacing:8) {
                            Text("اربطها بسطر من مذكراتك يومها").font(HabitType.section())
                            ForEach(lines,id:\.id) { line in
                                let on = entry == line.id
                                Button { entry = on ? nil : line.id } label: {
                                    HStack(alignment:.top,spacing:10) {
                                        Image(systemName:on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? theme.accent : theme.secondaryInk)
                                        Text(line.text).font(HabitType.body()).lineLimit(3).frame(maxWidth:.infinity,alignment:.leading)
                                    }.padding(12).background(theme.surface,in:.rect(cornerRadius:16)).contentShape(.rect)
                                }.buttonStyle(.madarPlain).accessibilityAddTraits(on ? .isSelected : []).accessibilityIdentifier("habit-past-line")
                            }
                        }
                    }
                    Button { log() } label: { Text(saveTitle).font(HabitType.section()).frame(maxWidth:.infinity,minHeight:48).background(theme.accentFill,in:.capsule).foregroundStyle(theme.onAccent) }
                        .buttonStyle(.madarPlain).disabled(busy || !hasSelectedTarget).accessibilityIdentifier("habit-past-save")
                } else {
                    Text("بدأت العادة اليوم؛ لا يوم قبله في سجلها.").font(HabitType.caption()).foregroundStyle(theme.secondaryInk)
                }
            }.padding(22)
        }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.accent).environment(\.roomTheme,theme)
        .madarSheetLock(saving: busy, draft: entry != nil || day != defaultDay)
        .onAppear { date = gmt(defaultDay) }
        .onChange(of:date) { entry = nil }
        .task(id: request) {
            loadedLines = nil
            guard let request,
                  let lines = try? await HabitDiaryLines.read([request.day], session: session)[request.day],
                  !Task.isCancelled else { return }
            loadedLines = (request, lines)
            if let entry, !lines.contains(where: { $0.id == entry }) { self.entry = nil }
        }
    }
    private func log() {
        guard !busy else { return }
        busy = true
        var payload:[String:MadarCore.JSONValue] = ["id":.string(reading.id.uuidString),"day":.string(day.description),"delta":.number(Double(delta))]
        if let entry, let loadedLines, loadedLines.request == lineRequest,
           loadedLines.lines.contains(where: { $0.id == entry }) {
            payload["entryID"] = .string(entry.uuidString)
        }
        Task { do { try await session.executeDiaryCommand("habit.complete",payload:payload); dismiss(); done() } catch { session.errorMessage = madarUserMessage(error) }; busy = false }
    }
}
