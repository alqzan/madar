import SwiftUI
import MadarCore
import MadarDesign
import MadarPrayer

struct PrayerTodayView: View {
    @Bindable var session: AppSession
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var selectedCell: PrayerCell?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let snapshot = try? session.prayerSnapshot(at: timeline.date) {
                        header(day: snapshot.today.day, at: timeline.date)
                        nextPrayer(snapshot, now: timeline.date)
                        prayerArches(snapshot)
                        MadarCard {
                            Text("يبقى ما لم يُسجّل غير محسوم. لا ينشأ قضاء تلقائيًا.")
                                .font(MadarTypography.caption())
                                .foregroundStyle(theme.secondaryInk)
                        }
                    } else {
                        header(day: nil, at: timeline.date)
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
        .sheet(item: $selectedCell) { cell in
            PrayerTodayLogSheet(cell: cell, isSaving: session.prayerWriteInProgress) { status, fridayKind in
                session.recordPrayer(cell.reference, status: status, fridayKind: fridayKind)
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
        .accessibilityIdentifier("prayer-today-arches")
    }

    @ViewBuilder private func prayerEntry(_ cell: PrayerCell, snapshot: PrayerSnapshot) -> some View {
        let canEdit = cell.canLog && cell.time != nil && [.pending, .jamaah, .alone].contains(cell.status)
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

    private func choose(_ cell: PrayerCell) {
        selectedCell = cell
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
        case .pending, .future, .qada, .unrecordedHistory: theme.secondaryInk
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
                        if cell.status == .pending || cell.status == .future || cell.status == .unrecordedHistory {
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

private struct PrayerTodayLogSheet: View {
    let cell: PrayerCell
    let isSaving: Bool
    let save: (PrayerStoredStatus, FridayPrayerKind?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var status: PrayerStoredStatus
    @State private var fridayKind: FridayPrayerKind

    init(cell: PrayerCell, isSaving: Bool, save: @escaping (PrayerStoredStatus, FridayPrayerKind?) -> Void) {
        self.cell = cell; self.isSaving = isSaving; self.save = save
        _status = State(initialValue: cell.status == .alone ? .alone : .jamaah)
        _fridayKind = State(initialValue: cell.status == .alone ? .dhuhr : (cell.fridayKind ?? .jumuah))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("حال الصلاة") {
                    HStack(spacing: 12) {
                        statusButton(.jamaah, title: "جماعة")
                        statusButton(.alone, title: "منفردًا")
                    }
                }
                if cell.isFriday {
                    Section("ظهر الجمعة") {
                        HStack(spacing: 12) {
                            if status == .jamaah { fridayButton(.jumuah, title: "الجمعة") }
                            fridayButton(.dhuhr, title: "الظهر")
                        }
                    }
                }
                Section {
                    Button("حفظ التسجيل") {
                        save(status, cell.isFriday ? fridayKind : nil)
                        dismiss()
                    }
                    .buttonStyle(MadarPrimaryButton())
                    .disabled(isSaving)
                    .accessibilityIdentifier("prayer-save")
                }
            }
            .navigationTitle("تسجيل \(title(cell.reference.prayer))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("إغلاق") { dismiss() }.accessibilityIdentifier("prayer-log-dismiss")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func statusButton(_ value: PrayerStoredStatus, title: String) -> some View {
        Button { status = value; if cell.isFriday && value == .alone { fridayKind = .dhuhr } } label: {
            Text(title).font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(status == value ? theme.onAccent : theme.ink)
                .background(status == value ? theme.accentFill : theme.surface, in: .rect(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.line, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("prayer-status-\(value.rawValue)")
        .accessibilityAddTraits(status == value ? .isSelected : [])
    }

    private func fridayButton(_ value: FridayPrayerKind, title: String) -> some View {
        Button { fridayKind = value } label: {
            Text(title).font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(fridayKind == value ? theme.onAccent : theme.ink)
                .background(fridayKind == value ? theme.accentFill : theme.surface, in: .rect(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.line, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("prayer-friday-\(value.rawValue)")
        .accessibilityAddTraits(fridayKind == value ? .isSelected : [])
    }

    private func title(_ prayer: Prayer) -> String {
        switch prayer { case .fajr: "الفجر"; case .dhuhr: "الظهر"; case .asr: "العصر"; case .maghrib: "المغرب"; case .isha: "العشاء" }
    }
}
