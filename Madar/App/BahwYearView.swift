import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarDesign

/// «ما يهمّك» item: a season or year landmark (read model, never a row) or a user day (UpcomingDay rule, B03).
struct BahwMatter: Identifiable, Equatable {
    enum Kind: Equatable { case season, year, mine }
    let id: String
    let title: String
    let kind: Kind
    let day: GregorianDay
    let daysLeft: Int
    let closed: Double
    let hijri: Bool
    let tone: String
    let rowID: UUID?
    /// Whole days since a passed one-time day that keeps counting (`countUpAfter`).
    var elapsedDays: Int? = nil
    var count: Int { elapsedDays ?? daysLeft }
}
/// The day strip: from the `core.dayStart` boundary to the next one, with the prayers as segment marks.
struct BahwDayModel: Equatable {
    let share: Double
    let marks: [Double]
    let next: String
}

extension AppBahwService {
    static let hijriMonths = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
    static let hijriShort = ["محرم", "صفر", "ربيع ١", "ربيع ٢", "جمادى ١", "جمادى ٢", "رجب", "شعبان", "رمضان", "شوال", "القعدة", "الحجة"]
    static let gregorianMonths = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]

    var weekStart: MadarWeekStart { MadarWeekStart(rawValue: session.string("core.weekStart")) ?? .saturday }

    /// Seasons, the Hijri new year, the Gregorian year end and the user's days, nearest first.
    func matters() -> [BahwMatter] {
        let days = calendarDays, day = today
        var items: [BahwMatter] = []
        if let rows = try? ModelContext(session.container).fetch(FetchDescriptor<UpcomingDay>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil })) {
            for row in rows {
                let rule = MadarUpcomingRule(calendar: row.calendar == "hijri" ? .hijri : .gregorian, year: row.year, month: row.month, day: row.day,
                                             repeats: MadarUpcomingRule.Repeats(rawValue: row.repeats) ?? .yearly, countFrom: try? GregorianDay(row.countFromDayKey), countUpAfter: row.countUpAfter)
                if let counter = rule.counter(today: day, days) {
                    items.append(.init(id: row.id.uuidString, title: row.title, kind: .mine, day: counter.occurrence, daysLeft: counter.daysLeft, closed: counter.closed, hijri: rule.calendar == .hijri, tone: "sepia", rowID: row.id, elapsedDays: counter.elapsedDays))
                }
            }
        }
        let seasons: [(String, Int, Int, String)] = [("رمضان", 9, 1, "amber"), ("عيد الفطر", 10, 1, "amber"), ("يوم عرفة", 12, 9, "green"), ("عيد الأضحى", 12, 10, "green"), ("رأس السنة", 1, 1, "amber")]
        for (title, month, date, tone) in seasons {
            let rule = MadarUpcomingRule(calendar: .hijri, month: month, day: date, repeats: .yearly)
            guard let ring = rule.ring(today: day, days), !items.contains(where: { $0.title == title && $0.day == ring.next }) else { continue }
            let name = month == 1 ? title + " " + digits.string(days.hijri(ring.next).year) : title
            items.append(.init(id: "season-\(month)-\(date)", title: name, kind: .season, day: ring.next, daysLeft: ring.daysLeft, closed: ring.closed, hijri: true, tone: tone, rowID: nil))
        }
        let end = MadarUpcomingRule(calendar: .gregorian, month: 12, day: 31, repeats: .yearly)
        if let ring = end.ring(today: day, days) {
            items.append(.init(id: "year-end", title: "نهاية " + digits.string(ring.next.year) + "م", kind: .year, day: ring.next, daysLeft: ring.daysLeft, closed: ring.closed, hijri: false, tone: "gregorianInk", rowID: nil))
        }
        return items.sorted { Self.nearestFirst(($0.elapsedDays, $0.daysLeft, $0.title), ($1.elapsedDays, $1.daysLeft, $1.title)) }
    }
    func dayModel() -> BahwDayModel? {
        let place = session.activePlace, boundary = DayBoundary(rawValue: session.string("core.dayStart")) ?? .fajr
        guard let todays = PrayerTimesEngine.calculate(day: today, place: place), let tomorrow = PrayerTimesEngine.calculate(day: today.adding(days: 1), place: place) else { return nil }
        let start: Date, end: Date
        switch boundary {
        case .fajr: start = todays.fajr; end = tomorrow.fajr
        case .maghrib: start = todays.maghrib; end = tomorrow.maghrib
        case .midnight: start = today.date(in: place.timeZone); end = today.adding(days: 1).date(in: place.timeZone)
        }
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return nil }
        let names: [(String, Date)] = [("الفجر", todays.fajr), ("الظهر", todays.dhuhr), ("العصر", todays.asr), ("المغرب", todays.maghrib), ("العشاء", todays.isha), ("الفجر", tomorrow.fajr), ("الظهر", tomorrow.dhuhr)]
        let marks = names.map { $0.1.timeIntervalSince(start) / length }.filter { $0 > 0.001 && $0 < 0.999 }
        let ahead = names.filter { $0.1 > now }.prefix(2).map { $0.0 + " " + PrayerCopy.after(seconds: $0.1.timeIntervalSince(now), digits: digits) }
        return .init(share: min(1, max(0, now.timeIntervalSince(start) / length)), marks: marks, next: ahead.joined(separator: "، و"))
    }
    func approx(_ days: Int) -> String? {
        guard days >= 14 else { return nil }
        if days < 60 {
            let w = Int((Double(days) / 7).rounded())
            return "نحو " + (w == 2 ? "أسبوعين" : digits.string(w) + " أسابيع")
        }
        let m = Int((Double(days) / 30.4).rounded())
        return "نحو " + (m == 2 ? "شهرين" : m <= 10 ? digits.string(m) + " أشهر" : digits.string(m) + " شهرًا")
    }
    func weekday(_ day: GregorianDay) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ar"); f.timeZone = .gmt; f.dateFormat = "EEEE"
        return f.string(from: day.date(in: .gmt).addingTimeInterval(12 * 3600))
    }
}

/// M4-V03 · `bahw/04-W3-Sana.jpg`: how much of the year has passed, and the days that matter. Only the strip view
/// ships in v1 (`bahw.yearView` alternatives are v2), so no view switcher is shown.
struct BahwYearView: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var hijriHero: Bool?
    @State private var filter = 0
    @State private var editing: BahwDayDraft?
    private var lobby: RoomTheme { RoomTheme(room: "bahw", dark: session.string("core.theme") == "dark") }
    private var service: AppBahwService { .init(session: session) }
    private var digits: MadarNumberFormatter { service.digits }
    private var which: String { session.string("bahw.yearWhich") }
    private var hijri: Bool { which == "hijri" ? true : which == "gregorian" ? false : hijriHero ?? (session.string("core.firstCalendar") != "gregorian") }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            VStack(spacing: 0) {
                topBar.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        hero
                        strips
                        matters
                    }.padding(.horizontal, 18).padding(.bottom, 28).frame(maxWidth: 620).frame(maxWidth: .infinity)
                }
            }
        }
        .background(lobby.background.ignoresSafeArea()).foregroundStyle(lobby.ink)
        .environment(\.roomTheme, lobby)
        .toolbarVisibility(.hidden, for: .navigationBar).toolbarVisibility(.hidden, for: .tabBar).hidesRoomAccessory(session, id: "bahw-year")
        .sheet(item: $editing) { draft in BahwDaySheet(session: session, draft: draft).presentationDetents([.large]) }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Label("البهو", systemImage: "chevron.backward").labelStyle(.titleAndIcon).font(MadarTypography.section()).lineLimit(1).fixedSize().padding(.horizontal, 16).frame(minHeight: 48)
                    .overlay { Capsule().stroke(lobby.line) }
            }.buttonStyle(.plain).accessibilityIdentifier("bahw-year-back")
            Spacer()
            if which == "both" {
                HStack(spacing: 2) {
                    segment("هجرية", on: hijri) { hijriHero = true }.accessibilityIdentifier("bahw-year-hijri-toggle")
                    segment("ميلادية", on: !hijri) { hijriHero = false }.accessibilityIdentifier("bahw-year-gregorian-toggle")
                }.padding(4).background(lobby.line, in: .capsule)
            }
            Spacer()
            Color.clear.frame(width: 96, height: 1)
        }
    }
    private func segment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy) { action() } }) {
            Text(title).font(MadarTypography.section()).lineLimit(1).fixedSize().padding(.horizontal, 18).frame(minHeight: 40)
                .background(on ? lobby.surface : .clear, in: .capsule).foregroundStyle(on ? lobby.ink : lobby.secondaryInk)
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: hero
    private var hero: some View {
        let model = service.year(), period = hijri ? model.hijri : model.gregorian, other = hijri ? model.gregorian : model.hijri
        let yearName = hijri ? digits.string(model.hijriYear) + "هـ" : digits.string(model.gregorianYear) + "م"
        let otherName = hijri ? digits.string(model.gregorianYear) + "م" : digits.string(model.hijriYear) + "هـ"
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("مضى من " + yearName).font(MadarTypography.body()).foregroundStyle(lobby.secondaryInk)
                Text(percent(period)).font(.custom("thmanyahserifdisplay-Bold", size: 84, relativeTo: .largeTitle)).foregroundStyle(lobby.color(hijri ? "sepia" : "gregorianInk"))
                    .lineLimit(1).minimumScaleFactor(0.5).accessibilityIdentifier("bahw-year-percent")
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 6) {
                Text("بقي " + digits.string(period.remaining) + " " + service.dayCount(period.remaining)).font(MadarTypography.title())
                if let ramadan = model.ramadanIn { Text("رمضان بعد " + digits.string(ramadan) + " " + service.dayCount(ramadan)).font(MadarTypography.body()).foregroundStyle(lobby.secondaryInk) }
                if which == "both" { Text("وفي " + otherName + " مضى " + percent(other)).font(MadarTypography.body()).foregroundStyle(lobby.secondaryInk) }
            }.padding(.top, 26)
        }.accessibilityElement(children: .combine).accessibilityIdentifier("bahw-year-hero")
    }

    // MARK: strips
    private var strips: some View {
        let model = service.year(), period = hijri ? model.hijri : model.gregorian
        let days = service.calendarDays, today = service.today
        let month = hijri ? MadarYear.hijriMonth(today, days) : MadarYear.gregorianMonth(today)
        let monthIndex = hijri ? model.hijriMonthIndex : model.gregorianMonthIndex
        let names = hijri ? AppBahwService.hijriMonths : AppBahwService.gregorianMonths
        let week = MadarYear.week(today, start: service.weekStart)
        let boundary = session.string("core.dayStart")
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("السنة " + (hijri ? digits.string(model.hijriYear) + "هـ" : digits.string(model.gregorianYear) + "م")).font(MadarTypography.section())
                    Spacer()
                    Text("مضى " + percent(period) + "، بقي " + digits.string(period.remaining) + " " + service.dayCount(period.remaining)).font(MadarTypography.caption()).foregroundStyle(lobby.secondaryInk)
                }
                yearStrip(period: period, month: monthIndex, landmarks: model.landmarks)
            }.accessibilityElement(children: .combine).accessibilityIdentifier("bahw-year-strip")
            let nextMonth = names[(monthIndex + 1) % 12]
            row("الشهر", detail: names[monthIndex], share: Double(month.elapsed) / Double(max(1, month.length)), segments: 1, tone: "sepia",
                caption: "بقي " + digits.string(month.remaining) + " " + service.dayCount(month.remaining) + "، و" + nextMonth + " بعد " + digits.string(month.remaining) + " " + service.dayCount(month.remaining), id: "month")
            row("الأسبوع", detail: (service.weekStart == .saturday ? "الجمعة" : "السبت") + " آخره", share: Double(week.elapsed) / 7, segments: 7, tone: "green",
                caption: week.remaining == 1 ? "آخر يوم في الأسبوع، وأسبوع جديد غدًا" : "بقي " + digits.string(week.remaining) + " " + service.dayCount(week.remaining) + " من الأسبوع", id: "week")
            if let day = service.dayModel() {
                row("اليوم", detail: boundary == "midnight" ? "من منتصف الليل" : boundary == "maghrib" ? "من المغرب" : "من الفجر", share: day.share, marks: day.marks, tone: "clay", caption: day.next, id: "day")
            }
        }
        .padding(18).background(lobby.surface, in: .rect(cornerRadius: 26)).overlay { RoundedRectangle(cornerRadius: 26).stroke(lobby.line) }
    }
    /// Twelve month cells (passed months filled) under the season marks of this year.
    private func yearStrip(period: MadarPeriod, month: Int, landmarks: [MadarLandmark]) -> some View {
        let fill = lobby.color(hijri ? "amber" : "lapis")
        let marks = landmarks.filter { [.ramadan, .eidAlFitr, .arafah].contains($0.name) && $0.daysLeft < period.remaining }
            .map { (mark: $0, at: Double(MadarCalendarDays.distance(from: period.start, to: $0.day)) / Double(max(1, period.length))) }
        let shorts = hijri ? AppBahwService.hijriShort : AppBahwService.gregorianMonths
        return VStack(spacing: 6) {
            GeometryReader { geometry in
                ForEach(Array(marks.enumerated()), id: \.offset) { index, item in
                    let x = geometry.size.width * item.at, tone = item.mark.name == .arafah ? "green" : "amber"
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(markTitle(item.mark.name) + " " + digits.string(item.mark.daysLeft)).font(MadarTypography.caption().bold())
                            .foregroundStyle(item.mark.name == .arafah ? lobby.ink : lobby.color("amberText")).fixedSize()
                        Capsule().fill(lobby.color(tone)).frame(width: 2, height: CGFloat(52 - (index % 2) * 18))
                    }
                    .alignmentGuide(.leading) { d in d[.trailing] }
                    .position(x: x, y: geometry.size.height - CGFloat(52 - (index % 2) * 18) / 2 - (index % 2 == 0 ? 10 : 0))
                }
            }.frame(height: 70).environment(\.layoutDirection, .rightToLeft)
            HStack(spacing: 4) {
                ForEach(0..<12, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 5).fill(index <= month ? fill : lobby.line.opacity(0.8)).frame(height: 32)
                }
            }.padding(.top, -30)
            HStack(spacing: 4) {
                ForEach(0..<12, id: \.self) { index in
                    Text(shorts[index]).font(.custom(index == month ? "thmanyahsans-Bold" : "thmanyahsans-Regular", size: 11, relativeTo: .caption2))
                        .foregroundStyle(index == month ? lobby.ink : lobby.secondaryInk).lineLimit(1).frame(maxWidth: .infinity)
                }
            }
        }
    }
    private func row(_ title: String, detail: String, share: Double, segments: Int = 1, marks: [Double] = [], tone: String, caption: String, id: String) -> some View {
        let cuts = segments > 1 ? (1..<segments).map { Double($0) / Double(segments) } : marks
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(MadarTypography.section())
                Text(detail).font(MadarTypography.caption()).foregroundStyle(lobby.secondaryInk)
                Spacer()
                Text(digits.string(Int(share * 100)) + "٪\u{061C}").font(.custom("thmanyahserifdisplay-Bold", size: 20, relativeTo: .title3)).foregroundStyle(lobby.ink)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(lobby.line)
                    Capsule().fill(lobby.color(tone)).frame(width: max(12, geometry.size.width * share))
                    ForEach(Array(cuts.enumerated()), id: \.offset) { _, cut in
                        Rectangle().fill(lobby.surface).frame(width: 2.5).offset(x: geometry.size.width * cut - 1.25)
                    }
                }
            }.frame(height: 12).environment(\.layoutDirection, .rightToLeft)
            Text(caption).font(MadarTypography.caption()).foregroundStyle(lobby.secondaryInk)
        }.accessibilityElement(children: .combine).accessibilityIdentifier("bahw-strip-" + id)
    }

    // MARK: what matters
    private var matters: some View {
        let all = service.matters()
        let shown = all.filter { filter == 0 || (filter == 1 ? $0.kind != .mine : $0.kind == .mine) }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("ما يهمّك").font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
                Text(digits.string(all.count) + " " + service.dayCount(all.count) + "، الأقرب أولًا").font(MadarTypography.caption()).foregroundStyle(lobby.secondaryInk)
                Spacer()
                Button { editing = .init(service: service) } label: {
                    Label("يوم يهمّك", systemImage: "plus").font(MadarTypography.section()).lineLimit(1).fixedSize().padding(.horizontal, 16).frame(minHeight: 46).overlay { Capsule().stroke(lobby.line) }
                }.buttonStyle(.plain).accessibilityIdentifier("bahw-add-day")
            }.padding(.top, 10)
            Picker("التصفية", selection: $filter) { Text("الكل").tag(0); Text("المواسم").tag(1); Text("أيامي").tag(2) }
                .pickerStyle(.segmented).accessibilityIdentifier("bahw-matters-filter")
            VStack(spacing: 0) {
                if shown.isEmpty {
                    Text(filter == 2 ? "لم تضف يومًا بعد. أضف يومًا يهمّك ليظهر هنا." : "لا شيء هنا الآن.").font(MadarTypography.body()).foregroundStyle(lobby.secondaryInk).padding(22).frame(maxWidth: .infinity)
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Rectangle().fill(lobby.line).frame(height: 1) }
                    matterRow(item)
                }
            }.background(lobby.surface, in: .rect(cornerRadius: 26)).overlay { RoundedRectangle(cornerRadius: 26).stroke(lobby.line) }
        }
    }
    @ViewBuilder private func matterRow(_ item: BahwMatter) -> some View {
        let content = HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 0) {
                Text(digits.string(item.count)).font(.custom("thmanyahserifdisplay-Bold", size: 38, relativeTo: .largeTitle)).foregroundStyle(lobby.color(item.tone)).lineLimit(1).minimumScaleFactor(0.6)
                Text(item.elapsedDays.map(service.sinceCount) ?? (item.daysLeft == 0 ? "اليوم" : service.dayCount(item.daysLeft))).font(MadarTypography.caption()).foregroundStyle(lobby.secondaryInk)
            }.frame(width: 70)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "seal.fill").font(.system(size: 10)).foregroundStyle(lobby.color(item.tone)).accessibilityHidden(true)
                    Text(item.title).font(MadarTypography.section()).lineLimit(1)
                }
                MadarDateLabel(session.dateLabels(item.day)).foregroundStyle(lobby.secondaryInk)
                if let approximation = service.approx(item.count) { Text((item.elapsedDays == nil ? "" : "مضى ") + approximation).font(MadarTypography.fine()).foregroundStyle(lobby.secondaryInk) }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(lobby.line).frame(height: 5)
                        Capsule().fill(lobby.color(item.tone)).frame(width: geometry.size.width * item.closed, height: 5)
                        Circle().fill(lobby.surface).frame(width: 13, height: 13).overlay { Circle().stroke(lobby.color(item.tone), lineWidth: 2.5) }
                            .offset(x: geometry.size.width * item.closed - 6.5)
                    }.frame(maxHeight: .infinity)
                }.frame(height: 14).environment(\.layoutDirection, .rightToLeft).accessibilityHidden(true)
            }
            Text(service.weekday(item.day)).font(MadarTypography.caption()).foregroundStyle(lobby.secondaryInk).frame(width: 56, alignment: .trailing)
        }.padding(.horizontal, 16).padding(.vertical, 14).contentShape(.rect)
        if let id = item.rowID {
            Button { editing = .init(service: service, matter: item, id: id) } label: { content }.buttonStyle(.plain)
                .accessibilityElement(children: .combine).accessibilityHint("لتعديل اليوم أو حذفه").accessibilityIdentifier("bahw-matter-" + item.title)
        } else {
            content.accessibilityElement(children: .combine).accessibilityIdentifier("bahw-matter-" + item.title)
        }
    }

    /// The Arabic letter mark keeps «٪» on the left of the digits, as in the design.
    private func percent(_ period: MadarPeriod) -> String { digits.string(period.basisPoints / 100) + "٪\u{061C}" }
    private func markTitle(_ name: MadarLandmark.Name) -> String {
        switch name { case .ramadan: "رمضان"; case .eidAlFitr: "عيد الفطر"; case .arafah: "عرفة"; case .hijriNewYear: "رأس السنة"; case .gregorianYearEnd: "نهاية السنة" }
    }
}

/// The add/edit form for a user day. Values are kept as the rule (calendar, month, day, repeat); occurrences are derived.
struct BahwDayDraft: Identifiable {
    let id: UUID
    var existing: Bool
    var title = ""
    var hijri = true
    var month = 1
    var day = 1
    var repeats = "yearly"
    var year: Int
    var countFrom: String?
    var countUpAfter = false
    @MainActor init(service: AppBahwService) {
        id = UUID(); existing = false
        let today = service.today
        hijri = service.session.string("core.firstCalendar") != "gregorian"
        let h = service.calendarDays.hijri(today)
        month = hijri ? h.month : today.month; day = hijri ? h.day : today.day; year = hijri ? h.year : today.year
    }
    @MainActor init(service: AppBahwService, matter: BahwMatter, id: UUID) {
        self.id = id; existing = true; title = matter.title
        let row = try? ModelContext(service.session.container).fetch(FetchDescriptor<UpcomingDay>()).first { $0.id == id }
        hijri = row?.calendar == "hijri"; month = row?.month ?? 1; day = row?.day ?? 1; repeats = row?.repeats ?? "yearly"
        countFrom = row?.countFromDayKey; countUpAfter = row?.countUpAfter ?? false
        year = row?.year ?? (hijri ? service.calendarDays.hijri(service.today).year : service.today.year)
    }
}

struct BahwDaySheet: View {
    @Bindable var session: AppSession
    @State var draft: BahwDayDraft
    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?
    private var lobby: RoomTheme { RoomTheme(room: "bahw", dark: session.string("core.theme") == "dark") }
    private var digits: MadarNumberFormatter { .init(style: session.string("core.numerals") == "western" ? .western : .hindi) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("الاسم") {
                        TextField("مثل: ذكرى زواجنا", text: $draft.title).font(MadarTypography.body()).padding(14)
                            .background(lobby.surface, in: .rect(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).stroke(lobby.line) }.accessibilityIdentifier("bahw-day-title")
                    }
                    field("التقويم") {
                        Picker("التقويم", selection: $draft.hijri) { Text("هجري").tag(true); Text("ميلادي").tag(false) }.pickerStyle(.segmented)
                            .onChange(of: draft.hijri) { _, hijri in if hijri { draft.day = min(draft.day, 30) } }
                    }
                    field("يتكرر") {
                        Picker("يتكرر", selection: $draft.repeats) { Text("كل سنة").tag("yearly"); Text("كل شهر").tag("monthly"); Text("مرة واحدة").tag("none") }.pickerStyle(.segmented)
                            .accessibilityIdentifier("bahw-day-repeats")
                    }
                    HStack(spacing: 12) {
                        field("اليوم") {
                            Picker("اليوم", selection: $draft.day) { ForEach(1...(draft.hijri ? 30 : 31), id: \.self) { Text(digits.string($0)).tag($0) } }.pickerStyle(.menu).accessibilityIdentifier("bahw-day-day")
                        }
                        if draft.repeats != "monthly" {
                            field("الشهر") {
                                Picker("الشهر", selection: $draft.month) {
                                    ForEach(1...12, id: \.self) { Text((draft.hijri ? AppBahwService.hijriMonths : AppBahwService.gregorianMonths)[$0 - 1]).tag($0) }
                                }.pickerStyle(.menu).accessibilityIdentifier("bahw-day-month")
                            }
                        }
                        if draft.repeats == "none" {
                            field("السنة") {
                                Stepper(digits.string(draft.year) + (draft.hijri ? "هـ" : "م"), value: $draft.year, in: (draft.hijri ? 1400...1500 : 1980...2080)).font(MadarTypography.body()).accessibilityIdentifier("bahw-day-year")
                            }
                        }
                    }
                    if draft.repeats == "none" {
                        // Owner, 25 Oct: a one-time day may keep counting the days since it.
                        Toggle(isOn: $draft.countUpAfter) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("واصل العدّ بعد الموعد").font(MadarTypography.body())
                                Text(draft.countUpAfter ? "يبقى بعد يومه ويعدّ: مضى كذا يومًا" : "يختفي بعد يومه").font(MadarTypography.caption()).foregroundStyle(lobby.secondaryInk)
                            }
                        }.padding(14).background(lobby.surface, in: .rect(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).stroke(lobby.line) }
                            .accessibilityIdentifier("bahw-day-count-up")
                    }
                    if let next = previewOccurrence { MadarDateLabel(session.dateLabels(next)).accessibilityIdentifier("bahw-day-date-preview") }
                    Text("يُحسب الموعد من القاعدة كل مرة، وإن لم يكن في الشهر هذا اليوم فآخر يوم فيه.").font(MadarTypography.caption()).foregroundStyle(lobby.secondaryInk)
                    if let failure { Text(failure).font(MadarTypography.caption()).foregroundStyle(lobby.ink) }
                    Button { save() } label: {
                        Text("احفظ").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(lobby.onAccent).background(lobby.accentFill, in: .capsule)
                    }.buttonStyle(.plain).disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("bahw-day-save")
                    if draft.existing {
                        Button(role: .destructive) { remove() } label: { Text("احذف اليوم").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 46) }
                            .buttonStyle(.plain).accessibilityIdentifier("bahw-day-delete")
                    }
                }.padding(18)
            }
            .background(lobby.background).foregroundStyle(lobby.ink)
            .navigationTitle(draft.existing ? "عدّل اليوم" : "يوم يهمّك").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
        }.tint(lobby.accent)
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(MadarTypography.caption()).foregroundStyle(lobby.secondaryInk); content() }
    }
    private var previewOccurrence: GregorianDay? {
        let service = AppBahwService(session: session)
        let rule = MadarUpcomingRule(calendar: draft.hijri ? .hijri : .gregorian, year: draft.year, month: draft.month, day: draft.day,
                                     repeats: MadarUpcomingRule.Repeats(rawValue: draft.repeats) ?? .yearly, countUpAfter: draft.repeats == "none" && draft.countUpAfter)
        return rule.counter(today: service.today, service.calendarDays)?.occurrence
    }
    private func save() {
        let today = AppBahwService(session: session).today
        var payload: [String: MadarCore.JSONValue] = ["id": .string(draft.id.uuidString), "title": .string(draft.title), "calendar": .string(draft.hijri ? "hijri" : "greg"),
                                            "month": .number(Double(draft.month)), "day": .number(Double(draft.day)), "repeats": .string(draft.repeats), "countFromDayKey": .string(draft.countFrom.flatMap { $0.isEmpty ? nil : $0 } ?? today.description)]
        if draft.repeats == "none" { payload["year"] = .number(Double(draft.year)); payload["countUpAfter"] = .bool(draft.countUpAfter) }
        Task {
            do { try await session.executeDiaryCommand("bahw.saveUpcomingDay", payload: payload); dismiss() }
            catch { failure = "لم يُحفظ اليوم. " + error.localizedDescription }
        }
    }
    private func remove() {
        Task {
            do { try await session.executeDiaryCommand("bahw.deleteUpcomingDay", payload: ["id": .string(draft.id.uuidString)]); dismiss() }
            catch { failure = "لم يُحذف اليوم. " + error.localizedDescription }
        }
    }
}
