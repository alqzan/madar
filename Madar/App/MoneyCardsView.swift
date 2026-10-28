import SwiftUI
import MadarCore
import MadarDesign
import MadarMoney

struct MoneyCardsView: View {
    let app: AppSession
    @Binding var revealed: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var reading: MoneyCardsReading?
    @State private var selected: UUID?
    @State private var tab = "نظرة"
    @State private var minimum = false
    @State private var purchaseMinor = 200_000
    @State private var selectedDue: String?
    @State private var source: MoneySourceDetail?
    @State private var failure: String?
    @State private var jarOpen = false
    @State private var adding = false
    private let tabs = ["نظرة", "متى يخرج النقد", "تقويم السداد", "المطابقة"]
    private var service: AppMoneyService { .init(app: app) }
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private func amount(_ minor: Int) -> String { visible ? service.amount(minor) : "•••" }
    private var card: MoneyCardReading? { reading?.cards.first { $0.id == selected } ?? reading?.cards.first }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1) } }
                        .buttonStyle(.plain).accessibilityLabel("إغلاق").accessibilityIdentifier("money-cards-close")
                    Text("البطاقات").font(.custom("thmanyahserifdisplay-Bold", size: 26, relativeTo: .title)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { adding = true } label: { Image(systemName: "plus").frame(width: 44, height: 44).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1) } }
                        .buttonStyle(.plain).accessibilityLabel("أضف بطاقة").accessibilityIdentifier("money-cards-add")
                }.padding(.top, 8)
                if let reading {
                    if reading.cards.isEmpty {
                        Text("لا بطاقات بعد").font(MadarTypography.cardTitle())
                        Text("أضف بطاقتك باسمها وآخر أربعة أرقامها، فتُربط بها رسائل البنك. لا تُنشأ بطاقة من رقم غير معروف تلقائيًا.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                        Button { adding = true } label: { Text("أضف بطاقة").font(MadarTypography.cardTitle()).frame(maxWidth: .infinity, minHeight: 54).background(theme.ink).foregroundStyle(theme.background) }
                            .buttonStyle(.plain).accessibilityIdentifier("money-cards-add-first")
                    } else {
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) { ForEach(reading.cards) { miniature($0) } }
                        }.scrollIndicators(.hidden).accessibilityIdentifier("money-card-strip")
                        if !visible { Button("أظهر الأرقام") { revealed = true }.frame(minHeight: 44).accessibilityIdentifier("money-cards-reveal") }
                        ViewThatFits(in: .horizontal) {
                            tabStrip
                            ScrollView(.horizontal) { tabStrip }.scrollIndicators(.hidden)
                        }
                        if let card {
                            switch tab {
                            case "متى يخرج النقد": cashFlow(reading)
                            case "تقويم السداد": calendar(reading)
                            case "المطابقة": match(card)
                            default: overview(card)
                            }
                        }
                    }
                } else if let failure { Text(failure).font(MadarTypography.body()); Button("أعِد المحاولة", action: load).frame(minHeight: 44) }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 250) }
            }.padding(.horizontal, 20).padding(.bottom, 30).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).environment(\.roomTheme, theme)
            .toolbarVisibility(.hidden, for: .navigationBar).accessibilityIdentifier("money-cards")
            .task { load() }.onChange(of: app.prayerRevision) { load() }
            .sheet(item: $source) { MoneySourceView(app: app, detail: $0, visible: visible).environment(\.roomTheme, theme) }
            .navigationDestination(isPresented: $jarOpen) { MoneyCashbackView(app: app, revealed: $revealed) }
            .sheet(isPresented: $adding, onDismiss: load) { MoneyCardSheet(app: app) }
    }
    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { name in
                Button { tab = name } label: {
                    Text(name).font(MadarTypography.fine()).bold().fixedSize().padding(.horizontal, 12).frame(minHeight: 42)
                        .background(tab == name ? theme.ink : Color.clear, in: Capsule()).foregroundStyle(tab == name ? theme.background : theme.ink)
                }.buttonStyle(.plain).accessibilityAddTraits(tab == name ? .isSelected : []).accessibilityIdentifier("money-cards-tab-" + name)
            }
        }.padding(3).background(theme.surface, in: Capsule()).overlay { Capsule().stroke(theme.line, lineWidth: 1) }
    }
    private func miniature(_ c: MoneyCardReading) -> some View {
        let active = card?.id == c.id
        return Button { selected = c.id; minimum = false } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(c.name).font(.custom("thmanyahserifdisplay-Bold", size: 16, relativeTo: .subheadline)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(c.kind == "credit" ? "عليك" : c.kind == "debit" ? "مدى" : "مسبقة الدفع").font(MadarTypography.fine())
                        if c.kind == "credit" { Text(figure: amount(c.owedMinor)).font(MadarTypography.body()) }
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    Text(c.network.isEmpty ? c.bank : networkName(c.network)).font(MadarTypography.fine()).lineLimit(1)
                    Spacer()
                    Text("•••• " + service.digits.localized(c.last4)).font(MadarTypography.fine()).environment(\.layoutDirection, .leftToRight)
                }
            }.padding(12).frame(width: dynamicType.isAccessibilitySize ? 280 : 171, height: dynamicType.isAccessibilitySize ? 160 : 106)
                // Keep the chip below the name on the right of an RTL card, as in the canonical miniatures.
                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [theme.color("reserve").opacity(0.95), theme.background.opacity(0.9), theme.color("reserve")], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 30, height: 22).overlay { Rectangle().stroke(theme.background.opacity(0.5), lineWidth: 0.7).padding(5) }.padding(.leading, 22).padding(.top, 6).accessibilityHidden(true) }
                .foregroundStyle(theme.background).background(cardFill(c), in: RoundedRectangle(cornerRadius: 13))
                .overlay { if !dynamicType.isAccessibilitySize { MoneyCardEtching().stroke(theme.background.opacity(0.16), lineWidth: 0.6).padding(6).clipShape(RoundedRectangle(cornerRadius: 9)).accessibilityHidden(true).allowsHitTesting(false) } }
                .overlay { RoundedRectangle(cornerRadius: 13).stroke(isPrimary(c) || active ? theme.color("reserve") : theme.background.opacity(0.28), lineWidth: active ? 2.2 : 1.4) }
                .overlay { RoundedRectangle(cornerRadius: 9).stroke(theme.background.opacity(0.35), lineWidth: 0.6).padding(5) }
                .shadow(color: theme.ink.opacity(0.14), radius: 5, y: 4)
        }.buttonStyle(.plain).accessibilityLabel(c.name + (c.kind == "credit" ? "، عليك " + amount(c.owedMinor) : "، ليست دينًا ائتمانيًا"))
            .accessibilityIdentifier("money-card-" + c.name)
    }
    private func isPrimary(_ c: MoneyCardReading) -> Bool { c.kind == "credit" && c.id == reading?.cards.first(where: { $0.kind == "credit" })?.id }
    /// Gold-edged dark card for the main credit card, navy for the others, olive-gold for debit and prepaid (canonical 16-Z-R19-cards-1).
    private func cardFill(_ c: MoneyCardReading) -> LinearGradient {
        let colors: [Color]
        if isPrimary(c) { colors = [theme.color("rod2"), theme.ink.opacity(0.92), theme.color("rod2").opacity(0.85)] }
        else if c.kind == "credit" { colors = [theme.color("accent").opacity(0.78), theme.color("accentText"), theme.color("accent").opacity(0.7)] }
        else { colors = [theme.color("reserveText"), theme.color("rod"), theme.color("reserveText")] }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private func overview(_ c: MoneyCardReading) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if c.kind != "credit" {
                Text(c.kind == "debit" ? "تُخصم مشتريات مدى من الحساب مباشرة" : "المشتريات من رصيد البطاقة المدفوع مقدمًا").font(MadarTypography.cardTitle())
                Text("لا تدخل في «عليك»، ولا يُنتظر سداد ائتماني لها.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
            } else {
                Button { source = c.sources["statement"] } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text("الكشف المستحق").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk); Spacer(); if let due = c.due { Text(due == reading!.today ? "اليوم" : due < reading!.today ? "حلّ موعده" : "بعد " + service.days(MadarCalendarDays.distance(from: reading!.today, to: due))).font(MadarTypography.fine()).foregroundStyle(theme.color("dueText")).padding(.horizontal, 10).padding(.vertical, 5).background(theme.color("dueText").opacity(0.1), in: Capsule()) } }
                        HStack(alignment: .lastTextBaseline) {
                            Text(c.close == nil ? "لم يصل كشف" : amount(c.billedMinor)).font(.custom("thmanyahserifdisplay-Black", size: 40, relativeTo: .largeTitle)).foregroundStyle(c.close == nil ? theme.ink : theme.color("debt")).accessibilityIdentifier("money-card-billed")
                            Spacer()
                            if let due = c.due { dates(due) }
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("money-card-statement-source")
                usage(c)
                HStack(alignment: .top, spacing: 8) {
                    tile("يقفل الكشف", value: c.nextClose.map { app.dateLabels($0, compact: true).primary } ?? "غير معروف", secondary: c.nextClose.map { app.dateLabels($0, compact: true).secondary + "، تقريبًا" }, key: nil, card: c)
                    tile("الحد الأدنى", value: c.minimumMinor.map(amount) ?? "غير معروف", secondary: "لا تكتفِ به", key: "minimum", card: c)
                    tile("الاسترداد", value: c.cashbackBp.map(percent) ?? "غير معروف", secondary: "تقدير الشراء", key: "cashbackBp", card: c)
                }
                Button { jarOpen = true } label: { HStack { Image(systemName: "drop"); Text("جرّة الاسترداد"); Spacer(); Image(systemName: "chevron.left").font(.caption) }.font(MadarTypography.caption()).frame(minHeight: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(theme.color("reserveText")).accessibilityIdentifier("money-cards-cashback-open")
                HStack { Text("كيف تسدّد").font(MadarTypography.cardTitle()); Spacer(); HStack(spacing: 0) {
                    ForEach([false, true], id: \.self) { option in
                        Button { minimum = option } label: { Text(option ? "الحد الأدنى" : "كامل").font(MadarTypography.caption()).bold().padding(.horizontal, 16).frame(minHeight: 44).background(minimum == option ? theme.ink : Color.clear).foregroundStyle(minimum == option ? theme.background : theme.ink).contentShape(Rectangle()) }
                            .buttonStyle(.plain).accessibilityAddTraits(minimum == option ? .isSelected : [])
                    }
                }.clipShape(Capsule()).overlay { Capsule().stroke(theme.ink, lineWidth: 1) }.accessibilityElement(children: .contain).accessibilityLabel("كيف تسدّد").accessibilityIdentifier("money-card-payment-choice") }
                if minimum {
                    let unpaid = max(0, c.billedMinor - (c.minimumMinor ?? 0))
                    Text("يبقى عليك " + amount(unpaid)).font(MadarTypography.body())
                    if let interest = CardPlanning.interestEstimate(unpaidMinor: unpaid, annualRateBp: c.aprBp, days: 30) {
                        Button { source = c.sources["aprBp"] } label: { Text("تقدير فائدة ٣٠ يومًا: " + amount(interest)).font(MadarTypography.body()).foregroundStyle(theme.color("reserveText")) }.buttonStyle(.plain)
                    } else { Text("نسبة الفائدة غير معروفة؛ لا يمكن تقديرها.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                    Text("تقدير تقريبي بفائدة بسيطة: النسبة السنوية × ٣٠ ÷ ٣٦٥، دون الرسوم أو التركيب. كشف البنك هو المرجع.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                } else { Label("سداد كامل المتبقي: " + amount(c.billedMinor), systemImage: "checkmark.circle.fill").font(MadarTypography.body()).foregroundStyle(theme.color("surplusText")) }
            }
            HStack { Text(c.kind == "credit" ? "في الكشف القادم" : "المشتريات المسجلة").font(MadarTypography.cardTitle()); Spacer(); if c.kind == "credit" { Button("غير المفوتر " + amount(c.unbilledMinor)) { source = c.sources["unbilled"] }.font(MadarTypography.fine()).buttonStyle(.plain) } }
            if c.purchases.isEmpty { Text("لا حركات مؤكّدة في هذه الفترة.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk) }
            ForEach(c.purchases) { movement($0) }
            if let best = reading?.cards.filter({ $0.kind == "credit" && $0.graceDays != nil }).max(by: { ($0.graceDays ?? 0) < ($1.graceDays ?? 0) }), let grace = best.graceDays {
                Button { tab = "متى يخرج النقد" } label: { HStack { Text("للشراء اليوم: " + best.name); Spacer(); Text("مهلة " + service.days(grace) + " تقريبًا") }.font(MadarTypography.caption()).padding(16).overlay { Capsule().stroke(theme.color("reserveText"), lineWidth: 1) }.contentShape(.rect) }.buttonStyle(.plain)
            }
        }
    }
    private func usage(_ c: MoneyCardReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let scale = max(1, c.limitMinor ?? c.owedMinor), billed = min(1, Double(c.billedMinor) / Double(scale)), unbilled = min(1 - billed, Double(c.unbilledMinor) / Double(scale))
                HStack(spacing: 2) { Rectangle().fill(c.close == nil ? theme.color("reserveText") : theme.color("debt")).frame(width: visible ? proxy.size.width * billed : 0); Rectangle().fill(theme.color("bills")).frame(width: visible ? proxy.size.width * unbilled : 0); Rectangle().fill(theme.line) }.clipShape(.capsule)
            }.frame(height: 12).accessibilityHidden(true)
            HStack(spacing: 10) {
                swatch(c.close == nil ? theme.color("reserveText") : theme.color("debt"), "كشف", nil)
                swatch(theme.color("bills"), "غير مفوتر", c.unbilledMinor > 0 ? amount(c.unbilledMinor) : nil)
                if let limit = c.limitMinor { swatch(theme.line, "متاح", amount(max(0, limit - c.owedMinor))) }
                Spacer(minLength: 4)
                Button { source = c.sources["limitMinor"] } label: { Text(visible ? CardPlanning.utilisationBp(owedMinor: c.owedMinor, limitMinor: c.limitMinor).map { percent($0) + " من الحد" } ?? "الحد غير معروف" : "•••").bold().foregroundStyle(c.close == nil ? theme.color("reserveText") : theme.color("dueText")) }.buttonStyle(.plain)
            }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
        }
    }
    private func swatch(_ color: Color, _ title: String, _ value: String?) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9); Text(title + (visible ? value.map { " " + $0 } ?? "" : "")) }.lineLimit(1)
    }
    /// Basis points as a short percent: 4300 → «٤٣٪», 50 → «٠٫٥٪».
    private func percent(_ bp: Int) -> String {
        if bp % 100 == 0 { return service.digits.percent(bp / 100) }
        if bp % 10 == 0 { return service.digits.amount(minorUnits: Int64(bp / 10), fractionDigits: 1, signed: false) + "٪" }
        return service.digits.amount(minorUnits: Int64(bp), fractionDigits: 2, signed: false) + "٪"
    }
    private func networkName(_ network: String) -> String {
        switch network.lowercased() {
        case "visa": "فيزا"
        case "mastercard", "master card": "ماستركارد"
        case "mada": "مدى"
        case "american express", "amex": "أمريكان إكسبريس"
        default: network
        }
    }
    private func tile(_ title: String, value: String, secondary: String?, key: String?, card: MoneyCardReading) -> some View {
        Button { if let key { source = card.sources[key] } else { source = .init(id: "close-" + card.id.uuidString, title: "موعد القفل القادم", amountMinor: 0, explanation: "توقّع من كشفين على يوم الشهر نفسه؛ ليس تاريخًا مؤكّدًا من البنك.", message: nil, date: card.nextClose, estimated: true, valueText: card.nextClose == nil ? "غير معروف" : "تقريبًا") } } label: {
            VStack(alignment: .leading, spacing: 6) { Text(title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk); Text(visible || key == nil ? value : "•••").font(.custom("thmanyahserifdisplay-Bold", size: 19, relativeTo: .headline)).lineLimit(1).minimumScaleFactor(0.6); if let secondary { Text(secondary).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) } }
                .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading).padding(8).background(theme.surface, in: RoundedRectangle(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).stroke(theme.line, lineWidth: 1) }
        }.buttonStyle(.plain)
    }
    private func movement(_ row: MoneyCardMovement) -> some View {
        Button { source = row.detail } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "diamond.fill").font(.system(size: 7)).foregroundStyle(theme.color("bills"))
                VStack(alignment: .leading, spacing: 5) { Text(row.merchant).font(MadarTypography.body()); Text(row.budgeted ? "احتُسب في الميزانية يوم الشراء" : "خارج الميزانية").font(MadarTypography.fine()).foregroundStyle(theme.color("surplusText")) }
                Spacer(minLength: 2); dates(row.day); Text(figure: amount(row.amountMinor)).font(MadarTypography.body())
            }.padding(.vertical, 11).overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 0.7) }.contentShape(.rect)
        }.buttonStyle(.plain).accessibilityIdentifier("money-card-movement-" + row.merchant)
    }
    private func dates(_ day: GregorianDay) -> some View {
        MadarDateLabel(app.dateLabels(day, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
    }
    private func cashFlow(_ r: MoneyCardsReading) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("لو اشتريت اليوم، متى يخرج النقد").font(MadarTypography.cardTitle())
            ForEach(r.cards.filter { $0.kind == "credit" }) { c in
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text(c.name).font(MadarTypography.cardTitle()); Spacer(); if let grace = c.graceDays { Text(service.days(grace) + " تقريبًا").font(MadarTypography.caption()).foregroundStyle(theme.color("surplusText")) } }
                    if let due = c.purchaseDue, let close = c.nextClose {
                        if !dynamicType.isAccessibilitySize {
                            timeline(c, today: r.today, close: close, purchaseDue: due)
                        } else {
                            Text("يقفل تقريبًا").font(MadarTypography.body()); dates(close)
                            Text("يُسدّد شراء اليوم تقريبًا").font(MadarTypography.body()); dates(due)
                        }
                    } else { Text("نحتاج كشفين متتاليين بيوم قفل متوافق وموعد سداد، حتى نقدّر موعد شراء اليوم.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk) }
                }.padding(.bottom, 14)
            }
            HStack {
                Text("مبلغ الشراء").font(MadarTypography.caption()); Spacer()
                ForEach([50_000, 200_000, 800_000], id: \.self) { value in
                    Button { purchaseMinor = value } label: { Text(figure: amount(value)).font(MadarTypography.caption()).padding(.horizontal, 12).frame(minHeight: 44).background(purchaseMinor == value ? theme.ink : Color.clear, in: Capsule()).foregroundStyle(purchaseMinor == value ? theme.background : theme.ink).overlay { Capsule().stroke(theme.line, lineWidth: 1) } }.buttonStyle(.plain)
                }
            }
            let best = r.cards.filter { $0.kind == "credit" && $0.graceDays != nil }.max { ($0.graceDays ?? 0) < ($1.graceDays ?? 0) }?.id
            ForEach(r.cards.filter { $0.kind == "credit" }) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(c.name).font(MadarTypography.cardTitle()); if c.id == best { Text("أطول مهلة").font(MadarTypography.fine()).foregroundStyle(theme.color("reserveText")) } }
                        Text(c.graceDays.map { service.days($0) + " مهلة تقريبًا" } ?? "المهلة غير معروفة").font(MadarTypography.body())
                        Text(CardPlanning.cashbackEstimate(purchaseMinor: purchaseMinor, rateBp: c.cashbackBp).map { "استرداد متوقّع " + amount($0) } ?? "نسبة الاسترداد غير معروفة").font(MadarTypography.caption()).foregroundStyle(theme.color("surplusText"))
                    }
                    Spacer()
                }.padding(16).background(theme.surface, in: RoundedRectangle(cornerRadius: 14)).overlay { RoundedRectangle(cornerRadius: 14).stroke(c.id == best ? theme.color("reserveText") : theme.line, lineWidth: c.id == best ? 1.5 : 1) }
            }
            Label("يومك يتأثر يوم الشراء؛ النقد يخرج عند السداد. المهلة والاسترداد تقديران، وشروط البنك هي المرجع.", systemImage: "clock").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("money-card-cashflow")
    }
    private func calendar(_ r: MoneyCardsReading) -> some View {
        var primary = Calendar(identifier: app.string("core.firstCalendar") == "gregorian" ? .gregorian : .islamicUmmAlQura)
        primary.timeZone = app.activePlace.timeZone
        primary.firstWeekday = app.string("core.weekStart") == "sunday" ? 1 : app.string("core.weekStart") == "monday" ? 2 : 7
        let instant = r.today.date(in: primary.timeZone).addingTimeInterval(12 * 3600)
        let daysCalendar = MadarCalendarDays(zone: primary.timeZone, source: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura, offset: Int(app.number("core.hijriOffset")))
        let start = primary.identifier == .gregorian ? primary.dateInterval(of: .month, for: instant)?.start ?? instant : daysCalendar.hijriMonthStart(containing: r.today).date(in: primary.timeZone)
        let offset = (primary.component(.weekday, from: start) - primary.firstWeekday + 7) % 7
        let first = GregorianDay.containing(start, in: primary.timeZone).adding(days: -offset)
        let length = primary.identifier == .gregorian ? primary.range(of: .day, in: .month, for: instant)?.count ?? 30 : daysCalendar.hijriMonthLength(containing: r.today)
        let cells = ((length + offset + 6) / 7) * 7
        let days = (0..<cells).map { first.adding(days: $0) }
        let selected = r.dues.first { $0.id == selectedDue } ?? r.dues.first { $0.cardID == card?.id } ?? r.dues.first
        return VStack(alignment: .leading, spacing: 16) {
            dates(r.today)
            if !dynamicType.isAccessibilitySize {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        let weekday = (primary.firstWeekday - 1 + index) % 7
                        Text(["أحد", "اثنين", "ثلاثاء", "أربعاء", "خميس", "جمعة", "سبت"][weekday]).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    }
                    ForEach(days, id: \.description) { day in calendarCell(day, calendar: primary, today: r.today, dues: r.dues, selectedID: selected?.id) }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("money-card-calendar-grid")
            }
            if let selected {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(selected.name).font(MadarTypography.cardTitle()); Spacer(); Text(figure: amount(-selected.amountMinor)).font(MadarTypography.cardTitle()) }
                    dates(selected.day)
                    Text("النقد بعد الالتزامات المعروفة حتى هذا الموعد: " + amount(selected.cashAfterMinor)).font(MadarTypography.body())
                    Label(visible ? selected.cashAfterMinor >= 0 ? "يكفي من النقد الحالي" : "النقد الحالي لا يغطي المواعيد المعروفة" : "•••", systemImage: !visible ? "eye.slash" : selected.cashAfterMinor >= 0 ? "checkmark.circle" : "exclamationmark.triangle").font(MadarTypography.caption()).foregroundStyle(theme.color(visible && selected.cashAfterMinor < 0 ? "dueText" : "surplusText"))
                }.padding(16).background(theme.surface, in: RoundedRectangle(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.color("reserveText"), lineWidth: 1) }.accessibilityIdentifier("money-card-due-detail")
            } else { Text("لا مبالغ مستحقة معروفة بعد.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk) }
            Text("المواعيد المعروفة").font(MadarTypography.cardTitle())
            ForEach(r.dues) { due in
                Button { selectedDue = due.id } label: { HStack { Text(due.name); Spacer(); dates(due.day); Text(figure: amount(due.amountMinor)) }.font(MadarTypography.caption()).padding(.vertical, 8).contentShape(.rect) }.buttonStyle(.plain)
            }
            Text("التغطية من النقد الموجود الآن بعد المواعيد السابقة فقط، دون افتراض راتب قادم. لا يُحجز المال ولا يُسجّل سداد من هذه الصفحة.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("money-card-calendar")
    }
    private func calendarCell(_ day: GregorianDay, calendar: Calendar, today: GregorianDay, dues: [MoneyCardDue], selectedID: String?) -> some View {
        let instant = day.date(in: calendar.timeZone).addingTimeInterval(12 * 3600)
        let pair = DualDate(instant: instant, timeZone: calendar.timeZone, source: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(app.number("core.hijriOffset")))
        let items = dues.filter { $0.day == day }
        let shown = items.first { $0.id == selectedID } ?? items.first
        let content = VStack(spacing: 2) {
                Text(service.digits.string(calendar.identifier == .gregorian ? pair.gregorian.day : pair.hijri.day)).font(MadarTypography.caption())
                Text(service.digits.string(calendar.identifier == .gregorian ? pair.hijri.day : pair.gregorian.day)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                Text(shown?.name ?? " ").font(MadarTypography.fine()).lineLimit(1).foregroundStyle(theme.color("accentText"))
                if items.count > 1 { Text("+" + service.digits.string(items.count - 1)).font(MadarTypography.fine()) }
            }.frame(maxWidth: .infinity, minHeight: 61).background(items.isEmpty ? Color.clear : theme.surface)
                .overlay { if day == today { RoundedRectangle(cornerRadius: 7).stroke(theme.color("reserveText"), style: .init(lineWidth: 1, dash: [3, 2])) } }
                .overlay { if items.contains(where: { $0.id == selectedID }) { RoundedRectangle(cornerRadius: 7).stroke(theme.color("reserveText"), lineWidth: 1.5) } }
                .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 0.5) }
        let label = app.dateLabels(day).primary + "، " + app.dateLabels(day).secondary + "، " + items.map(\.name).joined(separator: "، ")
        return Group {
            if items.isEmpty { content.accessibilityElement(children: .ignore).accessibilityLabel(label) }
            else { Button { if let due = items.first { selectedDue = due.id } } label: { content }.buttonStyle(.plain).accessibilityLabel(label) }
        }
    }
    private func match(_ c: MoneyCardReading) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let payment = c.payment {
                Button { source = payment.detail } label: {
                    HStack { Image(systemName: "arrow.left.arrow.right").foregroundStyle(theme.color("reserveText")); VStack(alignment: .leading, spacing: 5) { Text("سداد " + c.name).font(MadarTypography.cardTitle()); Text("تحويل، ليس مصروفًا جديدًا").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk); dates(payment.day) }; Spacer(); Text(figure: amount(payment.amountMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 28, relativeTo: .title)) }.padding(16).overlay { RoundedRectangle(cornerRadius: 13).stroke(theme.color("reserveText"), lineWidth: 1) }.contentShape(.rect(cornerRadius: 13))
                }.buttonStyle(.plain).accessibilityIdentifier("money-card-payment-source")
                if !c.matchedPurchases.isEmpty {
                    let total = c.matchedPurchases.reduce(0) { $0 + $1.amountMinor }
                    GeometryReader { proxy in
                        HStack(spacing: 2) { ForEach(Array(c.matchedPurchases.enumerated()), id: \.element.id) { index, row in Rectangle().fill([theme.color("reserveText"), theme.color("accentText"), theme.color("bills"), theme.color("surplusText")][index % 4]).frame(width: visible && total > 0 ? proxy.size.width * CGFloat(max(0, row.amountMinor)) / CGFloat(total) : 0) } }.clipShape(.capsule)
                    }.frame(height: 12).accessibilityHidden(true)
                    ForEach(c.matchedPurchases) { movement($0) }
                    Label(total == payment.amountMinor ? "المشتريات المسجّلة تساوي هذا السداد" : "الفرق بين السداد والمشتريات المسجّلة " + amount(payment.amountMinor - total), systemImage: total == payment.amountMinor ? "checkmark.circle.fill" : "text.magnifyingglass")
                        .font(MadarTypography.body()).foregroundStyle(theme.color("surplusText"))
                    Text("مقارنة للمصادر المسجّلة في فترة الكشف؛ قد يشمل كشف البنك رصيدًا سابقًا أو رسومًا أو ردودًا لا تمثّلها هذه المشتريات.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                } else { Text("لا توجد فترة كشف بمشتريات مسجّلة تكفي لمقارنة هذا السداد. لا نفترض مطابقة كاملة.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk) }
            } else { Text("لا سداد مؤكّد لهذه البطاقة بعد").font(MadarTypography.cardTitle()); Text("عند وصول رسالة السداد واعتمادها تظهر هنا كتحويل، وتبقى مشترياتك في أيامها.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk) }
            Text("الكشف الحالي: " + amount(c.billedMinor) + "؛ غير المفوتر: " + amount(c.unbilledMinor)).font(MadarTypography.caption())
            Text("إذا كان السداد أقل من الكشف يبقى الباقي ضمن «عليك». الفائدة تُقدّر من النسبة المدخلة؛ كشف البنك هو المرجع.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("money-card-match")
    }
    private func timeline(_ c: MoneyCardReading, today: GregorianDay, close: GregorianDay, purchaseDue: GregorianDay) -> some View {
        let green = theme.color("surplusText"), red = theme.color("dueText"), gold = theme.color("reserveText")
        let statementDays = c.due.map { max(0, MadarCalendarDays.distance(from: today, to: $0)) }
        let closeDays = max(0, MadarCalendarDays.distance(from: today, to: close))
        let endDays = max(1, MadarCalendarDays.distance(from: today, to: purchaseDue))
        let span = Double(max(endDays, closeDays, statementDays ?? 0) + 8)
        let closeLabels = app.dateLabels(close, compact: true)
        let purchaseDueLabels = app.dateLabels(purchaseDue, compact: true)
        return GeometryReader { g in
            let w = g.size.width
            let x: (Int) -> CGFloat = { days in w * (1 - CGFloat(Double(days) / span)) }
            let dateTagWidth = min(116, max(96, w * 0.34))
            let closeX = x(closeDays)
            let purchaseDueX = x(endDays)
            let datesNeedSeparateRows = abs(closeX - purchaseDueX) < dateTagWidth + 12
            let tagCenter: (CGFloat) -> CGFloat = { min(max(dateTagWidth / 2, $0), w - dateTagWidth / 2) }
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(theme.ink).frame(width: 1.5, height: 92).position(x: w - 1, y: 46)
                    if let sd = statementDays {
                        Capsule().fill(red).frame(width: max(2, x(0) - x(sd)), height: 4).position(x: (x(0) + x(sd)) / 2, y: 17)
                        Circle().fill(red).frame(width: 12, height: 12).position(x: x(sd), y: 17)
                        Text("كشف " + amount(c.billedMinor)).font(MadarTypography.fine()).foregroundStyle(red).position(x: max(70, min(w - 70, x(sd) + 60)), y: 5)
                    }
                    Rectangle().fill(gold).frame(width: 1.5, height: 22).position(x: closeX, y: 40)
                    Text("يقفل").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).position(x: closeX, y: 27)
                    Capsule().fill(green).frame(width: x(0) - purchaseDueX, height: 3).position(x: (x(0) + purchaseDueX) / 2, y: 55)
                    Circle().stroke(green, lineWidth: 2).background(Circle().fill(theme.background)).frame(width: 14, height: 14).position(x: closeX, y: 55)
                    Circle().fill(green).frame(width: 14, height: 14).position(x: purchaseDueX, y: 55)
                    Text("شراء اليوم يُسدَّد").font(MadarTypography.fine()).foregroundStyle(green).position(x: max(60, min(w - 60, purchaseDueX + 50)), y: 71)
                }
                timelineDate(close, tint: theme.secondaryInk, width: dateTagWidth)
                    .position(x: tagCenter(closeX), y: 106)
                timelineDate(purchaseDue, tint: green, width: dateTagWidth)
                    .position(x: tagCenter(purchaseDueX), y: datesNeedSeparateRows ? 129 : 106)
            }.environment(\.layoutDirection, .leftToRight).frame(height: 145)
        }.frame(height: 145).accessibilityElement(children: .combine)
            .accessibilityLabel("يقفل تقريبًا " + closeLabels.combined + "، شراء اليوم يُسدَّد تقريبًا " + purchaseDueLabels.combined)
            .accessibilityIdentifier("money-card-cashflow-timeline")
    }
    private func timelineDate(_ day: GregorianDay, tint: Color, width: CGFloat) -> some View {
        let labels = app.dateLabels(day, compact: true)
        return VStack(alignment: .center, spacing: 1) {
            Text(labels.primary).font(MadarTypography.fine()).foregroundStyle(tint)
            Text(labels.secondary).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
        }.frame(width: width).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
    }
    private func load() {
        do { reading = try service.loadCards(); failure = nil } catch { reading = nil; failure = "لم تكتمل قراءة البطاقات. حاول مرة أخرى." }
    }
}

private struct MoneyCardEtching: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            let center = CGPoint(x: r.width * 0.78, y: r.height * 0.28), radius = r.height * 0.43
            for rotation in [0.0, Double.pi / 8] {
                for n in 0..<8 {
                    let angle = Double(n) * .pi / 4 + rotation
                    let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                    if n == 0 { p.move(to: point) } else { p.addLine(to: point) }
                }
                p.closeSubpath()
            }
            p.move(to: .init(x: -10, y: r.height * 0.8))
            p.addQuadCurve(to: .init(x: r.maxX + 10, y: r.height * 0.65), control: .init(x: r.midX, y: r.height * 1.05))
        }
    }
}
