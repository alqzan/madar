import SwiftUI
import MadarCore
import MadarDesign
import MadarPrayer

/// S1 · Prayer home («الرواق والبركة»), matched to `screens/salah/01-S1-Home.jpg` and `-s1`.
/// Not copied from the canonical: the day/night button (prototype only), sample numbers,
/// the heart label under the arches (RP6), and the «تُحسب فائتة» line (RP1).
struct PrayerTodayView: View {
    @Bindable var session: AppSession
    @Environment(\.roomTheme) private var inheritedTheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var selectedSheet: PrayerTodaySheet?

    private var theme: RoomTheme { RoomTheme(room: "salah", dark: inheritedTheme.dark, calmPaper: inheritedTheme.calmPaper) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let instant = session.prayerNow(timeline.date)
            ScrollView {
                VStack(spacing: 0) {
                    if let snapshot = try? session.prayerSnapshot(at: instant) {
                        header(day: snapshot.today.day)
                            .padding(.top, 8)
                        nextPrayer(snapshot, now: instant)
                            .padding(.top, 26)
                        verseDivider
                            .padding(.top, 18)
                        riwaq(snapshot, now: instant)
                            .padding(.top, 18)
                        if snapshot.hasTimes {
                            Text(todaySummary(snapshot))
                                .font(PrayerHomeType.body)
                                .foregroundStyle(theme.secondaryInk)
                                .multilineTextAlignment(.center)
                                .padding(.top, 14)
                                .accessibilityIdentifier("prayer-today-summary")
                        }
                        VStack(spacing: 16) {
                            if let pending = notice(snapshot, now: instant) { pending }
                            heartNotice(snapshot)
                            haliCard(snapshot)
                            qadaCard(snapshot)
                            qiyamCard(snapshot)
                        }
                        .padding(.top, 20)
                    } else {
                        header(day: nil)
                        PrayerPaperCard {
                            Text("تعذّر حساب صلاة اليوم. راجع المدينة وطريقة الحساب في خصّص مدار.")
                                .font(MadarTypography.body())
                        }
                        .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(theme.background)
            .foregroundStyle(theme.ink)
        }
        .environment(\.roomTheme, theme)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .sheet(item: $selectedSheet) { route in
            Group {
            switch route {
            case .oldMissed:
                if let snapshot = try? session.prayerSnapshot(at: session.prayerNow()) {
                    PrayerOldMissedSheet(session: session, trackingStart: snapshot.tracking.day, finished: { selectedSheet = nil })
                }
            case .qiyam:
                if let snapshot = try? session.prayerSnapshot(at: session.prayerNow()) {
                    PrayerNightLoggingSheet(session: session, snapshot: snapshot, finished: { selectedSheet = nil })
                }
            case .heart(let cell):
                PrayerHeartAnswerSheet(session: session, cell: cell, finished: { selectedSheet = nil })
            case .statistics:
                NavigationStack {
                    if let snapshot = try? session.prayerSnapshot(at: session.prayerNow()) {
                        PrayerStatisticsView(session: session, snapshot: snapshot) { choose($0) }
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { selectedSheet = nil } } }
                    }
                }
            case .qadaList:
                NavigationStack {
                    PrayerQadaListSheet(session: session, dateLabel: qadaDate,
                        makeUp: { item in selectedSheet = .makeUp(item, isFridayNoon: item.isFriday, dateLabel: qadaDate(item.reference.day)) },
                        addOld: { selectedSheet = .oldMissed })
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { selectedSheet = nil } } }
                }
            case .log(let cell):
                PrayerTodayLogSheet(cell: cell, isSaving: session.prayerWriteInProgress,
                    answerHeart: session.bool("salah.askHeart") && [.jamaah, .alone, .qada].contains(cell.status) ? { selectedSheet = .heart(cell) } : nil) { status, fridayKind, makeUpNow in
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
                PrayerGapResolutionSheet(references: references, fridayReferences: fridayReferences, dateLabel: qadaDate, digits: digits) { resolutions in
                    session.resolvePrayerGap(resolutions)
                }
            }
            }
            .dynamicTypeSize(dynamicType)
            .environment(\.roomTheme, theme)
        }
    }

    // MARK: Header and next prayer

    private func header(day prayerDay: GregorianDay?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("الصلاة").font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
            Text(headerDate(prayerDay ?? GregorianDay.containing(session.prayerNow(), in: session.activePlace.timeZone)))
                .font(PrayerHomeType.body)
                .foregroundStyle(theme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("prayer-today-header")
    }

    /// «الأربعاء ٢٦ ربيع الآخر ١٤٤٨، ٧ أكتوبر». RU1: «،» separates the two dates, never «·».
    private func headerDate(_ day: GregorianDay) -> String {
        let place = session.activePlace
        let midday = day.date(in: place.timeZone).addingTimeInterval(12 * 3600)
        let dual = DualDate(instant: midday, timeZone: place.timeZone,
            source: HijriSource(rawValue: session.string("core.hijriSource")) ?? .ummAlQura,
            sightingOffset: Int(session.number("core.hijriOffset")))
        let numerals: NumeralStyle = session.string("core.numerals") == "western" ? .western : .hindi
        let digits = MadarNumberFormatter(style: numerals)
        let months = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
        let hijri = "\(digits.string(dual.hijri.day)) \(months[dual.hijri.month - 1]) \(digits.string(dual.hijri.year))"
        let formatter = DateFormatter()
        formatter.locale = numeralLocale
        formatter.timeZone = place.timeZone
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "EEEE"
        let weekday = formatter.string(from: midday)
        formatter.dateFormat = "d MMMM"
        let gregorian = formatter.string(from: midday)
        return session.string("core.firstCalendar") == "gregorian"
            ? "\(weekday) \(gregorian)، \(hijri)"
            : "\(weekday) \(hijri)، \(gregorian)"
    }

    private func nextPrayer(_ snapshot: PrayerSnapshot, now: Date) -> some View {
        VStack(spacing: 6) {
            if let next = snapshot.next {
                Text("الصلاة القادمة").font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
                Text(nextTitle(next.reference, snapshot: snapshot))
                    .font(PrayerHomeType.hero)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(nextLine(next, now: now))
                    .font(PrayerHomeType.lead)
                    .foregroundStyle(theme.secondaryInk)
                    .multilineTextAlignment(.center)
            } else if snapshot.hasTimes {
                Text("اكتمل يوم الصلاة").font(MadarTypography.cardTitle())
            } else {
                Text("لا تُحسب المواقيت هنا اليوم").font(MadarTypography.cardTitle())
                Text("لا تظهر أوقات غير متاحة أو تسجيلات مستقبلية.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("prayer-next")
    }

    private func nextLine(_ next: PrayerOccurrence, now: Date) -> String {
        let time = clock(next.time, timeZone: next.place.timeZone)
        guard next.time > now else { return time }
        return time + " · " + PrayerCopy.after(seconds: next.time.timeIntervalSince(now), digits: digits)
    }

    private var verseDivider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(theme.line).frame(height: 1)
            PrayerStar().fill(theme.accent).frame(width: 9, height: 9)
            Text("إِنَّ الصَّلَاةَ كَانَتْ عَلَى الْمُؤْمِنِينَ كِتَابًا مَوْقُوتًا")
                .font(.custom("Amiri-Regular", size: 15, relativeTo: .subheadline))
                .foregroundStyle(theme.secondaryInk)
                .lineLimit(1).minimumScaleFactor(0.6)
                .layoutPriority(1)
            PrayerStar().fill(theme.accent).frame(width: 9, height: 9)
            Rectangle().fill(theme.line).frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("إن الصلاة كانت على المؤمنين كتابًا موقوتًا")
    }

    // MARK: Riwaq

    private func riwaq(_ snapshot: PrayerSnapshot, now: Date) -> some View {
        Group {
            if dynamicType.isAccessibilitySize {
                PrayerPaperCard(tinted: true) {
                    VStack(spacing: 8) {
                        ForEach(snapshot.today.cells, id: \.reference) { cell in prayerEntry(cell, snapshot: snapshot, now: now) }
                    }
                }
            } else {
                PrayerRiwaq(pool: session.bool("salah.pool")) {
                    ForEach(snapshot.today.cells, id: \.reference) { cell in prayerEntry(cell, snapshot: snapshot, now: now) }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !snapshot.hasTimes {
                Text("يمكنك اختيار المدينة من خصّص مدار عند توفر المواقيت.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).padding(12)
            }
        }
    }

    @ViewBuilder private func prayerEntry(_ cell: PrayerCell, snapshot: PrayerSnapshot, now: Date) -> some View {
        let canEdit = cell.canLog && cell.time != nil && [.pending, .jamaah, .alone, .missed].contains(cell.status)
        let isNext = snapshot.next?.reference == cell.reference
        let arch = PrayerTodayArch(cell: cell, isNext: isNext,
            title: cell.isFriday && cell.reference.prayer == .dhuhr ? "الجمعة" : title(cell.reference.prayer),
            tall: cell.isFriday && cell.reference.prayer == .dhuhr && session.bool("salah.fridayTallArch"),
            timeLabel: (cell.prayerTime ?? cell.time).map { clock($0, timeZone: snapshot.activeTrip?.place.timeZone ?? session.activePlace.timeZone) } ?? "—",
            countdown: isNext && cell.status == .future ? cell.prayerTime.flatMap { PrayerCopy.countdown(until: $0, now: now, digits: digits) } : nil)
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

    /// «٣ من ٥ اليوم · بقيت صلاتان»: «·» sits between words only (RU1).
    private func todaySummary(_ snapshot: PrayerSnapshot) -> String {
        let cells = snapshot.today.cells.filter { $0.time != nil }
        let recorded = cells.filter { [.jamaah, .alone, .qada, .missed, .excused].contains($0.status) }.count
        let remaining = cells.count - recorded
        return "\(digits.string(recorded)) من \(digits.string(cells.count)) اليوم · " + PrayerCopy.remaining(remaining, digits: digits)
    }

    // MARK: Notices

    /// One quiet notice: an unrecorded prayer whose window has ended, or an older unresolved gap.
    /// RP1: neither ever turns into a missed prayer by itself.
    private func notice(_ snapshot: PrayerSnapshot, now: Date) -> AnyView? {
        let pending = Set(snapshot.pending)
        let open = currentPrayer(snapshot, now: now)
        let closed = snapshot.history.flatMap(\.cells)
            .filter { pending.contains($0.reference) && $0.canLog && $0.time != nil && $0.reference != open }
        let gap = snapshot.unconfirmed + closed.map(\.reference).filter { !snapshot.unconfirmed.contains($0) }
        guard !gap.isEmpty else { return nil }
        if gap.count == 1, let first = closed.first {
            return AnyView(PrayerNoticeRow(
                title: "مضى وقت \(self.title(first.reference.prayer))\(dayWord(first.reference.day, today: snapshot.today.day)) ولم تُسجِّلها.",
                detail: "تبقى معلّقة حتى تختار حالها.",
                action: "سجِّلها", identifier: "prayer-pending-review") { choose(first) })
        }
        let fridays = snapshot.unconfirmedFridayNoon.union(closed.filter { $0.isFriday && $0.reference.prayer == .dhuhr }.map(\.reference))
        return AnyView(PrayerNoticeRow(
            title: PrayerCopy.unconfirmed(gap.count, digits: digits),
            detail: "لا تُحسب فائتة إلا باختيارك.",
            action: "سجِّلها", identifier: snapshot.unconfirmed.isEmpty ? "prayer-pending-review" : "prayer-recovery") {
                selectedSheet = .recovery(gap, fridays, session.activePlace.timeZone)
            })
    }

    /// The prayer whose window is still open (its time has come and the next prayer has not).
    private func currentPrayer(_ snapshot: PrayerSnapshot, now: Date) -> PrayerReference? {
        snapshot.history.flatMap(\.cells).filter { ($0.prayerTime ?? .distantFuture) <= now }.max { ($0.prayerTime ?? .distantPast) < ($1.prayerTime ?? .distantPast) }?.reference
    }

    private func dayWord(_ day: GregorianDay, today: GregorianDay) -> String {
        if day == today { return "" }
        if day.adding(days: 1) == today { return " أمس" }
        return " يوم " + qadaDate(day)
    }

    @ViewBuilder private func heartNotice(_ snapshot: PrayerSnapshot) -> some View {
        // RP6: shown only when the owner turned the heart question on (default off).
        if session.bool("salah.askHeart"), let cell = snapshot.history.flatMap(\.cells).first(where: { snapshot.pendingHeart.contains($0.reference) }) {
            Button { selectedSheet = .heart(cell) } label: {
                HStack(spacing: 12) {
                    PrayerStar().fill(theme.accent).frame(width: 14, height: 14)
                    Text("بقي سؤال القلب عن \(title(cell.reference.prayer)).")
                        .font(PrayerHomeType.strong)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("أجِب").font(PrayerHomeType.strong).foregroundStyle(theme.accent)
                }
                .padding(.horizontal, 18).frame(minHeight: 58)
                .background(theme.color("surface"), in: .rect(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("prayer-heart-review")
        }
    }

    // MARK: Hali, qada and qiyam

    private func haliCard(_ snapshot: PrayerSnapshot) -> some View {
        let stats = snapshot.statistics
        let prayerStreak = "سلسلة الصلاة " + PrayerCopy.days(stats.prayerStreak, digits: digits)
        let mosqueStreak = session.bool("salah.showMosqueStreak") ? "المسجد " + PrayerCopy.days(stats.mosqueStreak, digits: digits) : nil
        let streaks = [prayerStreak, mosqueStreak].compactMap { $0 }.joined(separator: " · ")
        return Button { selectedSheet = .statistics } label: {
            PrayerPaperCard {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("حالي").font(PrayerHomeType.cardHead)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(stats.percentage.map(percent) ?? "—")
                                .font(PrayerHomeType.number)
                                .accessibilityIdentifier("prayer-month-percentage")
                            Text("هذا الشهر").font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
                        }
                        ViewThatFits(in: .horizontal) {
                            Text(streaks).lineLimit(1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(prayerStreak)
                                if let mosqueStreak { Text(mosqueStreak) }
                            }
                        }
                        .font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !dynamicType.isAccessibilitySize {
                        PrayerRecentBeads(cells: stats.last25, compact: true).frame(width: 118)
                        Image(systemName: "chevron.forward").font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.secondaryInk).accessibilityHidden(true)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("حالي، " + (stats.percentage.map(percent) ?? "لم تُحسب النسبة بعد") + " هذا الشهر، " + streaks)
        .accessibilityHint("افتح حالي وسجلّ الشهر")
        .accessibilityIdentifier("prayer-history")
    }

    @ViewBuilder private func qadaCard(_ snapshot: PrayerSnapshot) -> some View {
        let outstanding = snapshot.qada.filter { $0.madeUpAt == nil }
        if let first = outstanding.first {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    PrayerStar().fill(theme.color("missed")).frame(width: 15, height: 15)
                    Text(digits.string(outstanding.count)).font(PrayerHomeType.number)
                    Text(PrayerCopy.owed(outstanding.count)).font(PrayerHomeType.strong)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                HStack(alignment: .top, spacing: 12) {
                    Rectangle().fill(theme.color("missed")).frame(width: 2)
                    PrayerQadaCitation()
                }
                .fixedSize(horizontal: false, vertical: true)
                buttonsRow(first: first)
            }
            .padding(20)
            .background(theme.color("missed").opacity(0.05), in: .rect(cornerRadius: 22))
            .background(theme.background, in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.color("missed").opacity(0.28), lineWidth: 1) }
        } else {
            Button { selectedSheet = .oldMissed } label: {
                HStack {
                    Text(snapshot.qada.isEmpty ? "لا فوائت مسجّلة عليك" : "قضيتَ ما سجّلتَه من الفوائت")
                        .font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("أضف فائتة قديمة").font(PrayerHomeType.strong).foregroundStyle(theme.accent)
                }
                .padding(.horizontal, 18).frame(minHeight: 54)
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line, lineWidth: 1) }
                .contentShape(.rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("prayer-old-missed")
        }
    }

    @ViewBuilder private func buttonsRow(first: PrayerQada) -> some View {
        let makeUp = Button { selectedSheet = .makeUp(first, isFridayNoon: first.isFriday, dateLabel: qadaDate(first.reference.day)) } label: {
            Text("قضيتُ واحدة").font(PrayerHomeType.strong).frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(theme.background).background(theme.ink, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain).disabled(session.prayerWriteInProgress)
        .accessibilityIdentifier("prayer-qada-makeup")
        let places = Button { selectedSheet = .qadaList } label: {
            Text("مواضعها").font(PrayerHomeType.strong).frame(minHeight: 54).padding(.horizontal, 26)
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.ink.opacity(0.18), lineWidth: 1) }
                .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("prayer-qada-places")
        if dynamicType.isAccessibilitySize {
            VStack(spacing: 10) { makeUp; places.frame(maxWidth: .infinity) }
        } else {
            HStack(spacing: 12) { makeUp; places }
        }
    }

    private func qiyamCard(_ snapshot: PrayerSnapshot) -> some View {
        let night = snapshot.nights.first { $0.night == snapshot.nightDefault }
        let summary = night.map { PrayerCopy.rakaat($0.rakaat, digits: digits) + ($0.witr ? "، أوترتُ" : "") } ?? "لم تُسجَّل ليلتك"
        return Button { selectedSheet = .qiyam } label: {
            PrayerPaperCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("قيام الليل").font(PrayerHomeType.cardHead)
                        Spacer(minLength: 8)
                        Text(summary).font(PrayerHomeType.strong).foregroundStyle(theme.accent)
                            .accessibilityIdentifier("prayer-qiyam-summary")
                    }
                    if !dynamicType.isAccessibilitySize {
                        PrayerNightFootprint(nights: snapshot.nights, last: snapshot.nightDefault)
                    }
                    Text("آخر ثلاثين ليلة")
                        .font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("prayer-qiyam")
    }

    // MARK: Formatting

    private var digits: MadarNumberFormatter { MadarNumberFormatter(style: session.string("core.numerals") == "western" ? .western : .hindi) }
    private var numeralLocale: Locale { Locale(identifier: session.string("core.numerals") == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab") }

    private func percent(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = numeralLocale
        formatter.numberStyle = .percent
        return formatter.string(from: NSNumber(value: Double(value) / 100)) ?? digits.string(value)
    }

    private func qadaDate(_ day: GregorianDay) -> String {
        let formatter = DateFormatter()
        formatter.locale = numeralLocale
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

    private func nextTitle(_ reference: PrayerReference, snapshot: PrayerSnapshot) -> String {
        let friday = snapshot.today.cells.first { $0.reference == reference }?.isFriday ?? false
        return friday && reference.prayer == .dhuhr ? "الجمعة" : title(reference.prayer)
    }

    private func clock(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = numeralLocale
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Type roles measured from the canonical S1 (iOS points at the Large size)

enum PrayerHomeType {
    static let hero = Font.custom("thmanyahserifdisplay-Bold", size: 46, relativeTo: .largeTitle)
    static let number = Font.custom("thmanyahserifdisplay-Bold", size: 36, relativeTo: .title)
    static let cardHead = Font.custom("thmanyahserifdisplay-Bold", size: 20, relativeTo: .title3)
    static let archName = Font.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)
    static let lead = Font.custom("thmanyahsans-Regular", size: 16, relativeTo: .callout)
    static let strong = Font.custom("thmanyahsans-Bold", size: 16, relativeTo: .headline)
    static let body = Font.custom("thmanyahsans-Regular", size: 15, relativeTo: .subheadline)
    static let small = Font.custom("thmanyahsans-Regular", size: 13, relativeTo: .footnote)
    static let smallBold = Font.custom("thmanyahsans-Bold", size: 13, relativeTo: .footnote)
}

// MARK: - Arabic plural copy (RU3: String Catalog variants, digits follow core.numerals)

enum PrayerCopy {
    // Argument 1 chooses the Arabic plural; argument 2 is the count in core.numerals digits.
    static func hours(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.hours", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func minutes(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.minutes", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func days(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.days", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func remaining(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.remaining", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func pending(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.pending", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func unconfirmed(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.unconfirmed", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    static func rakaat(_ count: Int, digits: MadarNumberFormatter, bundle: Bundle = .main) -> String {
        let formatted = digits.string(count)
        return String(localized: "prayer.rakaat", defaultValue: "\(count) \(formatted)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    /// The count is shown large beside this phrase, so the phrase carries no digits.
    static func owed(_ count: Int, bundle: Bundle = .main) -> String {
        String(localized: "prayer.owed", defaultValue: "\(count)", table: "Prayer", bundle: bundle, locale: Locale(identifier: "ar"))
    }
    /// «بعد ساعة و١٤ دقيقة».
    static func after(seconds: TimeInterval, digits: MadarNumberFormatter) -> String {
        let total = max(0, Int(seconds / 60))
        let hours = total / 60, minutes = total % 60
        if total == 0 { return "الآن" }
        if hours == 0 { return "بعد " + self.minutes(minutes, digits: digits) }
        return "بعد " + self.hours(hours, digits: digits) + (minutes > 0 ? " و" + self.minutes(minutes, digits: digits) : "")
    }
    /// RL7: two fields, «بعد ١:١٤».
    static func countdown(until date: Date, now: Date, digits: MadarNumberFormatter) -> String? {
        guard date > now else { return nil }
        let total = Int(date.timeIntervalSince(now) / 60)
        let minutes = total % 60
        return "بعد " + digits.string(total / 60) + ":" + (minutes < 10 ? digits.string(0) : "") + digits.string(minutes)
    }
}

// MARK: - Shared S1 pieces

/// A paper card: the room background with a quiet hairline, as on S1.
struct PrayerPaperCard<Content: View>: View {
    var tinted = false
    @ViewBuilder let content: () -> Content
    @Environment(\.roomTheme) private var theme
    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.vertical, 18)
            .background(tinted ? theme.color("goldSoft") : .clear, in: .rect(cornerRadius: 22))
            .background(theme.background, in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(tinted ? theme.line : theme.ink.opacity(0.1), lineWidth: 1) }
    }
}

private struct PrayerNoticeRow: View {
    let title: String
    let detail: String
    let action: String
    let identifier: String
    let perform: () -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        Button(action: perform) {
            PrayerPaperCard {
                let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    HStack(alignment: .top, spacing: 12) {
                        Rectangle().fill(theme.color("missed")).frame(width: 8, height: 8).rotationEffect(.degrees(45)).padding(.top, 7)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(PrayerHomeType.strong).fixedSize(horizontal: false, vertical: true)
                            Text(detail).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(action).font(PrayerHomeType.strong).foregroundStyle(theme.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// The arcade card: arches stand on a water line; the pool reflects them (§5 HorseshoeArch).
private struct PrayerRiwaq<Content: View>: View {
    let pool: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.roomTheme) private var theme
    var body: some View {
        HStack(alignment: .top, spacing: 0) { content() }
            .padding(.horizontal, 10)
            .padding(.top, 22).padding(.bottom, 18)
            .background(alignment: .top) {
                // The water line runs edge to edge under the arches.
                Rectangle().fill(theme.ink.opacity(0.22)).frame(height: 1)
                    .padding(.top, 22 + PrayerTodayArch.archHeight)
            }
            .background(theme.color("goldSoft"), in: .rect(cornerRadius: 22))
            .background(theme.background, in: .rect(cornerRadius: 22))
            .clipShape(.rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.line, lineWidth: 1) }
            .environment(\.prayerPool, pool)
    }
}

private extension EnvironmentValues {
    @Entry var prayerPool = true
}

private struct PrayerTodayArch: View {
    static let archHeight: CGFloat = 92
    let cell: PrayerCell
    let isNext: Bool
    let title: String
    let tall: Bool
    let timeLabel: String
    let countdown: String?
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.prayerPool) private var pool

    private var statusText: String {
        switch cell.status {
        case .jamaah: "جماعة"
        case .alone: "وحدي"
        case .qada: "قُضيت"
        case .missed: "فاتتني"
        case .unrecordedHistory: "لم أسجّل"
        case .unconfirmed: "غير محسومة"
        case .excused: "معذور"
        case .pending: "لم تُسجَّل"
        case .future: "لم يحن"
        }
    }
    var accessibilityText: String { "\(title)، \(timeLabel)، \(statusText)" }
    private var gold: Color { theme.color("goldMid") }
    private var logged: Bool { [.jamaah, .alone, .qada, .missed].contains(cell.status) }
    private var bodyFill: Color {
        switch cell.status {
        case .jamaah: gold.opacity(0.62)
        case .alone: gold.opacity(0.36)
        case .qada: theme.ink.opacity(0.07)
        default: theme.background
        }
    }

    @ViewBuilder var body: some View {
        if dynamicType.isAccessibilitySize {
            accessibilityRow
        } else {
            VStack(spacing: 0) {
                arch
                    .frame(height: Self.archHeight + (tall ? 12 : 0))
                    .frame(height: Self.archHeight, alignment: .bottom)
                reflection
                    .frame(height: Self.archHeight * 0.42, alignment: .top)
                    .clipped()
                VStack(spacing: 3) {
                    Text(title).font(PrayerHomeType.archName).lineLimit(1).minimumScaleFactor(0.75)
                    Text(timeLabel).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.8)
                    Text(countdown ?? statusText)
                        .font(countdown != nil || cell.status == .missed ? PrayerHomeType.smallBold : PrayerHomeType.small)
                        .foregroundStyle(countdown != nil ? theme.accent : cell.status == .missed ? theme.color("missedTextOnSurface") : cell.status == .future ? theme.secondaryInk : theme.ink.opacity(0.78))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
    }

    private var arch: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width - 12, 58)
            let height = geometry.size.height
            let rect = CGRect(x: (geometry.size.width - width) / 2, y: 0, width: width, height: height)
            let shape = PrayerHorseshoe().path(in: rect)
            let spring = rect.minY + width / 2 * 1.5
            ZStack {
                // Pillars beside the arch.
                ForEach([rect.minX - 5, rect.maxX], id: \.self) { x in
                    Rectangle().fill(gold.opacity(0.1)).frame(width: 5, height: height - spring + 6)
                        .position(x: x + 2.5, y: (spring - 6 + height) / 2)
                }
                shape.fill(bodyFill)
                // Lattice: the whole head once a prayer is recorded, a frame band otherwise.
                PrayerLatticePattern(spacing: 9)
                    .stroke(theme.accent.opacity(logged ? 0.55 : 0.45), lineWidth: 1)
                    .mask {
                        if logged {
                            shape.fill().mask(alignment: .top) { Rectangle().frame(height: spring + 2) }
                        } else {
                            shape.stroke(lineWidth: 11).mask(alignment: .top) { Rectangle().frame(height: spring + 4) }
                        }
                    }
                if isNext {
                    shape.stroke(theme.accent, style: StrokeStyle(lineWidth: 5, lineJoin: .round))
                } else if cell.status == .missed {
                    shape.stroke(theme.color("missed"), lineWidth: 1.5)
                } else if cell.status == .pending {
                    shape.stroke(gold, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                symbol.position(x: rect.midX, y: spring)
            }
        }
    }

    @ViewBuilder private var symbol: some View {
        switch cell.status {
        case .jamaah:
            PrayerStar().fill(theme.accent).frame(width: 15, height: 15)
        case .alone:
            PrayerStar().fill(gold).overlay { PrayerStar().stroke(theme.accent, lineWidth: 1) }.frame(width: 15, height: 15)
        case .qada:
            PrayerStar().fill(theme.ink.opacity(0.32)).frame(width: 15, height: 15)
        case .missed:
            PrayerStar().stroke(theme.color("missed"), lineWidth: 1.2).frame(width: 15, height: 15)
        case .pending:
            TimelineView(.animation(minimumInterval: 1 / 15)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
                Capsule().fill(theme.accent).frame(width: 14, height: 2).opacity(0.35 + 0.5 * abs(1 - 2 * phase))
            }
        default:
            Capsule().fill(theme.ink.opacity(0.22)).frame(width: 14, height: 2)
        }
    }

    /// Mirrored, at about half the height, 28% opacity, with water lines every 6 points.
    @ViewBuilder private var reflection: some View {
        if pool {
            arch
                .frame(height: Self.archHeight)
                .scaleEffect(x: 1, y: -1)
                .scaleEffect(x: 1, y: 0.5, anchor: .top)
                .opacity(0.28)
                .overlay {
                    VStack(spacing: 5) { ForEach(0..<8, id: \.self) { _ in Rectangle().fill(theme.background.opacity(0.7)).frame(height: 1) } }
                }
                .mask(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
                .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }

    var accessibilityRow: some View {
        HStack(spacing: 12) {
            symbol.frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(MadarTypography.section())
                Text("\(timeLabel)، \(countdown ?? statusText)").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }
            Spacer(minLength: 8)
            if isNext { Image(systemName: "arrow.left").foregroundStyle(theme.accent).accessibilityHidden(true) }
        }
        .frame(minHeight: 54)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Diamond lattice of 1-point lines (§5: «إطار سبكة معيّنات ١ نقطة»).
private struct PrayerLatticePattern: Shape {
    let spacing: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x <= rect.maxX + rect.height {
            path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x + rect.height, y: rect.maxY))
            path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x - rect.height, y: rect.maxY))
            x += spacing
        }
        return path
    }
}

/// Last 30 nights as small squares, oldest on the right (RTL), the newest on the left.
private struct PrayerNightFootprint: View {
    let nights: [PrayerNight]
    let last: GregorianDay
    @Environment(\.roomTheme) private var theme
    var body: some View {
        let byDay = Dictionary(nights.map { ($0.night, $0) }, uniquingKeysWith: { $1 })
        HStack(spacing: 3) {
            ForEach(0..<30, id: \.self) { offset in
                let night = byDay[last.adding(days: offset - 29)]
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color(night))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
    }
    private func color(_ night: PrayerNight?) -> Color {
        guard let night, night.rakaat > 0 || night.witr else { return theme.ink.opacity(0.1) }
        return night.rakaat >= 8 ? theme.accent : theme.color("goldMid")
    }
}

/// «مواضعها»: every recorded missed prayer, oldest first, with one make-up action each.
private struct PrayerQadaListSheet: View {
    let session: AppSession
    let dateLabel: (GregorianDay) -> String
    let makeUp: (PrayerQada) -> Void
    let addOld: () -> Void
    @Environment(\.roomTheme) private var theme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("الفوائت").font(MadarTypography.title())
                if let snapshot = try? session.prayerSnapshot(at: session.prayerNow()) {
                    ForEach(snapshot.qada) { item in
                        HStack(spacing: 12) {
                            PrayerStar().stroke(item.madeUpAt == nil ? theme.color("missed") : theme.secondaryInk, lineWidth: 1).frame(width: 14, height: 14)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(prayerTitle(item.reference.prayer)).font(PrayerHomeType.strong)
                                Text(dateLabel(item.reference.day)).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                            }
                            Spacer()
                            if item.madeUpAt == nil {
                                Button("اقضِها") { makeUp(item) }.font(PrayerHomeType.strong).foregroundStyle(theme.accent).frame(minHeight: 44)
                            } else {
                                Text("قُضيت").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                            }
                        }
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("prayer-qada-row-\(item.reference.day)-\(item.reference.prayer.rawValue)")
                        Divider()
                    }
                }
                Button("أضف فائتة قديمة", action: addOld)
                    .font(PrayerHomeType.strong).foregroundStyle(theme.accent).frame(minHeight: 44)
                    .accessibilityIdentifier("prayer-old-missed")
            }
            .padding(20)
        }
        .background(theme.background)
        .foregroundStyle(theme.ink)
    }
}

private enum PrayerTodaySheet: Identifiable {
    case log(PrayerCell)
    case statistics
    case heart(PrayerCell)
    case qiyam
    case oldMissed
    case qadaList
    case makeUp(PrayerQada, isFridayNoon: Bool, dateLabel: String)
    case recovery([PrayerReference], Set<PrayerReference>, TimeZone)
    var id: String {
        switch self {
        case .oldMissed: "old-missed"
        case .qadaList: "qada-list"
        case .qiyam: "qiyam"
        case .statistics: "statistics"
        case .heart(let cell): "heart-\(cell.reference.naturalKey)"
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
    let answerHeart: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var status: PrayerStoredStatus
    @State private var fridayKind: FridayPrayerKind?

    init(cell: PrayerCell, isSaving: Bool, answerHeart: (() -> Void)? = nil, save: @escaping (PrayerStoredStatus, FridayPrayerKind?, Bool) -> Void) {
        self.cell = cell; self.isSaving = isSaving; self.save = save; self.answerHeart = answerHeart
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
                if let answerHeart {
                    Section { Button("سؤال القلب") { answerHeart() }.frame(minHeight: 44).accessibilityIdentifier("prayer-log-heart") }
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

/// «صلوات بلا تسجيل»: settle a gap in one tap, a day at a time, or prayer by prayer.
/// RP1: nothing here is chosen for the user; what is left unchosen stays as it is.
private struct PrayerGapResolutionSheet: View {
    let references: [PrayerReference]
    let fridayReferences: Set<PrayerReference>
    let dateLabel: (GregorianDay) -> String
    let digits: MadarNumberFormatter
    let resolve: ([PrayerGapResolution]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var choices: [PrayerReference: Choice] = [:]

    /// One choice as the user reads it; Friday noon carries its kind explicitly (RP5).
    struct Choice: Hashable {
        let status: PrayerStoredStatus
        var fridayKind: FridayPrayerKind? = nil
    }

    private var days: [GregorianDay] { Array(Set(references.map(\.day))).sorted() }
    private func prayers(on day: GregorianDay) -> [PrayerReference] {
        references.filter { $0.day == day }.sorted { $0.prayer.rawValue.order < $1.prayer.rawValue.order }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                quickActions
                ForEach(days, id: \.self) { day in dayCard(day) }
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .background(theme.background)
        .foregroundStyle(theme.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("صلوات بلا تسجيل").font(PrayerHomeType.cardHead).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("إغلاق") { dismiss() }.font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
                    .frame(minHeight: 44)
            }
            Text(PrayerCopy.unconfirmed(references.count, digits: digits))
                .font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
            if !rangeText.isEmpty {
                Text(rangeText).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
            }
            Text("لا يُحسب شيء منها فائتة إلا باختيارك، وما تتركه يبقى كما هو.")
                .font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
        }
    }

    private var rangeText: String {
        guard let first = days.first, let last = days.last else { return "" }
        return first == last ? dateLabel(first) : "من " + dateLabel(first) + " إلى " + dateLabel(last)
    }

    /// One tap settles the whole gap and closes; the undo bar on the home page reverses it.
    private var quickActions: some View {
        VStack(spacing: 10) {
            Button { apply(Choice(status: .alone, fridayKind: nil), to: references, saveNow: true) } label: {
                quickLabel("صلّيتها كلها", detail: "تُسجَّل في وقتها، وحدي")
            }
            .buttonStyle(.plain).accessibilityIdentifier("prayer-gap-alone-all")
            Button { apply(Choice(status: .unrecordedHistory), to: references, saveNow: true) } label: {
                quickLabel("لم أسجّل هذه الفترة", detail: "لا قضاء ولا نسبة ولا سلسلة")
            }
            .buttonStyle(.plain).accessibilityIdentifier("prayer-gap-unrecorded-all")
        }
    }

    private func quickLabel(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(PrayerHomeType.strong)
            Spacer(minLength: 8)
            Text(detail).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
        }
        .padding(.horizontal, 18).frame(maxWidth: .infinity, minHeight: 56)
        .background(theme.color("goldSoft"), in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line, lineWidth: 1) }
        .contentShape(.rect(cornerRadius: 18))
    }

    private func dayCard(_ day: GregorianDay) -> some View {
        let refs = prayers(on: day)
        return PrayerPaperCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(dateLabel(day)).font(PrayerHomeType.strong)
                    Spacer(minLength: 8)
                    Menu {
                        ForEach(dayOptions, id: \.self) { choice in
                            Button(title(choice, friday: false)) { apply(choice, to: refs, saveNow: false) }
                        }
                    } label: {
                        Text("اليوم كله").font(PrayerHomeType.smallBold).foregroundStyle(theme.accent)
                            .frame(minHeight: 44).contentShape(.rect)
                    }
                    .accessibilityIdentifier("prayer-gap-day-\(day)")
                }
                ForEach(refs, id: \.self) { ref in
                    prayerRow(ref)
                    if ref != refs.last { Divider().overlay(theme.line) }
                }
            }
        }
    }

    private func prayerRow(_ ref: PrayerReference) -> some View {
        let friday = fridayReferences.contains(ref)
        let chosen = choices[ref]
        return HStack {
            Text(friday ? "الجمعة" : prayerTitle(ref.prayer)).font(PrayerHomeType.body)
            Spacer(minLength: 8)
            Menu {
                ForEach(options(friday: friday), id: \.self) { choice in
                    Button(title(choice, friday: friday)) { choices[ref] = choice }
                }
                if chosen != nil {
                    Divider()
                    Button("اتركها كما هي") { choices[ref] = nil }
                }
            } label: {
                Text(chosen.map { title($0, friday: friday) } ?? "اختر")
                    .font(chosen == nil ? PrayerHomeType.small : PrayerHomeType.smallBold)
                    .foregroundStyle(chosen == nil ? theme.secondaryInk : chosenColor(chosen!))
                    .padding(.horizontal, 14).frame(minHeight: 36)
                    .overlay { Capsule().stroke(chosen == nil ? theme.ink.opacity(0.14) : theme.line, lineWidth: 1) }
                    .frame(minHeight: 44).contentShape(.rect)
            }
            .accessibilityIdentifier("prayer-gap-status-\(ref.day)-\(ref.prayer.rawValue)")
        }
        .frame(minHeight: 48)
    }

    private var saveBar: some View {
        let count = choices.count
        return Button {
            save()
        } label: {
            Text(count == 0 ? "اختر حال صلاة لتحفظها" : "احفظ ما اخترت")
                .font(PrayerHomeType.strong).frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(count == 0 ? theme.secondaryInk : theme.background)
                .background(count == 0 ? theme.color("surface") : theme.ink, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain).disabled(count == 0)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(theme.background)
        .accessibilityIdentifier("prayer-gap-save")
    }

    // MARK: Choices

    private var dayOptions: [Choice] {
        [.init(status: .jamaah, fridayKind: nil), .init(status: .alone), .init(status: .missed), .init(status: .unrecordedHistory), .init(status: .excused)]
    }
    private func options(friday: Bool) -> [Choice] {
        guard friday else { return dayOptions }
        return [.init(status: .jamaah, fridayKind: .jumuah), .init(status: .jamaah, fridayKind: .dhuhr), .init(status: .alone, fridayKind: .dhuhr),
                .init(status: .missed, fridayKind: .jumuah), .init(status: .missed, fridayKind: .dhuhr), .init(status: .unrecordedHistory), .init(status: .excused)]
    }

    /// A whole-day or whole-gap choice; Friday noon gets the kind the choice implies, and
    /// «في جماعة» or «فاتتني» on a Friday is left for the user to pick explicitly (RP5).
    private func apply(_ choice: Choice, to refs: [PrayerReference], saveNow: Bool) {
        for ref in refs {
            guard fridayReferences.contains(ref) else { choices[ref] = Choice(status: choice.status); continue }
            switch choice.status {
            case .alone: choices[ref] = Choice(status: .alone, fridayKind: .dhuhr)
            case .unrecordedHistory, .excused: choices[ref] = Choice(status: choice.status)
            default: if saveNow { choices[ref] = nil }
            }
        }
        if saveNow { save() }
    }

    private func save() {
        let resolutions = references.compactMap { ref -> PrayerGapResolution? in
            guard let choice = choices[ref] else { return nil }
            return .init(reference: ref, status: choice.status, fridayKind: choice.fridayKind)
        }
        guard !resolutions.isEmpty else { return }
        resolve(resolutions); dismiss()
    }

    private func title(_ choice: Choice, friday: Bool) -> String {
        switch (choice.status, choice.fridayKind) {
        case (.jamaah, .jumuah?): "صلّيت الجمعة"
        case (.jamaah, .dhuhr?): "الظهر في جماعة"
        case (.alone, .dhuhr?) where friday: "الظهر وحدي"
        case (.missed, .jumuah?): "فاتتني الجمعة"
        case (.missed, .dhuhr?): "فاتني الظهر"
        case (.jamaah, _): "في جماعة"
        case (.alone, _): "وحدي"
        case (.missed, _): "فاتتني"
        case (.unrecordedHistory, _): "لم أسجّل"
        case (.excused, _): "لي عذر"
        default: choice.status.rawValue
        }
    }
    private func chosenColor(_ choice: Choice) -> Color {
        switch choice.status {
        case .missed: theme.color("missedTextOnSurface")
        case .unrecordedHistory, .excused: theme.secondaryInk
        default: theme.accent
        }
    }
}

private extension String {
    /// Day order of the five prayers by raw value.
    var order: Int { ["fajr", "dhuhr", "asr", "maghrib", "isha"].firstIndex(of: self) ?? 9 }
}


private struct PrayerStatisticsView: View {
    let session: AppSession
    let snapshot: PrayerSnapshot
    let select: (PrayerCell) -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var formatter: MadarNumberFormatter { .init(style: session.string("core.numerals") == "western" ? .western : .hindi) }
    private var month: HijriDate { hijri(snapshot.today.day) }
    private var monthDays: [GregorianDay] {
        let start = snapshot.today.day.adding(days: -(month.day - 1))
        return (0..<30).map { start.adding(days: $0) }.filter { let date = hijri($0); return date.month == month.month && date.year == month.year }
    }
    private var monthTitle: String {
        let names = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
        return names[month.month - 1] + " " + formatter.string(month.year)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("حالي").font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
                if snapshot.statistics.denominator >= 5 {
                    metrics
                    PrayerSummarySection(title: "الميزان") {
                        MadarCard {
                            VStack(spacing: 12) {
                                if typeSize.isAccessibilitySize {
                                    DisclosureGroup("آخر \(formatter.string(snapshot.statistics.last25.count)) فرضًا") {
                                        ForEach(snapshot.statistics.last25) { cell in
                                            Text(cellLabel(cell)).font(MadarTypography.caption())
                                                .accessibilityIdentifier("prayer-bead-list-\(cell.reference.naturalKey)")
                                        }
                                    }.accessibilityIdentifier("prayer-beads-list")
                                } else {
                                    ZStack {
                                        PrayerRecentBeads(cells: snapshot.statistics.last25, compact: false)
                                        Text(snapshot.statistics.percentage.map { formatter.percent($0) } ?? "—")
                                            .font(MadarTypography.title()).offset(y: 15)
                                    }
                                }
                                Text("\(formatter.string(snapshot.statistics.onTime)) في وقتها من \(formatter.string(snapshot.statistics.denominator)) فرضًا محسوبًا")
                                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                                Text("ميزان يُرى، لا سجلّ يُعَدّ").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            }
                        }
                    }
                } else {
                    Text("يظهر حالي بعد خمسة فروض مسجّلة؛ المعلّقة لا تدخل في النسبة.")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
                PrayerSummarySection(title: "سجلّ الشهر") {
                    MadarCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(monthTitle).font(MadarTypography.cardTitle()).accessibilityIdentifier("prayer-history-month")
                            Text("المس يومًا لتعدّل تسجيله").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            if typeSize.isAccessibilitySize {
                                ForEach(snapshot.history.filter { hijri($0.day).month == month.month && hijri($0.day).year == month.year }, id: \.day) { day in
                                    NavigationLink { dayView(day) } label: { Text(dateTitle(day.day)).font(MadarTypography.caption()).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }
                                        .accessibilityIdentifier("prayer-history-day-\(day.day)")
                                }
                            } else { calendarGrid }
                        }
                    }
                }
                if session.bool("salah.askHeart"), !snapshot.statistics.heartDistribution.isEmpty {
                    PrayerSummarySection(title: "حضور القلب") {
                        MadarCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("كل إجابة لحظة خاصة، بلا درجة أو ترتيب.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                                ForEach(PrayerHeart.allCases, id: \.self) { heart in
                                    if snapshot.statistics.heartDistribution[heart, default: 0] > 0 {
                                        Text(heartTitle(heart) + "، " + heartSentence(heart)).font(MadarTypography.section())
                                    }
                                }
                            }.accessibilityIdentifier("prayer-heart-reflection")
                        }
                    }
                }
                PrayerSummarySection(title: "التزامك بكل صلاة") {
                    MadarCard {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Prayer.allCases, id: \.self) { prayer in
                                let value = snapshot.statistics.commitment[prayer]
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(prayerTitle(prayer)).font(MadarTypography.section())
                                    Text("\(formatter.string(value?.jamaah ?? 0)) جماعة، \(formatter.string(value?.alone ?? 0)) وحدي")
                                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                                    if !typeSize.isAccessibilitySize, let value, value.denominator > 0 {
                                        GeometryReader { geometry in
                                            HStack(spacing: 0) {
                                                Rectangle().fill(theme.accent).frame(width: geometry.size.width * Double(value.jamaah) / Double(value.denominator))
                                                Rectangle().fill(theme.color("goldMid")).frame(width: geometry.size.width * Double(value.alone) / Double(value.denominator))
                                                Spacer(minLength: 0)
                                            }
                                        }.frame(height: 7).background(theme.line).clipShape(.capsule).accessibilityHidden(true)
                                    }
                                }
                            }
                        }
                    }
                }
            }.padding(18).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(theme.background).foregroundStyle(theme.ink)
            .navigationTitle("حالي").navigationBarTitleDisplayMode(.inline)
    }

    private var metrics: some View {
        VStack(spacing: 12) {
            if typeSize.isAccessibilitySize {
                metric("هذا الشهر الهجري", value: snapshot.statistics.percentage.map { formatter.percent($0) } ?? "—", id: "prayer-stat-percentage")
                metric("سلسلة الصلاة", value: formatter.string(snapshot.statistics.prayerStreak) + " أيام", id: "prayer-stat-streak")
                if session.bool("salah.showMosqueStreak") { metric("سلسلة المسجد", value: formatter.string(snapshot.statistics.mosqueStreak) + " أيام", id: "prayer-stat-mosque") }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    metric("هذا الشهر", value: snapshot.statistics.percentage.map { formatter.percent($0) } ?? "—", id: "prayer-stat-percentage")
                    metric("سلسلة الصلاة", value: formatter.string(snapshot.statistics.prayerStreak) + " أيام", id: "prayer-stat-streak")
                    if session.bool("salah.showMosqueStreak") { metric("سلسلة المسجد", value: formatter.string(snapshot.statistics.mosqueStreak) + " أيام", id: "prayer-stat-mosque") }
                }
            }
            Text("قُضيت \(formatter.string(snapshot.statistics.madeUp))، عليك \(formatter.string(snapshot.statistics.owed))")
                .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("prayer-stat-qada")
        }
    }
    private func metric(_ title: String, value: String, id: String) -> some View {
        MadarCard { VStack(spacing: 8) { Text(value).font(MadarTypography.cardTitle()).accessibilityIdentifier(id); Text(title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }.frame(maxWidth: .infinity) }
    }
    private var calendarGrid: some View {
        let firstWeekday = session.string("core.weekStart") == "monday" ? 2 : session.string("core.weekStart") == "sunday" ? 1 : 7
        let names = ["أح", "إث", "ثل", "أر", "خم", "جم", "سب"]
        let weekdays = (0..<7).map { names[(firstWeekday - 1 + $0) % 7] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = session.activePlace.timeZone
        let leading = ((calendar.component(.weekday, from: monthDays[0].date(in: calendar.timeZone)) - firstWeekday) + 7) % 7
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 12) {
            ForEach(weekdays, id: \.self) { Text($0).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
            ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 44).accessibilityHidden(true) }
            ForEach(monthDays, id: \.self) { day in
                if let summary = snapshot.history.first(where: { $0.day == day }) {
                    NavigationLink { dayView(summary) } label: {
                        VStack(spacing: 5) {
                            HStack(spacing: 2) { ForEach(summary.cells) { cell in Circle().fill(cell.status == .jamaah || cell.status == .alone ? theme.accent : .clear).overlay { Circle().stroke(cell.status == .missed ? theme.color("missed") : theme.line, lineWidth: 1) }.frame(width: 4, height: 4) } }.accessibilityHidden(true)
                            Text(formatter.string(hijri(day).day)).font(MadarTypography.caption())
                        }.frame(minHeight: 44)
                    }.accessibilityLabel(dateTitle(day)).accessibilityIdentifier("prayer-history-day-\(day)")
                } else { Text(formatter.string(hijri(day).day)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).frame(minHeight: 44) }
            }
        }
    }
    private func dayView(_ day: PrayerDaySummary) -> some View {
        List {
            Section { Text(dateTitle(day.day)).font(MadarTypography.section()) }
            ForEach(day.cells) { cell in
                if cell.canLog && cell.time != nil && cell.status != .future {
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
            .text(firstCalendar: session.string("core.firstCalendar") == "gregorian" ? .gregorian : .hijri, numerals: formatter.style)
    }
    private func cellLabel(_ cell: PrayerCell) -> String { dateTitle(cell.reference.day) + "، " + prayerTitle(cell.reference.prayer) + "، " + statusTitle(cell.status) }
}

private struct PrayerRecentBeads: View {
    let cells: [PrayerCell]
    let compact: Bool
    @Environment(\.roomTheme) private var theme
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(cells.enumerated()), id: \.element.reference) { index, cell in
                    let angle = Double(30 - index * 10) * .pi / 180
                    let radius = min(geometry.size.width * 0.42, geometry.size.height * 0.47)
                    Circle().fill(cell.status == .jamaah ? theme.accent : cell.status == .alone ? theme.color("goldMid") : .clear)
                        .overlay { Circle().stroke(cell.status == .missed ? theme.color("missed") : theme.line, style: StrokeStyle(lineWidth: 1, dash: [.pending, .unconfirmed].contains(cell.status) ? [2, 2] : [])) }
                        .frame(width: index == cells.count - 1 ? 12 : 9, height: index == cells.count - 1 ? 12 : 9)
                        .position(x: geometry.size.width / 2 + cos(angle) * radius, y: geometry.size.height * 0.51 + sin(angle) * radius)
                }
            }
        }.frame(height: compact ? 92 : 190).environment(\.layoutDirection, .leftToRight).accessibilityHidden(true)
    }
}

private func prayerTitle(_ prayer: Prayer) -> String {
    switch prayer { case .fajr: "الفجر"; case .dhuhr: "الظهر"; case .asr: "العصر"; case .maghrib: "المغرب"; case .isha: "العشاء" }
}
private func statusTitle(_ status: PrayerDisplayStatus) -> String {
    switch status { case .jamaah: "في جماعة"; case .alone: "وحدي"; case .qada: "قُضيت"; case .missed: "فاتتني"; case .pending: "لم تُسجَّل"; case .future: "لم يحن"; case .unconfirmed: "غير محسومة"; case .excused: "معذورة"; case .unrecordedHistory: "لم أسجّل" }
}

private struct PrayerSummarySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Rectangle().fill(theme.accent).frame(width: 6, height: 6).rotationEffect(.degrees(45)).accessibilityHidden(true)
                Text(title).font(MadarTypography.section()).accessibilityAddTraits(.isHeader)
                Rectangle().fill(theme.line).frame(height: 1).accessibilityHidden(true)
            }
            content()
        }
    }
}

private struct PrayerHeartAnswerSheet: View {
    let session: AppSession
    let cell: PrayerCell
    let finished: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var answer: PrayerHeart?
    init(session: AppSession, cell: PrayerCell, finished: @escaping () -> Void) {
        self.session = session; self.cell = cell; self.finished = finished; _answer = State(initialValue: cell.heart)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("كيف كان حضور قلبك في " + prayerTitle(cell.reference.prayer) + "؟").font(MadarTypography.section())
                    Text("سؤال اختياري للتأمّل، بلا درجة أو مقارنة.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    ForEach(PrayerHeart.allCases, id: \.self) { heart in
                        Button { answer = heart } label: {
                            HStack { VStack(alignment: .leading, spacing: 5) { Text(heartTitle(heart)); Text(heartSentence(heart)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }; Spacer(); if answer == heart { Image(systemName: "checkmark") } }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("prayer-heart-\(heart.rawValue)").accessibilityAddTraits(answer == heart ? [.isSelected] : [])
                    }
                }
                Section {
                    Button("احفظ الإجابة") { save(answer) }.buttonStyle(MadarPrimaryButton()).disabled(answer == nil).opacity(answer == nil ? 0.5 : 1)
                        .accessibilityIdentifier("prayer-heart-save")
                    Button("أمرّ") { save(nil) }.frame(minHeight: 44).accessibilityIdentifier("prayer-heart-skip")
                }
            }.navigationTitle("سؤال القلب").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { finished() } } }
                .disabled(session.prayerWriteInProgress)
        }
    }
    private func save(_ value: PrayerHeart?) {
        session.answerPrayerHeart(cell.reference, heart: value) { succeeded in if succeeded { finished() } }
    }
}
private func heartTitle(_ heart: PrayerHeart) -> String {
    switch heart { case .distracted: "شارد"; case .present: "حاضر"; case .khashi: "خاشع" }
}
private func heartSentence(_ heart: PrayerHeart) -> String {
    switch heart { case .distracted: "كنت في وادٍ آخر"; case .present: "عرفت ما أقول"; case .khashi: "وجدت لها أثرًا" }
}


private struct PrayerNightLoggingSheet: View {
    let session: AppSession
    let snapshot: PrayerSnapshot
    let finished: () -> Void
    @State private var selectedNight: GregorianDay
    @State private var rakaat: Int
    @State private var witr: Bool
    @State private var confirmRestore = false
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    init(session: AppSession, snapshot: PrayerSnapshot, finished: @escaping () -> Void) {
        self.session = session; self.snapshot = snapshot; self.finished = finished
        _selectedNight = State(initialValue: snapshot.nightDefault)
        let previous = snapshot.nights.first { $0.night == snapshot.nightDefault }
        _rakaat = State(initialValue: previous?.rakaat ?? 0); _witr = State(initialValue: previous?.witr ?? false)
    }
    private var formatter: MadarNumberFormatter { .init(style: session.string("core.numerals") == "western" ? .western : .hindi) }
    private var eligibleNights: [GregorianDay] { (0..<7).map { snapshot.nightDefault.adding(days: -$0) } }
    private var footprint: [GregorianDay] { (0..<30).reversed().map { snapshot.nightDefault.adding(days: -$0) } }
    private var restoreNeeded: Bool { (try? session.qiyamRequiresRestore(selectedNight)) ?? true }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("قيام الليل").font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
                    Text("لم تُسجّل ليلتك؟ سجّل ما قمتَه.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    MadarCard {
                        VStack(alignment: .leading, spacing: 18) {
                            Picker("الليلة", selection: $selectedNight) {
                                ForEach(eligibleNights, id: \.self) { Text(dateTitle($0)).tag($0) }
                            }.accessibilityIdentifier("prayer-qiyam-night")
                            Text("من العشاء إلى الفجر التالي؛ وبعد الفجر نختار آخر ليلة انقضت.")
                                .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            HStack(spacing: 16) {
                                Text("الركعات").font(MadarTypography.section())
                                Spacer()
                                Button { rakaat = max(0, rakaat - 2) } label: { Image(systemName: "minus").frame(width: 44, height: 44).contentShape(Circle()) }
                                    .accessibilityLabel(rakaat == 1 ? "أنقص ركعة" : "أنقص ركعتين").accessibilityIdentifier("prayer-qiyam-minus").disabled(rakaat == 0)
                                Text(formatter.string(rakaat)).font(MadarTypography.cardTitle()).monospacedDigit().accessibilityIdentifier("prayer-qiyam-count")
                                Button { rakaat = min(99, rakaat + 2) } label: { Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Circle()) }
                                    .accessibilityLabel(rakaat == 98 ? "زد ركعة" : "زد ركعتين").accessibilityIdentifier("prayer-qiyam-plus").disabled(rakaat >= 99)
                            }
                            Toggle("أوترتُ", isOn: $witr).font(MadarTypography.section()).accessibilityIdentifier("prayer-qiyam-witr")
                            if restoreNeeded {
                                Text("سبق التراجع عن تسجيل هذه الليلة. يمكنك إعادة تسجيلها صراحة.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                                Button("أعد تسجيل الليلة") { confirmRestore = true }.buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("prayer-qiyam-restore")
                            } else {
                                Button("احفظ قيام الليلة") { save(restoring: false) }.buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("prayer-qiyam-save")
                            }
                        }
                    }
                    PrayerSummarySection(title: "آخر ثلاثين ليلة") {
                        MadarCard {
                            VStack(alignment: .leading, spacing: 14) {
                                if !typeSize.isAccessibilitySize {
                                    HStack(spacing: 3) { ForEach(footprint, id: \.self) { night in
                                        RoundedRectangle(cornerRadius: 3).fill(hasRecord(night) ? theme.accent : theme.line).frame(maxWidth: .infinity).frame(height: 22)
                                    } }.accessibilityHidden(true)
                                }
                                Text("ليس سلسلة تنكسر، أثرٌ يُرى.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                                DisclosureGroup("سجلّ الليالي") {
                                    ForEach(footprint.reversed(), id: \.self) { night in
                                        Text(dateTitle(night) + (hasRecord(night) ? "، قيام مسجّل" : "، بلا تسجيل"))
                                            .font(MadarTypography.caption()).fixedSize(horizontal: false, vertical: true)
                                    }
                                }.accessibilityIdentifier("prayer-qiyam-footprint-list")
                            }
                        }
                    }
                }.padding(18).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.background(theme.background).foregroundStyle(theme.ink)
                .navigationTitle("قيام الليل").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { finished() } } }
                .disabled(session.prayerWriteInProgress)
                .confirmationDialog("أعد تسجيل هذه الليلة؟", isPresented: $confirmRestore, titleVisibility: .visible) {
                    Button("أعد التسجيل") { save(restoring: true) }
                } message: { Text("يعود تسجيل الركعات والوتر لهذه الليلة؛ يبقى أثر التراجع محفوظًا.") }
                .onChange(of: selectedNight) { _, night in
                    let previous = snapshot.nights.first { $0.night == night }
                    rakaat = previous?.rakaat ?? 0; witr = previous?.witr ?? false
                }
        }
    }
    private func save(restoring: Bool) {
        session.recordQiyamNight(selectedNight, rakaat: rakaat, witr: witr, restoreDeleted: restoring) { succeeded in if succeeded { finished() } }
    }
    private func hasRecord(_ night: GregorianDay) -> Bool { snapshot.nights.contains { $0.night == night && ($0.rakaat > 0 || $0.witr) } }
    private func dateTitle(_ night: GregorianDay) -> String {
        DualDate(instant: night.date(in: session.activePlace.timeZone).addingTimeInterval(12 * 3600), timeZone: session.activePlace.timeZone,
            source: HijriSource(rawValue: session.string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(session.number("core.hijriOffset")))
            .text(firstCalendar: session.string("core.firstCalendar") == "gregorian" ? .gregorian : .hijri, numerals: formatter.style)
    }
}

private struct PrayerOldMissedSheet: View {
    @Bindable var session: AppSession
    let trackingStart: GregorianDay
    let finished: () -> Void
    @State private var date: Date
    @State private var prayer: Prayer = .fajr
    @State private var fridayKind: FridayPrayerKind? = nil
    @State private var confirmRestore = false
    init(session: AppSession, trackingStart: GregorianDay, finished: @escaping () -> Void) {
        self.session = session; self.trackingStart = trackingStart; self.finished = finished
        _date = State(initialValue: trackingStart.adding(days: -1).date(in: session.activePlace.timeZone).addingTimeInterval(12 * 3600))
    }
    private var reference: PrayerReference { .init(day: GregorianDay.containing(date, in: session.activePlace.timeZone), prayer: prayer) }
    private var fridayNoon: Bool { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = session.activePlace.timeZone; return prayer == .dhuhr && calendar.component(.weekday, from: date) == 6 }
    private var restoring: Bool { (try? session.oldMissedRequiresRestore(reference)) ?? true }
    private var calendar: Calendar { var c = Calendar(identifier: session.string("core.firstCalendar") == "gregorian" ? .gregorian : .islamicUmmAlQura); c.timeZone = session.activePlace.timeZone; return c }
    private var sightingOffset: Int {
        session.string("core.firstCalendar") != "gregorian" && session.string("core.hijriSource") == "sighting" ? Int(session.number("core.hijriOffset")) : 0
    }
    private func shifted(_ value: Date, by days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: value) ?? value }
    private var pickerDate: Binding<Date> { Binding(get: { shifted(date, by: sightingOffset) }, set: { date = shifted($0, by: -sightingOffset) }) }
    private var maximumDate: Date { shifted(trackingStart.date(in: session.activePlace.timeZone).addingTimeInterval(-1), by: sightingOffset) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("الفوائت القديمة لا تُضاف إلا باختيارك؛ ما قبل بداية التتبّع يبقى بلا تسجيل.")
                    DatePicker("التاريخ", selection: pickerDate, in: ...maximumDate, displayedComponents: .date)
                        .environment(\.calendar, calendar).environment(\.timeZone, session.activePlace.timeZone)
                        .accessibilityIdentifier("prayer-old-date")
                    Picker("الصلاة", selection: $prayer) {
                        ForEach(Prayer.allCases, id: \.self) { Text(title($0)).tag($0) }
                    }.accessibilityIdentifier("prayer-old-prayer")
                    if fridayNoon {
                        Picker("فرض ظهر الجمعة", selection: $fridayKind) {
                            Text("اختر النوع").tag(Optional<FridayPrayerKind>.none)
                            Text("الجمعة").tag(Optional(FridayPrayerKind.jumuah))
                            Text("الظهر").tag(Optional(FridayPrayerKind.dhuhr))
                        }.accessibilityIdentifier("prayer-old-friday")
                    }
                }
                Section {
                    if restoring {
                        Text("سبق حذف هذا التسجيل أو التراجع عنه؛ إعادته تحتاج اختيارًا صريحًا.")
                        Button("أعد تسجيل الفائتة") { confirmRestore = true }.accessibilityIdentifier("prayer-old-restore")
                    } else {
                        Button("أضف الفائتة") { save(false) }.accessibilityIdentifier("prayer-old-save")
                    }
                }.disabled(session.prayerWriteInProgress || (fridayNoon && fridayKind == nil))
            }
            .navigationTitle("فائتة قديمة").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { finished() } } }
            .confirmationDialog("أعد تسجيل هذه الفائتة؟", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("أعد التسجيل") { save(true) }
            }
            .onChange(of: date) { _, _ in fridayKind = nil }
            .onChange(of: prayer) { _, _ in fridayKind = nil }
        }
    }
    private func save(_ restore: Bool) { session.addOldMissedPrayer(reference, fridayKind: fridayNoon ? fridayKind : nil, restoreDeleted: restore) { success in if success { finished() } } }
    private func title(_ prayer: Prayer) -> String { switch prayer { case .fajr: "الفجر"; case .dhuhr: "الظهر"; case .asr: "العصر"; case .maghrib: "المغرب"; case .isha: "العشاء" } }
}
