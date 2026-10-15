import SwiftUI
import MadarCore
import MadarDesign

/// M3-V15 · `notes-app/21-today-travel.jpg`: air-mail head, a drawn route (no map tiles, nothing leaves the device),
/// the city stamp, a passport margin and «اكتب من [المدينة]». Every value comes from the shared Trip.
struct DiaryAirmailStripe: View {
    var body: some View {
        Canvas { context, size in
            let colors = (0..<3).map { MadarToken.colors["rooms.notes.travel.airmailStripe.\($0)"] ?? .clear }
            var x = -size.height, n = 0
            while x < size.width {
                var band = Path(); band.move(to: .init(x: x, y: size.height)); band.addLine(to: .init(x: x + size.height, y: 0))
                band.addLine(to: .init(x: x + size.height + 14, y: 0)); band.addLine(to: .init(x: x + 14, y: size.height)); band.closeSubpath()
                context.fill(band, with: .color(colors[[0, 1, 2, 1][n % 4]])); x += 14; n += 1
            }
        }.frame(height: 7).accessibilityHidden(true)
    }
}

/// «تقويم السفر · الإطار البريدي»: travel days wear an alternating red/blue dashed air-mail border in every calendar.
struct DiaryAirmailFrame: View {
    var lineWidth: CGFloat
    var dash: CGFloat
    var body: some View {
        let red = MadarToken.colors["rooms.notes.travel.airmailStripe.0"] ?? .red, blue = MadarToken.colors["rooms.notes.travel.airmailStripe.2"] ?? .blue
        ZStack {
            RoundedRectangle(cornerRadius: 2).stroke(red, style: .init(lineWidth: lineWidth, dash: [dash, dash]))
            RoundedRectangle(cornerRadius: 2).stroke(blue, style: .init(lineWidth: lineWidth, dash: [dash, dash], dashPhase: dash))
        }.accessibilityHidden(true)
    }
}

struct DiaryTravelHeader: View {
    let page: DiaryTravelPage
    let subtitle: String
    let distance: String
    let digits: MadarNumberFormatter
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 0) {
            DiaryAirmailStripe()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("بريد جوي", systemImage: "paperplane").font(.custom("thmanyahsans-Bold", size: 13, relativeTo: .footnote)).foregroundStyle(theme.accent)
                        .padding(.horizontal, 12).frame(minHeight: 30).overlay { Rectangle().stroke(theme.accent, lineWidth: 1.2) }
                    Spacer(minLength: 8)
                    Label(distance + " كم عن " + page.homeName, systemImage: "mappin")
                        .font(DiaryType.label).foregroundStyle(theme.color("ink2")).accessibilityIdentifier("diary-travel-distance")
                }
                // From AX1 the stamp stacks under the title and the drawn route becomes plain lines.
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                layout {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("من: " + page.city + " · إلى: مذكراتي").font(DiaryType.label).foregroundStyle(theme.color("ink2"))
                        Text("اليوم " + (DiaryTravelCalendar.ordinal(page.number) ?? digits.string(page.number)))
                            .font(.custom("thmanyahserifdisplay-Bold", size: 32, relativeTo: .largeTitle)).foregroundStyle(theme.ink).accessibilityIdentifier("diary-travel-title")
                        Text(subtitle).font(DiaryType.label).foregroundStyle(theme.color("ink2"))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    DiaryCityStamp(city: page.city).rotationEffect(.degrees(-4))
                }
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("من " + page.homeName + " إلى " + page.city)
                        if page.current { Text("أنت هنا الآن") }
                        Text(page.returned ? "العودة تمّت" : "العودة لم تأتِ بعد")
                    }.font(MadarTypography.body()).foregroundStyle(theme.color("ink2")).accessibilityIdentifier("diary-travel-route-list")
                } else {
                    DiaryTravelRoute(page: page).frame(height: 150).padding(.top, 8)
                }
            }.padding(.horizontal, 18).padding(.vertical, 14)
            DiaryAirmailStripe()
        }.accessibilityElement(children: .contain).accessibilityIdentifier("diary-travel")
    }
}

struct DiaryCityStamp: View {
    let city: String
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(spacing: 4) {
            DiaryDome().stroke(theme.onAccent, style: .init(lineWidth: 1.6, lineCap: .round, lineJoin: .round)).frame(width: 50, height: 40)
            Text(city).font(.custom("thmanyahsans-Bold", size: 12, relativeTo: .caption)).foregroundStyle(theme.onAccent).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(width: 76, height: 92).background(theme.color("accent")).padding(6)
            .overlay { Rectangle().stroke(theme.color("accent").opacity(0.45), style: .init(lineWidth: 2, dash: [3, 3])) }
            .accessibilityElement(children: .ignore).accessibilityLabel("طابع " + city).accessibilityIdentifier("diary-travel-stamp")
    }
}

private struct DiaryDome: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(), w = r.width, h = r.height
        p.move(to: .init(x: r.minX + w * 0.08, y: r.maxY)); p.addLine(to: .init(x: r.maxX - w * 0.08, y: r.maxY))
        p.move(to: .init(x: r.minX + w * 0.25, y: r.maxY)); p.addLine(to: .init(x: r.minX + w * 0.25, y: r.minY + h * 0.55))
        p.addQuadCurve(to: .init(x: r.maxX - w * 0.25, y: r.minY + h * 0.55), control: .init(x: r.midX, y: r.minY + h * 0.08))
        p.addLine(to: .init(x: r.maxX - w * 0.25, y: r.maxY))
        p.move(to: .init(x: r.midX, y: r.minY + h * 0.3)); p.addLine(to: .init(x: r.midX, y: r.minY))
        for x in [0.08, 0.92] { p.move(to: .init(x: r.minX + w * x, y: r.maxY)); p.addLine(to: .init(x: r.minX + w * x, y: r.minY + h * 0.18)) }
        for x in [0.4, 0.6] { p.move(to: .init(x: r.minX + w * x, y: r.maxY)); p.addLine(to: .init(x: r.minX + w * x, y: r.minY + h * 0.62)) }
        return p
    }
}

/// A drawn route, home on the reading edge, the trip city on the arc, and the way back dotted until the return.
struct DiaryTravelRoute: View {
    let page: DiaryTravelPage
    @Environment(\.roomTheme) private var theme
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var contours = Path()
            for (n, y) in [0.3, 0.55, 0.8].enumerated() {
                contours.move(to: .init(x: 0, y: h * y)); contours.addCurve(to: .init(x: w, y: h * (y - 0.12)), control1: .init(x: w * 0.3, y: h * (y - 0.2 + Double(n) * 0.05)), control2: .init(x: w * 0.65, y: h * (y + 0.18)))
            }
            context.stroke(contours, with: .color(theme.line), lineWidth: 1)
            context.fill(Path(ellipseIn: .init(x: -20, y: h * 0.62, width: 90, height: 70)), with: .color(theme.line.opacity(0.7)))
            let home = CGPoint(x: w - 28, y: h - 28), here = CGPoint(x: w * 0.6, y: h * 0.42), back = CGPoint(x: 30, y: h * 0.36)
            let red = MadarToken.colors["rooms.notes.travel.airmailStripe.0"] ?? theme.accent
            var out = Path(); out.move(to: home); out.addQuadCurve(to: here, control: .init(x: w * 0.82, y: h * 0.18))
            context.stroke(out, with: .color(red), style: .init(lineWidth: 2.4, lineCap: .round))
            var way = Path(); way.move(to: here); way.addQuadCurve(to: back, control: .init(x: w * 0.3, y: h * 0.2))
            context.stroke(way, with: .color(red), style: .init(lineWidth: 2.2, lineCap: .round, dash: page.returned ? [] : [1, 7]))
            context.fill(Path(ellipseIn: .init(x: home.x - 6, y: home.y - 6, width: 12, height: 12)), with: .color(theme.ink))
            context.stroke(Path(ellipseIn: .init(x: back.x - 6, y: back.y - 6, width: 12, height: 12)), with: .color(theme.color("ink2")), lineWidth: 2)
            if page.current { context.fill(Path(ellipseIn: .init(x: here.x - 18, y: here.y - 18, width: 36, height: 36)), with: .color(red.opacity(0.18))) }
            context.fill(Path(ellipseIn: .init(x: here.x - 10, y: here.y - 10, width: 20, height: 20)), with: .color(red))
            context.draw(Text(page.homeName).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.color("ink2")), at: .init(x: home.x, y: home.y + 16))
            context.draw(Text((page.current ? "أنت هنا · " : "") + page.city).font(.custom("thmanyahsans-Bold", size: 13, relativeTo: .caption)).foregroundStyle(theme.accent), at: .init(x: here.x, y: here.y + 26))
            context.draw(Text("العودة").font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.color("ink2")), at: .init(x: back.x + 6, y: back.y + 18))
        }
        .environment(\.layoutDirection, .leftToRight)
        .background(theme.surface, in: .rect(cornerRadius: 14)).overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.line) }
        .clipShape(.rect(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("المسار من " + page.homeName + " إلى " + page.city + (page.returned ? "، ثم العودة" : ""))
    }
}

/// One passport stamp per trip: city and the stored arrival day.
struct DiaryPassportStamp: View {
    let city: String
    let date: String
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(spacing: 2) {
            Text(city).font(.custom("thmanyahsans-Bold", size: 12, relativeTo: .caption))
            Text(date + "، دخول").font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).lineLimit(2).multilineTextAlignment(.center)
        }.foregroundStyle(theme.accent).padding(10).frame(width: 84, height: 84)
            .overlay { Circle().stroke(theme.accent, lineWidth: 1.6).padding(2) }.overlay { Circle().stroke(theme.accent.opacity(0.5), lineWidth: 0.8).padding(7) }
            .rotationEffect(.degrees(-14)).accessibilityElement(children: .combine).accessibilityIdentifier("diary-passport-stamp")
    }
}

/// §7.3 return moment: on the home page of the return day the trip is folded into an air-mail envelope.
struct DiaryTravelReturnCard: View {
    let trip: DiaryTravelReturn
    let days: String
    let distance: String
    let open: () -> Void
    @Environment(\.roomTheme) private var theme
    var body: some View {
        Button(action: open) {
            VStack(spacing: 0) {
                DiaryAirmailStripe()
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("عدت من " + trip.city).font(DiaryType.heading).foregroundStyle(theme.ink)
                        Text("طُويت الرحلة في ظرف: " + days + "، " + distance + " كم").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                        Text("الأختام").font(DiaryType.label).foregroundStyle(theme.accent).padding(.top, 2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    DiaryEnvelope(sealed: true).frame(width: 64, height: 44).rotationEffect(.degrees(-4)).accessibilityHidden(true)
                }.padding(.horizontal, 16).padding(.vertical, 12)
                DiaryAirmailStripe()
            }.background(theme.surface).clipShape(.rect(cornerRadius: 6)).overlay { RoundedRectangle(cornerRadius: 6).stroke(theme.line) }.contentShape(.rect)
        }.buttonStyle(.plain).accessibilityElement(children: .combine).accessibilityIdentifier("diary-travel-return")
    }
}

struct DiaryStampsView: View {
    @Bindable var app: AppSession
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var stamps: [DiaryTravelStamp] = []
    @State private var failure: String?
    private var service: AppDiaryService { AppDiaryService(app: app) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let failure { Text(failure).font(MadarTypography.body()) }
                    else if stamps.isEmpty { Text("لا أختام بعد. تظهر هنا مدن رحلاتك.").font(DiaryType.writing).foregroundStyle(theme.color("ink2")) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 18) {
                        ForEach(stamps) { stamp in
                            VStack(spacing: 8) {
                                DiaryPassportStamp(city: stamp.city, date: service.shortDate(stamp.arrival))
                                Text(stamp.departure.map { "العودة " + service.shortDate($0) } ?? "الرحلة مستمرة").font(DiaryType.label).foregroundStyle(theme.color("ink2"))
                            }.frame(maxWidth: .infinity)
                        }
                    }
                }.padding(18)
            }.background(theme.background).foregroundStyle(theme.ink)
                .navigationTitle("الأختام").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تم") { dismiss() }.accessibilityIdentifier("diary-stamps-done") } }
                .toolbarBackground(theme.background, for: .navigationBar).tint(theme.accent)
                .task { do { stamps = try service.travelStamps() } catch { failure = error.localizedDescription } }
        }.accessibilityIdentifier("diary-stamps")
    }
}

extension AppDiaryService {
    func kilometres(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: "ar_SA@numbers=" + (app.string("core.numerals") == "western" ? "latn" : "arab"))))
    }
    func shortDate(_ day: GregorianDay) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ar_SA@numbers=" + (app.string("core.numerals") == "western" ? "latn" : "arab"))
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = .gmt; formatter.dateFormat = "d MMMM"
        return formatter.string(from: day.date(in: .gmt).addingTimeInterval(12*3600))
    }
}
