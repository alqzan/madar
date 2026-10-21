import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarDesign
import MadarMoney
import MadarCommands

struct MoneyRoomView: View {
    let app: AppSession
    var isTabRoot = false
    @State private var trip = false
    @State private var loaded = false
    @State private var revealed = false
    var body: some View {
        Group {
            if !loaded { ProgressView() }
            else if trip { MoneyTravelView(app: app, revealed: $revealed, isTabRoot: isTabRoot) }
            else { MoneyHomeView(app: app, isTabRoot: isTabRoot) }
        }.task { load() }.onChange(of: app.prayerRevision) { load() }
    }
    private func load() { trip = (try? MoneyRepository(context: ModelContext(app.container)).trip(at: app.prayerNow())) != nil; loaded = true }
}

struct MoneyTravelView: View {
    let app: AppSession
    @Binding var revealed: Bool
    var isTabRoot = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var reading: MoneyTravelReading?
    @State private var selected: GregorianDay?
    @State private var homeUnits = false
    @State private var editor = false
    @State private var funding = false
    @State private var report = false
    @State private var expense = false
    @State private var regular = false
    @State private var entered = false
    @State private var failure: String?
    private var theme: RoomTheme { .init(room: "mal.travel", dark: colorScheme == .dark) }
    private var service: AppMoneyService { .init(app: app) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private var home: String { app.string("core.currency") }
    private var shownCurrency: String { homeUnits ? home : reading?.currency ?? home }
    private func amount(_ homeMinor: Int) -> String {
        guard visible else { return "•••" }
        guard shownCurrency != home else { return service.amount(homeMinor) }
        guard let rate = reading?.rate, let n = try? TravelBudget.foreignAmount(homeMinor: homeMinor, currency: shownCurrency, rate: rate, home: home) else { return "—" }
        return service.amount(n, currency: shownCurrency)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                header
                if let r = reading {
                    HStack {
                        Text(r.mode == "manual" ? "وضع السفر، يدوي" : "وضع السفر، تلقائي").font(MadarTypography.fine()).foregroundStyle(theme.color("accentText")).padding(8).overlay { Rectangle().stroke(theme.color("accentText"), style: .init(lineWidth: 1, dash: [3,2])) }.rotationEffect(.degrees(-3))
                        Spacer(minLength: 6)
                        Picker("عملة العرض", selection: $homeUnits) { Text(shortCurrency(reading?.currency ?? home)).tag(false); Text(shortCurrency(home)).tag(true) }.pickerStyle(.segmented).frame(width: 115).accessibilityIdentifier("money-travel-units")
                        Button { editor = true } label: { Image(systemName: "arrow.left.arrow.right").frame(width: 36, height: 44) }.accessibilityLabel("سعر الصرف").accessibilityIdentifier("money-travel-rate")
                    }
                    if let distance = r.distanceKm { Text(service.digits.string(distance) + " كم من مدينتك").font(.system(size: 11)).foregroundStyle(theme.secondaryInk) }
                    if !dynamicType.isAccessibilitySize { MoneyTravelSkyline().fill(theme.color("accent")).frame(height: 43).opacity(entered ? 0.88 : 0.3).animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: entered).accessibilityHidden(true) }
                    ticket(r)
                    days(r)
                    postcard(r)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(figure: r.dailyMinor.map { "خطة يومك " + amount($0) } ?? "حدّد مبلغ الرحلة وموعدها").font(MadarTypography.fine()).foregroundStyle(theme.color("stampText"))
                            Text(app.bool("mal.travelPausesDaily") ? "اليومية متوقفة؛ المصروف من مظروف الرحلة" : "اليومية مستمرة؛ مصروف الرحلة من مظروفها").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        }
                        Spacer(minLength: 8)
                        Button { funding = true } label: { Text(r.hasEnvelope ? "أضف للمظروف" : "موّل الرحلة").font(MadarTypography.fine()).frame(minHeight: 44) }.accessibilityIdentifier("money-travel-fund")
                    }
                    Button { report = true } label: { Text("تقرير الرحلة").font(MadarTypography.cardTitle()).frame(maxWidth: .infinity, minHeight: 56).foregroundStyle(theme.color("onButton")).background(theme.color("button"), in: .capsule) }.accessibilityIdentifier("money-travel-report")
                    HStack { Button("سجّل مصروفًا") { expense = true }.accessibilityIdentifier("money-travel-expense"); Spacer(); Button("دفتر المال") { regular = true }.accessibilityIdentifier("money-travel-ledger") }.font(MadarTypography.caption()).frame(minHeight: 44)
                    if let failure { Text(failure).font(MadarTypography.caption()) }
                } else { Text(failure ?? "لا توجد رحلة جارية. تبدأ الرحلة من حالة السفر المشتركة في الصلاة.").font(MadarTypography.body()).padding(24) }
            }.padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 24).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).buttonStyle(.plain).environment(\.roomTheme, theme)
            .toolbar(.hidden, for: .navigationBar, .tabBar).task { load(); entered = true }.onChange(of: app.prayerRevision) { load() }
            .onChange(of: scenePhase) { if scenePhase != .active { revealed = false } }
            .accessibilityIdentifier("money-travel")
            .sheet(isPresented: $editor) { if let r = reading { MoneyTripRateSheet(app: app, reading: r, visible: visible) } }
            .sheet(isPresented: $funding) { if let r = reading { MoneyTripFundingSheet(app: app, reading: r, visible: visible) } }
            .sheet(isPresented: $report) { if let r = reading { tripReport(r) } }
            .navigationDestination(isPresented: $expense) { MoneyExpenseView(app: app, revealed: $revealed) }
            .navigationDestination(isPresented: $regular) { MoneyHomeView(app: app) }
    }
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            if !isTabRoot {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).overlay { Circle().stroke(theme.color("stampText"), lineWidth: 1) } }.accessibilityLabel("إغلاق").accessibilityIdentifier("money-travel-close")
            }
            Text("المال، " + (reading?.city ?? "السفر")).font(.custom("thmanyahserifdisplay-Bold", size: 23, relativeTo: .title2)); Spacer(minLength: 0)
            if !visible { Button { revealed = true } label: { Image(systemName: "eye").frame(width: 44, height: 44) }.accessibilityLabel("أظهر الأرقام").accessibilityIdentifier("money-travel-reveal") }
        }
    }
    private func ticket(_ r: MoneyTravelReading) -> some View {
        HStack(alignment: .center, spacing: 15) {
            VStack(alignment: .leading, spacing: 7) {
                HStack { Text(r.homeCity.isEmpty ? "مدينتك" : r.homeCity); Spacer(minLength: 4); Image(systemName: "airplane").foregroundStyle(theme.color("accentText")); Spacer(minLength: 4); Text(r.city) }.font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline))
                HStack(spacing: 3) { ForEach(0..<7, id: \.self) { i in Capsule().fill(i < min(7, MadarCalendarDays.distance(from: r.start, to: r.today)+1) ? theme.color("accent") : theme.line).frame(height: 5) } }.accessibilityHidden(true)
                HStack { Text("اليوم " + service.digits.string(MadarCalendarDays.distance(from: r.start, to: r.today)+1)); Spacer(minLength: 4); MadarDateLabel(app.dateLabels(r.today, compact: true), primaryFont: .system(size: 11), secondaryFont: .system(size: 11)) }.font(.system(size: 11)).foregroundStyle(theme.secondaryInk)
                Text(r.dailyMinor == nil ? "في مظروف الرحلة" : "باقٍ من خطة اليوم").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).padding(.top, 8)
                Text(figure: amount(r.dailyMinor.map { $0 - r.todaySpentMinor } ?? r.balanceMinor)).font(.custom("thmanyahserifdisplay-Black", size: 40, relativeTo: .largeTitle)).foregroundStyle(theme.color("accentText")).contentTransition(.numericText()).minimumScaleFactor(0.6).lineLimit(1).accessibilityIdentifier("money-travel-remaining")
                HStack(alignment: .firstTextBaseline) { Text(service.currencyName(shownCurrency)).font(MadarTypography.fine()); Spacer(); if r.dailyMinor != nil { Text(figure: "وفي الرحلة " + amount(r.balanceMinor)).font(MadarTypography.fine()) } }.foregroundStyle(theme.secondaryInk)
                if r.currency == nil || (r.currency != home && r.rate == nil) { Button("أدخل عملة البلد وسعر الصرف") { editor = true }.font(MadarTypography.caption()).accessibilityIdentifier("money-travel-missing-rate") }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !dynamicType.isAccessibilitySize { Rectangle().fill(theme.line).frame(width: 1); stampGrid(r).frame(width: 77) }
        }.fixedSize(horizontal: false, vertical: true).padding(15).background(theme.surface, in: .rect(cornerRadius: 15)).overlay { RoundedRectangle(cornerRadius: 15).stroke(theme.line, lineWidth: 1) }
            .overlay(alignment: .top) { Circle().fill(theme.background).frame(width: 16, height: 16).offset(y: -8) }
            .overlay(alignment: .bottom) { Circle().fill(theme.background).frame(width: 16, height: 16).offset(y: 8) }
            .shadow(color: theme.ink.opacity(0.06), radius: 12, y: 8)
    }
    private func stampGrid(_ r: MoneyTravelReading) -> some View {
        let daily = r.dailyMinor ?? 0
        let count = visible ? TravelBudget.stampsRemaining(dailyMinor: daily, spentMinor: r.todaySpentMinor) : 0
        return VStack(spacing: 4) {
            Text("طوابع اليوم").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            ForEach(0..<5, id: \.self) { row in HStack(spacing: 4) { ForEach(0..<2, id: \.self) { col in let index = row*2+col; Image(systemName: index < count ? "seal" : "water.waves").font(.system(size: 15)).foregroundStyle(index < count ? theme.color("stampText") : theme.secondaryInk.opacity(0.5)).frame(maxWidth: .infinity).frame(height: 22).overlay { Rectangle().stroke(index < count ? theme.color("stampText") : theme.line, lineWidth: 1) } } } }
            Text(visible && daily > 0 ? "كل طابع عُشر الخطة" : "—").font(.system(size: 11)).foregroundStyle(theme.secondaryInk)
        }.accessibilityHidden(true)
    }
    private func days(_ r: MoneyTravelReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("أيام الرحلة").font(MadarTypography.cardTitle()); Spacer(); Text(figure: r.dailyMinor.map { "الخطة " + amount($0) } ?? "بلا خطة يومية").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
            ScrollView(.horizontal) { HStack(spacing: 5) { ForEach(r.days, id: \.description) { day in
                let rows = r.movements.filter { $0.day == day }, spent = rows.reduce(0) { $0 + ($1.isRefund ? -$1.homeMinor : $1.homeMinor) }
                Button { selected = day } label: {
                    VStack(spacing: 5) { Image(systemName: day > r.today ? "airplane" : rows.isEmpty ? "leaf" : "building.2").font(.system(size: 20)); Text(figure: day > r.today ? "—" : amount(spent)).font(MadarTypography.fine()).minimumScaleFactor(0.6).lineLimit(1); MadarDateLabel(stampDate(day), primaryFont: .system(size: 11), secondaryFont: .system(size: 11)) }.foregroundStyle((selected ?? r.today) == day ? theme.color("stampText") : theme.color("accentText")).padding(4).frame(width: 44, height: 83).background(theme.surface).overlay { Rectangle().stroke((selected ?? r.today) == day ? theme.color("stampText") : theme.line, lineWidth: (selected ?? r.today) == day ? 2 : 1) }.rotationEffect(.degrees(day.day.isMultiple(of: 2) ? -3 : 2))
                }.accessibilityLabel(app.dateLabels(day).combined).accessibilityIdentifier("money-travel-day-" + day.description)
            } }.padding(.vertical, 4) }.scrollIndicators(.hidden).defaultScrollAnchor(.trailing)
        }
    }
    private func postcard(_ r: MoneyTravelReading) -> some View {
        let day = selected ?? r.today, rows = r.movements.filter { $0.day == day }
        return VStack(alignment: .leading, spacing: 9) {
            MadarDateLabel(app.dateLabels(day), primaryFont: .custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline), secondaryFont: MadarTypography.fine()).accessibilityIdentifier("money-travel-selected-date")
            if rows.isEmpty { Text(day > r.today ? "صفحة تنتظر أيامك القادمة" : "لم يُسجّل مصروف لهذا اليوم").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk) }
            ForEach(rows) { row in HStack { Image(systemName: row.isRefund ? "arrow.uturn.backward" : "diamond.fill").font(.system(size: 7)).foregroundStyle(theme.color("accentText")); Text(row.name).lineLimit(1); Spacer(); Text(figure: (row.isRefund ? "+" : "") + amount(row.homeMinor)).monospacedDigit() }.font(MadarTypography.caption()) }
        }.padding(15).frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading).background(theme.surface).overlay { MoneyAirmailBorder().stroke(theme.color("accentText"), style: .init(lineWidth: 4, dash: [8,16])).padding(4); MoneyAirmailBorder().stroke(theme.color("alert"), style: .init(lineWidth: 4, dash: [8,16], dashPhase: 12)).padding(4); Rectangle().stroke(theme.color("stampText"), lineWidth: 0.5).padding(10) }
    }
    private func tripReport(_ r: MoneyTravelReading) -> some View {
        ScrollView { VStack(alignment: .leading, spacing: 14) {
            HStack { Text("تقرير رحلة " + r.city).font(MadarTypography.title()); Spacer(); Button("تم") { report = false }.frame(minHeight: 44).accessibilityIdentifier("money-trip-report-close") }
            MadarDateLabel(app.dateLabels(r.start), primaryFont: MadarTypography.body(), secondaryFont: MadarTypography.caption())
            Text(figure: "في المظروف " + amount(r.balanceMinor)).font(MadarTypography.cardTitle())
            ForEach(r.movements) { row in HStack { VStack(alignment: .leading) { Text(row.name); MadarDateLabel(app.dateLabels(row.day, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()) }; Spacer(); Text(figure: (row.isRefund ? "+" : "") + amount(row.homeMinor)) } }
            if r.movements.isEmpty { Text("تظهر هنا المصروفات بعد تسجيلها أو تأكيد رسائل البنك.").foregroundStyle(theme.secondaryInk) }
        }.font(MadarTypography.body()).padding(22) }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).accessibilityIdentifier("money-trip-report").buttonStyle(.plain).accessibilityIdentifier("money-travel-report-sheet")
    }
    private func stampDate(_ day: GregorianDay) -> MadarDateLabels {
        let date = DualDate(instant: day.date(in: app.activePlace.timeZone).addingTimeInterval(12*3600), timeZone: app.activePlace.timeZone, source: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(app.number("core.hijriOffset")))
        let h = service.digits.string(date.hijri.day) + "هـ", g = service.digits.string(date.gregorian.day) + "م"
        return app.string("core.firstCalendar") == "gregorian" ? .init(primary: g, secondary: h) : .init(primary: h, secondary: g)
    }
    private func shortCurrency(_ code: String) -> String { let name = service.currencyName(code); return name.split(separator: " ").first.map(String.init) ?? code }
    private func load() { do { reading = try service.loadTravel(); failure = nil } catch { failure = "لم تكتمل قراءة الرحلة. حاول مرة أخرى." } }
}
private struct MoneyAirmailBorder: Shape { func path(in r: CGRect) -> Path { Path(r) } }
private struct MoneyTravelSkyline: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.addRect(CGRect(x: 0, y: r.height-4, width: r.width, height: 4))
        for (x, w, h) in [(0.025,0.08,0.14),(0.29,0.14,0.23),(0.50,0.23,0.33),(0.81,0.14,0.25)] {
            let rect = CGRect(x:r.width*x,y:r.height*(1-h),width:r.width*w,height:r.height*h)
            p.addRect(rect); p.move(to: CGPoint(x:rect.minX,y:rect.minY)); p.addQuadCurve(to:CGPoint(x:rect.maxX,y:rect.minY),control:CGPoint(x:rect.midX,y:rect.minY-rect.width*0.62)); p.closeSubpath()
            p.addRect(CGRect(x:rect.midX-0.5,y:rect.minY-rect.width*0.34-6,width:1,height:10))
        }
        for (x,h) in [(0.14,0.85),(0.22,0.62),(0.435,0.77),(0.463,0.87),(0.488,0.86),(0.735,0.94),(0.758,0.90),(0.783,0.75),(0.965,0.72)] {
            let x = r.width*x, w = r.width*0.011, y = r.height*(1-h)
            p.addRect(CGRect(x:x,y:y,width:w,height:r.height-y)); p.move(to:CGPoint(x:x,y:y));p.addLine(to:CGPoint(x:x+w/2,y:y-8));p.addLine(to:CGPoint(x:x+w,y:y));p.closeSubpath()
        }
        return p
    }
}
