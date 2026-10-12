import SwiftUI
import MadarCore
import MadarDesign
import MadarPrayer

struct PrayerTodayView: View {
    @Bindable var session: AppSession
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var selectedSheet: PrayerTodaySheet?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let instant = session.prayerNow(timeline.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let snapshot = try? session.prayerSnapshot(at: instant) {
                        header(day: snapshot.today.day, at: instant)
                        nextPrayer(snapshot, now: instant)
                        prayerArches(snapshot)
                        if !snapshot.pending.isEmpty { pendingCard(snapshot) }
                        if !snapshot.unconfirmed.isEmpty { recoveryCard(snapshot) }
                        if !snapshot.qada.isEmpty { qadaCard(snapshot) }
                        MadarCard {
                            Text("ما لم تُسجّله يبقى غير محسوم؛ لا ينشأ قضاء تلقائيًا.")
                                .font(MadarTypography.caption())
                                .foregroundStyle(theme.secondaryInk)
                        }
                    } else {
                        header(day: nil, at: instant)
                        MadarCard {
                            Text("تعذّر حساب صلاة اليوم. راجع المدينة وطريقة الحساب في خصّص مدار.")
                                .font(MadarTypography.body())
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(theme.background)
            .foregroundStyle(theme.ink)
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .sheet(item: $selectedSheet) { route in
            switch route {
            case .log(let cell):
                PrayerTodayLogSheet(cell: cell, isSaving: session.prayerWriteInProgress) { status, fridayKind, makeUpNow in
                    if status == .qada {
                        session.makeUpPrayer(cell.reference, fridayKind: fridayKind)
                    } else if status == .missed && makeUpNow {
                        session.recordPrayer(cell.reference, status: .missed, fridayKind: fridayKind) { succeeded in
                            if succeeded { session.makeUpPrayer(cell.reference, fridayKind: fridayKind) }
                        }
                    } else {
                        session.recordPrayer(cell.reference, status: status, fridayKind: fridayKind)
                    }
                }
            case .makeUp(let item, let isFridayNoon, let dateLabel):
                PrayerMakeUpSheet(item: item, isFridayNoon: isFridayNoon, dateLabel: dateLabel, isSaving: session.prayerWriteInProgress) { kind in
                    session.makeUpPrayer(item.reference, fridayKind: kind)
                }
            case .recovery(let references, let fridayReferences, let timeZone):
                PrayerGapResolutionSheet(references: references, fridayReferences: fridayReferences, timeZone: timeZone) { resolutions in
                    session.resolvePrayerGap(resolutions)
                }
            }
        }
    }

    private func header(day prayerDay: GregorianDay?, at instant: Date) -> some View {
        let place = session.activePlace
        let day = prayerDay ?? GregorianDay.containing(instant, in: place.timeZone)
        let midday = day.date(in: place.timeZone).addingTimeInterval(12 * 3600)
        let dualDate = DualDate(instant: midday, timeZone: place.timeZone,
            source: HijriSource(rawValue: session.string("core.hijriSource")) ?? .ummAlQura,
            sightingOffset: Int(session.number("core.hijriOffset")))
        let numerals: NumeralStyle = session.string("core.numerals") == "western" ? .western : .hindi
        let firstCalendar: FirstCalendar = session.string("core.firstCalendar") == "gregorian" ? .gregorian : .hijri
        return VStack(alignment: .leading, spacing: 6) {
            Text("الصلاة").font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
            Text(dualDate.text(firstCalendar: firstCalendar, numerals: numerals))
                .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("prayer-today-header")
    }

    private func nextPrayer(_ snapshot: PrayerSnapshot, now: Date) -> some View {
        VStack(spacing: 8) {
            if let next = snapshot.next {
                Text("الصلاة القادمة").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                Text(title(next.reference.prayer)).font(MadarTypography.title())
                Text(clock(next.time, timeZone: next.place.timeZone))
                    .font(MadarTypography.body()).monospacedDigit()
                if next.time > now {
                    Text("بعد \(next.time, style: .relative)")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
            } else if snapshot.hasTimes {
                Text("اكتمل يوم الصلاة").font(MadarTypography.cardTitle())
            } else {
                Text("لا تُحسب المواقيت هنا اليوم").font(MadarTypography.cardTitle())
                Text("لا تظهر أوقات غير متاحة أو تسجيلات مستقبلية.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityIdentifier("prayer-next")
    }

    private func prayerArches(_ snapshot: PrayerSnapshot) -> some View {
        MadarCard {
            VStack(spacing: 12) {
                if dynamicType.isAccessibilitySize {
                    VStack(spacing: 8) {
                        ForEach(snapshot.today.cells, id: \.reference) { cell in prayerEntry(cell, snapshot: snapshot) }
                    }
                } else {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(snapshot.today.cells, id: \.reference) { cell in prayerEntry(cell, snapshot: snapshot) }
                    }
                }
                if !snapshot.hasTimes {
                    Text("يمكنك اختيار المدينة من خصّص مدار عند توفر المواقيت.")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
            }
        }
    }

    @ViewBuilder private func prayerEntry(_ cell: PrayerCell, snapshot: PrayerSnapshot) -> some View {
        let canEdit = cell.canLog && cell.time != nil && [.pending, .jamaah, .alone, .missed].contains(cell.status)
        let arch = PrayerTodayArch(cell: cell, isNext: snapshot.next?.reference == cell.reference,
            timeLabel: cell.time.map { clock($0, timeZone: snapshot.activeTrip?.place.timeZone ?? session.activePlace.timeZone) } ?? "—")
        if canEdit {
            Button { choose(cell) } label: { arch }
                .buttonStyle(.plain)
                .accessibilityElement(children: dynamicType.isAccessibilitySize ? .combine : .ignore)
                .accessibilityLabel(arch.accessibilityText)
                .accessibilityHint("سجّل الصلاة أو غيّر تسجيلها")
                .accessibilityIdentifier("prayer-arch-\(cell.reference.prayer.rawValue)")
        } else {
            arch.accessibilityElement(children: dynamicType.isAccessibilitySize ? .combine : .ignore)
                .accessibilityLabel(arch.accessibilityText)
                .accessibilityIdentifier("prayer-arch-\(cell.reference.prayer.rawValue)")
        }
    }

    @ViewBuilder private func pendingCard(_ snapshot: PrayerSnapshot) -> some View {
        let pending = Set(snapshot.pending)
        let first = snapshot.history.flatMap(\.cells).first { pending.contains($0.reference) && $0.canLog && $0.time != nil }
        if let first {
            MadarCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(number(snapshot.pending.count)) صلاة تنتظر تسجيلك").font(MadarTypography.section())
                    Text("تبقى غير محسومة حتى تختار حالها؛ لا تتحول إلى فائتة تلقائيًا.")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    Button("راجع \(title(first.reference.prayer))") { choose(first) }
                        .frame(minHeight: 44).accessibilityIdentifier("prayer-pending-review")
                }
            }
        }
    }

    private func recoveryCard(_ snapshot: PrayerSnapshot) -> some View {
        MadarCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(number(snapshot.unconfirmed.count)) صلاة غير محسومة").font(MadarTypography.section())
                Text("اختر ما ينطبق على الفترة؛ لن نعدّها فائتة من تلقاء أنفسنا.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                Button("راجع الفترة") {
                    selectedSheet = .recovery(snapshot.unconfirmed, snapshot.unconfirmedFridayNoon, session.activePlace.timeZone)
                }
                .frame(minHeight: 44).accessibilityIdentifier("prayer-recovery")
            }
        }
    }

    private func qadaCard(_ snapshot: PrayerSnapshot) -> some View {
        let outstanding = snapshot.qada.filter { $0.madeUpAt == nil }
        let shown = Array(snapshot.qada.suffix(5))
        return MadarCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("الفوائت والقضاء").font(MadarTypography.cardTitle())
                Text("\(number(snapshot.qada.count)) فوائت مسجّلة · \(number(snapshot.statistics.owed)) لم تُقضَ")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                PrayerQadaCitation()
                ForEach(shown) { item in
                    HStack {
                        PrayerStar().stroke(item.madeUpAt == nil ? theme.color("missedTextOnSurface") : theme.secondaryInk, lineWidth: 1).frame(width: 14, height: 14)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title(item.reference.prayer)).font(MadarTypography.section())
                            Text(qadaDate(item.reference.day)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        }
                        Spacer()
                        Text(item.madeUpAt == nil ? "لم تُقضَ" : "قُضيت").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    }.accessibilityIdentifier("prayer-qada-row-\(item.reference.day)-\(item.reference.prayer.rawValue)")
                }
                if let item = outstanding.first {
                    Button("اقضِ واحدة") { selectedSheet = .makeUp(item, isFridayNoon: item.isFriday, dateLabel: qadaDate(item.reference.day)) }
                        .buttonStyle(MadarPrimaryButton()).disabled(session.prayerWriteInProgress)
                        .accessibilityIdentifier("prayer-qada-makeup")
                }
            }
        }
    }

    private func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: session.string("core.numerals") == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab")
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func qadaDate(_ day: GregorianDay) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: session.string("core.numerals") == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab")
        formatter.timeZone = session.activePlace.timeZone
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: day.date(in: session.activePlace.timeZone).addingTimeInterval(12 * 3600))
    }

    private func choose(_ cell: PrayerCell) {
        selectedSheet = .log(cell)
    }

    private func title(_ prayer: Prayer) -> String {
        switch prayer { case .fajr: "الفجر"; case .dhuhr: "الظهر"; case .asr: "العصر"; case .maghrib: "المغرب"; case .isha: "العشاء" }
    }

    private func clock(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: session.string("core.numerals") == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

private struct PrayerTodayArch: View {
    let cell: PrayerCell
    let isNext: Bool
    let timeLabel: String
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType

    private var statusText: String {
        switch cell.status {
        case .jamaah: "جماعة"
        case .alone: "منفردًا"
        case .qada: "قُضيت"
        case .missed: "فاتتني"
        case .unrecordedHistory: "غير مسجلة تاريخيًا"
        case .unconfirmed: "غير محسومة"
        case .excused: "معذورة"
        case .pending: "لم تُسجّل"
        case .future: "لم يحن"
        }
    }
    var accessibilityText: String { "\(prayerTitle)، \(timeLabel)، \(statusText)" }
    private var prayerTitle: String {
        switch cell.reference.prayer { case .fajr: "الفجر"; case .dhuhr: "الظهر"; case .asr: "العصر"; case .maghrib: "المغرب"; case .isha: "العشاء" }
    }
    private var statusColor: Color {
        switch cell.status {
        case .missed: theme.color("missedTextOnSurface")
        case .jamaah: theme.accent
        case .alone: theme.color("goldMidText")
        case .pending, .future, .qada, .unrecordedHistory, .unconfirmed, .excused: theme.secondaryInk
        }
    }

    @ViewBuilder var body: some View {
        if dynamicType.isAccessibilitySize {
            accessibilityRow
        } else {
            VStack(spacing: 5) {
                ZStack {
                    PrayerHorseshoe().fill([.jamaah, .alone].contains(cell.status) ? theme.color("goldSoft") : .clear)
                    PrayerHorseshoe().stroke(isNext ? theme.accent : theme.line,
                        style: StrokeStyle(lineWidth: isNext ? 3 : 1, dash: cell.status == .pending ? [3, 3] : []))
                    VStack {
                        Spacer()
                        if cell.status == .pending || cell.status == .future || cell.status == .unrecordedHistory || cell.status == .unconfirmed || cell.status == .excused {
                            Capsule().fill(statusColor).frame(width: 12, height: 2).opacity(cell.status == .pending ? 0.7 : 0.25)
                        } else {
                            PrayerStar().fill(cell.status == .missed ? .clear : statusColor)
                                .overlay { if cell.status == .alone || cell.status == .missed { PrayerStar().stroke(statusColor, lineWidth: 1) } }
                                .frame(width: 16, height: 16)
                        }
                        Spacer()
                    }
                }
                .frame(height: 94)
                Text(prayerTitle).font(MadarTypography.section()).lineLimit(1).minimumScaleFactor(0.75)
                Text(timeLabel).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.7)
                Text(statusText).font(MadarTypography.fine()).foregroundStyle(statusColor).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
    }

    var accessibilityRow: some View {
        HStack(spacing: 12) {
            PrayerStar().fill(statusColor).frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(prayerTitle).font(MadarTypography.section())
                Text("\(timeLabel)، \(statusText)").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }
            Spacer(minLength: 8)
            if isNext { Image(systemName: "arrow.left").foregroundStyle(theme.accent).accessibilityHidden(true) }
        }
        .frame(minHeight: 54)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private enum PrayerTodaySheet: Identifiable {
    case log(PrayerCell)
    case makeUp(PrayerQada, isFridayNoon: Bool, dateLabel: String)
    case recovery([PrayerReference], Set<PrayerReference>, TimeZone)
    var id: String {
        switch self {
        case .log(let cell): "log-\(cell.reference.naturalKey)"
        case .makeUp(let item, _, _): "makeup-\(item.id.uuidString)"
        case .recovery(let references, _, _): "recovery-\(references.first?.naturalKey ?? "empty")"
        }
    }
}

private struct PrayerTodayLogSheet: View {
    let cell: PrayerCell
    let isSaving: Bool
    let save: (PrayerStoredStatus, FridayPrayerKind?, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var status: PrayerStoredStatus
    @State private var fridayKind: FridayPrayerKind?

    init(cell: PrayerCell, isSaving: Bool, save: @escaping (PrayerStoredStatus, FridayPrayerKind?, Bool) -> Void) {
        self.cell = cell; self.isSaving = isSaving; self.save = save
        let initial: PrayerStoredStatus = switch cell.status { case .alone: .alone; case .missed: .missed; default: .jamaah }
        _status = State(initialValue: initial)
        _fridayKind = State(initialValue: cell.fridayKind)
    }

    private var statusOptions: [PrayerStoredStatus] {
        [.jamaah, .alone] + (cell.canMarkMissed ? [.missed] : []) + (cell.canMakeUp ? [.qada] : [])
    }
    private var needsFridayKind: Bool { cell.isFriday && [.jamaah, .alone, .missed, .qada].contains(status) }
    private var saveDisabled: Bool { isSaving || (needsFridayKind && fridayKind == nil) }

    var body: some View {
        NavigationStack {
            Form {
                Section("حال الصلاة") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(statusOptions, id: \.self) { option in statusButton(option) }
                    }
                }
                if needsFridayKind {
                    Section("تصنيف ظهر الجمعة") {
                        Picker("نوع الصلاة", selection: $fridayKind) {
                            Text("اختر التصنيف").tag(nil as FridayPrayerKind?)
                            if status != .alone { Text("صلاة الجمعة").tag(FridayPrayerKind?.some(.jumuah)) }
                            Text("الظهر").tag(FridayPrayerKind?.some(.dhuhr))
                        }.accessibilityIdentifier("prayer-friday-kind")
                    }
                }
                if status == .missed {
                    Section {
                        Text("نزلت في القضاء، وهي عليك حتى تصلّيها.").font(MadarTypography.section()).foregroundStyle(theme.color("missedTextOnSurface"))
                        PrayerQadaCitation()
                        Button("قضيتُها الآن") { save(.missed, cell.isFriday ? fridayKind : nil, true); dismiss() }
                            .buttonStyle(MadarPrimaryButton()).disabled(saveDisabled).accessibilityIdentifier("prayer-makeup-now")
                        Button("لاحقًا") { save(.missed, cell.isFriday ? fridayKind : nil, false); dismiss() }
                            .disabled(saveDisabled).accessibilityIdentifier("prayer-missed-later")
                    }
                } else {
                    Section {
                        Button(status == .qada ? "قضيتُها الآن" : "احفظ التسجيل") {
                            save(status, cell.isFriday ? fridayKind : nil, false); dismiss()
                        }
                        .buttonStyle(MadarPrimaryButton()).disabled(saveDisabled)
                        .accessibilityIdentifier(status == .qada ? "prayer-makeup-now" : "prayer-save")
                    }
                }
            }
            .navigationTitle("تسجيل \(title(cell.reference.prayer))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("إغلاق") { dismiss() }.accessibilityIdentifier("prayer-log-dismiss") } }
        }
        .presentationDetents([.medium, .large])
    }

    private func statusButton(_ value: PrayerStoredStatus) -> some View {
        let title: String = switch value { case .jamaah: "جماعة"; case .alone: "منفردًا"; case .missed: "فاتتني"; case .qada: "قضاءً"; default: value.rawValue }
        return Button {
            status = value
            if cell.isFriday && value == .alone { fridayKind = .dhuhr }
        } label: {
            Text(title).font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(status == value ? theme.onAccent : theme.ink)
                .background(status == value ? theme.accentFill : theme.surface, in: .rect(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.line, lineWidth: 1) }
        }
        .buttonStyle(.plain).accessibilityIdentifier("prayer-status-\(value.rawValue)")
        .accessibilityAddTraits(status == value ? .isSelected : [])
    }

    private func title(_ prayer: Prayer) -> String {
        switch prayer { case .fajr: "الفجر"; case .dhuhr: "الظهر"; case .asr: "العصر"; case .maghrib: "المغرب"; case .isha: "العشاء" }
    }
}

private struct PrayerMakeUpSheet: View {
    let item: PrayerQada
    let isFridayNoon: Bool
    let dateLabel: String
    let isSaving: Bool
    let makeUp: (FridayPrayerKind?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var fridayKind: FridayPrayerKind?
    init(item: PrayerQada, isFridayNoon: Bool, dateLabel: String, isSaving: Bool, makeUp: @escaping (FridayPrayerKind?) -> Void) {
        self.item = item; self.isFridayNoon = isFridayNoon; self.dateLabel = dateLabel; self.isSaving = isSaving; self.makeUp = makeUp
        _fridayKind = State(initialValue: item.fridayKind)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(title(item.reference.prayer)) · \(dateLabel)").font(MadarTypography.cardTitle())
                    PrayerQadaCitation()
                }
                if isFridayNoon {
                    Section("نوع صلاة الجمعة") {
                        if let fridayKind { Text(fridayKind == .jumuah ? "صلاة الجمعة" : "الظهر") }
                        else {
                            Picker("التصنيف", selection: $fridayKind) {
                                Text("اختر التصنيف").tag(nil as FridayPrayerKind?)
                                Text("صلاة الجمعة").tag(FridayPrayerKind?.some(.jumuah))
                                Text("الظهر").tag(FridayPrayerKind?.some(.dhuhr))
                            }.accessibilityIdentifier("prayer-makeup-friday-kind")
                        }
                    }
                }
                Section {
                    Button("قضيتُها الآن") { makeUp(isFridayNoon ? fridayKind : nil); dismiss() }
                        .buttonStyle(MadarPrimaryButton())
                        .disabled(isSaving || (isFridayNoon && fridayKind == nil))
                        .accessibilityIdentifier("prayer-makeup-confirm")
                }
            }
            .navigationTitle("القضاء")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("إغلاق") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
    private func title(_ prayer: Prayer) -> String {
        switch prayer { case .fajr: "الفجر"; case .dhuhr: "الظهر"; case .asr: "العصر"; case .maghrib: "المغرب"; case .isha: "العشاء" }
    }
}

private struct PrayerGapResolutionSheet: View {
    let references: [PrayerReference]
    let fridayReferences: Set<PrayerReference>
    let timeZone: TimeZone
    let resolve: ([PrayerGapResolution]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [PrayerReference: PrayerStoredStatus] = [:]
    @State private var fridayKinds: [PrayerReference: FridayPrayerKind] = [:]

    private let options: [PrayerStoredStatus] = [.jamaah, .alone, .missed, .unrecordedHistory, .excused]
    private var canSave: Bool {
        guard choices.count == references.count else { return false }
        return references.allSatisfy { ref in
            guard let status = choices[ref] else { return false }
            guard fridayReferences.contains(ref), ![.unrecordedHistory, .excused].contains(status) else { return true }
            guard let kind = fridayKinds[ref] else { return false }
            return status != .alone || kind == .dhuhr
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("هذه الصلوات بقيت بلا تسجيل. اختر لكل واحدة ما ينطبق؛ لا يتحول الصمت إلى فائتة تلقائيًا.")
                        .font(MadarTypography.body())
                    Button("لم أُسجّل هذه الفترة") {
                        choices = Dictionary(uniqueKeysWithValues: references.map { ($0, .unrecordedHistory) })
                        fridayKinds = [:]
                    }.accessibilityIdentifier("prayer-gap-unrecorded-all")
                }
                ForEach(references, id: \.self) { reference in
                    Section("\(title(reference.prayer)) · \(dateLabel(reference.day))") {
                        Picker("حال الصلاة", selection: Binding(get: { choices[reference] }, set: { value in
                            choices[reference] = value
                            if value == .alone && fridayReferences.contains(reference) { fridayKinds[reference] = .dhuhr }
                            if value == .excused || value == .unrecordedHistory { fridayKinds[reference] = nil }
                        })) {
                            Text("اختر الحال").tag(nil as PrayerStoredStatus?)
                            ForEach(options, id: \.self) { value in Text(title(value)).tag(PrayerStoredStatus?.some(value)) }
                        }
                        .accessibilityIdentifier("prayer-gap-status-\(reference.day)-\(reference.prayer.rawValue)")
                        if fridayReferences.contains(reference), let status = choices[reference], ![.excused, .unrecordedHistory].contains(status) {
                            Picker("نوع صلاة الجمعة", selection: Binding(get: { fridayKinds[reference] }, set: { fridayKinds[reference] = $0 })) {
                                Text("اختر التصنيف").tag(nil as FridayPrayerKind?)
                                if status != .alone { Text("صلاة الجمعة").tag(FridayPrayerKind?.some(.jumuah)) }
                                Text("الظهر").tag(FridayPrayerKind?.some(.dhuhr))
                            }.accessibilityIdentifier("prayer-gap-friday-\(reference.day)")
                        }
                    }
                }
                Section {
                    Button("احفظ المراجعة") {
                        let resolutions = references.compactMap { ref -> PrayerGapResolution? in
                            guard let status = choices[ref] else { return nil }
                            return .init(reference: ref, status: status, fridayKind: fridayKinds[ref])
                        }
                        resolve(resolutions); dismiss()
                    }
                    .buttonStyle(MadarPrimaryButton()).disabled(!canSave)
                    .accessibilityIdentifier("prayer-gap-save")
                }
            }
            .navigationTitle("مراجعة الفترة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("إغلاق") { dismiss() } } }
        }.presentationDetents([.large])
    }

    private func dateLabel(_ day: GregorianDay) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ar_SA@numbers=arab")
        formatter.timeZone = timeZone; formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: day.date(in: timeZone).addingTimeInterval(12 * 3600))
    }
    private func title(_ prayer: Prayer) -> String {
        switch prayer { case .fajr: "الفجر"; case .dhuhr: "الظهر"; case .asr: "العصر"; case .maghrib: "المغرب"; case .isha: "العشاء" }
    }
    private func title(_ status: PrayerStoredStatus) -> String {
        switch status { case .jamaah: "في جماعة"; case .alone: "وحدي"; case .missed: "فاتتني"; case .unrecordedHistory: "لم أسجّل"; case .excused: "معذورة"; default: status.rawValue }
    }
}
