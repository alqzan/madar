import SwiftUI
import MadarCore
import MadarDesign
import MadarMoney
import MadarCommands

struct MoneyZakatView: View {
    let app: AppSession
    @Binding var revealed: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var reading: MoneyZakatReading?
    @State private var basis = NisabBasis.gold
    @State private var basisChosen = false
    @State private var debt = ZakatDebtsPolicy.unset
    @State private var editor = false
    @State private var reminderDraft: String?
    @State private var entered = false
    @State private var failure: String?
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var service: AppMoneyService { .init(app: app) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private var input: ZakatInput? { guard var n = reading?.input else { return nil }; n.debtsPolicy = debt; n.nisabBasis = basis; return n }
    private var result: ZakatAssessment? { input.map { ZakatEngine.assess($0, now: app.prayerNow()) } }
    private var hawl: MoneyHawl? { input?.hawlStartHijri.flatMap { MoneyHawl.read($0, app: app) } }
    private func amount(_ n: Int) -> String { visible ? service.amount(n) : "•••" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1) } }.accessibilityLabel("إغلاق"); Text("الزكاة").font(MadarTypography.title()); Spacer(); if !visible { Button("أظهر الأرقام") { revealed = true }.font(MadarTypography.caption()).accessibilityIdentifier("money-zakat-reveal") } }
                if let r = reading, let input, let result {
                    hawlArc
                    if !dynamicType.isAccessibilitySize {
                        VStack(spacing: 4) {
                            MoneyZakatScale(pool: max(0, result.poolMinor - result.deductedMinor), nisab: result.nisabMinor, visible: visible && basisChosen && debt != .unset, entered: entered, theme: theme)
                                .frame(height: 255)
                                .accessibilityHidden(true)
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("مالك في الحساب").font(MadarTypography.fine())
                                    Text(amount(max(0, result.poolMinor - result.deductedMinor))).font(MadarTypography.cardTitle()).foregroundStyle(theme.color("surplusText"))
                                }
                                Spacer(minLength: 12)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(basis == .gold ? "النصاب، ذهب ٢٤ قيراطًا" : "النصاب، فضة").font(MadarTypography.fine())
                                    Text(result.nisabMinor.map(amount) ?? "أدخل السعر").font(MadarTypography.cardTitle())
                                }
                            }
                            .foregroundStyle(theme.secondaryInk)
                            .padding(.horizontal, 8)
                        }
                    }
                    assessment(result)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("اختر أساس النصاب").font(MadarTypography.section())
                        HStack(spacing: 8) { basisButton(.gold, "ذهب ٢٤ قيراطًا"); basisButton(.silver, "فضة") }
                        Text("كيف تحسب الديون؟").font(MadarTypography.section())
                        Picker("الديون", selection: $debt) { Text("اختر حسابك").tag(ZakatDebtsPolicy.unset); ForEach([ZakatDebtsPolicy.none, .dueNow, .allOwed, .allOwedAndLoan], id: \.rawValue) { Text(debtTitle($0)).tag($0) } }.accessibilityIdentifier("money-zakat-debts")
                        if !r.hasProfile || basis != r.input.nisabBasis || debt != r.input.debtsPolicy { Text("معاينة؛ احفظ اختيارك من بيانات الحساب").font(MadarTypography.fine()).foregroundStyle(theme.color("reserveText")) }
                        Text(debtExplanation(input)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    }.padding(14).background(theme.surface).overlay { Rectangle().stroke(theme.line, lineWidth: 1) }
                    if basisChosen {
                        let price = basis == .gold ? input.goldPricePerGramMinor : input.silverPricePerGramMinor
                        let at = basis == .gold ? input.goldPriceSetAt : input.silverPriceSetAt
                        Button { editor = true } label: { VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(basis == .gold ? "سعر الغرام، ذهب ٢٤ قيراطًا" : "سعر غرام الفضة"); Spacer(); Text(price.map(amount) ?? "أدخله يدويًا") }.font(MadarTypography.caption())
                            if let at { MadarDateLabel(app.dateLabels(.containing(at, in: app.activePlace.timeZone)), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()) }
                            Text(result.goldPriceStale ? "السعر أقدم من ٣٠ يومًا؛ حدّثه" : "سعر أدخلته يدويًا").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect) }.accessibilityIdentifier("money-zakat-price")
                    }
                    if hawl != nil { zakatReminder }
                    Button { editor = true } label: { Label("بيانات الحساب والحول", systemImage: "slider.horizontal.3").font(MadarTypography.body()).frame(maxWidth: .infinity, minHeight: 50).background(theme.ink).foregroundStyle(theme.background) }.accessibilityIdentifier("money-zakat-edit")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ما يدخل في الوعاء").font(MadarTypography.section())
                        ForEach(r.accounts) { a in HStack { Text(a.name); Spacer(); Text(a.included ? amount(a.homeMinor) : "مستبعد").foregroundStyle(a.included ? theme.ink : theme.secondaryInk) }.font(MadarTypography.caption()) }
                        Text("المظاريف والاحتياطي أجزاء من أرصدة الحسابات؛ لا تُضاف مرة ثانية.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    }
                    Text("حساب تقريبي بلا ترجيح. التاريخ الذي تختاره لا يُثبت أن المال بقي فوق النصاب طوال الحول.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                } else { Text(failure ?? "جارٍ قراءة الحساب…").font(MadarTypography.body()) }
            }.padding(.horizontal, 18).padding(.bottom, 24).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).buttonStyle(.plain).environment(\.roomTheme, theme).toolbar(.hidden, for: .navigationBar, .tabBar)
            .task { load(); entered = true }.onChange(of: app.prayerRevision) { load() }.onChange(of: scenePhase) { if scenePhase != .active { revealed = false } }
            .sheet(isPresented: $editor, onDismiss: load) { if let r = reading { MoneyZakatEditor(app: app, reading: r, basis: basis, chosen: basisChosen, debt: debt, visible: visible) } }
            .accessibilityIdentifier("money-zakat")
    }
    private var zakatReminder: some View {
        let saved = app.string("mal.zakatReminder")
        let selected = reminderDraft ?? saved
        let leadTitle = reminderTitle(selected)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("تذكير موعد الزكاة").font(MadarTypography.section())
                    Text("اختَر متى يذكّرك مدار قبل موعد الحول").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }
                Spacer()
                if saved != "off" { Text("مفعل: " + reminderTitle(saved)).font(MadarTypography.fine()).foregroundStyle(theme.color("reserveText")).accessibilityIdentifier("money-zakat-reminder-state") }
            }
            reminderChips
            HStack(alignment: .top) {
                Text("موعد الحول القادم").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                Spacer()
                if let hawl {
                    MadarDateLabel(app.dateLabels(hawl.anniversary), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine())
                        .accessibilityElement(children: .ignore).accessibilityLabel(app.dateLabels(hawl.anniversary).combined)
                        .accessibilityIdentifier("money-zakat-reminder-date")
                }
            }
            if selected == "off" && saved == "off" {
                Text("التذكير متوقف حتى تختار مهلة وتثبّتها.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            } else if selected != saved {
                Button {
                    app.set(.string(selected), key: "mal.zakatReminder") { reminderDraft = nil }
                } label: {
                    VStack(spacing: 3) {
                        Text(saved == "off" ? "ثبّت التذكير السنوي" : "حدّث التذكير السنوي").font(MadarTypography.body())
                        Text(leadTitle + " من الموعد المعروض").font(MadarTypography.fine())
                    }.frame(maxWidth: .infinity, minHeight: 48).background(theme.ink).foregroundStyle(theme.background)
                }.disabled(app.settingsWriteInProgress).accessibilityIdentifier("money-zakat-reminder-save")
            } else if saved != "off" {
                Button("أوقف التذكير السنوي") {
                    app.set(.string("off"), key: "mal.zakatReminder") { reminderDraft = nil }
                }.font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(app.settingsWriteInProgress).accessibilityIdentifier("money-zakat-reminder-disable")
            }
        }
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.color("reserveText").opacity(0.7), lineWidth: 1) }
    }
    @ViewBuilder private var reminderChips: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 0) { reminderChipRow }
        } else { reminderChipRow }
    }
    private var reminderChipRow: some View {
        HStack(spacing: 7) {
            reminderChip("1day", title: "قبل يوم")
            reminderChip("1week", title: "قبل أسبوع")
            reminderChip("1month", title: "قبل شهر")
        }
    }
    private func reminderChip(_ value: String, title: String) -> some View {
        let selected = (reminderDraft ?? app.string("mal.zakatReminder")) == value
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.18)) { reminderDraft = value }
        } label: {
            reminderChipLabel(title, selected: selected, shape: shape)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("money-zakat-reminder-option-\(value)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    @ViewBuilder private func reminderChipLabel(_ title: String, selected: Bool, shape: RoundedRectangle) -> some View {
        let content = Text(title).font(MadarTypography.caption()).fontWeight(selected ? .semibold : .regular).foregroundStyle(theme.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(theme.surface.opacity(0.28), in: shape)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(theme.color("reserve").opacity(selected ? 0.24 : 0.08)).interactive(), in: shape)
                .overlay { shape.stroke(selected ? theme.color("reserveText") : theme.line, lineWidth: selected ? 1.5 : 1) }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.stroke(selected ? theme.color("reserveText") : theme.line, lineWidth: selected ? 1.5 : 1) }
        }
    }
    private func reminderTitle(_ value: String) -> String {
        switch value { case "1day": "قبل يوم"; case "1week": "قبل أسبوع"; case "1month": "قبل شهر"; default: "بلا تذكير" }
    }
    private var hawlArc: some View {
        VStack(spacing: 8) {
            if !dynamicType.isAccessibilitySize { GeometryReader { g in
                ZStack {
                    Path { p in p.move(to: CGPoint(x: 10, y: 62)); p.addQuadCurve(to: CGPoint(x: g.size.width-10, y: 62), control: CGPoint(x: g.size.width/2, y: -35)) }.stroke(theme.color("reserveText"), lineWidth: 1)
                    ForEach(0..<12, id: \.self) { n in let t = Double(n)/11; let y = 62 - sin(t * .pi) * 45
                        Image(systemName: n == Int((hawl?.fraction ?? 0) * 11) ? "moon.fill" : "moon").font(.system(size: n == Int((hawl?.fraction ?? 0) * 11) ? 22 : 17)).foregroundStyle(theme.color("reserveText")).position(x: 10 + t * (g.size.width-20), y: y)
                    }
                }
            }.frame(height: 76).accessibilityHidden(true) }
            if let hawl {
                Text(hawl.daysLeft == 0 ? "موعد حسابك اليوم" : "موعد حسابك بعد " + service.days(hawl.daysLeft)).font(MadarTypography.cardTitle()).accessibilityIdentifier("money-zakat-hawl")
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) { Text("بداية حسابك"); MadarDateLabel(app.dateLabels(hawl.chosen), primaryFont: .system(size: 11), secondaryFont: .system(size: 11)) }
                    Spacer()
                    VStack(alignment: .leading, spacing: 3) { Text("الموعد القادم"); MadarDateLabel(app.dateLabels(hawl.anniversary), primaryFont: .system(size: 11), secondaryFont: .system(size: 11)) }
                }.font(.system(size: 11)).foregroundStyle(theme.secondaryInk)
            } else { Button("اختر تاريخًا تحاسب فيه نفسك كل سنة") { editor = true }.font(MadarTypography.body()).frame(minHeight: 44).accessibilityIdentifier("money-zakat-choose-hawl") }
        }
    }
    @ViewBuilder private func assessment(_ r: ZakatAssessment) -> some View {
        VStack(spacing: 5) {
            if !visible { Text("•••").font(.largeTitle).accessibilityIdentifier("money-zakat-result") }
            else if !basisChosen { Text("اختر أساس النصاب قبل الحساب").font(MadarTypography.cardTitle()).accessibilityIdentifier("money-zakat-result") }
            else {
                switch r.outcome {
                case .invalidAmounts: Text("راجع القيم؛ تعذّر حساب هذه المبالغ.").font(MadarTypography.body()).accessibilityIdentifier("money-zakat-result")
                case .askDebts: Text("اختر كيف تحسب الديون أولًا").font(MadarTypography.cardTitle()).accessibilityIdentifier("money-zakat-result")
                case .askPrice: Text("أدخل سعر الغرام يدويًا").font(MadarTypography.cardTitle()).accessibilityIdentifier("money-zakat-result")
                case .belowNisab: Text("دون النصاب تقريبًا").font(MadarTypography.cardTitle()).accessibilityIdentifier("money-zakat-result")
                case .due(let n):
                    Text("لو حال الحول اليوم، تقريبي").font(MadarTypography.caption()).foregroundStyle(theme.color("surplusText"))
                    Text(amount(n)).font(.custom("thmanyahserifdisplay-Black", size: 48, relativeTo: .largeTitle)).contentTransition(.numericText()).accessibilityIdentifier("money-zakat-result")
                    Text(amount(max(0, r.poolMinor-r.deductedMinor)) + " × ٢٫٥٪").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 10)
    }
    private func basisButton(_ choice: NisabBasis, _ title: String) -> some View { Button { basis = choice; basisChosen = true } label: { Text(title).font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 44).background(basisChosen && basis == choice ? theme.ink : theme.background).foregroundStyle(basisChosen && basis == choice ? theme.background : theme.ink).overlay { Rectangle().stroke(theme.color("reserveText"), lineWidth: 1) } }.accessibilityIdentifier("money-zakat-basis-" + choice.rawValue) }
    private func debtTitle(_ p: ZakatDebtsPolicy) -> String { switch p { case .unset: "لم أختر"; case .none: "لا أخصم ديونًا"; case .dueNow: "المستحق الآن فقط"; case .allOwed: "عليك كله، دون باقي القرض"; case .allOwedAndLoan: "عليك وباقي القرض" } }
    private func debtExplanation(_ i: ZakatInput) -> String { switch debt { case .unset: "اختر ما تعمل به؛ لا يختار مدار عنك."; case .none: "لا يُخصم شيء من الوعاء."; case .dueNow: "الكشوف المستحقة والأقساط التي حلّت ولم تُدفع: " + amount(i.dueNowMinor); case .allOwed: "ديون الائتمان والتقسيط: " + amount(i.owedAllMinor) + "، وباقي القرض خارجها."; case .allOwedAndLoan: "عليك " + amount(i.owedAllMinor) + "، وباقي القرض " + amount(i.loanRemainingMinor) } }
    private func load() { do { let r = try service.loadZakat(); reading = r; basis = r.input.nisabBasis; basisChosen = r.hasProfile; debt = r.input.debtsPolicy; failure = nil } catch { failure = "لم تكتمل قراءة الزكاة. راجع العملات في الحسابات ثم حاول مرة أخرى." } }
}
