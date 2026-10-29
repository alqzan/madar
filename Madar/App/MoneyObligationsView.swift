import SwiftUI
import MadarCore
import MadarData
import MadarDesign
import MadarMoney
import MadarCommands

/// «الالتزامات» (`mal/11-Z-R19-obl`): what this cycle owes on a thread from salary to salary, the instalment ladder of
/// the months ahead, and every obligation on its shelf.
struct MoneyObligationsView: View {
    private enum ObligationSheetRoute: Identifiable {
        case new
        case suggestion(SubscriptionSuggestionEngine.Suggestion)
        var id: String {
            switch self { case .new: "new"; case .suggestion(let value): "suggestion-" + value.id }
        }
        var suggestion: SubscriptionSuggestionEngine.Suggestion? {
            if case .suggestion(let value) = self { value } else { nil }
        }
    }

    let app: AppSession
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var reading: MoneyObligationsReading?
    @State private var failure: String?
    @State private var selected: String?
    @State private var obligationSheet: ObligationSheetRoute?
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
                    }.buttonStyle(.madarPlain).accessibilityLabel("إغلاق").accessibilityIdentifier("money-obligations-close")
                    Text("الالتزامات").font(.custom("thmanyahserifdisplay-Bold", size: 28, relativeTo: .title)).accessibilityAddTraits(.isHeader)
                    Spacer()
                }.padding(.top, 8)
                if let reading {
                    summary(reading)
                    if !visible { Button("أظهر الأرقام") { revealed = true }.font(MadarTypography.caption()).frame(minHeight: 44) }
                    thread(reading)
                    if let due = current(reading) { detail(due, reading) }
                    if reading.ladder.contains(where: { $0.total > 0 }) { ladder(reading) } else { Text("لا أقساط ولا فواتير في الأشهر القادمة؛ يظهر سلّمها هنا حين تضيف التزامًا.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-ladder-empty") }
                    ForEach(reading.subscriptionSuggestions) { suggestion in subscriptionSuggestion(suggestion) }
                    Button { obligationSheet = .new } label: {
                        Text("+ أضف التزامًا، وشاهد أثره على السلّم").font(.custom("thmanyahserifdisplay-Bold", size: 19, relativeTo: .headline)).foregroundStyle(theme.background)
                            .frame(maxWidth: .infinity, minHeight: 60).background(theme.ink).shadow(color: theme.ink.opacity(0.18), radius: 8, y: 4)
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("money-obligations-add")
                    shelves(reading)
                } else if let failure { Text(failure).font(MadarTypography.body()) }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 240) }
            }.padding(.horizontal, 16).padding(.bottom, 30).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.clipped().background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
            .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
            .task { load() }.onChange(of: app.prayerRevision) { load() }
            .sheet(item: $obligationSheet) { route in
                if let reading {
                    MoneyObligationSheet(app: app, ladder: reading.ladder, visible: visible, revealed: $revealed, suggestion: route.suggestion)
                        .environment(\.roomTheme, theme)
                }
            }
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
                Text(figure: amount(r.totalMinor)).font(.custom("thmanyahserifdisplay-Black", size: 58, relativeTo: .largeTitle)).lineLimit(1).minimumScaleFactor(0.5)
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
            Text(figure: amount(minor)).font(.custom("thmanyahsans-Bold", size: 15, relativeTo: .callout))
        }
    }

    // MARK: The thread, salary to salary

    private func thread(_ r: MoneyObligationsReading) -> some View {
        let length = max(1, MadarCalendarDays.distance(from: r.cycleStart, to: r.cycleEnd))
        let elapsed = min(length, max(0, MadarCalendarDays.distance(from: r.cycleStart, to: r.today)))
        return Group {
            if dynamicType.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(r.cycle) { due in Button { selected = due.id } label: { HStack { Text(due.name); Spacer(); Text(figure: amount(due.amountMinor)) }.contentShape(.rect) }.buttonStyle(.madarPlain) }
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
                        // OR-24 (owner: a clearer timeline): close dues fan out sideways first, each on a short slanted string
                        // from its real day, and neighbours alternate between two heights as in the design.
                        let trueX = r.cycle.map { x(MadarCalendarDays.distance(from: r.cycleStart, to: $0.due)) }
                        let shownX = spread(trueX, gap: 44, low: 37, high: proxy.size.width - 37)
                        let levels = lanternLevels(shownX)
                        ForEach(Array(r.cycle.enumerated()), id: \.element.id) { index, due in
                            Path { p in p.move(to: CGPoint(x: trueX[index], y: 31)); p.addLine(to: CGPoint(x: shownX[index], y: 41)) }
                                .stroke(theme.color("reserveText"), lineWidth: 1)
                            Button { withAnimation(.easeOut(duration: 0.2)) { selected = due.id } } label: { lantern(due, drop: 14 + CGFloat(levels[index]) * 76, active: current(r)?.id == due.id) }
                                .buttonStyle(.madarPlain).frame(width: 74).offset(x: shownX[index] - 37, y: 31)
                                // Higher lanterns sit above the strings of the ones hanging below them.
                                .zIndex(-Double(levels[index]))
                                .accessibilityIdentifier("money-obligation-lantern-" + due.name)
                        }
                    }.environment(\.layoutDirection, .leftToRight)
                }.frame(height: 130 + CGFloat(threadDepth(r)) * 76).accessibilityIdentifier("money-obligations-thread")
            }
        }
    }
    /// Lanterns still closer than one label's width hang one row lower, so no two labels overlap.
    private func lanternLevels(_ xs: [CGFloat]) -> [Int] {
        // In order along the thread, so close neighbours alternate rows instead of piling up.
        var lastX: [CGFloat] = [], levels = Array(repeating: 0, count: xs.count)
        for index in xs.indices.sorted(by: { xs[$0] < xs[$1] }) {
            let x = xs[index]
            if let free = lastX.firstIndex(where: { abs($0 - x) >= 76 }) { lastX[free] = x; levels[index] = free }
            else { lastX.append(x); levels[index] = lastX.count - 1 }
        }
        return levels
    }
    /// Pushes neighbouring positions apart to at least `gap`, keeping their order and staying inside the thread.
    private func spread(_ xs: [CGFloat], gap: CGFloat, low: CGFloat, high: CGFloat) -> [CGFloat] {
        let order = xs.indices.sorted { xs[$0] < xs[$1] }
        var v = order.map { min(high, max(low, xs[$0])) }
        for _ in 0..<40 {
            for i in v.indices.dropFirst() where v[i] - v[i - 1] < gap { let push = (gap - (v[i] - v[i - 1])) / 2; v[i - 1] -= push; v[i] += push }
            for i in v.indices { v[i] = min(high, max(low, v[i])) }
        }
        var result = xs
        for (k, index) in order.enumerated() { result[index] = v[k] }
        return result
    }
    private func threadDepth(_ r: MoneyObligationsReading) -> Int {
        let length = max(1, MadarCalendarDays.distance(from: r.cycleStart, to: r.cycleEnd)), w: CGFloat = 340
        let xs = r.cycle.map { w - CGFloat(MadarCalendarDays.distance(from: r.cycleStart, to: $0.due)) / CGFloat(length) * w + 12 }
        return lanternLevels(spread(xs, gap: 44, low: 37, high: w + 24 - 37)).max() ?? 0
    }
    private func lantern(_ due: MoneyObligationDue, drop: CGFloat, active: Bool) -> some View {
        let tint = color(due.group), outline = due.group == .statement
        return VStack(spacing: 3) {
            Rectangle().fill(theme.color("reserveText")).frame(width: 1, height: drop)
            ZStack {
                LanternShape().fill(outline ? theme.background : tint)
                LanternShape().stroke(outline ? tint : theme.color("reserve"), lineWidth: active ? 3 : 1.5)
                if !outline { Circle().fill(theme.background.opacity(0.85)).frame(width: 6, height: 6).offset(y: 2) }
            }.frame(width: 26, height: 30).scaleEffect(active ? 1.15 : 1)
            VStack(spacing: 3) {
                Text(figure: amount(due.amountMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 15, relativeTo: .callout)).lineLimit(1).minimumScaleFactor(0.74)
                Text(due.name).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1)
            }.padding(.horizontal, 3).background(theme.background, in: .rect(cornerRadius: 4))
        }
    }

    // MARK: The selected obligation

    private func detail(_ due: MoneyObligationDue, _ r: MoneyObligationsReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(due.name).font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title3))
                Spacer(minLength: 8)
                Text(figure: amount(due.amountMinor)).font(.custom("thmanyahserifdisplay-Black", size: 26, relativeTo: .title2))
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
                }.environment(\.layoutDirection, .rightToLeft).accessibilityLabel("دفعت " + service.digits.string(paid) + " من " + service.counted(total, ("دفعة واحدة", "دفعتين", "دفعات", "دفعة")))
                HStack(spacing: 4) {
                    Text((paid == 0 ? "لم تدفع بعد من " : "دفعت " + service.digits.string(paid) + " من ") + service.counted(total, ("دفعة واحدة", "دفعتين", "دفعات", "دفعة")) + (due.remainingMinor.map { "، يبقى " + amount($0) } ?? "، والمتبقي غير معروف") + (due.lastDue == nil ? "" : "، وآخر دفعة"))
                    if let last = due.lastDue { MadarDateLabel(app.dateLabels(last, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()) }
                }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-obligation-progress")
            } else if let schedule = due.schedule {
                Text((due.group == .subscription ? "اشتراك يتكرر " : "فاتورة تتكرر ") + schedule).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    .accessibilityIdentifier("money-obligation-schedule")
            } else if let day = due.dueDay {
                Text("فاتورة تتكرر يوم " + service.digits.string(day) + " من كل شهر").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
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
                ForEach(r.ladder) { month in HStack { Text(month.label + "، " + month.hijri); Spacer(); Text(figure: amount(month.total)) } }
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
                            Text(figure: amount(due.amountMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 19, relativeTo: .headline))
                            Text(due.due >= r.cycleEnd ? "الدورة القادمة" : service.relative(r.today, due.due)).font(.custom("thmanyahsans-Bold", size: 12, relativeTo: .caption))
                                .foregroundStyle(MadarCalendarDays.distance(from: r.today, to: due.due) <= 3 ? theme.color("dueText") : theme.secondaryInk)
                        }
                    }.padding(.vertical, 10).padding(.horizontal, 8).background(current(r)?.id == due.id ? theme.surface : Color.clear)
                        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 0.6) }.contentShape(Rectangle())
                }.buttonStyle(.madarPlain).accessibilityIdentifier("money-obligation-row-" + due.name)
            }
        }
    }

    @ViewBuilder private func subscriptionSuggestion(_ suggestion: SubscriptionSuggestionEngine.Suggestion) -> some View {
        let card = Button {
            obligationSheet = .suggestion(suggestion)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("تكرّر عندك في " + service.counted(suggestion.count, ("شهر واحد", "شهرين متتاليين", "أشهر متتالية", "شهرًا متتاليًا")))
                            .font(MadarTypography.fine().weight(.semibold)).foregroundStyle(theme.color("reserveText")).lineLimit(1)
                        HStack(spacing: 5) {
                            Text(suggestion.name).font(.custom("thmanyahserifdisplay-Bold", size: 19, relativeTo: .title3)).lineLimit(1)
                            Text("،").foregroundStyle(theme.secondaryInk)
                            Text(figure: amount(suggestion.amountMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 19, relativeTo: .title3))
                                .accessibilityIdentifier("money-subscription-suggestion-amount")
                        }
                    }
                    Spacer(minLength: 6)
                    Text("راجع وثبّت").font(MadarTypography.caption().weight(.semibold)).foregroundStyle(theme.ink)
                        .padding(.horizontal, 10).frame(minHeight: 40)
                        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(theme.color("reserveText"), lineWidth: 1) }
                }
                HStack(spacing: 5) {
                    ForEach(Array(suggestion.evidenceDates.enumerated()), id: \.offset) { _, date in
                        let day = GregorianDay.containing(date, in: app.activePlace.timeZone)
                        MadarDateLabel(app.dateLabels(day, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine())
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .center)
                            .padding(.horizontal, 3)
                    }
                }
                HStack(alignment: .center, spacing: 8) {
                    Text("يتكرر كل شهر · موعده القادم").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    MadarDateLabel(app.dateLabels(.containing(suggestion.nextDue, in: app.activePlace.timeZone), compact: true),
                                   primaryFont: MadarTypography.fine().weight(.semibold), secondaryFont: MadarTypography.fine())
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.madarPlain)
        .accessibilityLabel("اشتراك محتمل من مدفوعاتك، \(suggestion.name)، \(amount(suggestion.amountMinor))، راجع التفاصيل")
        .accessibilityIdentifier("money-subscription-suggestion")

        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                card.glassEffect(.regular.tint(theme.color("reserve").opacity(0.12)).interactive(), in: .rect(cornerRadius: 18, style: .continuous))
            }.overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.color("reserveText").opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        } else {
            card.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.color("reserveText").opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
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
