import SwiftUI
import MadarCore
import MadarDesign
import MadarMoney

/// «الاسترداد النقدي · الجرّة» (`mal/25-Z-R18-cb-1`): the year's cashback as a jar that fills month by month, one layer
/// per month split by card, the year-end line dotted, then the months as stacked columns and what the purchases already
/// made would have returned on the highest-rate card. Numbers come from `CashbackJar`; the only write is a card's rate.
struct MoneyCashbackView: View {
    let app: AppSession
    @Binding var revealed: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reading: MoneyCashbackReading?
    @State private var loaded = false
    @State private var failure: String?
    @State private var selectedMonth: Int?
    @State private var selectedChip: String?
    @State private var savingPreferredCard = false
    @State private var preferredCardFailure: String?
    @State private var rateCard: MoneyCashbackCard?
    @State private var grown = false
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var service: AppMoneyService { .init(app: app) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private func amount(_ n: Int) -> String { visible ? service.amount(n) : "•••" }
    /// Shapes in the card's own colour (the miniature order of «البطاقات»); text under 24 pt uses the *Text variant.
    private func fill(_ tint: Int) -> Color { [theme.color("reserve"), theme.color("accent"), theme.color("surplus"), theme.color("bills")][tint % 4] }
    private func ink(_ tint: Int) -> Color { [theme.color("reserveText"), theme.color("accent"), theme.color("surplusText"), theme.ink][tint % 4] }
    /// mal rule: reserve (gold) shapes in charts carry a 1 pt reserveText edge; reserve on paper alone is 2.86:1.
    private func edge(_ tint: Int) -> Color { tint % 4 == 0 ? theme.color("reserveText") : .clear }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let reading {
                    if reading.cards.isEmpty { emptyPage }
                    else {
                        hero(reading)
                        if !visible { Button("أظهر الأرقام") { revealed = true }.font(MadarTypography.caption()).frame(minHeight: 44).accessibilityIdentifier("money-cashback-reveal") }
                        if reading.hasPurchases {
                            DoubleRule().stroke(theme.color("reserveText"), lineWidth: 0.8).frame(height: 3)
                            monthly(reading)
                            destinationSection(reading)
                            if let suggestion = reading.switchSuggestion { switchSection(suggestion) }
                        } else {
                            destinationSection(reading)
                        }
                        footnote(reading)
                    }
                } else if loaded {
                    Text(failure ?? "لم تكتمل قراءة الاسترداد. حاول مرة أخرى.").font(MadarTypography.body())
                    Button("أعِد المحاولة", action: load).frame(minHeight: 44)
                } else { ProgressView().frame(maxWidth: .infinity, minHeight: 260) }
            }.padding(.horizontal, 16).padding(.bottom, 96).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
            .task { load() }.onChange(of: app.prayerRevision) { load() }
            .sheet(item: $rateCard) { card in
                MoneyCashbackRateSheet(app: app, card: card, visible: visible) { rateCard = nil; load() }.environment(\.roomTheme, theme)
            }
            .accessibilityIdentifier("money-cashback")
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3).frame(width: 52, height: 52).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1.2) } }
                .buttonStyle(.plain).accessibilityLabel("إغلاق").accessibilityIdentifier("money-cashback-close")
            Text("الاسترداد النقدي").font(.custom("thmanyahserifdisplay-Bold", size: 28, relativeTo: .title)).accessibilityAddTraits(.isHeader)
            Spacer()
        }.padding(.top, 8)
    }

    // MARK: The jar and the year

    private func hero(_ r: MoneyCashbackReading) -> some View {
        let text = VStack(alignment: .leading, spacing: 4) {
            Text((r.jar.landedMinor > 0 ? "رجع لك ويتجمّع من بطاقاتك في " : "كسبته بطاقاتك في ") + r.yearTitle).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            Text(r.yearSecondary).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(whole(r.jar.headlineMinor)).font(.custom("thmanyahserifdisplay-Black", size: 76, relativeTo: .largeTitle)).lineLimit(1).minimumScaleFactor(0.45)
                    .contentTransition(.numericText()).accessibilityIdentifier("money-cashback-headline")
                VStack(alignment: .leading, spacing: 0) {
                    Text(app.string("core.currency") == "SAR" ? "ريال" : app.string("core.currency")).font(MadarTypography.body())
                    if r.jar.accumulatingMinor > 0 { Text("تقريبًا").font(MadarTypography.fine()).accessibilityIdentifier("money-cashback-approx") }
                }.foregroundStyle(theme.secondaryInk).fixedSize()
            }
            landedLine(r)
            VStack(alignment: .leading, spacing: 16) { ForEach(r.cards) { cardRow($0) } }.padding(.top, 14)
        }
        return Group {
            if dynamicType.isAccessibilitySize { text }
            else {
                HStack(alignment: .top, spacing: 8) {
                    text.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 6) {
                        MoneyCashbackJar(reading: r, visible: visible, spoken: whole(r.jar.headlineMinor), grown: grown, reduceMotion: reduceMotion, fill: fill, theme: theme)
                            .frame(width: 136, height: 232).accessibilityIdentifier("money-cashback-jar")
                        if let end = r.jar.yearEndMinor, visible {
                            Text("المنقّط: آخر السنة نحو " + whole(end)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).multilineTextAlignment(.center)
                                .accessibilityIdentifier("money-cashback-yearend")
                        } else if r.hasPurchases, visible {
                            Text("نقدّر آخر السنة بعد ثلاثة أشهر كاملة").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).multilineTextAlignment(.center)
                        }
                    }.frame(width: 138)
                }
            }
        }
    }
    /// The jar's numbers are estimates: whole currency units, as halalas would claim a precision they lack. Less than
    /// one unit stays exact, so a small earning never reads as zero.
    private func whole(_ n: Int) -> String {
        var scale = 1; for _ in 0..<(CurrencyExponents.specified.exponent(app.string("core.currency")) ?? 2) { scale *= 10 }
        return n != 0 && abs(n) < scale ? amount(n) : amount(MoneyMath.divideRounded(n, by: scale) * scale)
    }
    @ViewBuilder private func landedLine(_ r: MoneyCashbackReading) -> some View {
        let landed = Text(figure: amount(r.jar.landedMinor)).bold().foregroundStyle(theme.color("surplusText"))
        let gathering = Text(whole(r.jar.accumulatingMinor)).bold()
        Group {
            if r.jar.landedMinor == 0 { Text("لم ينزل شيء بعد، ويتجمّع \(gathering)") }
            else { Text("نزل \(landed)، ويتجمّع \(gathering)") }
        }.font(MadarTypography.body()).accessibilityIdentifier("money-cashback-landed")
        if !r.jar.unknownCards.isEmpty {
            let names = r.cards.filter { $0.total.unknown }.map(\.name).joined(separator: "، ")
            Text("لا يشمل " + names + "؛ نسبتها غير معروفة.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func cardRow(_ c: MoneyCashbackCard) -> some View {
        Button { rateCard = c } label: {
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 5).fill(LinearGradient(colors: c.tint == 0 ? [theme.color("rod2"), theme.ink.opacity(0.92)] : [fill(c.tint).opacity(0.85), fill(c.tint)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { RoundedRectangle(cornerRadius: 5).stroke(theme.color("reserve"), lineWidth: 1.2) }
                    .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(theme.color("reserve")).frame(width: 12, height: 9).padding(.leading, 8) }
                    .frame(width: 52, height: 36).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(.custom("thmanyahseriftext-Bold", size: 16, relativeTo: .subheadline)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(c.rateBp.map { "استرداد " + service.percent($0) } ?? "النسبة غير معروفة").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                }.layoutPriority(1)
                Spacer(minLength: 4)
                if let earned = c.total.earnedMinor, c.rateBp != nil || c.recorded {
                    Text(whole(earned)).font(.custom("thmanyahserifdisplay-Bold", size: 28, relativeTo: .title2)).foregroundStyle(ink(c.tint)).lineLimit(1).minimumScaleFactor(0.6)
                } else {
                    Text("أدخلها").font(MadarTypography.caption()).foregroundStyle(theme.color("accent")).padding(.horizontal, 10).frame(minHeight: 32)
                        .overlay { Capsule().stroke(theme.color("accent"), lineWidth: 1) }
                }
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(c.name + "، " + (c.rateBp.map { "استرداد " + service.percent($0) } ?? "النسبة غير معروفة") + (c.total.earnedMinor.map { c.rateBp != nil || c.recorded ? "، " + whole($0) : "" } ?? ""))
            .accessibilityHint("يفتح نسبة الاسترداد").accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("money-cashback-card-" + c.name)
    }

    // MARK: Month by month

    private func monthly(_ r: MoneyCashbackReading) -> some View {
        let shown = r.cards.filter { $0.rateBp != nil || $0.recorded }
        let selected = r.months.first { $0.id == (selectedMonth ?? r.current) } ?? r.months[r.current]
        let peak = max(1, r.jar.monthTotals.max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("كل شهر").font(.custom("thmanyahserifdisplay-Bold", size: 26, relativeTo: .title2)).accessibilityAddTraits(.isHeader)
                Spacer()
                HStack(spacing: 10) {
                    ForEach(shown) { card in
                        HStack(spacing: 4) { Rectangle().fill(fill(card.tint)).overlay { Rectangle().stroke(edge(card.tint), lineWidth: 1) }.frame(width: 10, height: 10); Text(card.name).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(1) }
                    }
                }.accessibilityHidden(true)
            }
            if dynamicType.isAccessibilitySize {
                ForEach(r.months) { m in
                    Button { selectedMonth = m.id } label: { HStack { Text(m.labels.primary); Spacer(); Text(whole(r.jar.monthTotals[m.id])) }.font(MadarTypography.body()).frame(minHeight: 44) }.buttonStyle(.plain)
                }
            } else {
                HStack(alignment: .bottom, spacing: r.months.count > 8 ? 4 : 10) {
                    ForEach(r.months) { m in monthColumn(m, reading: r, shown: shown, selected: m.id == selected.id, peak: peak) }
                }.frame(maxWidth: .infinity).animation(reduceMotion ? nil : .spring(duration: 0.5), value: selectedMonth)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("money-cashback-months")
            }
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selected.labels.primary + (selected.current ? " (يتجمّع)" : "")).font(.custom("thmanyahseriftext-Bold", size: 16, relativeTo: .subheadline))
                    Text(selected.labels.secondary).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    ForEach(shown) { card in
                        HStack(spacing: 5) {
                            Text(card.name).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(1)
                            Text(whole(card.total.monthly[selected.id] ?? 0)).font(MadarTypography.caption().bold()).foregroundStyle(ink(card.tint))
                        }
                    }
                }
            }.accessibilityElement(children: .combine).accessibilityIdentifier("money-cashback-selected")
        }
    }

    private func monthColumn(_ m: MoneyCashbackMonth, reading r: MoneyCashbackReading, shown: [MoneyCashbackCard], selected: Bool, peak: Int) -> some View {
        let narrow = r.months.count > 8
        let bars = VStack(spacing: 0) {
            Spacer(minLength: 0)
            // First card at the bottom, as in the jar.
            ForEach(shown.reversed()) { card in
                let value = CGFloat(card.total.monthly[m.id] ?? 0), scale: CGFloat = grown ? 1 : 0.02
                Rectangle().fill(fill(card.tint).opacity(m.current ? 0.6 : 1)).overlay { Rectangle().stroke(edge(card.tint), lineWidth: value > 0 ? 1 : 0) }
                    .frame(height: visible ? value / CGFloat(peak) * 132 * scale : 0)
            }
        }
        let label = Text(m.short).font(selected ? MadarTypography.fine().bold() : MadarTypography.fine())
        return Button { selectedMonth = m.id } label: {
            VStack(spacing: 6) {
                bars.frame(width: narrow ? 24 : 30, height: 136).padding(.horizontal, narrow ? 4 : 8)
                    .background { if selected { RoundedRectangle(cornerRadius: 3).fill(theme.color("glass")).padding(.top, -6) } }
                    .overlay(alignment: .bottom) { Rectangle().fill(theme.ink).frame(height: 1).padding(.horizontal, -6) }
                VStack(spacing: 0) {
                    label.foregroundStyle(selected ? theme.ink : theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.7)
                    Text(m.secondaryShort).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.55)
                }
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(m.labels.primary + "، " + m.labels.secondary + "، " + whole(r.jar.monthTotals[m.id]) + (m.current ? "، يتجمّع" : ""))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("money-cashback-month-" + String(m.id))
    }

    // MARK: The highest rate

    private func switchSection(_ s: MoneyCashbackSwitch) -> some View {
        // Up to four categories, the rest together as «أخرى».
        var chips = Array(s.rows.prefix(s.rows.count > 5 ? 4 : 5))
        if s.rows.count > 5 {
            let rest = s.rows.dropFirst(4)
            chips.append(.init(id: "other", categoryID: nil, title: "أخرى", from: Array(Set(rest.flatMap(\.from))).sorted(),
                               baseMinor: rest.reduce(0) { $0 + $1.baseMinor }, gainMinor: rest.reduce(0) { $0 + $1.gainMinor }, preferredCardID: nil))
        }
        let chosen = chips.first { $0.id == selectedChip }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("لو كانت على " + s.to.name).font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title3)).lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text("+" + whole(s.totalMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 26, relativeTo: .title2)).foregroundStyle(theme.color("surplusText"))
                Text("هذه السنة").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }.accessibilityElement(children: .combine).accessibilityIdentifier("money-cashback-switch")
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        Button { selectedChip = selectedChip == chip.id ? nil : chip.id } label: {
                        VStack(spacing: 3) {
                            Text(chip.title).font(MadarTypography.caption().bold()).lineLimit(1).minimumScaleFactor(0.75)
                            Text("+" + whole(chip.gainMinor)).font(MadarTypography.fine().bold()).foregroundStyle(theme.color("surplusText"))
                        }.frame(maxWidth: .infinity, minHeight: 62).padding(.horizontal, 2)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                        .overlay { RoundedRectangle(cornerRadius: 14).stroke(chip.id == selectedChip ? theme.color("reserveText") : theme.line, lineWidth: 1) }
                        .accessibilityAddTraits(chip.id == selectedChip ? .isSelected : [])
                        .accessibilityIdentifier("money-cashback-chip-" + chip.title + (chips.filter { $0.title == chip.title }.count > 1 ? "-" + chip.id : ""))
                    }
                }
            }
            if let chosen {
                Text("اشتريت «" + chosen.title + "» بـ" + whole(chosen.baseMinor) + " على " + chosen.from.joined(separator: " و") + " هذه السنة؛ بنسبة " + s.to.name + " (" + (s.to.rateBp.map(service.percent) ?? "") + ") كانت ترجع " + whole(chosen.gainMinor) + " أكثر.")
                    .font(MadarTypography.body()).fixedSize(horizontal: false, vertical: true).padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16)).accessibilityIdentifier("money-cashback-chip-detail")
                if let categoryID = chosen.categoryID {
                    let isPreferred = chosen.preferredCardID == s.to.id
                    Button { setPreferredCard(categoryID: categoryID, cardID: isPreferred ? nil : s.to.id, selectionID: chosen.id) } label: {
                        Text(isPreferred ? "أزل البطاقة المفضلة لـ" + chosen.title : "اجعل " + s.to.name + " المفضلة لـ" + chosen.title)
                            .font(MadarTypography.caption().weight(.semibold)).frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.plain).disabled(savingPreferredCard)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .accessibilityLabel(isPreferred ? "أزل البطاقة المفضلة لتصنيف " + chosen.title : "اجعل " + s.to.name + " البطاقة المفضلة لتصنيف " + chosen.title)
                    .accessibilityIdentifier("money-cashback-preferred-card-" + chosen.id)
                    if let preferredCardFailure { Text(preferredCardFailure).font(MadarTypography.fine()).foregroundStyle(theme.color("dueText")) }
                }
            }
            Text("مقارنة لما اشتريته فعلًا، لا دعوة لشراء أكثر. قد تستثني شروط البنك بعض الفئات أو تضع للاسترداد سقفًا.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func footnote(_ r: MoneyCashbackReading) -> some View {
        Label(r.hasPurchases ? "الجرّة تقدير: مشتريات كل بطاقة في الشهر بعد الردود × نسبتها. لا تغيّر نقدك ولا «لك فعلًا»، وما ينزل فعلًا يُحسب مرة واحدة. اضغط بطاقة لترى نسبتها ومصدرها."
                : "لا مشتريات مؤكّدة بالبطاقة في هذه السنة بعد. تمتلئ الجرّة مع أول شراء، من نسبة كل بطاقة.", systemImage: "info.circle")
            .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
    }

    private func destinationSection(_ r: MoneyCashbackReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("وين يروح الاسترداد؟").font(MadarTypography.section()).accessibilityAddTraits(.isHeader)
            Text("عند تأكيد استرداد نقدي مودع، ينتقل إلى الظرف الذي تختاره. إذا خفّض الاسترداد دين بطاقة ائتمان، يبقى تخفيضًا للدين.")
                .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            GlassEffectContainer(spacing: 8) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                          alignment: .trailing, spacing: 8) {
                    destinationChip(id: nil, name: "الفائض", selected: r.destinationID == nil)
                    ForEach(r.destinations) { destination in
                        destinationChip(id: destination.id, name: destination.name, selected: r.destinationID == destination.id)
                    }
                }
            }
            if r.destinations.isEmpty {
                Text("أضف ظرفًا من غرفة المال ليظهر هنا.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
        }
        .padding(.top, 4)
        .accessibilityIdentifier("money-cashback-destination-section")
    }

    private func destinationChip(id: UUID?, name: String, selected: Bool) -> some View {
        Button {
            guard !selected else { return }
            app.set(.string(id?.uuidString ?? ""), key: "mal.cashbackDestination") { load() }
        } label: {
            Text(name).font(MadarTypography.caption().weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.78).padding(.horizontal, 4).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .overlay { Capsule().stroke(selected ? theme.color("reserveText") : .clear, lineWidth: 1) }
        .accessibilityLabel(name + (selected ? "، الوجهة المختارة" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("money-cashback-destination-\(id?.uuidString ?? "surplus")")
    }

    private func setPreferredCard(categoryID: UUID, cardID: UUID?, selectionID: String) {
        guard !savingPreferredCard else { return }
        savingPreferredCard = true
        preferredCardFailure = nil
        Task {
            do {
                try await app.executeMoneyCommand("money.setCategoryPreferredCard", payload: [
                    "categoryID": .string(categoryID.uuidString), "cardID": cardID.map { .string($0.uuidString) } ?? .null
                ])
                selectedChip = selectionID
                load()
            } catch { preferredCardFailure = "لم يُحفظ التفضيل. حاول مرة أخرى." }
            savingPreferredCard = false
        }
    }

    private var emptyPage: some View {
        VStack(spacing: 14) {
            MoneyCashbackJarOutline().stroke(theme.color("reserveText"), lineWidth: 1.4).frame(width: 120, height: 190)
                .overlay(alignment: .top) { RoundedRectangle(cornerRadius: 1.5).fill(theme.color("reserve")).frame(width: 53, height: 7) }
                .padding(.top, 20).accessibilityHidden(true)
            Text("لا بطاقات بعد").font(MadarTypography.cardTitle())
            Text("تظهر بطاقاتك هنا بعد تحديد هويتها في رسائل البنك، ثم تمتلئ الجرّة من نسبة استرداد كل بطاقة.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine).accessibilityIdentifier("money-cashback-empty")
    }

    private func load() {
        do { reading = try service.loadCashback(); failure = reading == nil ? "لم تكتمل قراءة الاسترداد. حاول مرة أخرى." : nil }
        catch { reading = nil; failure = "لم تكتمل قراءة الاسترداد. حاول مرة أخرى." }
        loaded = true
        guard !grown else { return }
        if reduceMotion { grown = true } else { withAnimation(.spring(duration: 1.1, bounce: 0.15).delay(0.15)) { grown = true } }
    }
}

// MARK: The jar

/// The jar's body: lid, neck, round shoulders, a full belly and a narrower foot.
struct MoneyCashbackJarOutline: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        return Path { p in
            p.move(to: .init(x: w * 0.36, y: h * 0.035))
            p.addLine(to: .init(x: w * 0.36, y: h * 0.11))
            p.addCurve(to: .init(x: w * 0.02, y: h * 0.52), control1: .init(x: w * 0.36, y: h * 0.17), control2: .init(x: w * 0.0, y: h * 0.24))
            p.addCurve(to: .init(x: w * 0.24, y: h), control1: .init(x: w * 0.04, y: h * 0.78), control2: .init(x: w * 0.14, y: h * 0.93))
            p.addLine(to: .init(x: w * 0.76, y: h))
            p.addCurve(to: .init(x: w * 0.98, y: h * 0.52), control1: .init(x: w * 0.86, y: h * 0.93), control2: .init(x: w * 0.96, y: h * 0.78))
            p.addCurve(to: .init(x: w * 0.64, y: h * 0.11), control1: .init(x: w * 1.0, y: h * 0.24), control2: .init(x: w * 0.64, y: h * 0.17))
            p.addLine(to: .init(x: w * 0.64, y: h * 0.035))
            p.closeSubpath()
        }
    }
}

private struct MoneyCashbackJar: View {
    let reading: MoneyCashbackReading
    let visible: Bool
    let spoken: String
    let grown: Bool
    let reduceMotion: Bool
    let fill: (Int) -> Color
    let theme: RoomTheme

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height - 14, body = MoneyCashbackJarOutline()
            let total = reading.jar.headlineMinor, end = reading.jar.yearEndMinor ?? 0
            // The jar holds a little more than the year end, so the dotted line sits below the neck.
            let capacity = CGFloat(max(1, max(end, total))) * 1.12
            let usable = h * 0.86, base = h
            ZStack(alignment: .topLeading) {
                // A soft reflection under the jar, as on polished wood.
                Ellipse().fill(RadialGradient(colors: [theme.color("rod").opacity(0.22), .clear], center: .center, startRadius: 2, endRadius: w * 0.42))
                    .frame(width: w * 0.8, height: 16).position(x: w / 2, y: h + 5)
                body.fill(theme.color("surface")).frame(width: w, height: h)
                if visible {
                    ZStack(alignment: .topLeading) {
                        layers(width: w, base: base, usable: usable, capacity: capacity)
                        if end > 0 {
                            let y = base - CGFloat(end) / capacity * usable
                            Path { p in p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: w, y: y)) }
                                .stroke(theme.ink, style: .init(lineWidth: 1.2, dash: [4, 3]))
                        }
                    }.frame(width: w, height: h).clipShape(body)
                    if reading.jar.accumulatingMinor > 0 { drops(width: w, top: h * 0.2, bottom: base - CGFloat(total) / capacity * usable * (grown ? 1 : 0)) }
                }
                // Glass light on the left shoulder.
                Path { p in p.move(to: .init(x: w * 0.12, y: h * 0.42)); p.addQuadCurve(to: .init(x: w * 0.16, y: h * 0.8), control: .init(x: w * 0.07, y: h * 0.62)) }
                    .stroke(Color.white.opacity(0.55), style: .init(lineWidth: 3, lineCap: .round))
                // Ornament under the neck.
                Path { p in
                    p.move(to: .init(x: w * 0.24, y: h * 0.27)); p.addQuadCurve(to: .init(x: w * 0.42, y: h * 0.2), control: .init(x: w * 0.3, y: h * 0.19))
                    p.move(to: .init(x: w * 0.76, y: h * 0.27)); p.addQuadCurve(to: .init(x: w * 0.58, y: h * 0.2), control: .init(x: w * 0.7, y: h * 0.19))
                }.stroke(theme.color("reserve"), lineWidth: 1)
                body.stroke(theme.color("reserveText"), lineWidth: 1.6).frame(width: w, height: h)
                RoundedRectangle(cornerRadius: 1.5).fill(theme.color("reserve")).overlay { RoundedRectangle(cornerRadius: 1.5).stroke(theme.color("reserveText"), lineWidth: 0.8) }
                    .frame(width: w * 0.44, height: h * 0.035).position(x: w / 2, y: h * 0.0175)
            }.environment(\.layoutDirection, .leftToRight)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(visible ? "جرّة الاسترداد، فيها " + spoken : "جرّة الاسترداد، المبالغ مخفية")
    }

    /// One layer per month from the bottom, split left to right by card; the month still gathering is lighter.
    private func layers(width w: CGFloat, base: CGFloat, usable: CGFloat, capacity: CGFloat) -> some View {
        let shown = reading.cards.filter { $0.rateBp != nil || $0.recorded }
        var y = base
        var rects: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: Color, edge: Color, current: Bool)] = []
        for month in reading.months {
            let height = CGFloat(reading.jar.monthTotals[month.id]) / capacity * usable * (grown ? 1 : 0)
            guard height > 0 else { continue }
            let monthTotal = CGFloat(max(1, reading.jar.monthTotals[month.id]))
            var x: CGFloat = 0
            for card in shown.reversed() {
                let value = CGFloat(card.total.monthly[month.id] ?? 0)
                guard value > 0 else { continue }
                let part = w * value / monthTotal
                rects.append((x, y - height, part, height, fill(card.tint), card.tint % 4 == 0 ? theme.color("reserveText") : .clear, month.current)); x += part
            }
            y -= height
        }
        return ZStack(alignment: .topLeading) {
            ForEach(Array(rects.enumerated()), id: \.offset) { _, r in
                Rectangle().fill(r.color.opacity(r.current ? 0.55 : 0.95)).overlay { Rectangle().stroke(r.edge, lineWidth: 0.8) }.frame(width: r.w, height: r.h)
                    .overlay(alignment: .top) { Rectangle().fill(theme.color("surface").opacity(0.75)).frame(height: 0.8) }
                    .offset(x: r.x, y: r.y)
            }
        }.frame(width: w, height: base, alignment: .topLeading)
    }

    /// Three drops falling into what is still gathering; still when Reduce Motion is on.
    private func drops(width w: CGFloat, top: CGFloat, bottom: CGFloat) -> some View {
        let lane = max(8, bottom - top)
        return TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0.35 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let phase = (t / 2.6 + Double(index) * 0.33).truncatingRemainder(dividingBy: 1)
                    let x = [0.47, 0.55, 0.5][index] * w, y = top + CGFloat(phase) * lane
                    MoneyCashbackDrop().fill(theme.color("accent").opacity(reduceMotion ? 0.85 : 1 - phase * 0.6))
                        .frame(width: index == 1 ? 7 : 9, height: index == 1 ? 10 : 13).position(x: x, y: y)
                }
            }
        }.allowsHitTesting(false)
    }
}

private struct MoneyCashbackDrop: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: .init(x: r.midX, y: r.minY))
            p.addCurve(to: .init(x: r.midX, y: r.maxY), control1: .init(x: r.midX + r.width * 0.75, y: r.height * 0.55), control2: .init(x: r.maxX, y: r.maxY))
            p.addCurve(to: .init(x: r.midX, y: r.minY), control1: .init(x: r.minX, y: r.maxY), control2: .init(x: r.midX - r.width * 0.75, y: r.height * 0.55))
        }
    }
}

// MARK: The rate sheet

/// §7.5 «يدخل يدويًا مرة: نسبة الاسترداد»: the rate in quarter-percent steps, what it returns on an amount the user can
/// picture, and where the stored rate came from. Saving is `money.setCardCashback` with the app's undo.
struct MoneyCashbackRateSheet: View {
    let app: AppSession
    let card: MoneyCashbackCard
    let visible: Bool
    let done: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var bp: Int?
    @State private var saving = false
    @State private var failure: String?
    private var service: AppMoneyService { .init(app: app) }
    init(app: AppSession, card: MoneyCashbackCard, visible: Bool, done: @escaping () -> Void) {
        self.app = app; self.card = card; self.visible = visible; self.done = done
        _bp = State(initialValue: card.rateBp)
    }
    private var unit: Int { var scale = 1; for _ in 0..<(CurrencyExponents.specified.exponent(app.string("core.currency")) ?? 2) { scale *= 10 }; return scale }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("نسبة الاسترداد").font(.custom("thmanyahserifdisplay-Bold", size: 24, relativeTo: .title2)).accessibilityAddTraits(.isHeader)
                Text(card.name).font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                HStack(spacing: 18) {
                    stepButton("plus", label: "زد ربع بالمئة", id: "money-cashback-rate-plus") { bp = min(10_000, (bp ?? 0) + 25) }
                    Text(bp.map(service.percent) ?? "؟").font(.custom("thmanyahserifdisplay-Black", size: 54, relativeTo: .largeTitle)).frame(maxWidth: .infinity)
                        .contentTransition(.numericText()).accessibilityIdentifier("money-cashback-rate-value")
                    stepButton("minus", label: "أنقص ربع بالمئة", id: "money-cashback-rate-minus") { bp = max(0, (bp ?? 25) - 25) }
                }
                HStack(spacing: 6) {
                    ForEach([50, 100, 150, 200], id: \.self) { value in
                        Button { bp = value } label: {
                            Text(service.percent(value)).font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 44)
                                .background(bp == value ? theme.ink : Color.clear, in: Capsule()).foregroundStyle(bp == value ? theme.background : theme.ink)
                                .overlay { Capsule().stroke(theme.line, lineWidth: 1) }
                        }.buttonStyle(.plain).accessibilityAddTraits(bp == value ? .isSelected : []).accessibilityIdentifier("money-cashback-rate-chip-" + String(value))
                    }
                }
                let sample = 1_000 * unit
                Text(bp.flatMap { CardPlanning.cashbackEstimate(purchaseMinor: sample, rateBp: $0) }.map { "كل " + service.amount(sample) + " ريال تشتري بها يرجع منها " + service.amount($0) + " تقريبًا." } ?? "اختر النسبة كما في شروط البطاقة.")
                    .font(MadarTypography.body()).accessibilityIdentifier("money-cashback-rate-preview")
                Text(card.source.explanation).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                if let message = card.source.message { Text(message).font(MadarTypography.fine()).padding(10).background(theme.surface, in: RoundedRectangle(cornerRadius: 10)) }
                Text("تجدها في شروط البطاقة أو في كشف البنك.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                if let failure { Text(failure).font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")) }
                Button { if let bp { save(bp) } } label: {
                    Text("احفظ النسبة").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 52).background(theme.ink, in: Capsule()).foregroundStyle(theme.background)
                }.buttonStyle(.plain).disabled(saving || bp == nil || bp == card.rateBp).opacity(bp == nil || bp == card.rateBp ? 0.45 : 1).accessibilityIdentifier("money-cashback-rate-save")
                if card.rateBp != nil {
                    Button { save(nil) } label: { Text("لا أعرفها").font(MadarTypography.body()).frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.plain).disabled(saving).accessibilityIdentifier("money-cashback-rate-unknown")
                }
            }.padding(20)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
            .presentationDetents([.fraction(0.72), .large]).presentationDragIndicator(.visible)
            .accessibilityIdentifier("money-cashback-rate-sheet")
    }
    private func stepButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.title3).frame(width: 48, height: 48).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1) } }
            .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private func save(_ value: Int?) {
        guard !saving else { return }
        saving = true
        Task {
            do {
                try await app.executeMoneyCommand("money.setCardCashback", payload: ["id": .string(card.id.uuidString), "cashbackBp": value.map { .number(Double($0)) } ?? .null])
                done()
            } catch { failure = "لم تُحفظ النسبة. حاول مرة أخرى."; saving = false }
        }
    }
}
