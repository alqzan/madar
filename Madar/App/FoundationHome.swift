import SwiftUI
import MadarCore
import MadarDesign

struct FoundationHome: View {
    @Bindable var session: AppSession
    @Environment(\.roomTheme) private var theme
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(dateLine(timeline.date, primary: true)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            Text("يومك بين الصلوات").font(MadarTypography.title())
                            Text(dateLine(timeline.date, primary: false)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
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
                    if PrayerTimesEngine.calculate(day: GregorianDay.containing(timeline.date, in: session.activePlace.timeZone), place: session.activePlace) == nil {
                        MadarCard {
                            Label("تعذّر حساب المواقيت لهذا الموقع اليوم. بداية اليوم من الفجر أو المغرب تحتاج مواقيت متاحة؛ يمكنك اختيار منتصف الليل من خصّص مدار.", systemImage: "info.circle")
                                .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                                .accessibilityIdentifier("prayer-boundary-unavailable")
                        }
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
    private func dateLine(_ instant: Date, primary: Bool) -> String {
        let useHijri = (session.string("core.firstCalendar") == "hijri") == primary
        let place = session.activePlace
        let day = GregorianDay.containing(instant, in: place.timeZone)
        let prayers = [day.adding(days: -1), day].compactMap { PrayerTimesEngine.calculate(day: $0, place: place) }
        let key = try? MadarDay.resolve(instant: instant, place: place, boundary: DayBoundary(rawValue: session.string("core.dayStart")) ?? .fajr, prayerDays: prayers, hijriSource: HijriSource(rawValue: session.string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(session.number("core.hijriOffset")))
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
