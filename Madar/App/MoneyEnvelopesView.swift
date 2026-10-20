import SwiftUI
import MadarCore
import MadarData
import MadarDesign
import MadarMoney
import MadarCommands

struct MoneyEnvelopesView: View {
    let app: AppSession
    @Binding var revealed: Bool
    @Environment(\.roomTheme) private var inheritedTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var reading: MoneyEnvelopesReading?
    @State private var previewMinor = 0
    @State private var targetOpen = false
    @State private var failure: String?
    @State private var selectedEnvelope: UUID?
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var service: AppMoneyService { .init(app: app) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Button { dismiss() } label: { HStack(spacing: 5) { Image(systemName: "chevron.backward"); Text("المال") }.font(MadarTypography.body()).foregroundStyle(theme.color("reserveText")).frame(minHeight: 44) }.buttonStyle(.plain).accessibilityIdentifier("money-envelopes-back")
                HStack(alignment: .firstTextBaseline) {
                    Text("المظاريف").font(MadarTypography.title())
                    Spacer()
                    if let reading { Text(figure: amount(reading.totalMinor)).font(MadarTypography.cardTitle()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-envelope-total") }
                }
                if !visible { Button("أظهر الأرقام") { revealed = true }.frame(minHeight: 44).accessibilityIdentifier("money-envelopes-reveal") }
                if let reading {
                    if let cycle = reading.home.cycle { dailySplit(cycle) }
                    reserve(reading)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("الفائض").font(MadarTypography.cardTitle()).foregroundStyle(theme.color("surplusText")); Text(figure: amount(reading.home.surplusMinor)).font(MadarTypography.cardTitle()); Spacer() }
                        Text("كيف تجمّع من الدورات").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        if visible && !dynamicType.isAccessibilitySize && reading.home.surplusMinor >= 0 {
                            MoneySurplusChart(points: reading.waterfall, current: reading.home.surplusMinor, next: reading.home.cycle?.expectedEndDay, app: app).frame(height: 148)
                        }
                    }.padding(.top, 8)
                    HStack { Text("مظاريف الأهداف").font(MadarTypography.cardTitle()).foregroundStyle(theme.color("accent")); DoubleRule().stroke(theme.color("reserveText"), lineWidth: 0.7).frame(height: 3) }
                    if reading.home.envelopes.isEmpty {
                        Text("لم تُضف مظاريف أهداف بعد").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).padding(.vertical, 18)
                    }
                    ForEach(reading.home.envelopes) { envelope in
                        Button { selectedEnvelope = envelope.id } label: { MoneyGoalOverview(envelope: envelope, app: app, visible: visible).contentShape(.rect) }.buttonStyle(.plain).accessibilityIdentifier("money-envelope-" + envelope.name)
                    }
                } else if let failure {
                    Text(failure).font(MadarTypography.body()); Button("أعِد المحاولة", action: load).frame(minHeight: 44)
                } else { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            }.padding(.horizontal, 18).padding(.top, 0).padding(.bottom, 30).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.clipped().background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
            .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
            .task { load() }.onChange(of: app.prayerRevision) { load() }
            .sheet(isPresented: $targetOpen) { MoneyReserveTargetView(app: app, current: reading?.reserveTargetMinor) { load() }.environment(\.roomTheme, theme) }
            .navigationDestination(item: $selectedEnvelope) { id in MoneyEnvelopeDetailView(app: app, id: id, revealed: $revealed).environment(\.roomTheme, theme) }
            .accessibilityIdentifier("money-envelopes")
    }
    private func dailySplit(_ cycle: MoneyCycleReading) -> some View {
        let day = CycleEngine.day(cycle.elapsedDays, cycle.input), plans = day.allowanceMinor - day.dailyMinor
        return VStack(alignment: .leading, spacing: 8) {
            HStack { Text("قسمة يومك"); Spacer(); Text("من " + amount(day.allowanceMinor) + ": لك " + amount(day.dailyMinor) + " ولمظاريفك " + amount(plans)) }
                .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-envelope-daily-split")
            if visible && !dynamicType.isAccessibilitySize {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        if day.allowanceMinor > 0 {
                            Rectangle().fill(theme.color("surplus")).frame(width: proxy.size.width * CGFloat(day.dailyMinor) / CGFloat(day.allowanceMinor))
                            Rectangle().fill(theme.color("accent")).frame(maxWidth: .infinity)
                        } else { Rectangle().stroke(theme.line, lineWidth: 1) }
                    }
                }.frame(height: 7).accessibilityHidden(true)
            }
        }
    }
    private func reserve(_ reading: MoneyEnvelopesReading) -> some View {
        let preview = try? ReserveEngine.preview(balanceMinor: reading.home.reserveMinor, spendMinor: previewMinor,
            dailyMinor: reading.reserve.dailyMinor, cycleLengthDays: reading.home.cycle?.input.expectedLengthDays ?? 30,
            obligationsPerCycleMinor: reading.home.obligationsPerCycleMinor)
        let after = preview?.after ?? reading.reserve
        return VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { reserveTitle(reading); Spacer(minLength: 4); reserveModes(reading) }
                VStack(alignment: .leading, spacing: 8) { reserveTitle(reading); reserveModes(reading) }
            }
            if visible, let whole = reading.reserve.wholeDailies {
                Text(service.dailies(whole) + (reading.reserve.partialDailyMinor.map { $0 > 0 ? "، وباقي " + amount($0) : "" } ?? ""))
                    .font(MadarTypography.body()).accessibilityIdentifier("money-reserve-dailies")
            } else if visible {
                Text(reading.reserve.dailyMinor == 0 ? "اليومية صفر؛ المدة من الالتزامات المسجّلة وحدها." : "تظهر اليوميات والمدة بعد ضبط اليومية.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }
            if visible, let coverage = after.runway {
                Text(service.coverage(coverage.days) + " بعد التزامات الدورة").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-reserve-coverage")
            }
            if visible && !dynamicType.isAccessibilitySize, let daily = reading.reserve.dailyMinor, daily > 0 {
                MoneyReserveGrid(beforeMinor: reading.home.reserveMinor, afterMinor: after.balanceMinor, dailyMinor: daily, app: app)
            }
            if visible, let daily = reading.reserve.dailyMinor, daily > 0 {
                HStack(spacing: 8) {
                    Rectangle().fill(theme.color("reserve")).overlay { Rectangle().stroke(theme.color("reserveText"), lineWidth: 1) }.frame(width: 8, height: 8)
                    Text("مربع = يومية " + amount(daily))
                    Spacer(minLength: 0)
                    Text("السطر = " + service.dailies(30))
                }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
            if let target = reading.reserveTargetMinor {
                HStack { Text("هدف الاحتياطي"); Spacer(); Text(figure: amount(target)) }.font(MadarTypography.caption()).foregroundStyle(theme.color("reserveText")).accessibilityElement(children: .combine).accessibilityIdentifier("money-reserve-target")
                if visible { ProgressView(value: min(1, Double(max(0, reading.home.reserveMinor)) / Double(target))).tint(theme.color("reserveText")) }
            }
            if visible {
            HStack {
                Text("لو صرفت منه").font(MadarTypography.caption())
                Spacer(minLength: 2)
                ForEach(previews(reading.home.reserveMinor), id: \.self) { value in
                    Button { previewMinor = value } label: {
                        Text(figure: value == 0 ? "لا شيء" : visible ? service.amount(value) : "•••")
                            .font(MadarTypography.fine()).padding(.horizontal, 10).padding(.vertical, 7)
                            .foregroundStyle(value == previewMinor ? theme.background : theme.ink)
                            .background(value == previewMinor ? theme.ink : .clear, in: .capsule)
                            .overlay { Capsule().stroke(theme.color("reserveText"), lineWidth: 1) }
                            .frame(minHeight: 44)
                    }.buttonStyle(.plain).accessibilityIdentifier("money-reserve-preview-" + String(value))
                }
            }
            }
            if previewMinor > 0 && visible {
                HStack { Text("يبقى " + amount(after.balanceMinor)); Spacer(); Text("معاينة فقط") }
                    .font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")).accessibilityElement(children: .combine).accessibilityIdentifier("money-reserve-after")
            }
            Rectangle().fill(theme.line).frame(height: 1)
        }
    }
    private func reserveTitle(_ reading: MoneyEnvelopesReading) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("الاحتياطي").font(MadarTypography.cardTitle()).foregroundStyle(theme.color("reserveText"))
            Text(figure: amount(reading.home.reserveMinor)).font(MadarTypography.cardTitle()).accessibilityIdentifier("money-envelope-reserve")
        }
    }
    private func reserveModes(_ reading: MoneyEnvelopesReading) -> some View {
        HStack(spacing: 0) {
            mode("مفتوح", selected: reading.reserveTargetMinor == nil, id: "open") {
                guard reading.reserveTargetMinor != nil else { return }
                Task { do { try await app.executeMoneyCommand("money.setReserveGoal", payload: ["targetMinor": .null]); load() } catch { failure = "لم يُحفظ التغيير." } }
            }
            mode("بهدف", selected: reading.reserveTargetMinor != nil, id: "goal") { targetOpen = true }
        }.overlay { Capsule().stroke(theme.color("reserveText"), lineWidth: 1) }.fixedSize()
    }
    private func mode(_ text: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(text).font(MadarTypography.fine()).padding(.horizontal, 13).padding(.vertical, 8).foregroundStyle(selected ? theme.background : theme.ink).background(selected ? theme.ink : .clear, in: .capsule).frame(minHeight: 44) }
            .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier("money-reserve-mode-" + id)
    }
    private func previews(_ balance: Int) -> [Int] { [0] + Array(Set([max(0, balance) / 4, max(0, balance) / 2, max(0, balance) / 4 * 3].filter { $0 > 0 })).sorted() }
    private func amount(_ value: Int) -> String { visible ? service.amount(value) : "•••" }
    private func load() {
        do { reading = try service.loadEnvelopes(); previewMinor = min(previewMinor, max(0, reading?.home.reserveMinor ?? 0)); failure = nil }
        catch { reading = nil; failure = "لم تكتمل قراءة المظاريف. يمكنك إعادة المحاولة." }
    }
}

struct MoneyReserveTargetView: View {
    let app: AppSession
    let current: Int?
    var saved: () -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var working = false
    @State private var errorMessage: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MoneyPageHeader(title: "هدف الاحتياطي", close: { dismiss() })
            Text("المبلغ الذي تريد أن يصل إليه احتياطك").font(MadarTypography.body())
            TextField("المبلغ المستهدف", text: $input).keyboardType(.decimalPad).font(MadarTypography.cardTitle()).padding(16).overlay { RoundedRectangle(cornerRadius: 12).stroke(theme.color("reserveText"), lineWidth: 1) }.accessibilityIdentifier("money-reserve-target-input")
            if let errorMessage { Text(errorMessage).font(MadarTypography.caption()) }
            Button("احفظ الهدف") { save() }.buttonStyle(MadarPrimaryButton()).disabled(working).accessibilityIdentifier("money-reserve-target-save")
            Spacer(minLength: 0)
        }.padding(20).background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
            .presentationDetents([.medium]).presentationDragIndicator(.visible)
            .task { if let current { input = AppMoneyService(app: app).amount(current, full: true) } }
    }
    private func save() {
        let raw = BankMessageParser.clean(input).replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let exp = CurrencyExponents.specified.exponent(app.string("core.currency")), let value = MoneyAmountInput.minor(raw, exponent: exp), value > 0 else { errorMessage = "أدخل مبلغًا موجبًا للهدف."; return }
        working = true
        Task {
            defer { working = false }
            do { try await app.executeMoneyCommand("money.setReserveGoal", payload: ["targetMinor": .string(String(value))]); saved(); dismiss() }
            catch { errorMessage = "لم يُحفظ الهدف. أعد المحاولة." }
        }
    }
}
