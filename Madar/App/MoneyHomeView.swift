import SwiftUI
import MadarCore
import MadarData
import MadarDesign
import MadarMoney
import MadarCommands

struct MoneyHomeView: View {
    @Bindable var app: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.scenePhase) private var scenePhase
    @State private var reading: MoneyHomeReading?
    @State private var failure: String?
    @State private var revealed = false
    @State private var basisOpen = false
    @State private var envelopesOpen = false
    private var service: AppMoneyService { .init(app: app) }
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var amountsVisible: Bool { !app.bool("core.hideMoneyUntilTouch") || revealed }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                if let reading {
                    if let cycle = reading.cycle {
                        if dynamicType.isAccessibilitySize { cycleSummary(cycle) }
                        else { MoneyScrollChart(cycle: cycle, app: app, visible: amountsVisible, obligations: reading.obligations).frame(height: 224) }
                        headline(reading, cycle: cycle)
                    } else { firstPage(reading) }
                    envelopeSection(reading)
                    lowerDesk(reading)
                } else if let failure {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("لم تكتمل قراءة المال").font(MadarTypography.cardTitle())
                        Text(failure).font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                        Button("أعِد المحاولة", action: load).frame(minHeight: 44)
                    }.padding(20)
                } else { ProgressView().frame(maxWidth: .infinity, minHeight: 300) }
            }.padding(.horizontal, 16).padding(.top, 0).padding(.bottom, 30).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .clipped().background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
        .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $envelopesOpen) { MoneyEnvelopesView(app: app, revealed: $revealed) }
        .sheet(isPresented: $basisOpen) { MoneyBasisView(app: app, revealed: $revealed) }
        .task {
            do { try await app.executeMoneyCommand("money.accruePlans") } catch { }
            load()
        }.onChange(of: app.prayerRevision) { load() }
        .onChange(of: app.bool("core.hideMoneyUntilTouch")) { revealed = false }
        .onChange(of: app.selectedTab) { revealed = false }
        .onChange(of: scenePhase) { if scenePhase != .active { revealed = false } }
        .accessibilityIdentifier("money-home")
    }
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("المال").font(MadarTypography.title()).accessibilityIdentifier("money-title")
            if let cycle = reading?.cycle {
                let left = max(0, MadarCalendarDays.distance(from: cycle.today, to: cycle.expectedEndDay))
                Text(left == 0 ? "موعد الراتب اليوم" : "بقي للراتب " + service.days(left)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }
            Spacer(minLength: 0)
            if let count = reading?.pendingCount, count > 0 {
                HStack(spacing: 5) { Image(systemName: "tray"); Text(service.digits.string(count)) }
                    .font(MadarTypography.fine()).padding(.horizontal, 9).padding(.vertical, 7)
                    .overlay { Capsule().stroke(theme.color("reserveText"), lineWidth: 1) }
                    .accessibilityElement(children: .ignore).accessibilityLabel(service.pending(count)).accessibilityIdentifier("money-pending")
            }
            Button { dismiss() } label: { Image(systemName: "chevron.backward").font(.body).frame(width: 44, height: 44) }
                .buttonStyle(.plain).accessibilityLabel("العودة").accessibilityIdentifier("money-back")
        }.frame(minHeight: 48)
    }
    private func headline(_ reading: MoneyHomeReading, cycle: MoneyCycleReading) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("اليوم").font(MadarTypography.section())
                Spacer()
                Text("صرفت " + amount(cycle.headline.todaySpentMinor) + " من " + amount(cycle.headline.todayAllowanceMinor))
                    .font(MadarTypography.body()).accessibilityIdentifier("money-today")
            }
            HStack(alignment: .center) {
                Button { basisOpen = true } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("لك الآن").font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)).foregroundStyle(theme.color("reserveText"))
                    Text(amount(cycle.headline.availableNowMinor)).font(.custom("thmanyahserifdisplay-Black", size: 54, relativeTo: .largeTitle))
                        .contentTransition(.numericText()).minimumScaleFactor(0.55).lineLimit(1).accessibilityIdentifier("money-available")
                }
                }.buttonStyle(.plain).accessibilityIdentifier("money-basis-open")
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 7) {
                    Text("لك فعلًا").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    Text(amount(reading.basis.netMinor)).font(MadarTypography.cardTitle()).accessibilityIdentifier("money-net")
                    Text(reading.currency == "SAR" ? "ريال سعودي" : reading.currency).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }
            }
            if let over = cycle.headline.overTodayMinor {
                Text("تجاوزت يومك بـ" + amount(over)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-over-today")
            }
            if let over = cycle.headline.overCycleMinor {
                Text("تجاوزت استحقاق الدورة بـ" + amount(over)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-over-cycle")
            }
            if !amountsVisible {
                Button("أظهر الأرقام") { revealed = true }.font(MadarTypography.caption()).frame(minHeight: 44).accessibilityIdentifier("money-reveal")
            }
        }.accessibilityElement(children: .contain)
    }
    private func firstPage(_ reading: MoneyHomeReading) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                Capsule().fill(theme.color("rod2")).frame(width: 14)
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "sparkle").foregroundStyle(theme.color("reserveText"))
                    Text("صفحة مالك الأولى").font(MadarTypography.title())
                    Text(reading.hasAccounts ? "حساباتك هنا. يظهر يومك ومنحنى الصرف بعد بدء دورتك." : "سيجتمع هنا يومك، وما تدّخره، وما يستحق قريبًا. تبدأ الأرقام من بياناتك.")
                        .font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                }.padding(22).frame(maxWidth: .infinity, minHeight: 200).background(theme.surface)
                Capsule().fill(theme.color("rod2")).frame(width: 14)
            }.accessibilityIdentifier("money-empty")
            if reading.hasAccounts {
                Button { basisOpen = true } label: {
                    HStack { Text("في حسابك"); Spacer(); Text(amount(reading.basis.inAccountMinor)).font(MadarTypography.cardTitle()); Image(systemName: "chevron.left").font(.caption) }.frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel("على أي أساس، في حسابك " + amount(reading.basis.inAccountMinor))
                if !amountsVisible { Button("أظهر الأرقام") { revealed = true }.frame(minHeight: 44).accessibilityIdentifier("money-reveal") }
            }
        }
    }
    private func envelopeSection(_ reading: MoneyHomeReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { envelopesOpen = true } label: { HStack { sectionTitle("المظاريف", color: theme.color("accent")); Image(systemName: "chevron.left").font(.caption) }.frame(minHeight: 44) }.buttonStyle(.plain).accessibilityIdentifier("money-envelopes-open")
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("الاحتياطي").font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)).foregroundStyle(theme.color("reserveText"))
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(amount(reading.reserveMinor)).font(MadarTypography.cardTitle()).accessibilityIdentifier("money-reserve")
                        if amountsVisible, let runway = reading.reserveRunway {
                            Text(service.days(runway.days)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicType.isAccessibilitySize && amountsVisible {
                    MoneyReserveSquares(days: reading.reserveDailies ?? 0).frame(width: 152, height: 42)
                }
            }
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("الفائض").font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)).foregroundStyle(theme.color("surplusText"))
                    Text(amount(reading.surplusMinor)).font(MadarTypography.cardTitle()).accessibilityIdentifier("money-surplus")
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicType.isAccessibilitySize && amountsVisible {
                    MoneyWaterfall(values: reading.surplusHistory).frame(width: 152, height: 38)
                }
            }
            if reading.envelopes.isEmpty {
                Text("لم تُضف مظروفًا بعد").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).padding(.vertical, 4)
            } else {
                ForEach(reading.envelopes) { envelope in MoneyEnvelopeLine(envelope: envelope, app: app, visible: amountsVisible) }
            }
        }
    }
    private func lowerDesk(_ reading: MoneyHomeReading) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                limits(reading).frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(theme.line).frame(width: 1, height: 126)
                obligations(reading).frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 16) { limits(reading); obligations(reading) }
        }.padding(.top, 12).overlay(alignment: .top) { DoubleRule().stroke(theme.color("reserveText"), lineWidth: 0.8).frame(height: 3) }
    }
    private func limits(_ reading: MoneyHomeReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("حدود الصرف").font(MadarTypography.cardTitle()).foregroundStyle(theme.color("surplusText"))
            if reading.limits.isEmpty { Text("لا حدود مضافة").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
            ForEach(reading.limits.prefix(4)) { limit in
                HStack(spacing: 8) {
                    if !dynamicType.isAccessibilitySize && amountsVisible {
                        ZStack {
                            Circle().stroke(theme.line, lineWidth: 4)
                            Circle().trim(from: 0, to: limit.limitMinor > 0 ? min(1, Double(max(0, limit.spentMinor)) / Double(limit.limitMinor)) : limit.spentMinor > 0 ? 1 : 0)
                                .stroke(theme.color("surplus"), style: .init(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                        }.frame(width: 26, height: 26).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(limit.title).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        Text(amount(limit.spentMinor)).font(MadarTypography.section())
                    }
                }.accessibilityElement(children: .combine)
            }
            }
        }
    }
    private func obligations(_ reading: MoneyHomeReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("الالتزامات").font(MadarTypography.cardTitle()).foregroundStyle(theme.color("bills"))
            if reading.obligations.isEmpty { Text("لا مواعيد مسجّلة").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
            ForEach(reading.obligations.prefix(3)) { obligation in
                HStack(alignment: .top, spacing: 7) {
                    DiamondMark().stroke(theme.color("reserveText"), lineWidth: 1).frame(width: 12, height: 14).padding(.top, 3).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(obligation.name).font(MadarTypography.caption()).lineLimit(1)
                        MadarDateLabel(app.dateLabels(obligation.due, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    }
                    Spacer(minLength: 0)
                    Text(amount(obligation.amountMinor)).font(MadarTypography.section()).fixedSize()
                }.accessibilityElement(children: .combine)
            }
        }
    }
    private func sectionTitle(_ title: String, color: Color) -> some View {
        HStack { Text(title).font(MadarTypography.cardTitle()).foregroundStyle(color); Rectangle().fill(theme.line).frame(height: 1) }
    }
    private func cycleSummary(_ cycle: MoneyCycleReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("دورتك").font(MadarTypography.cardTitle())
            MadarDateLabel(app.dateLabels(cycle.startDay))
            Text("حتى").font(MadarTypography.caption())
            MadarDateLabel(app.dateLabels(cycle.expectedEndDay))
        }.padding(16).background(theme.surface, in: .rect(cornerRadius: 16))
    }
    private func amount(_ value: Int) -> String { amountsVisible ? service.amount(value) : "•••" }
    private func load() {
        do { reading = try service.load(); failure = nil }
        catch MoneyCommandError.missingRate { failure = "يلزم سعر تحويل يدوي لجمع أرصدتك بعملة البيت."; reading = nil }
        catch { failure = "تعذّرت قراءة البيانات الآن. أعد المحاولة."; reading = nil }
    }
}

struct DoubleRule: Shape {
    func path(in rect: CGRect) -> Path { Path { p in p.move(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: rect.width, y: 0)); p.move(to: .init(x: 0, y: 3)); p.addLine(to: .init(x: rect.width, y: 3)) } }
}
struct DiamondMark: Shape {
    func path(in r: CGRect) -> Path { Path { p in p.move(to: .init(x: r.midX, y: r.minY)); p.addLine(to: .init(x: r.maxX, y: r.midY)); p.addLine(to: .init(x: r.midX, y: r.maxY)); p.addLine(to: .init(x: r.minX, y: r.midY)); p.closeSubpath() } }
}
