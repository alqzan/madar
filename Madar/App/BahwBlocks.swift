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
    @State private var mihbaraSnapshot: MihbaraSnapshot?
    @State private var mihbaraLocked = true
    @Environment(\.roomTheme) private var lobby
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
            .onChange(of: service.session.prayerRevision) { _, _ in refreshMihbaraSnapshot() }
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
        case .salah: salah
        case .quran: quran
        case .notes: notes
        case .year: year
        case .upcoming: upcoming
        case .mihbara: mihbara
        default: EmptyView()
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
            let payload = service.session.moneyWidgetPayload(hidden: service.session.bool("core.hideMoneyUntilTouch"), at: service.now)
            VStack(spacing: 2) { Text("لك الآن").font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)); Text(payload.rows.first?.value ?? "افتح").font(big).lineLimit(1).minimumScaleFactor(0.7) }.frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(MadarToken.colors["widgetIdentity.room.mal.\(dark ? "dark" : "light").ink"] ?? lobby.ink)
        } else { MoneyWidgetContent(snapshot: service.session.moneyWidgetPayload(hidden: service.session.bool("core.hideMoneyUntilTouch"), at: service.now), family: size == .icon ? .accessoryCircular : size == .small ? .systemSmall : size == .wide ? .systemMedium : .systemLarge, template: size == .wide ? "basis" : "now") }
    }

    private var habits: some View {
        let rows = (try? HabitRepository(context: ModelContext(service.session.container)).readings(at:service.now)) ?? []
        let met = rows.filter { $0.summary.current?.met == true }.count
        return VStack(alignment:.leading,spacing:size == .wide ? 4 : 10) {
            Button { service.session.habitsOpen = true } label: { HStack { title(room.accent); Spacer();if !rows.isEmpty {Text(digits.string(met)+" من "+digits.string(rows.count)).font(label).foregroundStyle(room.accent)} }.frame(minHeight:44) }.buttonStyle(.plain).accessibilityIdentifier("bahw-habits-open").disabled(!interactive)
            if rows.isEmpty {
                // Improvement 16 Oct: no «٠ من ٠»; the four period rings at rest show what a habit becomes, and the action is a real button.
                Spacer(minLength:0)
                if size == .large { HStack { ForEach([HabitFrequency.daily,.weekly,.monthly,.yearly],id:\.self){f in VStack(spacing:4){HabitMiniRing(share:0,theme:room).frame(width:24,height:24);Text(f.arabic).font(small).foregroundStyle(room.secondaryInk)}.frame(maxWidth:.infinity)} }.accessibilityHidden(true).padding(.bottom,12) }
                Text("عادة صغيرة تدوم").font(size == .icon ? small : big)
                if size == .icon { EmptyView() }
                else if size == .small { Text("أضف أول عادة").font(small).foregroundStyle(room.secondaryInk) }
                else {
                    Text("أقلّ القليل كل يوم يصير سلسلة تراها هنا").font(small).foregroundStyle(room.secondaryInk)
                    Button { service.session.habitsOpen = true } label: { Label("أضف أول عادة", systemImage: "plus").font(label).padding(.horizontal,18).frame(minHeight:44).foregroundStyle(room.onAccent).background(room.accentFill, in: .capsule) }
                        .buttonStyle(.plain).disabled(!interactive).padding(.top,6).accessibilityIdentifier("bahw-habits-add-first")
                }
                Spacer(minLength:0)
            }
            else if size == .large {
                HStack { ForEach([HabitFrequency.daily,.weekly,.monthly,.yearly],id:\.self){f in let group=rows.filter{$0.summary.current?.rule.frequency == f};VStack(spacing:4){HabitMiniRing(share:group.isEmpty ? 0 : Double(group.filter{$0.summary.current?.met == true}.count)/Double(group.count),theme:room).frame(width:24,height:24);Text(f.arabic).font(small)}.frame(maxWidth:.infinity)} }
                // Improvement 20 Oct: the room left under the grid names the next useful habit, the same
                // «التالي» line as the wide size, instead of staying blank; the chips keep their order.
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8){ ForEach(Array(rows.prefix(6))){r in
                    Button {
                        if r.source == "walking" {service.session.habitsOpen=true}
                        else if let source=r.source { service.session.selectedTab=source == "jamaah" ? "prayer" : source == "review" ? "quran" : "notes" }
                        else { Task { do {try await service.session.executeDiaryCommand("habit.complete",payload:["id":.string(r.id.uuidString),"delta":.number(r.summary.current?.rule.measure == .duration ? 15 : 1)])}catch{service.session.errorMessage=error.localizedDescription} } }
                    } label:{HStack(spacing:5){Image(systemName:r.paused ? "pause.circle" : r.summary.current?.met == true ? "checkmark.circle.fill" : "circle");Text(r.name).lineLimit(1)}.font(small).frame(maxWidth:.infinity,minHeight:44).background(room.background,in:.rect(cornerRadius:12))}.buttonStyle(.plain).disabled(!interactive || r.paused)
                } }
                Spacer(minLength:0)
                BahwHabitsWide(rows: rows, digits: digits, theme: room, interactive: interactive, showsPeriods: false) {
                    service.session.habitsOpen = true
                }
            } else if size == .wide {
                BahwHabitsWide(rows: rows, digits: digits, theme: room, interactive: interactive) {
                    service.session.habitsOpen = true
                }
            } else {
                Spacer(minLength:0)
                HabitMiniRing(share:Double(met)/Double(max(1,rows.count)),theme:room).frame(width:34,height:34)
                if let next=rows.first(where:{$0.summary.current?.met != true && !$0.paused}) {
                    Text(next.name).font(small).lineLimit(1)
                }
                if size == .small, let risk=rows.first(where:{$0.summary.atRisk && !$0.paused}) {
                    Text(risk.summary.consecutiveMisses == 1 ? "فاتتك فترة" : risk.summary.consecutiveMisses == 2 ? "فاتتك فترتان" : "فاتتك " + digits.string(risk.summary.consecutiveMisses) + " فترات")
                        .font(small).foregroundStyle(room.accent).lineLimit(1).accessibilityIdentifier("bahw-habits-at-risk")
                }
                Spacer(minLength:0)
            }
        }
    }

    // MARK: prayer
    @ViewBuilder private var salah: some View {
        if let model = service.prayer() {
            if size == .icon {
                VStack(spacing: 2) { Text(model.nextName ?? "الصلاة").font(small).foregroundStyle(room.secondaryInk); Text(model.nextTime ?? "").font(big).minimumScaleFactor(0.6) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: size == .small ? 8 : 6) {
                    HStack { title(room.accent).accessibilityLabel("الصلاة في " + service.session.cityName); Spacer(); Text(digits.string(model.done) + " من " + digits.string(5)).font(small).foregroundStyle(room.secondaryInk).accessibilityIdentifier("bahw-salah-done") }
                    HStack(alignment: .bottom, spacing: size == .small ? 4 : 10) {
                        ForEach(model.arches) { arch in
                            VStack(spacing: 4) {
                                ZStack {
                                    PrayerHorseshoe().fill(arch.done ? room.color("goldMid") : room.surface)
                                    PrayerHorseshoe().stroke(room.accent, lineWidth: arch.next ? 2.4 : 1)
                                    if arch.done { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(room.ink) }
                                }.frame(maxWidth: size == .small ? 26 : 34).frame(height: size == .small ? 36 : 40).accessibilityHidden(true)
                                if size != .small { Text(arch.name + " " + arch.time).font(small).lineLimit(1).minimumScaleFactor(0.7) }
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
        } else { Text("المواقيت غير متاحة لهذا الموقع اليوم.").font(small).foregroundStyle(room.secondaryInk) }
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
                if let last = model?.last { Text("آخرها " + service.time(last) + (model?.photo != nil ? "، وصورة" : "")).font(small).foregroundStyle(room.secondaryInk).lineLimit(1) }
                if model?.photo == nil { Spacer(minLength: 0) }
            }
        }
    }

    // MARK: year
    @ViewBuilder private var year: some View {
        let model = service.year()
        if size == .icon {
            VStack(spacing: 2) { Text("مضى").font(small).foregroundStyle(lobby.secondaryInk); Text(percent(model.hijri)).font(big) }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if size == .small {
            VStack(alignment: .leading, spacing: 6) {
                title(lobby.accent)
                Text(percent(model.hijri)).font(big)
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
                Text("بقي " + digits.string(period.remaining) + " " + service.dayCount(period.remaining)).font(small).foregroundStyle(lobby.secondaryInk)
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
    private func percent(_ period: MadarPeriod) -> String { digits.string(period.basisPoints / 100) + "٪\u{061C}" }
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
                ForEach(items.dropFirst()) { item in Text(item.title + " بعد " + digits.string(item.daysLeft) + " " + service.dayCount(item.daysLeft)).font(small).foregroundStyle(lobby.secondaryInk).lineLimit(1) }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack { title(lobby.accent); Spacer(); Text("كل حلقة على مقياس سنة").font(small).foregroundStyle(lobby.secondaryInk) }
                HStack(alignment: .top, spacing: 6) {
                    ForEach(items.prefix(4)) { item in
                        VStack(spacing: 6) {
                            ring(item, diameter: 64)
                            Text(item.title).font(label).lineLimit(1).minimumScaleFactor(0.75)
                            MadarDateLabel(service.session.dateLabels(item.day, compact: true)).foregroundStyle(lobby.secondaryInk)
                        }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore)
                            .accessibilityLabel(item.title + " بعد " + digits.string(item.daysLeft) + " " + service.dayCount(item.daysLeft)).accessibilityIdentifier("bahw-upcoming-item")
                    }
                }
                // Large: the rest of `bahw.upcomingCount` as lines.
                ForEach(items.dropFirst(4)) { item in
                    HStack { Text(item.title).font(label); Spacer(); Text(digits.string(item.daysLeft) + " " + service.dayCount(item.daysLeft)).font(small).foregroundStyle(lobby.secondaryInk) }
                        .accessibilityElement(children: .combine).accessibilityIdentifier("bahw-upcoming-item")
                }
            }
        }
    }
    /// The ring closes as the day nears; the number inside is the days left.
    private func ring(_ item: BahwUpcomingItem, diameter: CGFloat) -> some View {
        ZStack {
            Circle().stroke(lobby.line, lineWidth: 5)
            Circle().trim(from: 0, to: service.upcomingCloseness(daysLeft: item.daysLeft)).stroke(lobby.color("clay"), style: .init(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(digits.string(item.daysLeft)).font(.custom("thmanyahserifdisplay-Bold", size: diameter * 0.34, relativeTo: .title2)).minimumScaleFactor(0.5)
                Text(service.dayCount(item.daysLeft)).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(lobby.secondaryInk)
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
                            Text(step(for: next)).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1)
                        } else {
                            Text("اكتمل ما يستحق في هذه الفترة").font(.custom("thmanyahsans-Regular", size: 12, relativeTo: .caption)).lineLimit(1)
                        }
                        if let missed {
                            Text(missedText(for: missed)).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.accent).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondaryInk)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!interactive)
            .accessibilityIdentifier("bahw-habits-next")
        }
    }

    private func step(for row: HabitReading) -> String {
        guard let current = row.summary.current else { return "افتح العادة" }
        if current.rule.measure == .once { return "أكملها" }
        let remaining = max(0, current.target - current.value)
        let unit = current.rule.unit.map(habitUnitName) ?? "مرة"
        return "بقي " + digits.string(remaining) + " " + unit
    }

    private func missedText(for row: HabitReading) -> String {
        let count = row.summary.consecutiveMisses
        if count == 1 { return "فاتتك فترة في " + row.name }
        if count == 2 { return "فاتتك فترتان في " + row.name }
        return "فاتتك " + digits.string(count) + " فترات في " + row.name
    }
}

private struct BahwHabitPeriod: View {
    let rows: [HabitReading]
    let frequency: HabitFrequency
    let digits: MadarNumberFormatter
    let theme: RoomTheme

    private var active: [HabitReading] {
        rows.filter { !$0.paused && $0.summary.current?.rule.frequency == frequency && ($0.summary.current?.target ?? 0) > 0 }
    }

    var body: some View {
        let done = active.filter { $0.summary.current?.met == true }.count
        return VStack(spacing: 2) {
            HabitMiniRing(share: Double(done) / Double(max(1, active.count)), theme: theme)
                .frame(width: 20, height: 20)
            Text(frequency.arabic).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).lineLimit(1)
            Text(active.isEmpty ? "لا استحقاق" : digits.string(done) + " من " + digits.string(active.count))
                .font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2))
                .foregroundStyle(theme.secondaryInk).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
