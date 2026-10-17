import SwiftUI
import MadarCore
import MadarData
import MadarDesign
import MadarMoney
import MadarCommands

/// «الالتزامات» (`mal/11-Z-R19-obl`): what this cycle owes on a thread from salary to salary, the instalment ladder of
/// the months ahead, and every obligation on its shelf.
struct MoneyObligationsView: View {
    let app: AppSession
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var reading: MoneyObligationsReading?
    @State private var failure: String?
    @State private var selected: String?
    @State private var adding = false
    @State private var revealed = false
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var service: AppMoneyService { .init(app: app) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private func amount(_ minor: Int) -> String { visible ? service.amount(minor) : "•••" }
    private func color(_ group: MoneyObligationDue.Group) -> Color {
        switch group { case .loan: theme.color("accent"); case .installment: theme.color("bills"); case .bill: theme.color("surplus"); case .subscription: theme.color("reserve"); case .statement: theme.color("due") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.title3).frame(width: 52, height: 52).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1.2) }
                    }.buttonStyle(.plain).accessibilityLabel("إغلاق").accessibilityIdentifier("money-obligations-close")
                    Text("الالتزامات").font(.custom("thmanyahserifdisplay-Bold", size: 28, relativeTo: .title)).accessibilityAddTraits(.isHeader)
                    Spacer()
                }.padding(.top, 8)
                if let reading {
                    summary(reading)
                    if !visible { Button("أظهر الأرقام") { revealed = true }.font(MadarTypography.caption()).frame(minHeight: 44) }
                    thread(reading)
                    if let due = current(reading) { detail(due, reading) }
                    ladder(reading)
                    Button { adding = true } label: {
                        Text("+ أضف التزامًا، وشاهد أثره على السلّم").font(.custom("thmanyahserifdisplay-Bold", size: 19, relativeTo: .headline)).foregroundStyle(theme.background)
                            .frame(maxWidth: .infinity, minHeight: 60).background(theme.ink).shadow(color: theme.ink.opacity(0.18), radius: 8, y: 4)
                    }.buttonStyle(.plain).accessibilityIdentifier("money-obligations-add")
                    shelves(reading)
                } else if let failure { Text(failure).font(MadarTypography.body()) }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 240) }
            }.padding(.horizontal, 16).padding(.bottom, 30).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.clipped().background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
            .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
            .task { load() }.onChange(of: app.prayerRevision) { load() }
            .sheet(isPresented: $adding) { if let reading { MoneyObligationSheet(app: app, ladder: reading.ladder, visible: visible).environment(\.roomTheme, theme) } }
            .accessibilityIdentifier("money-obligations")
    }

    private func current(_ r: MoneyObligationsReading) -> MoneyObligationDue? {
        let all = r.cycle + r.installments + r.bills + r.subscriptions + r.statements
        return all.first { $0.id == selected } ?? r.cycle.first { $0.due >= r.today } ?? r.installments.first ?? r.bills.first ?? r.subscriptions.first
    }

    private func summary(_ r: MoneyObligationsReading) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("مستحق هذه الدورة").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                HStack(alignment: .top, spacing: 4) {
                    MadarDateLabel(app.dateLabels(r.cycleStart, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine())
                    Text("←").font(MadarTypography.fine())
                    MadarDateLabel(app.dateLabels(r.cycleEnd, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine())
                }.foregroundStyle(theme.secondaryInk)
                Text(amount(r.totalMinor)).font(.custom("thmanyahserifdisplay-Black", size: 58, relativeTo: .largeTitle)).lineLimit(1).minimumScaleFactor(0.5)
                    .accessibilityIdentifier("money-obligations-total")
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 10) {
                legend("من الراتب", r.fromSalaryMinor, theme.color("accent"), striped: false)
                if r.cardsMinor > 0 { legend("سداد بطاقات", r.cardsMinor, theme.color("due"), striped: true) }
            }.padding(.bottom, 10)
        }
    }
    private func legend(_ title: String, _ minor: Int, _ tint: Color, striped: Bool) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(striped ? tint.opacity(0.35) : tint).frame(width: 12, height: 12).overlay { if striped { Rectangle().stroke(tint, lineWidth: 1.5) } }
            Text(title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            Text(amount(minor)).font(.custom("thmanyahsans-Bold", size: 15, relativeTo: .callout))
        }
    }

    // MARK: The thread, salary to salary

    private func thread(_ r: MoneyObligationsReading) -> some View {
        let length = max(1, MadarCalendarDays.distance(from: r.cycleStart, to: r.cycleEnd))
        let elapsed = min(length, max(0, MadarCalendarDays.distance(from: r.cycleStart, to: r.today)))
        return Group {
            if dynamicType.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(r.cycle) { due in Button { selected = due.id } label: { HStack { Text(due.name); Spacer(); Text(amount(due.amountMinor)) } }.buttonStyle(.plain) }
                }
            } else {
                GeometryReader { proxy in
                    let w = proxy.size.width - 24, x: (Int) -> CGFloat = { day in w - CGFloat(day) / CGFloat(length) * w + 12 }
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(theme.color("reserve")).frame(width: proxy.size.width, height: 1.2).offset(y: 30)
                        Rectangle().fill(theme.ink).frame(width: x(0) - x(elapsed), height: 4).offset(x: x(elapsed), y: 28.6)
                        ForEach(0...length, id: \.self) { day in
                            Rectangle().fill(theme.color("reserveText")).frame(width: 1, height: day % 7 == 0 ? 12 : 7).offset(x: x(day), y: day % 7 == 0 ? 24 : 27)
                        }
                        VStack(spacing: 2) {
                            Text("اليوم").font(.custom("thmanyahsans-Bold", size: 12, relativeTo: .caption)); Image(systemName: "arrowtriangle.down.fill").font(.system(size: 8))
                        }.frame(width: 50).offset(x: x(elapsed) - 25, y: 0)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("الراتب القادم").font(.custom("thmanyahsans-Bold", size: 11, relativeTo: .caption2)).fixedSize().foregroundStyle(theme.color("surplusText"))
                            Circle().fill(theme.color("surplus")).frame(width: 12, height: 12).padding(.leading, 6)
                        }.frame(width: 90, alignment: .leading).offset(x: x(length) - 12, y: 9)
                        let levels = lanternLevels(r.cycle.map { x(MadarCalendarDays.distance(from: r.cycleStart, to: $0.due)) })
                        ForEach(Array(r.cycle.enumerated()), id: \.element.id) { index, due in
                            let day = MadarCalendarDays.distance(from: r.cycleStart, to: due.due)
                            Button { withAnimation(.easeOut(duration: 0.2)) { selected = due.id } } label: { lantern(due, drop: 14 + CGFloat(levels[index]) * 76, active: current(r)?.id == due.id) }
                                .buttonStyle(.plain).frame(width: 74).offset(x: x(day) - 37, y: 31)
                                .accessibilityIdentifier("money-obligation-lantern-" + due.name)
                        }
                    }.environment(\.layoutDirection, .leftToRight)
                }.frame(height: 130 + CGFloat(threadDepth(r)) * 76).accessibilityIdentifier("money-obligations-thread")
            }
        }
    }
    /// Lanterns closer than one label's width hang one row lower, so no two labels overlap.
    private func lanternLevels(_ xs: [CGFloat]) -> [Int] {
        var lastX: [CGFloat] = []
        return xs.map { x in
            if let free = lastX.firstIndex(where: { abs($0 - x) >= 76 }) { lastX[free] = x; return free }
            lastX.append(x); return lastX.count - 1
        }
    }
    private func threadDepth(_ r: MoneyObligationsReading) -> Int {
        let length = max(1, MadarCalendarDays.distance(from: r.cycleStart, to: r.cycleEnd)), w: CGFloat = 340
        return lanternLevels(r.cycle.map { CGFloat(MadarCalendarDays.distance(from: r.cycleStart, to: $0.due)) / CGFloat(length) * w }).max() ?? 0
    }
    private func lantern(_ due: MoneyObligationDue, drop: CGFloat, active: Bool) -> some View {
        let tint = color(due.group), outline = due.group == .statement
        return VStack(spacing: 3) {
            Rectangle().fill(theme.color("reserveText")).frame(width: 1, height: drop)
            ZStack {
                LanternShape().fill(outline ? Color.clear : tint)
                LanternShape().stroke(outline ? tint : theme.color("reserve"), lineWidth: active ? 3 : 1.5)
                if !outline { Rectangle().fill(theme.background.opacity(0.8)).frame(width: 2, height: 10) }
            }.frame(width: 26, height: 30).scaleEffect(active ? 1.15 : 1)
            Text(amount(due.amountMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 15, relativeTo: .callout)).lineLimit(1).minimumScaleFactor(0.6)
            Text(due.name).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    // MARK: The selected obligation

    private func detail(_ due: MoneyObligationDue, _ r: MoneyObligationsReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(due.name).font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title3))
                Spacer(minLength: 8)
                Text(amount(due.amountMinor)).font(.custom("thmanyahserifdisplay-Black", size: 26, relativeTo: .title2))
            }
            HStack(alignment: .top) {
                HStack(spacing: 6) {
                    MadarDateLabel(app.dateLabels(due.due, compact: true), primaryFont: MadarTypography.caption(), secondaryFont: MadarTypography.fine())
                    Text(due.group == .statement ? "من حساب البطاقة" : due.due < r.cycleEnd ? "محجوز من الراتب" : "").font(MadarTypography.caption())
                }.foregroundStyle(theme.secondaryInk)
                Spacer(minLength: 8)
                Text(service.relative(r.today, due.due)).font(.custom("thmanyahsans-Bold", size: 14, relativeTo: .callout))
                    .foregroundStyle(MadarCalendarDays.distance(from: r.today, to: due.due) <= 3 ? theme.color("dueText") : theme.secondaryInk)
            }
            if let paid = due.paidCount, let total = due.totalCount, total > 0 {
                let columns = [GridItem(.adaptive(minimum: 10, maximum: 14), spacing: 3)]
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(0..<total, id: \.self) { n in
                        RoundedRectangle(cornerRadius: 1.5).fill(n < paid ? color(due.group) : Color.clear)
                            .overlay { RoundedRectangle(cornerRadius: 1.5).stroke(n < paid ? Color.clear : theme.color("reserve"), lineWidth: 1) }.frame(height: 12)
                    }
                }.environment(\.layoutDirection, .rightToLeft).accessibilityLabel("دفعت " + service.digits.string(paid) + " من " + service.digits.string(total))
                HStack(spacing: 4) {
                    Text("دفعت " + service.digits.string(paid) + " من " + service.digits.string(total) + "، يبقى " + amount(due.remainingMinor ?? 0) + (due.lastDue == nil ? "" : "، آخره"))
                    if let last = due.lastDue { MadarDateLabel(app.dateLabels(last, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()) }
                }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-obligation-progress")
            } else if let schedule = due.schedule {
                Text((due.group == .subscription ? "اشتراك يتكرر " : "فاتورة تتكرر ") + schedule).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    .accessibilityIdentifier("money-obligation-schedule")
            } else if let day = due.dueDay {
                Text("فاتورة شهرية يوم " + service.digits.string(day) + " من كل شهر").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            } else if let minimum = due.minimumMinor, minimum > 0 {
                Text("الحد الأدنى " + amount(minimum) + (due.estimated ? "، الموعد تقريبي" : "")).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
        }.padding(14).background(theme.surface).overlay(alignment: .trailing) { Rectangle().fill(color(due.group)).frame(width: 4) }
            .environment(\.layoutDirection, .rightToLeft).accessibilityElement(children: .contain).accessibilityIdentifier("money-obligation-detail")
    }

    // MARK: The ladder of the months ahead

    private func ladder(_ r: MoneyObligationsReading) -> some View {
        let peak = max(1, r.ladder.map(\.total).max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            DoubleRule().stroke(theme.color("reserveText"), lineWidth: 0.7).frame(height: 3)
            HStack(alignment: .firstTextBaseline) {
                Text("سلّم الأقساط").font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title3))
                Spacer()
                if let first = r.ladder.first { Text(first.label + "، " + first.hijri + " " + amount(first.total)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
            }
            HStack(spacing: 12) {
                key("القرض", theme.color("accent")); key("التقسيط", theme.color("bills")); key("الفواتير", theme.color("surplus"))
                if r.ladder.contains(where: { $0.subscriptionMinor > 0 }) { key("الاشتراكات", theme.color("reserve")) }
            }.font(MadarTypography.fine())
            ForEach(r.endings) { ending in
                Label(ending.name + " آخره " + app.dateLabels(ending.lastDue, compact: true).combined + "، فيعود لك " + amount(ending.returnsMinor) + " كل شهر", systemImage: "arrow.down")
                    .font(MadarTypography.fine()).foregroundStyle(theme.color("surplusText")).accessibilityIdentifier("money-ladder-ending")
            }
            if dynamicType.isAccessibilitySize {
                ForEach(r.ladder) { month in HStack { Text(month.label + "، " + month.hijri); Spacer(); Text(amount(month.total)) } }
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(r.ladder.enumerated()), id: \.element.id) { index, month in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            segment(month.installmentMinor, peak, theme.color("bills"))
                            segment(month.subscriptionMinor, peak, theme.color("reserve"))
                            segment(month.billMinor, peak, theme.color("surplus"))
                            segment(month.loanMinor, peak, theme.color("accent"))
                        }.frame(maxWidth: .infinity).frame(height: 130)
                            .overlay(alignment: .bottom) {
                                if index % 3 == 0 {
                                    VStack(spacing: 0) {
                                        Text(month.label).font(.custom(index == 0 ? "thmanyahsans-Bold" : "thmanyahsans-Regular", size: 11, relativeTo: .caption2))
                                        Text(month.hijri).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2))
                                    }.foregroundStyle(index == 0 ? theme.ink : theme.secondaryInk).lineLimit(1).fixedSize().offset(y: 36)
                                }
                            }
                    }
                }.overlay(alignment: .bottom) { Rectangle().fill(theme.ink).frame(height: 1) }.padding(.bottom, 40)
                    .environment(\.layoutDirection, .rightToLeft).accessibilityIdentifier("money-ladder")
            }
        }
    }
    private func segment(_ minor: Int, _ peak: Int, _ tint: Color) -> some View {
        Rectangle().fill(tint).frame(height: visible ? 130 * CGFloat(minor) / CGFloat(peak) : 0)
    }
    private func key(_ title: String, _ tint: Color) -> some View {
        HStack(spacing: 4) { Rectangle().fill(tint).frame(width: 10, height: 10); Text(title).foregroundStyle(theme.secondaryInk) }
    }

    // MARK: The shelves

    private func shelves(_ r: MoneyObligationsReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DoubleRule().stroke(theme.color("reserveText"), lineWidth: 0.7).frame(height: 3)
            HStack(alignment: .firstTextBaseline) {
                Text("الرفوف").font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title3))
                Spacer()
                Text("كل التزام في مكانه").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
            shelf("الأقساط", r.installments, r)
            shelf("الفواتير", r.bills, r)
            shelf("الاشتراكات", r.subscriptions, r)
            shelf("كشوف البطاقات", r.statements, r)
        }
    }
    private func shelf(_ title: String, _ dues: [MoneyObligationDue], _ r: MoneyObligationsReading) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "sparkle").foregroundStyle(theme.color("reserve"))
                Text(title).font(.custom("thmanyahserifdisplay-Bold", size: 19, relativeTo: .headline))
                Spacer()
                Text(dues.isEmpty ? "—" : amount(dues.reduce(0) { $0 + $1.amountMinor })).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }.padding(.vertical, 8).overlay(alignment: .bottom) { DoubleRule().stroke(theme.color("reserveText"), lineWidth: 0.6).frame(height: 3) }
            if dues.isEmpty {
                Text("لا شيء على هذا الرفّ.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).padding(.vertical, 10)
            }
            ForEach(dues) { due in
                Button { withAnimation(.easeOut(duration: 0.2)) { selected = due.id } } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2).fill(color(due.group)).frame(width: 40, height: 28)
                            .overlay { RoundedRectangle(cornerRadius: 2).stroke(theme.color("reserve"), lineWidth: 1) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(due.name).font(.custom("thmanyahsans-Bold", size: 16, relativeTo: .body)).lineLimit(1)
                            Text(app.dateLabels(due.due, compact: true).combined).font(MadarTypography.fine())
                                .foregroundStyle(theme.secondaryInk)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(amount(due.amountMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 19, relativeTo: .headline))
                            Text(due.due >= r.cycleEnd ? "الدورة القادمة" : service.relative(r.today, due.due)).font(.custom("thmanyahsans-Bold", size: 12, relativeTo: .caption))
                                .foregroundStyle(MadarCalendarDays.distance(from: r.today, to: due.due) <= 3 ? theme.color("dueText") : theme.secondaryInk)
                        }
                    }.padding(.vertical, 10).padding(.horizontal, 8).background(current(r)?.id == due.id ? theme.surface : Color.clear)
                        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 0.6) }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("money-obligation-row-" + due.name)
            }
        }
    }

    private func load() {
        do { reading = try service.loadObligations(); failure = nil } catch { failure = "تعذّرت قراءة الالتزامات الآن." }
    }
}

/// A hanging lantern: a narrow top, a round body, a flat foot.
struct LanternShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(), w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.3, y: 0)); p.addLine(to: CGPoint(x: w * 0.7, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: h * 0.5), control: CGPoint(x: w, y: h * 0.1))
        p.addQuadCurve(to: CGPoint(x: w * 0.7, y: h), control: CGPoint(x: w, y: h * 0.9))
        p.addLine(to: CGPoint(x: w * 0.3, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h * 0.5), control: CGPoint(x: 0, y: h * 0.9))
        p.addQuadCurve(to: CGPoint(x: w * 0.3, y: 0), control: CGPoint(x: 0, y: h * 0.1))
        return p
    }
}
