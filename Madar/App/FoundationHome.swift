import SwiftUI
import MadarCore
import MadarDesign

struct FoundationPrayerTimeRow: Identifiable, Equatable {
    let prayer: Prayer
    let title: String
    let clock: String
    var id: Prayer { prayer }
    var accessibilityLabel: String { "\(title)، \(clock)" }
}

/// A read-only presentation of the active place's civil day; stored room day keys are untouched.
struct FoundationPrayerTimesPresentation {
    let day: GregorianDay
    let prayerDay: PrayerDay?
    let rows: [FoundationPrayerTimeRow]

    init(instant: Date, place: ActivePlace, options: PrayerCalculationOptions = .init(), numerals: NumeralStyle = .hindi) {
        day = GregorianDay.containing(instant, in: place.timeZone)
        let calculated = PrayerTimesEngine.calculate(day: day, place: place, options: options)
        prayerDay = calculated
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        let formatter = MadarNumberFormatter(style: numerals)
        rows = calculated.map { times in
            Prayer.allCases.map { prayer in
                let title = switch prayer { case .fajr: "الفجر"; case .dhuhr: "الظهر"; case .asr: "العصر"; case .maghrib: "المغرب"; case .isha: "العشاء" }
                let components = calendar.dateComponents([.hour, .minute], from: times.time(for: prayer))
                let clock = String(format: "%02d:%02d", locale: Locale(identifier: "en_US_POSIX"), components.hour ?? 0, components.minute ?? 0)
                return FoundationPrayerTimeRow(prayer: prayer, title: title, clock: formatter.localized(clock))
            }
        } ?? []
    }
}

private struct FoundationPrayerTimesCard: View {
    let rows: [FoundationPrayerTimeRow]
    let cityName: String
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        MadarCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("مواقيت اليوم").font(MadarTypography.cardTitle()).accessibilityAddTraits(.isHeader)
                    Text(cityName).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
                ForEach(rows) { row in
                    Group {
                        if dynamicType.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 4) { Text(row.title); clock(row) }
                        } else {
                            HStack { Text(row.title); Spacer(); clock(row) }
                        }
                    }
                    .font(MadarTypography.body()).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.accessibilityLabel)
                    .accessibilityIdentifier("foundation-prayer-time-\(row.prayer.rawValue)")
                }
            }
        }
    }
    private func clock(_ row: FoundationPrayerTimeRow) -> some View {
        Text("\u{2068}\(row.clock)\u{2069}").monospacedDigit().fixedSize(horizontal: false, vertical: true)
    }
}

struct FoundationHome: View {
    @Bindable var session: AppSession
    @Environment(\.roomTheme) private var theme
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let place = session.activePlace
            let options = prayerOptions
            let today = FoundationPrayerTimesPresentation(instant: timeline.date, place: place, options: options, numerals: session.string("core.numerals") == "western" ? .western : .hindi)
            let prayerDays = [PrayerTimesEngine.calculate(day: today.day.adding(days: -1), place: place, options: options), today.prayerDay].compactMap { $0 }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(dateLine(timeline.date, primary: true, place: place, day: today.day, prayerDays: prayerDays)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            Text("يومك بين الصلوات").font(MadarTypography.title())
                            Text(dateLine(timeline.date, primary: false, place: place, day: today.day, prayerDays: prayerDays)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        }
                        Spacer()
                        Button { session.selectedTab = "customize" } label: {
                            Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                        }.accessibilityLabel("خصّص مدار").accessibilityIdentifier("settings-button")
                            .background(theme.surface, in: .circle)
                    }
                    MadarCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("مدار", systemImage: "circle.hexagongrid").font(MadarTypography.section()).foregroundStyle(theme.accent)
                            Text("مساحة هادئة ليومك").font(MadarTypography.cardTitle())
                            Text("اختر كيف يبدأ يومك، واضبط مدينتك ومظهر مدار بما يناسبك.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                            Button("خصّص مدار") { session.selectedTab = "customize" }.buttonStyle(MadarPrimaryButton())
                        }
                    }
                    if today.rows.isEmpty {
                        MadarCard {
                            Label("تعذّر حساب المواقيت لهذا الموقع اليوم. بداية اليوم من الفجر أو المغرب تحتاج مواقيت متاحة؛ يمكنك اختيار منتصف الليل من خصّص مدار.", systemImage: "info.circle")
                                .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                                .accessibilityIdentifier("prayer-boundary-unavailable")
                        }
                    } else {
                        FoundationPrayerTimesCard(rows: today.rows, cityName: session.cityName)
                    }
                    MadarCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(session.cityName, systemImage: "location").font(MadarTypography.section())
                            Text("اليوم يبدأ من \(boundaryLabel)").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                            HStack {
                                Text("التقويم الأول").foregroundStyle(theme.secondaryInk)
                                Spacer()
                                Text(session.string("core.firstCalendar") == "hijri" ? "الهجري" : "الميلادي")
                            }
                        }
                    }
                }.padding(16).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.background(theme.background).foregroundStyle(theme.ink)
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
    private var boundaryLabel: String {
        switch session.string("core.dayStart") { case "maghrib": "المغرب"; case "midnight": "منتصف الليل"; default: "الفجر" }
    }
    private var prayerOptions: PrayerCalculationOptions {
        var offsets: [Prayer: Int] = [:]
        if case .object(let values) = session.values["salah.offsets"] {
            for prayer in Prayer.allCases {
                if case .number(let minutes) = values[prayer.rawValue] { offsets[prayer] = Int(minutes) }
            }
        }
        return PrayerCalculationOptions(method: PrayerCalculationMethod(rawValue: session.string("salah.method")) ?? .ummAlQura,
            hanafiAsr: session.string("salah.asr") == "hanafi",
            highLatitudeRule: PrayerHighLatitudeRule(rawValue: session.string("salah.highLatitudeRule")) ?? .auto,
            offsets: offsets, hijriSource: HijriSource(rawValue: session.string("core.hijriSource")) ?? .ummAlQura,
            sightingOffset: Int(session.number("core.hijriOffset")))
    }
    private func dateLine(_ instant: Date, primary: Bool, place: ActivePlace, day: GregorianDay, prayerDays: [PrayerDay]) -> String {
        let useHijri = (session.string("core.firstCalendar") == "hijri") == primary
        let key = try? MadarDay.resolve(instant: instant, place: place, boundary: DayBoundary(rawValue: session.string("core.dayStart")) ?? .fajr, prayerDays: prayerDays, hijriSource: HijriSource(rawValue: session.string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(session.number("core.hijriOffset")))
        let date = (key?.date ?? day).date(in: place.timeZone).addingTimeInterval(12 * 3600)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: session.string("core.numerals") == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab")
        formatter.timeZone = place.timeZone
        formatter.calendar = Calendar(identifier: useHijri ? .islamicUmmAlQura : .gregorian)
        formatter.dateFormat = "EEEE، d MMMM yyyy"
        let adjusted = useHijri && session.string("core.hijriSource") == "sighting" ? date.addingTimeInterval(session.number("core.hijriOffset") * 86400) : date
        return formatter.string(from: adjusted)
    }
}
