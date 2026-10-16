import SwiftUI
import MadarCore
import MadarData
import MadarDesign
import MadarMoney
import MadarCommands

/// «منذ آخر زيارة» (`mal/08-Z-R19-since`): a newspaper of the days away, built only from stored facts.
struct MoneySinceView: View {
    let app: AppSession
    let home: MoneyHomeReading
    @Binding var revealed: Bool
    var openMessages: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var reading: MoneySinceReading?
    @State private var selected: GregorianDay?
    @State private var failure: String?
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var service: AppMoneyService { .init(app: app) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private func amount(_ minor: Int) -> String { visible ? service.amount(minor) : "•••" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("منذ آخر زيارة").font(MadarTypography.cardTitle()).accessibilityIdentifier("money-since-title")
                    Button(action: finish) {
                        Image(systemName: "xmark").font(.title3).frame(width: 52, height: 52).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1.2) }
                    }.buttonStyle(.plain).accessibilityLabel("إغلاق").accessibilityIdentifier("money-since-close")
                    Spacer()
                }.padding(.top, 8)
                if let reading {
                    masthead(reading)
                    headline(reading)
                    if let silent = reading.silentDays {
                        Label("لم تصل رسائل منذ " + service.days(silent) + "؛ تأكّد أن الاختصار ما زال يعمل", systemImage: "antenna.radiowaves.left.and.right.slash")
                            .font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .overlay { Rectangle().stroke(theme.color("dueText").opacity(0.6), style: .init(lineWidth: 1, dash: [3, 2])) }
                            .accessibilityIdentifier("money-since-silent")
                    }
                    if !visible { Button("أظهر الأرقام") { revealed = true }.font(MadarTypography.caption()).frame(minHeight: 44) }
                    columns(reading)
                    dayDetail(reading)
                    if reading.pending > 0 { decisions(reading) }
                    doors(reading)
                    Button(action: finish) {
                        Text("تمّ، افتح المال").font(.custom("thmanyahsans-Bold", size: 18, relativeTo: .headline)).foregroundStyle(theme.background)
                            .frame(maxWidth: .infinity, minHeight: 58).background(theme.ink)
                    }.buttonStyle(.plain).accessibilityIdentifier("money-since-done").padding(.top, 6)
                } else if let failure { Text(failure).font(MadarTypography.body()) }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 240) }
            }.padding(.horizontal, 16).padding(.bottom, 30).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.clipped().background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
            .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
            .task { load() }.accessibilityIdentifier("money-since")
    }
    private func masthead(_ r: MoneySinceReading) -> some View {
        VStack(spacing: 6) {
            Rectangle().fill(theme.ink).frame(height: 2.5); Rectangle().fill(theme.ink).frame(height: 0.8)
            HStack(alignment: .center, spacing: 4) {
                box("لك الآن", r.availableNowMinor.map(amount) ?? "—", tint: theme.ink)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Image(systemName: "sparkle").foregroundStyle(theme.color("reserve"))
                    Text("صحيفة مالك").font(.custom("thmanyahserifdisplay-Black", size: 28, relativeTo: .title)).lineLimit(1).minimumScaleFactor(0.5).fixedSize()
                    Image(systemName: "sparkle").foregroundStyle(theme.color("reserve"))
                }.accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if let next = r.nextObligation {
                    let left = MadarCalendarDays.distance(from: r.today, to: next.due)
                    box(next.name + " " + (left == 0 ? "اليوم" : left == 1 ? "غدًا" : left == 2 ? "بعد يومين" : "بعد " + service.days(left)), amount(next.amountMinor), tint: theme.color("accent"))
                } else { Color.clear.frame(width: 1, height: 1) }
            }
            HStack {
                Text("عدد الأيام " + service.digits.string(r.days.count)).foregroundStyle(theme.secondaryInk)
                Text("✓ " + service.digits.string(r.shortcutCount) + (r.shortcutCount == 1 ? " رسالة عبر الاختصار" : " رسائل عبر الاختصار")).bold().foregroundStyle(theme.color("surplusText"))
                Spacer()
                MadarDateLabel(app.dateLabels(r.today, compact: true, weekday: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine())
            }.font(MadarTypography.fine())
            Rectangle().fill(theme.ink).frame(height: 0.8); Rectangle().fill(theme.ink).frame(height: 2.5)
        }
    }
    private func box(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
            Text(value).font(.custom("thmanyahserifdisplay-Bold", size: 19, relativeTo: .headline)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
        }.padding(.horizontal, 6).padding(.vertical, 5).frame(maxWidth: 92).overlay { Rectangle().stroke(theme.line, lineWidth: 1) }
    }
    /// The lead sentence picks the biggest fact of the days away.
    private func headline(_ r: MoneySinceReading) -> some View {
        let text: Text
        if r.salaryMinor > 0 {
            text = Text("نزل الراتب ") + Text(amount(r.salaryMinor)).foregroundStyle(theme.color("surplusText")) + Text(r.envelopesMinor > 0 ? "، وتعبّأت مظاريفك بـ" : "") + Text(r.envelopesMinor > 0 ? amount(r.envelopesMinor) : "").foregroundStyle(theme.color("accent"))
        } else if r.allowanceMinor > 0 {
            let saved = r.allowanceMinor - r.spentMinor
            text = Text("صرفت ") + Text(amount(r.spentMinor)).foregroundStyle(theme.color("accent")) + Text(" من يومك في " + service.days(r.days.filter { $0.allowanceMinor != nil }.count)) + Text(saved >= 0 ? "، وبقي منه " : "، وتجاوزته بـ") + Text(amount(abs(saved))).foregroundStyle(saved >= 0 ? theme.color("surplusText") : theme.color("dueText"))
        } else {
            text = Text("مرّت " + service.days(r.days.count) + " منذ زيارتك الأخيرة")
        }
        return text.font(.custom("thmanyahserifdisplay-Bold", size: 30, relativeTo: .title)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("money-since-headline")
    }
    private func columns(_ r: MoneySinceReading) -> some View {
        let maxSpent = max(1, r.days.map { max($0.spentMinor, $0.allowanceMinor ?? 0) }.max() ?? 1)
        let current = selected ?? r.days.last?.day
        return Group {
            if dynamicType.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(r.days) { day in HStack { Text(app.dateLabels(day.day, compact: true).primary); Spacer(); Text(amount(day.spentMinor)) } }
                }
            } else {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(r.days.reversed()) { day in
                        Button { selected = day.day } label: { column(day, maxSpent: maxSpent, active: day.day == current) }
                            .buttonStyle(.plain).accessibilityIdentifier("money-since-day-" + day.id)
                    }
                }.environment(\.layoutDirection, .rightToLeft)
            }
        }
    }
    private func column(_ d: MoneySinceDay, maxSpent: Int, active: Bool) -> some View {
        let labels = app.dateLabels(d.day, compact: true, weekday: true)
        let parts = labels.primary.split(separator: " ")
        return VStack(spacing: 6) {
            Text(String(parts.dropFirst().first ?? Substring(labels.primary))).font(.custom("thmanyahserifdisplay-Bold", size: 17, relativeTo: .headline))
            Text(String(parts.first ?? "")).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.7)
            VStack(spacing: 5) {
                if d.salaryMinor > 0 { icon("arrow.down", theme.color("surplus")) }
                if d.messages > 0 { icon("envelope", theme.color("accent")) }
                if d.statements > 0 { icon("creditcard", theme.color("bills")) }
                if d.over { icon("exclamationmark", theme.color("due")) }
                if d.pending > 0 { icon("hourglass", theme.color("reserveText"), outline: true) }
            }.frame(maxHeight: .infinity, alignment: .top)
            Text(amount(d.spentMinor)).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(d.over ? theme.color("dueText") : theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.6)
            GeometryReader { proxy in
                let h = proxy.size.height
                ZStack(alignment: .bottom) {
                    Rectangle().fill(d.over ? theme.color("due") : theme.color("surplus")).frame(height: visible ? max(4, h * CGFloat(d.spentMinor) / CGFloat(maxSpent)) : 4)
                    if let allowance = d.allowanceMinor, visible {
                        Rectangle().stroke(theme.color("reserve"), style: .init(lineWidth: 1, dash: [3, 2])).frame(height: 1).offset(y: -h * CGFloat(allowance) / CGFloat(maxSpent))
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }.frame(height: 64).padding(.horizontal, 5)
        }.padding(.top, 12).padding(.bottom, 6).frame(maxWidth: .infinity, minHeight: 250)
            .background(active ? theme.surface : theme.surface.opacity(0.5), in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
            .overlay { UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22).stroke(active ? theme.color("reserveText") : theme.line, lineWidth: active ? 2 : 1) }
            .accessibilityElement(children: .combine)
    }
    private func icon(_ name: String, _ tint: Color, outline: Bool = false) -> some View {
        Image(systemName: name).font(.caption.bold()).foregroundStyle(outline ? tint : theme.background).frame(width: 26, height: 26)
            .background(outline ? .clear : tint, in: .circle).overlay { if outline { Circle().stroke(tint, lineWidth: 1.2) } }
    }
    private func dayDetail(_ r: MoneySinceReading) -> some View {
        let current = selected ?? r.days.last?.day
        return Group {
            if let day = r.days.first(where: { $0.day == current }) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        MadarDateLabel(app.dateLabels(day.day, compact: true, weekday: true), primaryFont: MadarTypography.cardTitle(), secondaryFont: MadarTypography.fine())
                        Spacer()
                        if let allowance = day.allowanceMinor { Text("حد يومك " + amount(allowance)).font(MadarTypography.fine()).foregroundStyle(theme.color("reserveText")) }
                    }
                    detailRow("صرفت من يومك", day.allowanceMinor.map { amount(day.spentMinor) + " من " + amount($0) } ?? amount(day.spentMinor), tint: day.over ? theme.color("dueText") : theme.color("surplusText"))
                    if day.salaryMinor > 0 { detailRow("نزل الراتب", "+" + amount(day.salaryMinor), tint: theme.color("surplusText")) }
                    if day.envelopesMinor > 0 { detailRow("المظاريف تحرّكت", amount(day.envelopesMinor), tint: theme.color("accent"), diamond: theme.color("accent")) }
                    if day.messages > 0 { detailRow("رسائل البنك", service.digits.string(day.messages), tint: theme.ink, diamond: theme.color("accent")) }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("money-since-detail")
            }
        }
    }
    private func detailRow(_ title: String, _ value: String, tint: Color, diamond: Color? = nil) -> some View {
        HStack {
            DiamondMark().fill(diamond ?? theme.color("surplus")).frame(width: 11, height: 13)
            Text(title).font(MadarTypography.body())
            Spacer()
            Text(value).font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)).foregroundStyle(tint)
        }.padding(.bottom, 6).overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
    }
    private func decisions(_ r: MoneySinceReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("يحتاج قرارك").font(.custom("thmanyahserifdisplay-Bold", size: 24, relativeTo: .title2)); Spacer()
                Text(service.pending(r.pending)).font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")) }
            Button(action: openMessages) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("رسائل البنك").font(MadarTypography.cardTitle())
                        Text("اعتمد الواضح منها بلمسة، وراجع الباقي").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: "chevron.backward").foregroundStyle(theme.color("reserveText"))
                }.padding(16).frame(minHeight: 64).background(theme.surface).overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.color("dueText").opacity(0.7), lineWidth: 1.2) }
                    .clipShape(.rect(cornerRadius: 14))
            }.buttonStyle(.plain).accessibilityIdentifier("money-since-decisions")
        }.padding(.top, 8).overlay(alignment: .top) { DoubleRule().stroke(theme.ink, lineWidth: 0.8).frame(height: 3).offset(y: -4) }
    }
    private func doors(_ r: MoneySinceReading) -> some View {
        let cards: [(String, AnyView)] = [
            r.salaryMinor > 0 ? ("salary", AnyView(door("نزل الراتب", "+" + amount(r.salaryMinor), r.salaryDay.map { app.dateLabels($0, compact: true).primary + "\n" + app.dateLabels($0, compact: true).secondary } ?? "", tint: theme.color("surplusText")))) : nil,
            r.envelopesMinor > 0 ? ("envelopes", AnyView(door("المظاريف تعبّأت", amount(r.envelopesMinor), "من الراتب واليومية حسب الخطط", tint: theme.color("accent")))) : nil,
            r.allowanceMinor > 0 ? ("spent", AnyView(door("صرفك من يومك", amount(r.spentMinor), "من " + amount(r.allowanceMinor) + " في " + service.days(r.days.filter { $0.allowanceMinor != nil }.count), tint: theme.ink))) : nil,
            !r.statements.isEmpty ? ("statements", AnyView(statementsDoor(r.statements))) : nil,
        ].compactMap { $0 }
        return Group {
            if !cards.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("أبواب العدد").font(.custom("thmanyahserifdisplay-Bold", size: 24, relativeTo: .title2))
                    LazyVGrid(columns: dynamicType.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(cards, id: \.0) { $0.1.accessibilityIdentifier("money-since-door-" + $0.0) }
                    }
                }.padding(.top, 10).overlay(alignment: .top) { DoubleRule().stroke(theme.ink, lineWidth: 0.8).frame(height: 3).offset(y: -4) }
            }
        }
    }
    private func door(_ title: String, _ value: String, _ note: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(MadarTypography.caption()).bold()
            Text(value).font(.custom("thmanyahserifdisplay-Black", size: 26, relativeTo: .title2)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
            Text(note).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(2)
        }.padding(14).frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading).background(theme.surface, in: .rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line, lineWidth: 1) }
    }
    private func statementsDoor(_ items: [MoneySinceStatement]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(items.count == 1 ? "كشف وصل" : "كشوف وصلت").font(MadarTypography.caption()).bold().foregroundStyle(theme.color("bills"))
            ForEach(items.prefix(3)) { item in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.title).font(MadarTypography.fine())
                        if let due = item.due { HStack(spacing: 3) { Text("يستحق"); MadarDateLabel(app.dateLabels(due, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()) }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                    }
                    Spacer(minLength: 4)
                    Text(amount(item.amountMinor)).font(MadarTypography.caption()).bold()
                }
            }
        }.padding(14).frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading).background(theme.surface, in: .rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.color("reserveText"), lineWidth: 1) }
    }
    private func finish() {
        Task { try? await app.executeMoneyCommand("money.markVisit"); dismiss() }
    }
    private func load() {
        do { reading = try service.loadSince(home: home); failure = nil } catch { failure = "تعذّرت قراءة الأيام" }
    }
}
