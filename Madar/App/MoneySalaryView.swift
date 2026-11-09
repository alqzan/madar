import SwiftUI
import MadarCore
import MadarData
import MadarDesign
import MadarMoney
import MadarCommands

/// «نزل الراتب» (`mal/10-Z-R19-sal2`): the cycle report as a ledger. Every figure comes from `SalaryOpening.plan`, the same
/// plan `money.confirmSalary` writes; nothing is written until «اعتمد الراتب وافتح الدورة».
struct MoneySalaryView: View {
    let app: AppSession
    let salaryID: UUID
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var reading: MoneySalaryReading?
    @State private var failure: String?
    @State private var confirmFailed = false
    @State private var adjustFailed = false
    @State private var selected: String?
    @State private var remainderTo: SalaryRemainder?
    @State private var revealed = false
    @State private var busy = false
    /// The preview's cycle id becomes the command id, so the rows previewed are the rows written.
    @State private var commandID = UUID()
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var service: AppMoneyService { .init(app: app) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private func amount(_ minor: Int) -> String { visible ? service.amount(minor) : "•••" }
    private func signed(_ minor: Int) -> String { visible ? (minor > 0 ? "+" : minor < 0 ? "−" : "") + service.amount(abs(minor)) : "•••" }
    private func tint(_ key: String) -> Color { key == "ink" ? theme.ink : theme.color(key + "Text") }

    var body: some View { screen.hidesMoneyInBackground($revealed) }
    @ViewBuilder private var screen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let reading {
                    masthead(reading)
                    opening(reading)
                    if !visible { Button("أظهر الأرقام") { revealed = true }.font(MadarTypography.caption()).frame(minHeight: 44) }
                    ledger(reading)
                    if reading.needsChoice || remainderTo != nil { remainderChoice(reading) }
                    confirmButton(reading)
                    summary(reading)
                    if reading.history.count > 1 { carryFigure(reading) }
                    if !reading.opening.envelopes.isEmpty { envelopes(reading) }
                } else if let failure {
                    Text(failure).font(MadarTypography.body()).accessibilityIdentifier("money-salary-failure")
                    Button("أعِد المحاولة", action: load).frame(minHeight: 44).accessibilityIdentifier("money-salary-retry")
                } else { ProgressView().frame(maxWidth: .infinity, minHeight: 240) }
            }.padding(.horizontal, 16).padding(.bottom, 30).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.clipped().background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
            .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
            .task { load() }.onChange(of: app.prayerRevision) { load() }
            .madarSheetLock(saving: busy)
            .accessibilityIdentifier("money-salary")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.title3).frame(width: 52, height: 52).glassEffect(.regular.interactive(), in: .circle)
            }.buttonStyle(.madarPlain).disabled(busy).accessibilityLabel("إغلاق").accessibilityIdentifier("money-salary-close")
            Text("نزل الراتب").font(.custom("thmanyahserifdisplay-Bold", size: 28, relativeTo: .title)).accessibilityAddTraits(.isHeader)
            Spacer()
        }.padding(.top, 8).environment(\.layoutDirection, .rightToLeft)
    }

    private func masthead(_ r: MoneySalaryReading) -> some View {
        HStack(spacing: 8) {
            Text("مدار، تقرير الدورة").font(.custom("thmanyahsans-Bold", size: 13, relativeTo: .caption))
            Spacer(minLength: 6)
            Text("مسودة").font(.custom("thmanyahsans-Bold", size: 13, relativeTo: .caption)).foregroundStyle(theme.color("reserveText"))
            MadarDateLabel(app.dateLabels(r.today, compact: true, weekday: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine())
        }.foregroundStyle(theme.background).padding(.horizontal, 12).padding(.vertical, 8).background(theme.ink)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.color("reserve")).frame(height: 2).offset(y: 4) }
    }

    private func opening(_ r: MoneySalaryReading) -> some View {
        let length = r.opening.input.expectedLengthDays
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("افتتاح الدورة، " + service.days(length)).font(.custom("thmanyahsans-Bold", size: 13, relativeTo: .caption)).foregroundStyle(theme.color("reserveText"))
                Text(r.cycleName).font(.custom("thmanyahserifdisplay-Black", size: 34, relativeTo: .largeTitle)).lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityIdentifier("money-salary-cycle")
                HStack(alignment: .top, spacing: 6) {
                    MadarDateLabel(app.dateLabels(r.opening.startDay, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine())
                    Text("←").font(MadarTypography.fine())
                    MadarDateLabel(app.dateLabels(r.opening.endDay, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine())
                }.foregroundStyle(theme.secondaryInk)
                keyFigures(r)
            }
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("التقييم").font(MadarTypography.fine())
                    Text(r.ratingWord).font(.custom("thmanyahserifdisplay-Black", size: 30, relativeTo: .title)).lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: 4) { ForEach(0..<3, id: \.self) { _ in Capsule().frame(height: 3) } }.padding(.horizontal, 18)
                }.foregroundStyle(theme.background).padding(10).frame(maxWidth: .infinity)
                    .background(theme.color(r.ratingTint)).overlay { Rectangle().stroke(theme.background, lineWidth: 1.5).padding(4) }
                    .accessibilityElement(children: .combine).accessibilityIdentifier("money-salary-rating")
                VStack(spacing: 2) {
                    Text("اليومية المستهدفة").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    Text(figure: amount(r.plan.rate.dailyRateMinor)).font(.custom("thmanyahserifdisplay-Black", size: 52, relativeTo: .largeTitle)).lineLimit(1).minimumScaleFactor(0.5)
                        .accessibilityIdentifier("money-salary-daily")
                    if let previous = r.opening.previousDailyMinor {
                        Text(figure: "السابقة " + amount(previous) + "، " + (r.opening.previousMode == "percent" ? "نسبة" : "ثابتة")).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    }
                }
            }.frame(width: 150)
        }.environment(\.layoutDirection, .rightToLeft)
    }

    private func keyFigures(_ r: MoneySalaryReading) -> some View {
        let salary = r.opening.salaryMinor, plan = r.plan
        let destination = plan.toReserveMinor == 0 && plan.toSurplusMinor > 0 ? "الفوائض" : plan.toSurplusMinor == 0 && plan.toReserveMinor > 0 ? "الاحتياطي" : "الفوائض ثم الاحتياطي"
        return VStack(spacing: 0) {
            HStack { Text("أرقام رئيسية").bold().foregroundStyle(theme.color("reserveText")); Spacer(); Text("٪").foregroundStyle(theme.secondaryInk) }
                .font(MadarTypography.fine()).padding(.vertical, 5).overlay(alignment: .top) { Rectangle().fill(theme.ink).frame(height: 1.2) }
            figure("الراتب", amount(salary), service.percent(salary, of: salary), theme.ink)
            figure("الالتزامات", signed(-plan.obligationsMinor), service.percent(plan.obligationsMinor, of: salary), tint("accent"))
            figure("المظاريف", signed(-plan.envelopesMinor), service.percent(plan.envelopesMinor, of: salary), tint("bills"))
            figure("يومياتك " + service.days(r.opening.input.expectedLengthDays), signed(-plan.dailiesMinor), service.percent(plan.dailiesMinor, of: salary), tint("surplus"))
            HStack {
                Text(plan.leftoverMinor >= 0 ? "الباقي ← " + destination : "الباقي").bold()
                Spacer(minLength: 4)
                Text(figure: amount(plan.leftoverMinor)).bold().foregroundStyle(plan.leftoverMinor >= 0 ? tint("reserve") : tint("due"))
                Text(plan.leftoverMinor < 0 ? "" : service.percent(plan.leftoverMinor, of: salary)).foregroundStyle(theme.secondaryInk).frame(width: 34, alignment: .trailing)
            }.font(MadarTypography.fine()).padding(.vertical, 5).overlay(alignment: .top) { Rectangle().fill(theme.ink).frame(height: 1.2) }
                .accessibilityIdentifier("money-salary-leftover")
            if let carried = r.opening.input.closing?.availableNowMinor {
                HStack {
                    Text(carried >= 0 ? "الفائض المرحّل" : "العجز المرحّل")
                    Spacer(minLength: 4)
                    Text(figure: signed(carried) + " " + carryWord(r)).foregroundStyle(carried >= 0 ? tint("surplus") : tint("due"))
                }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).padding(.vertical, 5).accessibilityIdentifier("money-salary-carry")
            }
        }
    }
    private func carryWord(_ r: MoneySalaryReading) -> String {
        guard let close = r.plan.close else { return "" }
        if close.offsetMinor > 0 { return close.carryMinor < 0 ? "مقاصة جزئية" : "مقاصة من الفوائض" }
        if close.carryMinor < 0 { return "يُرحَّل" }
        if close.toReserveMinor > 0 { return close.toSurplusMinor > 0 ? "فوائض ثم احتياطي" : "احتياطي" }
        return "فوائض"
    }
    private func figure(_ title: String, _ value: String, _ share: String, _ color: Color) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 4)
            Text(figure: value).foregroundStyle(color).lineLimit(1)
            Text(share).foregroundStyle(theme.secondaryInk).frame(width: 34, alignment: .trailing)
        }.font(MadarTypography.fine()).padding(.vertical, 5).overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 0.6) }
    }

    // MARK: Table 1, the ledger

    private func ledger(_ r: MoneySalaryReading) -> some View {
        let salary = max(1, r.opening.salaryMinor)
        return VStack(alignment: .leading, spacing: 10) {
            DoubleRule().stroke(theme.color("reserveText"), lineWidth: 0.7).frame(height: 3)
            HStack(alignment: .firstTextBaseline) {
                Text("الجدول ١، دفتر القيد").font(.custom("thmanyahserifdisplay-Bold", size: 21, relativeTo: .title3))
                Spacer()
                Text("الرصيد بعد كل قيد").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
            ForEach(r.entries) { entry in
                Button { withAnimation(.easeOut(duration: 0.2)) { selected = selected == entry.id ? nil : entry.id } } label: { ledgerRow(entry, salary: salary) }
                    .buttonStyle(.madarPlain).accessibilityIdentifier("money-salary-entry-" + entry.id)
                if selected == entry.id {
                    Text(entry.explanation).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .overlay { Rectangle().stroke(theme.color("reserveText"), style: .init(lineWidth: 1, dash: [3, 2])) }
                        .accessibilityIdentifier("money-salary-explanation")
                }
            }
            HStack(spacing: 6) {
                Rectangle().fill(theme.color("reserve")).frame(height: 1)
                Image(systemName: "sparkle").foregroundStyle(theme.color("reserve"))
                Rectangle().fill(theme.color("reserve")).frame(height: 1)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("الباقي").font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title3))
                    Text(figure: amount(r.plan.leftoverMinor)).font(.custom("thmanyahserifdisplay-Black", size: 44, relativeTo: .largeTitle))
                        .foregroundStyle(r.plan.leftoverMinor >= 0 ? tint("reserve") : tint("due")).lineLimit(1).minimumScaleFactor(0.5)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    if r.plan.toSurplusMinor > 0 { split("للفوائض", r.plan.toSurplusMinor) }
                    if r.plan.toReserveMinor > 0 { split("للاحتياطي", r.plan.toReserveMinor) }
                    if r.plan.awaitingChoiceMinor > 0 { split("ينتظر اختيارك", r.plan.awaitingChoiceMinor) }
                }
            }
            GeometryReader { proxy in
                let w = proxy.size.width * CGFloat(max(0, r.plan.leftoverMinor)) / CGFloat(salary)
                Rectangle().fill(theme.color("reserve")).frame(width: visible ? w : 0, height: 26).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 26).environment(\.layoutDirection, .leftToRight)
        }
    }
    private func split(_ title: String, _ minor: Int) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            Text(figure: amount(minor)).font(.custom("thmanyahserifdisplay-Bold", size: 17, relativeTo: .headline))
        }
    }
    /// A waterfall step: the bar spans what this entry moved, measured from the right (the salary's start).
    private func ledgerRow(_ e: MoneySalaryEntry, salary: Int) -> some View {
        let before = e.amountMinor > 0 ? 0 : e.balanceMinor - e.amountMinor
        let hi = e.amountMinor > 0 ? e.amountMinor : before, lo = e.amountMinor > 0 ? 0 : max(0, e.balanceMinor)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(e.title).font(.custom("thmanyahsans-Bold", size: 16, relativeTo: .body))
                Text(figure: signed(e.amountMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 19, relativeTo: .headline)).foregroundStyle(tint(e.tint))
                Spacer(minLength: 6)
                Text(figure: amount(e.balanceMinor)).font(.custom("thmanyahsans-Regular", size: 15, relativeTo: .callout)).foregroundStyle(theme.secondaryInk)
            }
            GeometryReader { proxy in
                let w = proxy.size.width, unit = w / CGFloat(salary)
                let width = visible ? max(e.amountMinor == 0 ? 0 : 3, CGFloat(max(0, hi - lo)) * unit) : 0
                Rectangle().fill(e.tint == "ink" ? theme.ink : theme.color(e.tint)).frame(width: width, height: 18)
                    .offset(x: CGFloat(max(0, salary - hi)) * unit)
            }.frame(height: 18)
        }.contentShape(Rectangle())
    }

    private func remainderChoice(_ r: MoneySalaryReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("إلى أين يذهب الباقي؟").font(MadarTypography.cardTitle())
            HStack(spacing: 10) {
                choice("الفوائض ثم الاحتياطي", .surplusThenReserve)
                choice("الاحتياطي", .reserve)
            }
        }
    }
    private func choice(_ title: String, _ value: SalaryRemainder) -> some View {
        Button { remainderTo = value; load() } label: {
            Text(title).font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(remainderTo == value ? theme.background : theme.ink)
                .background(remainderTo == value ? theme.ink : .clear).overlay { Rectangle().stroke(theme.ink, lineWidth: 1) }
        }.buttonStyle(.madarPlain).accessibilityAddTraits(remainderTo == value ? .isSelected : [])
    }

    private func confirmButton(_ r: MoneySalaryReading) -> some View {
        let blocked = r.needsChoice && remainderTo == nil
        return VStack(spacing: 4) { Button(action: confirm) {
            Text("اعتمد الراتب وافتح الدورة").font(.custom("thmanyahserifdisplay-Bold", size: 20, relativeTo: .headline)).foregroundStyle(theme.background)
                .frame(maxWidth: .infinity, minHeight: 60).background(theme.ink.opacity(blocked || busy ? 0.4 : 1))
                .shadow(color: theme.ink.opacity(0.18), radius: 8, y: 4)
        }.buttonStyle(.madarPlain).disabled(blocked || busy).accessibilityIdentifier("money-salary-confirm").padding(.vertical, 6)
            // A failed confirm used to reload silently; say so under the button.
            if confirmFailed { Text("لم يُعتمد الراتب. حاول مرة أخرى.").font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")).accessibilityIdentifier("money-salary-confirm-failed") }
        }
    }

    private func summary(_ r: MoneySalaryReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DoubleRule().stroke(theme.color("reserveText"), lineWidth: 0.7).frame(height: 3)
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "sparkle").foregroundStyle(theme.color("reserve"))
                Text("ملخّص المحلّل").font(.custom("thmanyahserifdisplay-Bold", size: 21, relativeTo: .title3))
                Spacer()
                Text("قرأه مدار من رسائلك").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
            if visible, let previous = r.opening.previousDailyMinor {
                dailyComparison(previous: previous, current: r.plan.rate.dailyRateMinor)
            }
            ForEach(r.bullets.filter { $0.id.hasPrefix("short-") } + r.bullets.filter { !$0.id.hasPrefix("short-") }) { bullet in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "diamond.fill").font(.caption2).foregroundStyle(theme.color(bullet.tint))
                    Text(visible ? bullet.text : "•••").font(MadarTypography.body()).fixedSize(horizontal: false, vertical: true)
                }.accessibilityIdentifier("money-salary-bullet-" + bullet.id)
            }
        }
    }

    /// Both amounts are the engine's daily rates; the bars compare them without changing the plan.
    private func dailyComparison(previous: Int, current: Int) -> some View {
        let peak = max(1, max(previous, current))
        return VStack(alignment: .leading, spacing: 10) {
            Text(current == previous ? "يوميتك كما في الدورة السابقة" : current > previous ? "يوميتك أعلى من الدورة السابقة" : "يوميتك أقل من الدورة السابقة")
                .font(MadarTypography.section())
            comparisonRow("السابقة", value: previous, peak: peak, color: theme.secondaryInk)
            comparisonRow("هذه الدورة", value: current, peak: peak, color: theme.color("reserveText"))
        }.padding(.vertical, 6).accessibilityElement(children: .contain).accessibilityIdentifier("money-salary-daily-comparison")
    }
    private func comparisonRow(_ title: String, value: Int, peak: Int, color: Color) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title).foregroundStyle(theme.secondaryInk)
                Spacer()
                Text(figure: amount(value)).foregroundStyle(theme.ink)
            }.font(MadarTypography.caption())
            GeometryReader { geometry in
                Capsule().fill(theme.line)
                Capsule().fill(color).frame(width: geometry.size.width * CGFloat(max(0, value)) / CGFloat(peak))
            }.frame(height: 5).accessibilityHidden(true)
        }
    }

    // MARK: Figure 1, the carried surplus

    private func carryFigure(_ r: MoneySalaryReading) -> some View {
        let peak = max(1, r.history.map { abs($0.carriedMinor) }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(theme.line).frame(height: 1)
            Text("الشكل ١، الفائض المرحّل").font(.custom("thmanyahserifdisplay-Bold", size: 21, relativeTo: .title3))
            Text("آخر " + service.counted(r.history.count, ("دورة", "دورتين", "دورات", "دورةً")) + "، والأخيرة هي التي تُغلق الآن").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            if dynamicType.isAccessibilitySize {
                ForEach(r.history) { bar in HStack { Text(bar.label); Spacer(); Text(figure: signed(bar.carriedMinor)) } }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    ForEach(r.history) { bar in carryBar(bar, peak: peak) }
                }.frame(height: 170)
            }
            HStack {
                Text("الفوائض بعدها").foregroundStyle(theme.secondaryInk)
                Text(figure: amount(r.surplusAfterMinor)).bold()
                Spacer()
            }.font(MadarTypography.caption()).accessibilityIdentifier("money-salary-surplus-after")
        }.accessibilityIdentifier("money-salary-history")
    }
    private func carryBar(_ bar: MoneySalaryHistoryBar, peak: Int) -> some View {
        let positive = bar.carriedMinor >= 0, height = visible ? max(3, 70 * CGFloat(abs(bar.carriedMinor)) / CGFloat(peak)) : 3
        let fill = bar.current ? theme.color("reserve") : positive ? theme.color("surplus") : theme.color("due")
        return VStack(spacing: 4) {
            VStack(spacing: 3) {
                Spacer(minLength: 0)
                if positive { Text(figure: signed(bar.carriedMinor)).font(.custom("thmanyahsans-Bold", size: 11, relativeTo: .caption2)).lineLimit(1)
                    Rectangle().fill(fill).frame(height: height).overlay { if bar.current { Rectangle().stroke(theme.ink, lineWidth: 2) } } }
            }.frame(height: 88)
            Rectangle().fill(theme.ink).frame(height: 1)
            VStack(spacing: 3) {
                if !positive { Rectangle().fill(fill).frame(height: height).overlay { if bar.current { Rectangle().stroke(theme.ink, lineWidth: 2) } }
                    Text(figure: signed(bar.carriedMinor)).font(.custom("thmanyahsans-Bold", size: 11, relativeTo: .caption2)).foregroundStyle(tint("due")).lineLimit(1) }
                Spacer(minLength: 0)
            }.frame(height: 50)
            Text(bar.current ? bar.label + "، هذه" : bar.label).font(.custom(bar.current ? "thmanyahsans-Bold" : "thmanyahsans-Regular", size: 12, relativeTo: .caption))
                .foregroundStyle(bar.current ? theme.ink : theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.92)
        }.frame(maxWidth: .infinity)
    }

    // MARK: Envelopes this cycle

    private func envelopes(_ r: MoneySalaryReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(theme.line).frame(height: 1)
            HStack(alignment: .firstTextBaseline) {
                Text("مظاريف هذه الدورة").font(.custom("thmanyahserifdisplay-Bold", size: 21, relativeTo: .title3))
                Spacer()
                if r.opening.envelopes.contains(where: \.adjustable) { Text("عدّلها قبل الاعتماد").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                ForEach(r.opening.envelopes) { envelopeCard($0) }
            }.environment(\.layoutDirection, .rightToLeft)
            if adjustFailed { Text("لم يُحفظ التعديل؛ تحدّثت الأرقام، فعدّل من جديد.").font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")).accessibilityIdentifier("money-salary-adjust-failed") }
        }
    }
    private func envelopeCard(_ e: SalaryOpeningReading.EnvelopeLine) -> some View {
        let color = e.repay ? theme.color("due") : theme.color("bills")
        return VStack(spacing: 6) {
            Text(e.name).font(.custom("thmanyahsans-Bold", size: 15, relativeTo: .callout)).lineLimit(1).minimumScaleFactor(0.74)
            Text(figure: amount(e.amountMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title3))
            if let line = completion(e) { Text(line).font(MadarTypography.fine()).foregroundStyle(tint("surplus")).lineLimit(2).multilineTextAlignment(.center) }
            if e.adjustable {
                HStack(spacing: 6) {
                    stepper("minus", e, -5_000)
                    stepper("plus", e, 5_000)
                }.environment(\.layoutDirection, .leftToRight)
            }
        }.padding(10).frame(maxWidth: .infinity).background(theme.surface)
            .overlay(alignment: .top) { Rectangle().fill(color).frame(height: 3) }.overlay { Rectangle().stroke(theme.line, lineWidth: 1) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("money-salary-envelope-" + e.name)
    }
    /// «يكتمل بعد ٢ راتبين» from the target, the balance and the share; a repayment counts down its debt.
    private func completion(_ e: SalaryOpeningReading.EnvelopeLine) -> String? {
        if e.repay { return e.balanceMinor < 0 ? "سداد، يبقى " + amount(-e.balanceMinor) : nil }
        guard let target = e.targetMinor, e.amountMinor > 0 else { return nil }
        let left = target - e.balanceMinor
        guard left > 0 else { return "اكتمل" }
        let salaries = (left + e.amountMinor - 1) / e.amountMinor
        return salaries == 1 ? "يكتمل بهذا الراتب" : salaries == 2 ? "يكتمل بعد راتبين" : "يكتمل بعد " + service.counted(salaries, ("راتب", "راتبين", "رواتب", "راتبًا"))
    }
    private func stepper(_ symbol: String, _ e: SalaryOpeningReading.EnvelopeLine, _ delta: Int) -> some View {
        Button {
            run("money.setEnvelopeSaving", ["id": .string(e.planID.uuidString), "amountMinor": .string(String(max(0, e.amountMinor + delta))), "expectedMinor": .string(String(e.amountMinor))])
        } label: {
            Image(systemName: symbol).font(.body).frame(maxWidth: .infinity, minHeight: 44).overlay { Rectangle().stroke(theme.ink, lineWidth: 1) }
        }.buttonStyle(.madarPlain).disabled(busy || (delta < 0 && e.amountMinor == 0))
            .accessibilityLabel((delta > 0 ? "زد " : "أنقص ") + e.name + " " + (visible ? service.amount(abs(delta)) : "•••"))
    }

    // MARK: Actions

    private func load() {
        do { reading = try service.loadSalary(id: salaryID, previewCycle: commandID, remainderTo: remainderTo); failure = nil }
        catch MoneyCommandError.invalidAmount { reading = nil; failure = "اضبط يومك في الإعدادات أولًا؛ التقرير يحسب على اليومية." }
        catch MoneyCommandError.salaryNeedsCycleConfirmation { reading = nil; failure = "قد يكون هذا الراتب مكرّرًا أو أقدم من الدورة المفتوحة؛ احسمه من رسائل البنك أولًا." }
        catch MoneyCommandError.missingRow { reading = nil; failure = "هذا الراتب اعتُمد أو حُذف." }
        catch { reading = nil; failure = "تعذّر قراءة الراتب الآن." }
    }
    private func confirm() {
        var payload: [String: MadarCore.JSONValue] = ["id": .string(salaryID.uuidString)]
        if let remainderTo { payload["remainderTo"] = .string(remainderTo == .reserve ? "reserve" : "surplus") }
        busy = true; confirmFailed = false
        Task {
            do { try await app.executeMoneyCommand("money.confirmSalary", payload: payload, id: commandID); busy = false; dismiss() }
            catch { busy = false; commandID = UUID(); load(); if reading != nil { failure = nil }; confirmFailed = true }
        }
    }
    private func run(_ name: String, _ payload: [String: MadarCore.JSONValue]) {
        busy = true; adjustFailed = false
        // AU-40: a refused ± says so; the numbers reload either way.
        Task {
            do { try await app.executeMoneyCommand(name, payload: payload) } catch { adjustFailed = true }
            busy = false; load()
        }
    }
}
