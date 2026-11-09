import SwiftUI
import MadarCore
import SwiftData
import MadarCommands
import MadarDesign
import MadarSnapshots
import WidgetKit

/// Built lobby blocks at the four sizes (§7.1 «ما تعرضه كل ودجة»). Room identities: prayer warm paper with
/// gold arches, Quran green cover with gold, diary the day's photo, year and upcoming on lobby paper.
struct BahwBlockView: View {
    let service: AppBahwService
    let block: BahwBlock
    let size: BahwBlockSize
    var interactive = true
    /// §7.1 «المال مخفي حتى اللمس»: the lobby shows the figures for four seconds after a touch, then hides them again.
    var moneyRevealed = false
    @State private var mihbaraSnapshot: MihbaraSnapshot?
    @State private var mihbaraLocked = true
    private var habitPeriod: HabitFrequency? {
        get { service.session.lobbyHabitPeriod.flatMap(HabitFrequency.init(rawValue:)) }
        nonmutating set { service.session.lobbyHabitPeriod = newValue?.rawValue }
    }
    @State private var completionInFlight: Set<UUID> = []
    /// The lobby reads the full prayer history once per minute off the main actor, then reuses its projection for redraws.
    @State private var prayerModel: BahwPrayerModel?
    @State private var prayerLoadedKey: [Int] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.roomTheme) private var lobby
    @Environment(\.isFrontRoom) private var isFrontRoom
    private var dark: Bool { lobby.dark }
    private var room: RoomTheme {
        switch block { case .salah: RoomTheme(room: "salah", dark: dark); case .quran: RoomTheme(room: "quran", dark: dark); case .notes: RoomTheme(room: "notes", dark: dark); case .mihbara: RoomTheme(room: "mihbara", dark: dark); default: lobby }
    }
    private var widgetFamily: WidgetFamily { switch size { case .icon: .accessoryCircular; case .small: .systemSmall; case .wide: .systemMedium; case .large: .systemLarge } }
    private var mayReadMihbara: Bool { service.session.lockController?.canPresent(.app) ?? service.session.protectedDataAuthorized }
    var body: some View {
        content
            .padding(size == .icon ? 8 : 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(background, in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(block == .quran ? room.color("gold").opacity(0.35) : room.line) }
            .clipShape(.rect(cornerRadius: 22))
            .task(id: block) { refreshMihbaraSnapshot() }
            .onChange(of: mayReadMihbara) { _, _ in refreshMihbaraSnapshot() }
            .onChange(of: service.session.prayerRevision) { _, _ in if isFrontRoom { refreshMihbaraSnapshot() } }
            .onChange(of: service.session.selectedTab) { _, selected in
                if selected == "foundation" { refreshMihbaraSnapshot() }
            }
    }
    private var background: Color { if block == .mal { return MadarToken.colors["widgetIdentity.room.mal.\(dark ? "dark" : "light").bg"] ?? lobby.surface }; return block == .quran ? room.color("cover") : room.surface }
    private var digits: MadarNumberFormatter { service.digits }
    private var big: Font { .custom("thmanyahserifdisplay-Bold", size: size == .icon ? 22 : 40, relativeTo: .largeTitle) }
    private var label: Font { .custom("thmanyahsans-Bold", size: 14, relativeTo: .footnote) }
    private var small: Font { .custom("thmanyahsans-Regular", size: 12, relativeTo: .caption) }

    @ViewBuilder private var content: some View {
        switch block {
        case .mal: money
        case .habits: habits
        case .salah:
            let key = prayerKey, isFront = isFrontRoom
            salah.task(id: key + [isFront ? 1 : 0]) {
                guard isFront else { return }
                await refreshPrayer(for: key)
            }
        case .quran: quran
        case .notes: notes
        case .year: year
        case .upcoming: upcoming
        case .mihbara: mihbara
        }
    }
    private var mihbara: some View {
        RoomWidgetContent(room: .mihbara, snapshot: nil, family: widgetFamily,
                          mihbaraSnapshot: mihbaraSnapshot, mihbaraLocked: mihbaraLocked,
                          numerals: service.session.string("core.numerals"))
    }
    private func refreshMihbaraSnapshot() {
        guard block == .mihbara else { return }
        let allowed = mayReadMihbara
        mihbaraLocked = !allowed
        mihbaraSnapshot = allowed ? service.session.mihbaraWidgetSnapshot(locked: false, at: service.now) : nil
    }
    private func title(_ color: Color) -> some View {
        Label { Text(block.title) } icon: { MadarGlyph(block.symbol, size: 17) }.font(label).foregroundStyle(color).labelStyle(.titleAndIcon).lineLimit(1)
    }

    @ViewBuilder private var money: some View {
        if size == .icon {
            let payload = service.session.moneyWidgetPayload(hidden: service.session.bool("core.hideMoneyUntilTouch") && !moneyRevealed, at: service.now)
            VStack(spacing: 2) { Text("لك الآن").font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)); displayFigure(payload.rows.first?.value ?? "افتح", "thmanyahserifdisplay-Bold", size: 22, relativeTo: .largeTitle).lineLimit(1).minimumScaleFactor(0.7) }.frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(MadarToken.colors["widgetIdentity.room.mal.\(dark ? "dark" : "light").ink"] ?? lobby.ink)
        } else { MoneyWidgetContent(snapshot: service.session.moneyWidgetPayload(hidden: service.session.bool("core.hideMoneyUntilTouch") && !moneyRevealed, at: service.now), family: size == .icon ? .accessoryCircular : size == .small ? .systemSmall : size == .wide ? .systemMedium : .systemLarge, template: size == .wide ? "basis" : "now") }
    }

    private func periodRing(_ f: HabitFrequency, rows: [HabitReading], selected: Bool) -> some View {
        let group = rows.filter { $0.summary.current?.rule.band == f }
        let met = group.filter { $0.summary.current?.met == true }.count
        let share: Double = group.isEmpty ? 0 : Double(met) / Double(group.count)
        let spoken: String = group.isEmpty ? "لا عادات" : digits.string(met) + " من " + digits.string(group.count)
        return Button { withAnimation(reduceMotion ? nil : .snappy) { habitPeriod = f } } label: {
            VStack(spacing: 3) {
                Text(f.arabic).font(selected ? label : small).lineLimit(1)
                Capsule().fill(selected ? room.accentFill : room.line)
                    .frame(height: selected ? 3 : 2)
                    .overlay(alignment: .leading) {
                        if !selected && !group.isEmpty {
                            GeometryReader { proxy in
                                Capsule().fill(room.accentFill).frame(width: proxy.size.width * share)
                            }
                        }
                    }
            }
            .foregroundStyle(selected ? room.accent : room.secondaryInk)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect).opacity(group.isEmpty ? 0.45 : 1)
        }.buttonStyle(.madarPlain).disabled(!interactive || group.isEmpty)
        .accessibilityLabel(f.arabic + "، " + spoken)
        .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier("bahw-habits-period-" + f.rawValue)
    }
    private func periodChoice(_ f: HabitFrequency, rows: [HabitReading], selected: Bool) -> some View {
        let group = rows.filter { $0.summary.current?.rule.band == f }
        let met = group.filter { $0.summary.current?.met == true }.count
        let spoken = group.isEmpty ? "لا عادات" : digits.string(met) + " من " + digits.string(group.count)
        return Button { withAnimation(reduceMotion ? nil : .snappy) { habitPeriod = f } } label: {
            Text(f.arabic + "، " + spoken)
                .font(MadarTypography.caption())
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 4)
                .background(selected ? room.accentFill : room.background, in: .rect(cornerRadius: 12))
                .foregroundStyle(selected ? room.onAccent : room.secondaryInk)
        }
        .buttonStyle(.madarPlain)
        .disabled(!interactive || group.isEmpty)
        .accessibilityLabel(f.arabic + "، " + spoken)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("bahw-habits-period-" + f.rawValue)
    }
    private func habitProgress(_ row: HabitReading) -> String {
        if row.paused { return "مجمّدة" }
        guard let current = row.summary.current else { return "لا فترة بعد" }
        if current.outcome == .excluded { return "إجازتها اليوم" }
        if current.rule.measure == .once {
            if current.outcome == .minimum { return "أقلّ القليل" }
            return current.met ? "تمّت" : "لم تتمّها بعد"
        }
        guard current.target > 0 else { return row.statusTitle }
        return habitProgressText(current.value, current.target, current.rule.unit, digits)
    }
    private func activateHabit(_ row: HabitReading) {
        if row.source == "walking" { service.session.habitsOpen = true }
        else if let source = row.source {
            switch source {
            case "jamaah": service.session.selectedTab = "prayer"
            case "review", "wird": service.session.selectedTab = "quran"
            case "diaryLine": service.session.selectedTab = "notes"
            case "reading", "hadith": service.session.selectedTab = "mihbara"
            default: service.session.errorMessage = "لا توجد غرفة مرتبطة بهذا المصدر."
            }
        }
        else {
            guard !completionInFlight.contains(row.id) else { return }
            completionInFlight.insert(row.id)
            Task {
                defer { completionInFlight.remove(row.id) }
                do {
                    try await service.session.executeDiaryCommand("habit.complete", payload: [
                        "id": .string(row.id.uuidString),
                        "delta": .number(row.summary.current?.rule.measure == .duration ? 15 : 1)
                    ])
                } catch { service.session.errorMessage = madarUserMessage(error) }
            }
        }
    }
    private func habitRing(_ row: HabitReading) -> some View {
        let ringSide: CGFloat = size == .wide ? 32 : 42
        let current = row.summary.current
        let share = Double(current?.value ?? 0) / Double(max(1, current?.target ?? 1))
        let progress = habitProgress(row)
        let compactProgress = current.map { digits.string($0.value) + " من " + digits.string($0.target) } ?? progress
        let ringTheme: RoomTheme = switch row.source {
        case "jamaah": .init(room: "salah", dark: dark)
        case "review", "wird": .init(room: "quran", dark: dark)
        case "diaryLine": .init(room: "notes", dark: dark)
        case "reading", "hadith": .init(room: "mihbara", dark: dark)
        default: room
        }
        return Button { activateHabit(row) } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    // DA-05: the same coloured ring and glyph as the wide card.
                    HabitRingGlyph(share: row.paused ? 0 : share, done: current?.met == true, symbol: row.symbol == "checkmark" ? nil : row.symbol, lineWidth: 4)
                        .environment(\.roomTheme, ringTheme).opacity(row.paused ? 0.45 : 1)
                        .frame(width: ringSide, height: ringSide)
                    if row.paused || (row.source != nil && current?.outcome == .complete) {
                        Image(systemName: row.paused ? "pause.fill" : "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(room.ink)
                            .padding(3)
                            .background(room.surface, in: .circle)
                            .offset(x: 1, y: -1)
                    }
                }
                Text(row.name).font(small).lineLimit(2, reservesSpace: true).multilineTextAlignment(.center)
                // Tour 25 Oct: an empty ring already says «not yet»; the line below speaks only when it adds something.
                if size != .wide, row.summary.streak > 1, current?.met != true { HabitFlame(count: row.summary.streak, frequency: current?.rule.frequency ?? .daily, digits: digits) }
                else if progress != "لم تتمّها بعد" { Text(size == .wide && !row.paused && (current?.target ?? 0) > 0 ? compactProgress : progress).font(MadarTypography.fine()).foregroundStyle(room.secondaryInk).lineLimit(size == .wide ? 1 : 2).multilineTextAlignment(.center) }
            }
            .frame(maxWidth: .infinity, minHeight: size == .wide ? 78 : 100, maxHeight: size == .wide ? 78 : nil, alignment: .top)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.madarPlain)
        .disabled(!interactive || row.paused || completionInFlight.contains(row.id))
        .accessibilityLabel(row.name + "، " + progress + (row.statusTitle == progress ? "" : "، " + row.statusTitle))
        .accessibilityHint(row.source == nil ? "المس لتسجيل العادة" : "المس لفتح الغرفة المرتبطة")
        .accessibilityIdentifier("bahw-habit-ring-" + row.id.uuidString)
    }
    /// W1 ring: 46 pt, the habit's room colour, its glyph inside, a half-moon badge when a period was missed.
    private func wideHabitRing(_ row: HabitReading, shown6: Bool) -> some View {
        let current = row.summary.current
        let done = current?.met == true
        let share = Double(current?.value ?? 0) / Double(max(1, current?.target ?? 1))
        let progress = habitProgress(row)
        let amount: String = {
            guard let current, !row.paused else { return progress }
            if current.rule.measure == .once || current.target <= 1 { return done ? "تمّت" : current.rule.frequency == .daily ? "باقية" : current.rule.frequency.arabic }
            return digits.string(current.value) + " من " + digits.string(current.target)
        }()
        let ringTheme: RoomTheme = switch row.source {
        case "jamaah": .init(room: "salah", dark: dark)
        case "review", "wird": .init(room: "quran", dark: dark)
        case "diaryLine": .init(room: "notes", dark: dark)
        case "reading", "hadith": .init(room: "mihbara", dark: dark)
        default: room
        }
        return Button { activateHabit(row) } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    HabitRingGlyph(share: row.paused ? 0 : share, done: done, symbol: row.symbol == "checkmark" ? nil : row.symbol, lineWidth: 4.5)
                        .environment(\.roomTheme, ringTheme)
                        .opacity(row.paused ? 0.45 : 1)
                        .frame(width: 46, height: 46)
                    if row.paused || (row.summary.atRisk && !done) {
                        Image(systemName: row.paused ? "pause.circle.fill" : "circle.lefthalf.filled")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(room.accent)
                            .background(room.surface, in: .circle).offset(x: 3, y: -3)
                    }
                }
                Text(row.name).font(.custom("thmanyahsans-Bold", size: 12, relativeTo: .caption)).lineLimit(2, reservesSpace: shown6).multilineTextAlignment(.center).minimumScaleFactor(0.85).padding(.horizontal, 1)
                Text(amount).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(room.secondaryInk).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.madarPlain)
        .disabled(!interactive || row.paused || completionInFlight.contains(row.id))
        .accessibilityLabel(row.name + "، " + progress + (row.statusTitle == progress ? "" : "، " + row.statusTitle))
        .accessibilityHint(row.source == nil ? "المس لتسجيل العادة" : "المس لفتح الغرفة المرتبطة")
        .accessibilityIdentifier("bahw-habit-ring-" + row.id.uuidString)
    }
    private func habitListRow(_ row: HabitReading) -> some View {
        let progress = habitProgress(row)
        return Button { activateHabit(row) } label: {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name).font(MadarTypography.body())
                    Spacer(minLength: 8)
                    Text(progress).font(MadarTypography.caption()).foregroundStyle(room.secondaryInk)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name).font(MadarTypography.body())
                    Text(progress).font(MadarTypography.caption()).foregroundStyle(room.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.madarPlain)
        .disabled(!interactive || row.paused || completionInFlight.contains(row.id))
        .accessibilityLabel(row.name + "، " + progress + (row.statusTitle == progress ? "" : "، " + row.statusTitle))
        .accessibilityHint(row.source == nil ? "المس لتسجيل العادة" : "المس لفتح الغرفة المرتبطة")
        .accessibilityIdentifier("bahw-habit-item-" + row.id.uuidString)
    }
    private func wideHabitStep(_ row: HabitReading) -> String {
        guard let period = row.summary.current else { return row.name }
        let amount = max(0, (row.summary.atRisk ? period.rule.minimum ?? period.target : period.target) - period.value)
        let step = period.rule.measure == .once ? "أكملها اليوم" : "بقي " + habitUnitCount(amount, period.rule.unit, digits)
        return row.name + ": " + (row.summary.atRisk ? row.missedPhrase(digits) + "، " : "") + step
    }

    @ViewBuilder private var habits: some View {
        let rows = service.session.habitReadings(at: service.now)
        let daily = rows.filter { !$0.paused && $0.summary.current?.rule.frequency == .daily && ($0.summary.current?.target ?? 0) > 0 }
        let met = daily.filter { $0.summary.current?.met == true }.count
        if size == .icon {
            // A 1×1 cell has no room for the full card header or the next-habit details.
            // The lobby makes this whole indicator a room-entry button.
            VStack(spacing: 4) {
                ZStack {
                    HabitMiniRing(share: Double(met) / Double(max(1, daily.count)), theme: room)
                        .frame(width: 38, height: 38)
                    if !daily.isEmpty {
                        Text(digits.string(met) + "/" + digits.string(daily.count))
                            .font(MadarTypography.fine()).lineLimit(1)
                            .frame(maxWidth: 30)
                            .accessibilityLabel(digits.string(met) + " من " + digits.string(daily.count) + " اليوم")
                            .accessibilityIdentifier("bahw-habits-icon-count")
                    } else {
                        Image(systemName: rows.isEmpty ? "plus" : "moon")
                            .font(.system(size: 13)).foregroundStyle(room.accent)
                    }
                }
                Text(rows.isEmpty ? "ابدأ عادة" : "عاداتك").font(MadarTypography.fine())
                    .lineLimit(1).foregroundStyle(room.accent)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
        VStack(alignment:.leading,spacing:size == .wide ? 4 : 10) {
            Button { service.session.habitsOpen = true } label: { HStack { title(room.accent); Spacer();if !daily.isEmpty { if size == .wide { Text(digits.string(met)+" من "+digits.string(daily.count)+" اليوم").font(small).foregroundStyle(room.secondaryInk) } else { Text(digits.string(met)+" من "+digits.string(daily.count)).font(label).foregroundStyle(room.accent)} } }.frame(minHeight:44).contentShape(.rect) }.buttonStyle(.madarPlain).accessibilityIdentifier("bahw-habits-open").disabled(!interactive)
            if rows.isEmpty {
                // Improvement 16 Oct: no «٠ من ٠»; the four period rings at rest show what a habit becomes, and the action is a real button.
                Spacer(minLength:0)
                if size == .large {
                    HStack {
                        ForEach([HabitFrequency.daily, .weekly, .monthly, .yearly], id: \.self) { f in
                            if dynamicTypeSize.isAccessibilitySize { Text(f.arabic).font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 44) }
                            else { VStack(spacing: 4) { HabitMiniRing(share: 0, theme: room).frame(width: 24, height: 24); Text(f.arabic).font(small).foregroundStyle(room.secondaryInk) }.frame(maxWidth: .infinity) }
                        }
                    }.accessibilityHidden(true).padding(.bottom, 12)
                }
                Text("عادة صغيرة تدوم").font(size == .icon ? small : big)
                if size == .icon { EmptyView() }
                else if size == .small { Text("أضف أول عادة").font(small).foregroundStyle(room.secondaryInk) }
                else {
                    Button { service.session.habitsOpen = true } label: { Label("أضف أول عادة", systemImage: "plus").font(label).padding(.horizontal,18).frame(minHeight:44).foregroundStyle(room.onAccent).background(room.accentFill, in: .capsule) }
                        .buttonStyle(.madarPlain).disabled(!interactive).padding(.top,6).accessibilityIdentifier("bahw-habits-add-first")
                }
                Spacer(minLength:0)
            }
            else if size == .large {
                // Owner 20 Oct («ولا فيه تفريق صاحي»): the period rings choose which habits the grid shows, as in the
                // habits room; it opens on the first period with something unfinished.
                let periods=[HabitFrequency.daily,.weekly,.monthly,.yearly]
                let open=periods.first{f in rows.contains{$0.summary.current?.rule.band == f && $0.summary.current?.met != true && !$0.paused}} ?? periods.first{f in rows.contains{$0.summary.current?.rule.band == f}} ?? .daily
                let period=habitPeriod.flatMap{p in rows.contains{$0.summary.current?.rule.band == p} ? p : nil} ?? open
                let shown=service.session.habitRowsForWidgetScope(rows.filter{$0.summary.current?.rule.band == period})
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { ForEach(periods, id: \.self) { f in periodChoice(f, rows: rows, selected: f == period) } }
                            ForEach(Array(shown.prefix(6))) { row in habitListRow(row) }
                            if shown.count > 6 { Button("افتح بقية العادات") { service.session.habitsOpen = true }.font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()) }
                            BahwHabitsWide(rows: service.session.habitRowsForWidgetScope(rows), digits: digits, theme: room, interactive: interactive, showsPeriods: false) { service.session.habitsOpen = true }
                        }
                    }
                } else {
                    HStack { ForEach(periods, id: \.self) { f in periodRing(f, rows: rows, selected: f == period) } }
                    HStack(alignment: .top, spacing: 3) {
                        ForEach(Array(shown.prefix(6))) { row in habitRing(row) }
                    }
                    Spacer(minLength: 0)
                    BahwHabitsWide(rows: service.session.habitRowsForWidgetScope(rows), digits: digits, theme: room, interactive: interactive, showsPeriods: false) {
                        service.session.habitsOpen = true
                    }
                }
            } else if size == .wide {
                if dynamicTypeSize.isAccessibilitySize {
                    BahwHabitsWide(rows: service.session.habitRowsForWidgetScope(rows), digits: digits, theme: room, interactive: interactive) {
                        service.session.habitsOpen = true
                    }
                } else {
                    let daily = rows.filter { $0.summary.current?.rule.frequency == .daily }
                    let shown = service.session.habitRowsForWidgetScope(daily.isEmpty ? rows : daily)
                    // DA-05 (owner 27 Oct, «وش ذا القبح»): W1's rings, thick and in each habit's own room colour with
                    // its glyph inside, the name and the amount beneath; a habit at risk speaks first, then the week.
                    HStack(alignment: .top, spacing: 2) {
                        ForEach(Array(shown.prefix(6))) { row in wideHabitRing(row, shown6: shown.count > 4) }
                    }
                    Spacer(minLength: 0)
                    // The rings already say «٠ من ٨»; the line speaks only when a habit is at risk, so it never repeats a ring.
                    if let next = shown.first(where: { !$0.paused && $0.summary.atRisk && $0.summary.current?.met != true }) {
                        Label { Text(wideHabitStep(next)) } icon: { Image(systemName: next.summary.atRisk ? "circle.lefthalf.filled" : "circle.dotted").font(.system(size: 11, weight: .semibold)) }
                            .font(MadarTypography.fine()).foregroundStyle(room.accent)
                            .lineLimit(1).accessibilityIdentifier("bahw-habits-wide-step")
                    }
                    let week = rows.filter { !$0.paused && $0.summary.current?.rule.frequency == .weekly && ($0.summary.current?.target ?? 0) > 0 }
                    if !week.isEmpty, !daily.isEmpty {
                        Text("هذا الأسبوع: " + week.prefix(3).map { r in r.summary.current?.met == true ? r.name + " تمّت" : r.name + " " + digits.string(r.summary.current?.value ?? 0) + " من " + (r.summary.current?.rule.unit.map { u in habitUnitCount(r.summary.current?.target ?? 0, u, digits, genitive: true) } ?? digits.string(r.summary.current?.target ?? 0)) }.joined(separator: "، "))
                            .font(MadarTypography.fine()).foregroundStyle(room.secondaryInk)
                            .lineLimit(1).accessibilityIdentifier("bahw-habits-wide-week")
                    }
                }
            } else {
                Spacer(minLength:0)
                HabitMiniRing(share:Double(met)/Double(max(1,daily.count)),theme:room).frame(width:34,height:34)
                if let next=service.session.habitRowsForWidgetScope(rows).first(where:{$0.summary.current?.met != true && !$0.paused}) {
                    Text(next.name).font(small).lineLimit(1)
                }
                if size == .small, let risk=rows.first(where:{$0.summary.atRisk && !$0.paused}) {
                    Text(risk.missedPhrase(digits))
                        .font(small).foregroundStyle(room.accent).lineLimit(1).accessibilityIdentifier("bahw-habits-at-risk")
                }
                Spacer(minLength:0)
            }
        }
        }
    }

    // MARK: prayer
    private var prayerKey: [Int] {
        [Int(service.now.timeIntervalSince1970 / 60), service.session.prayerRevision]
    }
    private var currentPrayer: BahwPrayerModel? {
        let key = prayerKey, instant = service.now
        if prayerLoadedKey == key { return prayerModel }
        guard prayerLoadedKey.count == 2,
              prayerLoadedKey[1] == key[1],
              prayerModel?.nextAt.map({ $0 > instant }) == true else { return nil }
        return prayerModel
    }
    private func refreshPrayer(for key: [Int]) async {
        guard block == .salah, prayerLoadedKey != key else { return }
        let instant = service.now
        guard key == [Int(instant.timeIntervalSince1970 / 60), service.session.prayerRevision] else { return }
        do {
            let snapshot = try await service.session.prayerSnapshotOffMain(at: instant)
            try Task.checkCancellation()
            guard key == prayerKey else { return }
            prayerModel = AppBahwService(session: service.session, evaluationDate: instant).prayer(snapshot: snapshot)
            prayerLoadedKey = key
        } catch is CancellationError {
        } catch {
            guard key == prayerKey else { return }
            prayerModel = nil
            prayerLoadedKey = key
        }
    }
    @ViewBuilder private var salah: some View {
        if let model = currentPrayer {
            if size == .icon {
                VStack(spacing: 2) { Text(model.nextName ?? "الصلاة").font(small).foregroundStyle(room.secondaryInk); Text(model.nextTime ?? "").font(big).minimumScaleFactor(0.6) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: size == .small ? 8 : 6) {
                    HStack { title(room.accent).accessibilityLabel("الصلاة في " + service.session.cityName); Spacer(); if model.done > 0 { Text(digits.string(model.done) + " من " + digits.string(5)).font(small).foregroundStyle(room.secondaryInk).accessibilityIdentifier("bahw-salah-done") } }
                    HStack(alignment: .bottom, spacing: size == .small ? 4 : 10) {
                        ForEach(model.arches) { arch in
                            VStack(spacing: 4) {
                                // DA-05: W1's arches: a star in each (prayed in ink, the next faint, the rest paler),
                                // Jumu'ah stands taller, and prayers still ahead are drawn lighter than the day's done ones.
                                let jumuah = arch.name == "الجمعة", ahead = !arch.done && !arch.next
                                ZStack {
                                    PrayerHorseshoe().fill(arch.done ? room.color("goldMid").opacity(0.45) : room.surface)
                                    PrayerHorseshoe().stroke(room.accent.opacity(ahead ? 0.4 : 1), lineWidth: arch.next ? 2.4 : 1.2)
                                    PrayerStar().fill(arch.done ? room.accent : arch.next ? room.accent.opacity(0.35) : room.ink.opacity(0.14))
                                        .frame(width: 10, height: 10).offset(y: -2)
                                }.frame(maxWidth: size == .small ? 26 : 34).frame(height: (size == .small ? 36 : 40) + (jumuah ? 8 : 0)).accessibilityHidden(true)
                                if size != .small { Text(arch.name + " " + arch.time).font(small).lineLimit(1).minimumScaleFactor(0.6) }
                            }.frame(maxWidth: .infinity)
                                .accessibilityElement(children: .ignore).accessibilityLabel(arch.name + "، " + arch.clock24 + (arch.done ? "، صُلّيت" : ""))
                                .accessibilityIdentifier("foundation-prayer-time-" + arch.id)
                        }
                    }
                    Spacer(minLength: 0)
                    if let name = model.nextName {
                        let layout = size == .small ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: 8))
                        layout {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("القادمة").font(small).foregroundStyle(room.secondaryInk)
                                Text(name + " " + (model.nextTime ?? "")).font(.custom("thmanyahserifdisplay-Bold", size: size == .small ? 20 : 24, relativeTo: .title2)).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            if size != .small { Spacer(minLength: 0) }
                            if let after = model.nextAfter { Text(after).font(label).foregroundStyle(room.accent).lineLimit(1).minimumScaleFactor(0.8) }
                        }.accessibilityElement(children: .combine).accessibilityIdentifier("bahw-salah-next")
                    }
                }
            }
        } else if prayerLoadedKey != prayerKey {
            ProgressView().controlSize(.small).tint(room.accent)
                .accessibilityLabel("جارٍ تحديث مواقيت الصلاة")
                .accessibilityIdentifier("bahw-salah-loading")
        } else {
            Text("المواقيت غير متاحة لهذا الموقع اليوم.").font(small).foregroundStyle(room.secondaryInk)
        }
    }

    // MARK: Quran
    @ViewBuilder private var quran: some View {
        let gold = room.color("gold"), on = room.color("onCover")
        if let model = service.quran() {
            if size == .icon {
                VStack(spacing: 2) { MadarGlyph("MadarQuran", size: 22).foregroundStyle(gold); Text(model.coverage).font(small).foregroundStyle(on).multilineTextAlignment(.center).minimumScaleFactor(0.6) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    title(gold)
                    Text("في صدرك").font(small).foregroundStyle(on)
                    Text(model.coverage).font(.custom("thmanyahserifdisplay-Bold", size: size == .small ? 24 : 30, relativeTo: .title)).foregroundStyle(gold).lineLimit(2).minimumScaleFactor(0.6).accessibilityIdentifier("bahw-quran-coverage")
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        ForEach(Array(model.days.enumerated()), id: \.offset) { _, day in
                            RoundedRectangle(cornerRadius: 2).fill(day.review > 0 || day.hifz > 0 ? room.color("memorized") : on.opacity(0.18)).frame(height: 12)
                        }
                    }.accessibilityLabel("مراجعة آخر سبعة أيام")
                    Text(model.next).font(small).foregroundStyle(on).lineLimit(1)
                }
            }
        } else { Text("افتح القرآن لتبدأ.").font(small).foregroundStyle(on) }
    }

    // MARK: diary
    @ViewBuilder private var notes: some View {
        let model = service.diary()
        let count = model?.count ?? 0
        if size == .icon {
            VStack(spacing: 2) { MadarGlyph("MadarDiary", size: 22).foregroundStyle(room.accent); Text(count == 0 ? "اكتب" : service.lineCount(count)).font(small).multilineTextAlignment(.center).minimumScaleFactor(0.7) }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if let data = model?.photo, let image = UIImage(data: data) {
                    Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }.clipShape(.rect(cornerRadius: 14)).padding(.bottom, 8).accessibilityHidden(true)
                }
                title(room.accent)
                Text(count == 0 ? "اكتب سطر اليوم" : service.lineCount(count)).font(.custom("thmanyahserifdisplay-Bold", size: 26, relativeTo: .title2)).lineLimit(2).minimumScaleFactor(0.7).accessibilityIdentifier("bahw-notes-count")
                if let last = model?.last { Text("آخرها " + service.time(last, zone: model?.lastTZID) + (model?.photo != nil ? "، وصورة" : "")).font(small).foregroundStyle(room.secondaryInk).lineLimit(1) }
                if model?.photo == nil, size != .wide, let line = model?.lastText {
                    Text(figure: line).font(.custom("thmanyahseriftext-Regular", size: 15, relativeTo: .body)).foregroundStyle(room.ink)
                        .lineLimit(size == .large ? 6 : 3).lineSpacing(3).padding(.top, 10)
                        .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("bahw-notes-last-line")
                }
                if model?.photo == nil { Spacer(minLength: 0) }
            }
        }
    }

    // MARK: year
    @ViewBuilder private var year: some View {
        let model = service.year()
        if size == .icon {
            VStack(spacing: 2) { Text("مضى").font(small).foregroundStyle(lobby.secondaryInk); Text(percent(model.hijri)).font(big).lineLimit(1).minimumScaleFactor(0.6) }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if size == .small {
            VStack(alignment: .leading, spacing: 6) {
                title(lobby.accent)
                Text(percent(model.hijri)).font(big).lineLimit(1).minimumScaleFactor(0.6)
                strip(model.hijri, month: model.hijriMonthIndex, hijri: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                title(lobby.accent)
                yearRow(digits.string(model.hijriYear) + "هـ", model.hijri, month: model.hijriMonthIndex, hijri: true)
                yearRow(digits.string(model.gregorianYear) + "م", model.gregorian, month: model.gregorianMonthIndex, hijri: false)
                Spacer(minLength: 0)

            }
        }
    }
    private func yearRow(_ name: String, _ period: MadarPeriod, month: Int, hijri: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(label)
                Spacer()
                Text("بقي " + service.daysPhrase(period.remaining)).font(small).foregroundStyle(lobby.secondaryInk)
                Text(percent(period)).font(.custom("thmanyahserifdisplay-Bold", size: 20, relativeTo: .title3)).foregroundStyle(hijri ? lobby.color("amberText") : lobby.color("gregorianInk"))
            }
            strip(period, month: month, hijri: hijri)
        }.accessibilityElement(children: .combine).accessibilityIdentifier(hijri ? "bahw-year-hijri" : "bahw-year-gregorian")
    }
    /// Twelve month segments; passed months filled, the current one by its share. Ramadan and Eid gold, Arafah green.
    private func strip(_ period: MadarPeriod, month: Int, hijri: Bool) -> some View {
        let fill = hijri ? lobby.color("amber") : lobby.color("lapis")
        let monthShare = Double(period.elapsed) / Double(max(1, period.length)) * 12 - Double(month)
        return HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { index in
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(lobby.line.opacity(0.7))
                        RoundedRectangle(cornerRadius: 2).fill(fill).frame(width: geometry.size.width * (index < month ? 1 : index == month ? min(1, max(0.08, monthShare)) : 0))
                    }
                }.frame(height: 10)
                .overlay(alignment: .top) {
                    if hijri, [8, 9, 11].contains(index) { Capsule().fill(index == 11 ? lobby.color("green") : lobby.color("amber")).frame(width: 2, height: 16).offset(y: -4) }
                }
            }
        }.environment(\.layoutDirection, .rightToLeft).accessibilityHidden(true)
    }
    // AU-33: the first days of a year read «دون ١٪», not a «٠٪» that says nothing has passed.
    private func percent(_ period: MadarPeriod) -> String {
        if period.elapsed > 0 && period.basisPoints < 100 { return "دون " + digits.string(1) + "٪\u{061C}" }
        return digits.string(period.basisPoints / 100) + "٪\u{061C}"
    }
    private func markTitle(_ name: MadarLandmark.Name) -> String {
        switch name { case .ramadan: "رمضان"; case .eidAlFitr: "العيد"; case .arafah: "عرفة"; case .hijriNewYear: "رأس السنة"; case .gregorianYearEnd: "نهاية السنة" }
    }

    // MARK: upcoming
    @ViewBuilder private var upcoming: some View {
        let items = service.upcoming(limit: size == .small ? 3 : size == .large ? max(4, Int(service.session.number("bahw.upcomingCount"))) : 4)
        if size == .icon, let first = items.first {
            ring(first, diameter: 54).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if size == .small, let first = items.first {
            VStack(alignment: .leading, spacing: 6) {
                title(lobby.accent)
                HStack { ring(first, diameter: 66); VStack(alignment: .leading) { Text(first.title).font(label); MadarDateLabel(service.session.dateLabels(first.day, compact: true)).foregroundStyle(lobby.secondaryInk) } }
                ForEach(items.dropFirst()) { item in Text(item.title + " " + service.countPhrase(daysLeft: item.daysLeft, elapsed: item.elapsedDays)).font(small).foregroundStyle(lobby.secondaryInk).lineLimit(1) }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                title(lobby.accent)
                HStack(alignment: .top, spacing: 6) {
                    ForEach(items.prefix(4)) { item in
                        VStack(spacing: 6) {
                            ring(item, diameter: 64)
                            Text(item.title).font(label).lineLimit(1).minimumScaleFactor(0.79)
                            MadarDateLabel(service.session.dateLabels(item.day, compact: true)).foregroundStyle(lobby.secondaryInk)
                        }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore)
                            .accessibilityLabel(item.title + " " + service.countPhrase(daysLeft: item.daysLeft, elapsed: item.elapsedDays)).accessibilityIdentifier("bahw-upcoming-item")
                    }
                }
                // Large: the rest of `bahw.upcomingCount` as lines.
                ForEach(items.dropFirst(4)) { item in
                    HStack { Text(item.title).font(label); Spacer(); Text(item.elapsedDays.map(service.sincePhrase) ?? (item.daysLeft == 0 ? "اليوم" : service.daysPhrase(item.daysLeft))).font(small).foregroundStyle(lobby.secondaryInk) }
                        .accessibilityElement(children: .combine).accessibilityIdentifier("bahw-upcoming-item")
                }
            }
        }
    }
    /// The ring closes as the day nears; the number inside is the days left, or the days since for a day that keeps counting (full ring).
    private func ring(_ item: BahwUpcomingItem, diameter: CGFloat) -> some View {
        ZStack {
            Circle().stroke(lobby.line, lineWidth: 5)
            Circle().trim(from: 0, to: service.upcomingCloseness(daysLeft: item.daysLeft)).stroke(lobby.color("clay"), style: .init(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                // AU-32: on the day itself the ring says «اليوم», not a «٠» that reads as nothing.
                if item.elapsedDays == nil && item.daysLeft == 0 {
                    Text("اليوم").font(.custom("thmanyahserifdisplay-Bold", size: diameter * 0.24, relativeTo: .title2)).minimumScaleFactor(0.51)
                } else {
                Text(digits.string(item.count)).font(.custom("thmanyahserifdisplay-Bold", size: diameter * 0.34, relativeTo: .title2)).minimumScaleFactor(0.51)
                Text(item.elapsedDays.map(service.sinceCount) ?? service.dayCount(item.daysLeft)).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(lobby.secondaryInk)
                }
            }
        }.frame(width: diameter, height: diameter).accessibilityHidden(true)
    }
}

private struct BahwHabitsWide: View {
    let rows: [HabitReading]
    let digits: MadarNumberFormatter
    let theme: RoomTheme
    let interactive: Bool
    var showsPeriods = true
    let open: () -> Void

    private var next: HabitReading? {
        let pending = rows.filter { !$0.paused && $0.summary.current?.met != true && ($0.summary.current?.target ?? 0) > 0 }
        return pending.first(where: { $0.isNow && $0.summary.atRisk })
            ?? pending.first(where: \.isNow)
            ?? pending.first(where: { $0.summary.atRisk })
            ?? pending.first
    }

    private var missed: HabitReading? {
        rows.first { !$0.paused && $0.summary.consecutiveMisses > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsPeriods {
                HStack(spacing: 4) {
                    ForEach([HabitFrequency.daily, .weekly, .monthly, .yearly], id: \.self) { frequency in
                        BahwHabitPeriod(rows: rows, frequency: frequency, digits: digits, theme: theme)
                    }
                }
            }
            Button(action: open) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let next {
                            Text("التالي: " + next.name).font(.custom("thmanyahsans-Bold", size: 12, relativeTo: .caption)).lineLimit(1)
                            // The same habit is named once: its misses join its step instead of a third line.
                            if missed?.id == next.id, let missed {
                                Text(missedCount(missed) + "، " + step(for: next) + (next.summary.current?.rule.frequency == .daily ? " اليوم" : "")).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.accent).lineLimit(1)
                            } else {
                                Text(step(for: next)).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1)
                            }
                        } else {
                            Text("اكتمل ما يستحق في هذه الفترة").font(.custom("thmanyahsans-Regular", size: 12, relativeTo: .caption)).lineLimit(1)
                        }
                        if let missed, missed.id != next?.id {
                            Text(missedText(for: missed)).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.accent).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondaryInk)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.madarPlain)
            .disabled(!interactive)
            .accessibilityIdentifier("bahw-habits-next")
        }
    }

    private func step(for row: HabitReading) -> String {
        guard let current = row.summary.current else { return "افتح العادة" }
        if current.rule.measure == .once { return "أكملها" }
        let remaining = max(0, current.target - current.value)
        return "بقي " + habitUnitCount(remaining, current.rule.unit, digits)
    }

    private func missedCount(_ row: HabitReading) -> String {
        row.missedPhrase(digits)
    }

    private func missedText(for row: HabitReading) -> String {
        row.missedPhrase(digits) + " في " + row.name
    }
}

private struct BahwHabitPeriod: View {
    let rows: [HabitReading]
    let frequency: HabitFrequency
    let digits: MadarNumberFormatter
    let theme: RoomTheme

    private var active: [HabitReading] {
        rows.filter { !$0.paused && $0.summary.current?.rule.band == frequency && ($0.summary.current?.target ?? 0) > 0 }
    }

    var body: some View {
        let done = active.filter { $0.summary.current?.met == true }.count
        return VStack(spacing: 2) {
            HabitMiniRing(share: Double(done) / Double(max(1, active.count)), theme: theme)
                .frame(width: 20, height: 20)
            Text(frequency.arabic).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).lineLimit(1)
            Text(active.isEmpty ? "لا شيء مستحق" : digits.string(done) + " من " + digits.string(active.count))
                .font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2))
                .foregroundStyle(theme.secondaryInk).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
