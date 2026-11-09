import SwiftUI
import MadarCore
import MadarDesign
import MadarMoney

/// «المطابقة مع البنك» (`mal/24-Z-R19-rec`, F03): Madar's book and the bank's figure side by side under two arches,
/// the difference in the diamond between them, a name for it, and «محضر جرد الحسابات» for every account and card.
/// One press writes the whole record in one command with one undo.
struct MoneyReconcileView: View {
    let app: AppSession
    @Binding var revealed: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    struct Entry: Equatable { var observedMinor: Int; var at: Date?; var name: ReconcileName? }
    @State private var reading: MoneyReconcileReading?
    @State private var failure: String?
    @State private var entries: [UUID: Entry] = [:]
    @State private var selected: UUID?
    @State private var typed = ""
    @State private var source: MoneySourceDetail?
    @State private var saving = false
    @State private var note: String?
    @State private var messagesOpen = false
    @State private var unknownAccount: MoneyAccountEdit?
    @FocusState private var typing: Bool
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var service: AppMoneyService { .init(app: app) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private var exponent: Int { CurrencyExponents.specified.exponent(app.string("core.currency")) ?? 2 }
    private func amount(_ minor: Int) -> String { visible ? service.amount(minor) : "•••" }
    /// A signed difference reads left to right («−٣٢٠») inside the Arabic line.
    private func signed(_ minor: Int) -> String {
        guard visible else { return "•••" }
        return "\u{2066}" + (minor < 0 ? "−" : minor > 0 ? "+" : "") + service.amount(abs(minor)) + "\u{2069}"
    }
    private var row: MoneyReconcileRow? { reading?.rows.first { $0.id == selected } ?? reading?.rows.first }
    private var reconcileEveryDays: Int { min(365, max(1, Int(app.number("mal.reconcileEveryDays")))) }
    private func line(_ r: MoneyReconcileRow) -> ReconcileLine? {
        entries[r.id].map { ReconcileLine(side: r.side, expectedMinor: r.expectedMinor, observedMinor: $0.observedMinor) }
    }
    private var summary: ReconcileEngine.Summary {
        ReconcileEngine.summary((reading?.rows ?? []).compactMap { r in line(r).map { ($0, entries[r.id]?.name) } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let reading {
                    ForEach(reading.unknownAccounts) { account in
                        Button { unknownAccount = account } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(account.name).font(MadarTypography.cardTitle())
                                Text("لم يُعرف رصيدها بعد").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                                Label("أدخل رصيد البنك", systemImage: "plus.circle").font(MadarTypography.body())
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(theme.surface, in: .rect(cornerRadius: 12))
                        }.buttonStyle(.madarPlain).accessibilityIdentifier("money-reconcile-unknown-" + account.id.uuidString)
                    }
                    if reading.rows.isEmpty && reading.unknownAccounts.isEmpty { emptyPage }
                    else if let row {
                        status(row)
                        identity(row, reading: reading)
                        arches(row)
                        sentence(row)
                        if !visible { Button { revealed = true } label: { Text("أظهر الأرقام").font(MadarTypography.caption()).frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("money-reconcile-reveal") }
                        nudges(row)
                        naming(row, reading: reading)
                        hint(row)
                        ledger(reading)
                    }
                } else if let failure { Text(failure).font(MadarTypography.body()); Button("أعِد المحاولة", action: load).frame(minHeight: 44) }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 260) }
            }.padding(.horizontal, 16).padding(.bottom, 24).frame(maxWidth: 620).frame(maxWidth: .infinity)
                .accessibilityElement(children: .contain).accessibilityIdentifier("money-reconcile")
        }
        .safeAreaInset(edge: .bottom) { if reading?.rows.isEmpty == false { saveButton } }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).environment(\.roomTheme, theme)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task { load() }.onChange(of: app.prayerRevision) { load() }
        .madarSheetLock(saving: saving)
        .sheet(item: $source) { MoneySourceView(app: app, detail: $0, visible: visible).environment(\.roomTheme, theme) }
        .sheet(item: $unknownAccount, onDismiss: load) { MoneyAccountSheet(app: app, original: $0, visible: visible, revealed: $revealed) }
        .navigationDestination(isPresented: $messagesOpen) { MoneyMessagesView(app: app, revealed: $revealed) }
        .onChange(of: messagesOpen) { if !messagesOpen { load() } }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3).frame(width: 52, height: 52).glassEffect(.regular.interactive(), in: .circle) }.madarWaitsForSave()
                .buttonStyle(.madarPlain).glassEffect(.regular.interactive(), in: Circle())
                .disabled(saving).accessibilityLabel("إغلاق").accessibilityIdentifier("money-reconcile-close")
            Text("المطابقة مع البنك").font(.custom("thmanyahserifdisplay-Bold", size: 27, relativeTo: .title)).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }.padding(.top, 6)
    }

    /// «آخر مطابقة» with both dates, and one square per day since: gold where a confirmed movement could have drifted the book.
    private func status(_ r: MoneyReconcileRow) -> some View {
        let today = reading?.today ?? .containing(app.prayerNow(), in: app.activePlace.timeZone)
        let span = r.since.map { max(0, MadarCalendarDays.distance(from: $0, to: today)) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if let last = r.lastAt {
                    let day = GregorianDay.containing(last, in: app.activePlace.timeZone)
                    Text("آخر مطابقة").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    inlineDate(day)
                } else {
                    Text(r.side == .account ? "لم تُطابقه بعد" : "لم تُطابقها بعد").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }
                if let span, span > 0, !dynamicType.isAccessibilitySize {
                    MoneyReconcileSquares(days: span, active: r.since.map { since in Set(r.activeDays.map { MadarCalendarDays.distance(from: since, to: $0) }) } ?? [])
                        .frame(height: 10).frame(maxWidth: .infinity).accessibilityHidden(true)
                } else { Spacer(minLength: 0) }
                if let span {
                    Text(span == 0 ? "اليوم" : "مرّ " + PrayerCopy.days(span, digits: service.digits)).font(MadarTypography.fine()).bold().foregroundStyle(theme.color("dueText")).fixedSize()
                }
            }
            if r.lastAt == nil, let since = r.since {
                HStack(spacing: 6) { Text(r.side == .account ? "الدفتر من رصيد البداية" : "الدفتر من أول حركة").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk); inlineDate(since) }
            }
            if let span {
                let left = reconcileEveryDays - span
                HStack {
                    Spacer(minLength: 0)
                    Text(left > 0 ? "موعد المطابقة بعد " + PrayerCopy.days(left, digits: service.digits)
                         : left == 0 ? "حان موعد المطابقة"
                         : "تأخرت المطابقة " + PrayerCopy.days(abs(left), digits: service.digits))
                        .font(MadarTypography.fine()).foregroundStyle(left > 0 ? theme.secondaryInk : theme.color("dueText"))
                        .accessibilityIdentifier("money-reconcile-cadence")
                }
            }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("money-reconcile-status")
    }

    private func identity(_ r: MoneyReconcileRow, reading: MoneyReconcileReading) -> some View {
        Menu {
            ForEach(reading.rows) { item in Button(item.name) { select(item.id) } }
        } label: {
            HStack(spacing: 10) {
                Text(String(r.name.prefix(1))).font(.custom("thmanyahserifdisplay-Bold", size: 15, relativeTo: .body)).foregroundStyle(theme.color("accentText"))
                    .frame(width: 32, height: 32).glassEffect(.regular.interactive(), in: .circle)
                Text(r.name).font(.custom("thmanyahserifdisplay-Bold", size: 25, relativeTo: .title2)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 6)
                Text(r.side == .account ? "حساب، يقارن النقد" : r.side == .creditCard ? "بطاقة، تقارن الدين" : "تقسيط، يقارن رصيد المزود")
                    .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }.contentShape(Rectangle())
        }.buttonStyle(.madarPlain).accessibilityIdentifier("money-reconcile-account")
    }

    private func arches(_ r: MoneyReconcileRow) -> some View {
        let entry = entries[r.id], delta = line(r)?.deltaMinor
        let matched = delta == 0
        return ZStack(alignment: .top) {
            HStack(spacing: 50) {
                Button { source = composition(r) } label: {
                    arch(caption: bookCaption(r), title: bookTitle(r), tint: theme.color("accent"), titleTint: theme.color("accentText"), matched: matched) {
                        Text(figure: amount(r.expectedMinor)).font(.custom("thmanyahserifdisplay-Black", size: 33, relativeTo: .largeTitle)).minimumScaleFactor(0.5).lineLimit(1)
                            .accessibilityIdentifier("money-reconcile-expected")
                    }
                }.buttonStyle(.madarPlain).disabled(!visible).accessibilityHint("يعرض كيف تكوّن هذا الرقم")
                    .accessibilityIdentifier("money-reconcile-madar")
                arch(caption: providerCaption(r), title: providerTitle(r), tint: theme.color("dueText"), titleTint: theme.color("dueText"), matched: matched) {
                    VStack(spacing: 4) {
                        if visible {
                            // The figure reads like Madar's (grouped digits); a tap turns it into the field.
                            ZStack {
                                TextField("أدخِل", text: $typed).keyboardType(.decimalPad).multilineTextAlignment(.center).focused($typing)
                                    .font(.custom("thmanyahserifdisplay-Black", size: 33, relativeTo: .largeTitle)).foregroundStyle(theme.color("dueText"))
                                    .minimumScaleFactor(0.5).opacity(typing || entry == nil ? 1 : 0)
                                    .accessibilityLabel(r.side == .account ? "رصيد البنك" : "مستحق البنك").accessibilityIdentifier("money-reconcile-bank-field")
                                    .onChange(of: typed) { commitTyped(r) }
                                if let entry, !typing {
                                    Text(figure: amount(entry.observedMinor)).font(.custom("thmanyahserifdisplay-Black", size: 33, relativeTo: .largeTitle)).foregroundStyle(theme.color("dueText"))
                                        .minimumScaleFactor(0.5).lineLimit(1).contentTransition(.numericText()).onTapGesture { typing = true }
                                        .accessibilityHidden(true)
                                }
                            }
                        } else { Text("•••").font(.custom("thmanyahserifdisplay-Black", size: 33, relativeTo: .largeTitle)) }
                        Line().stroke(theme.color("dueText"), style: .init(lineWidth: 0.9, dash: [3, 3])).frame(height: 1).padding(.horizontal, 14)
                    }
                }
            }
            VStack(spacing: 6) {
                PrayerStar().fill(theme.color("reserve")).frame(width: 22, height: 22).padding(.top, 2).accessibilityHidden(true)
                ZStack {
                    Rectangle().fill(theme.background).frame(width: 52, height: 52).rotationEffect(.degrees(45))
                    Rectangle().stroke(matched ? theme.color("surplusText") : theme.color("dueText"), lineWidth: 1.2).frame(width: 52, height: 52).rotationEffect(.degrees(45))
                    Rectangle().stroke(matched ? theme.color("surplusText") : theme.color("dueText"), lineWidth: 0.7).frame(width: 44, height: 44).rotationEffect(.degrees(45))
                    Text(delta.map(signed) ?? "؟").font(MadarTypography.caption()).bold().foregroundStyle(matched ? theme.color("surplusText") : theme.color("dueText"))
                        .minimumScaleFactor(0.85).lineLimit(1).frame(width: 66).contentTransition(.numericText())
                        .accessibilityLabel(delta.map { "الفرق " + signed($0) } ?? "لم يُدخل رصيد البنك").accessibilityIdentifier("money-reconcile-delta")
                }.padding(.top, 34)
            }
        }.frame(maxWidth: .infinity).animation(reduceMotion ? nil : .snappy, value: entry)
    }

    private func bookCaption(_ r: MoneyReconcileRow) -> String {
        switch r.side { case .account: "ما يظنه مدار"; case .creditCard: "ما يحسبه مدار عليك"; case .installment: "ما بقي في جدول مدار" }
    }
    private func bookTitle(_ r: MoneyReconcileRow) -> String {
        switch r.side { case .account: "نقد مدار"; case .creditCard: "دين مدار"; case .installment: "المتبقي عند مدار" }
    }
    private func providerCaption(_ r: MoneyReconcileRow) -> String {
        switch r.side { case .account: "كم عندك فعلًا"; case .creditCard: "كم عليك فعلًا"; case .installment: "ما يظهر في حساب المزود" }
    }
    private func providerTitle(_ r: MoneyReconcileRow) -> String {
        switch r.side { case .account: "رصيد البنك"; case .creditCard: "مستحق البنك"; case .installment: "رصيد المزود" }
    }

    private func arch<Content: View>(caption: String, title: String, tint: Color, titleTint: Color, matched: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 4) {
            Text(caption).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).padding(.top, 34)
            Text(title).font(MadarTypography.caption()).bold().foregroundStyle(titleTint)
            Spacer(minLength: 6)
            content()
            Spacer(minLength: 10)
        }.frame(maxWidth: .infinity).frame(height: 158)
            .background { MoneyArch().fill(theme.color("surface2")) }
            .overlay { MoneyArch().stroke(matched ? theme.color("surplusText") : tint, lineWidth: 1.3) }
            .overlay { MoneyArch().stroke((matched ? theme.color("surplusText") : tint).opacity(0.75), lineWidth: 0.7).padding(5) }
            .shadow(color: matched && !reduceMotion ? theme.color("surplus").opacity(0.35) : .clear, radius: 10)
    }

    private func sentence(_ r: MoneyReconcileRow) -> some View {
        let text: String, color: Color
        if let line = line(r) {
            let size = visible ? " بـ " + service.amount(abs(line.deltaMinor)) : ""
            if line.deltaMinor == 0 { text = "يطابق دفتر مدار تمامًا"; color = theme.color("surplusText") }
            else if r.side == .account { text = (line.deltaMinor < 0 ? "عندك أقل" : "عندك أكثر") + size + " مما يظن مدار"; color = theme.color("dueText") }
            else if r.side == .creditCard { text = (line.deltaMinor > 0 ? "عليك أكثر" : "عليك أقل") + size + " مما يحسب مدار"; color = theme.color("dueText") }
            else { text = (line.deltaMinor > 0 ? "المزود يطلب أكثر" : "المزود يطلب أقل") + size + " من جدول مدار"; color = theme.color("dueText") }
        } else { text = r.side == .account ? "اكتب رصيدك كما يظهر في تطبيق البنك" : "اكتب ما تطلبه البطاقة كما يظهر في تطبيق البنك"; color = theme.secondaryInk }
        return VStack(spacing: 4) {
            Text(text).font(MadarTypography.body()).bold().foregroundStyle(color).multilineTextAlignment(.center).accessibilityIdentifier("money-reconcile-sentence")
            if let entry = entries[r.id], let at = entry.at, let suggestion = r.suggestion, entry.observedMinor == suggestion.observedMinor {
                Button { source = .init(id: "message-" + r.id.uuidString, title: "رصيد من رسالة البنك", amountMinor: suggestion.observedMinor, explanation: "آخر رسالة على هذا الحساب ذكرت رصيده، ولم يتحرك دفتر مدار بعدها. عدّله إن كان تطبيق البنك يقول غير ذلك.", message: suggestion.text, date: suggestion.day) } label: {
                    HStack(spacing: 5) { Image(systemName: "envelope"); Text("من رسالة البنك"); inlineDate(suggestion.day); Text(service.time(at)) }
                        .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }.buttonStyle(.madarPlain).accessibilityIdentifier("money-reconcile-from-message")
            }
        }.frame(maxWidth: .infinity)
    }

    private func nudges(_ r: MoneyReconcileRow) -> some View {
        HStack(spacing: 8) {
            Text("عدّل الواقع").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize()
            Spacer(minLength: 4)
            ForEach([-100, -10, 10, 100], id: \.self) { units in
                Button { nudge(r, units) } label: {
                    Text("\u{2066}" + (units < 0 ? "−" : "+") + service.digits.string(abs(units)) + "\u{2069}").font(MadarTypography.body())
                        .frame(maxWidth: 66, minHeight: 58).frame(maxWidth: .infinity)
                        .background(theme.color("surface2"), in: Rectangle()).overlay { Rectangle().stroke(theme.line, lineWidth: 1) }
                }.buttonStyle(.madarPlain).disabled(!visible).accessibilityLabel((units < 0 ? "أنقص " : "زِد ") + service.digits.string(abs(units)))
                    .accessibilityIdentifier("money-reconcile-nudge-" + String(units))
            }
        }
    }

    private func naming(_ r: MoneyReconcileRow, reading: MoneyReconcileReading) -> some View {
        let names = line(r).map(ReconcileEngine.names) ?? []
        let chosen = entries[r.id]?.name
        return VStack(alignment: .trailing, spacing: 6) {
            if !names.isEmpty {
                HStack(spacing: 8) {
                    Text("سمّ الفرق").font(MadarTypography.caption()).bold().fixedSize()
                    Spacer(minLength: 4)
                    ForEach(names, id: \.self) { name in
                        Button { entries[r.id]?.name = chosen == name ? nil : name } label: {
                            Text(title(name)).font(MadarTypography.caption()).bold().lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 8)
                                .frame(minHeight: 58).frame(maxWidth: .infinity)
                                .background(chosen == name ? theme.ink : theme.color("surface2"), in: Rectangle())
                                .foregroundStyle(chosen == name ? theme.background : theme.ink).overlay { Rectangle().stroke(theme.line, lineWidth: 1) }
                        }.buttonStyle(.madarPlain).disabled(!visible).accessibilityAddTraits(chosen == name ? .isSelected : []).accessibilityIdentifier("money-reconcile-name-" + name.rawValue)
                    }
                }
                Text(caption(chosen, reading: reading)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-reconcile-name-caption")
            } else if r.side == .installment, let line = line(r), line.deltaMinor != 0 {
                Text("راجع جدول الأقساط في مدار؛ يبقى الفرق مفتوحًا ولا يُسجّل مصروفًا أو تسوية تلقائية.")
                    .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-reconcile-installment-note")
            }
        }.animation(reduceMotion ? nil : .snappy, value: chosen)
    }
    private func title(_ name: ReconcileName) -> String { name == .missedSpend ? "مصاريف فاتتني" : name == .bankFee ? "رسوم بنكية" : "تسوية بلا تفسير" }
    private func caption(_ name: ReconcileName?, reading: MoneyReconcileReading) -> String {
        switch name {
        case .missedSpend: reading.hasOtherCategory ? "تُخصم من يومك تحت «أخرى» بتاريخ اليوم" : "تُخصم من يومك بتاريخ اليوم"
        case .bankFee: "تُخصم من يومك بتاريخ اليوم باسم «رسوم بنكية»"
        case .unexplained: "يتعدّل الرصيد وحده، ويومك لا يتغيّر"
        case nil: "بلا اسم يبقى الفرق مفتوحًا في المحضر، ولا يتغيّر شيء"
        }
    }

    /// A difference that equals a draft still waiting is probably that draft: confirming it beats a second «مصاريف فاتتني».
    @ViewBuilder private func hint(_ r: MoneyReconcileRow) -> some View {
        if visible, let line = line(r), line.isShortfall, let match = r.pending.first(where: { $0.amountMinor == abs(line.deltaMinor) }) {
            Button { messagesOpen = true } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "text.magnifyingglass").foregroundStyle(theme.color("reserveText")).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("الفرق يساوي حركة تنتظر قرارك").font(MadarTypography.caption()).bold()
                        HStack(spacing: 6) { Text(figure: match.title + "، " + service.amount(match.amountMinor)); inlineDate(match.day) }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        Text("اعتمدها من رسائل البنك بدل تسجيلها مرتين").font(MadarTypography.fine()).foregroundStyle(theme.color("reserveText"))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.left").font(.caption).foregroundStyle(theme.secondaryInk)
                }.padding(12).background(theme.surface, in: RoundedRectangle(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).stroke(theme.color("reserveText"), style: .init(lineWidth: 1, dash: [4, 3])) }
            }.buttonStyle(.madarPlain).accessibilityIdentifier("money-reconcile-hint")
        }
    }

    // MARK: «محضر جرد الحسابات»

    private func ledger(_ reading: MoneyReconcileReading) -> some View {
        let cash = reading.rows.filter { $0.side == .account }, cards = reading.rows.filter { $0.side == .creditCard }, installments = reading.rows.filter { $0.side == .installment }
        let s = summary
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("محضر جرد الحسابات").font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title3))
                Spacer(minLength: 6)
                inlineDate(reading.today)
            }
            if dynamicType.isAccessibilitySize {
                ForEach(reading.rows) { item in Button { select(item.id) } label: { accessibleRow(item) }.buttonStyle(.madarPlain) }
            } else {
                HStack(spacing: 4) {
                    Text("الحساب / المزود").frame(maxWidth: .infinity, alignment: .leading)
                    Text("دفتر مدار").frame(width: 70)
                    Text("الواقع").frame(width: 70)
                    Text("الفرق").frame(width: 52)
                    Text("الختم").frame(width: 40)
                }.font(MadarTypography.fine()).bold().foregroundStyle(theme.secondaryInk)
                Rectangle().fill(theme.ink).frame(height: 1)
                if !cash.isEmpty { group("النقد", cash) }
                if !cards.isEmpty { group("البطاقات", cards) }
                if !installments.isEmpty { group("اشترِ الآن وادفع لاحقًا", installments) }
                Rectangle().fill(theme.ink).frame(height: 1)
            }
            HStack {
                Text(s.open == 0 ? "لا فروق مفتوحة" : service.counted(s.open, ("فرق مفتوح", "فرقان مفتوحان", "فروق مفتوحة", "فرقًا مفتوحًا"))).font(MadarTypography.caption()).bold().accessibilityIdentifier("money-reconcile-open-count")
                Spacer()
                if s.negativeMinor != 0 { Text(figure: signed(s.negativeMinor)).font(MadarTypography.caption()).bold().foregroundStyle(theme.color("dueText")) }
                if s.positiveMinor != 0 { Text(figure: signed(s.positiveMinor)).font(MadarTypography.caption()).bold().foregroundStyle(theme.color("accentText")) }
            }
        }.padding(.horizontal, 18).padding(.vertical, 18)
            .background(theme.surface)
            .overlay { Rectangle().stroke(theme.color("reserve"), lineWidth: 1.4) }
            .overlay { Rectangle().stroke(theme.color("reserve"), lineWidth: 0.7).padding(6) }
            .overlay(alignment: .topLeading) { corner } .overlay(alignment: .topTrailing) { corner }
            .overlay(alignment: .bottomLeading) { corner } .overlay(alignment: .bottomTrailing) { corner }
            .padding(.top, 6).accessibilityElement(children: .contain).accessibilityIdentifier("money-reconcile-ledger")
    }
    private var corner: some View {
        PrayerStar().fill(theme.background).overlay { PrayerStar().stroke(theme.color("reserve"), lineWidth: 1) }.frame(width: 22, height: 22).offset(x: 0, y: 0).padding(-11).accessibilityHidden(true)
    }
    private func group(_ title: String, _ rows: [MoneyReconcileRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(MadarTypography.caption()).bold().foregroundStyle(theme.color("reserveText")).padding(.top, 6).padding(.bottom, 2)
            ForEach(rows) { item in
                Button { select(item.id) } label: { ledgerRow(item) }.buttonStyle(.madarPlain).accessibilityIdentifier("money-reconcile-row-" + item.name)
                if item.id != rows.last?.id { Rectangle().fill(theme.line).frame(height: 0.7) }
            }
        }
    }
    private func ledgerRow(_ item: MoneyReconcileRow) -> some View {
        let l = line(item), active = item.id == row?.id
        return HStack(spacing: 4) {
            Text(item.name).font(MadarTypography.body()).lineLimit(1).minimumScaleFactor(0.79).frame(maxWidth: .infinity, alignment: .leading)
            Text(figure: amount(item.expectedMinor)).font(MadarTypography.caption()).lineLimit(1).minimumScaleFactor(0.85).frame(width: 70)
            Text(figure: l.map { amount($0.observedMinor) } ?? "—").font(MadarTypography.caption()).bold().lineLimit(1).minimumScaleFactor(0.85).frame(width: 70)
                .foregroundStyle(l.map { $0.deltaMinor == 0 ? theme.ink : theme.color("dueText") } ?? theme.secondaryInk)
            Text(l.map { $0.deltaMinor == 0 ? "—" : signed($0.deltaMinor) } ?? "").font(MadarTypography.caption()).bold().lineLimit(1).minimumScaleFactor(0.85).frame(width: 52)
                .foregroundStyle(l.map { $0.deltaMinor < 0 ? theme.color("dueText") : $0.deltaMinor > 0 ? theme.color("accentText") : theme.secondaryInk } ?? theme.secondaryInk)
            stamp(item).frame(width: 40)
        }.padding(.vertical, 10).padding(.horizontal, 6)
            .background(active ? theme.color("glass") : Color.clear)
            .overlay(alignment: .leading) { if active { Rectangle().fill(theme.color("reserve")).frame(width: 3) } }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore).accessibilityLabel(accessibilityText(item)).accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
    private func accessibleRow(_ item: MoneyReconcileRow) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(item.name).font(MadarTypography.body()); Text(accessibilityText(item)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
            .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func accessibilityText(_ item: MoneyReconcileRow) -> String {
        let l = line(item)
        return item.name + "، دفتر مدار " + amount(item.expectedMinor) + "، " + (l.map { "الواقع " + amount($0.observedMinor) + "، " + stampText(item, $0) } ?? "لم يُدخل الواقع")
    }
    private func stampText(_ item: MoneyReconcileRow, _ l: ReconcileLine) -> String {
        l.deltaMinor == 0 ? "طابق" : entries[item.id]?.name == nil ? "فرق" : "تسوية"
    }
    @ViewBuilder private func stamp(_ item: MoneyReconcileRow) -> some View {
        if let l = line(item) {
            let text = stampText(item, l), tint = l.deltaMinor == 0 ? theme.color("surplusText") : text == "تسوية" ? theme.color("reserveText") : theme.color("dueText")
            ZStack {
                Circle().stroke(tint, lineWidth: 1.2); Circle().stroke(tint, lineWidth: 0.6).padding(3)
                Text(figure: text).font(.custom("thmanyahserifdisplay-Bold", size: 11, relativeTo: .caption2)).foregroundStyle(tint)
            }.frame(width: 36, height: 36).rotationEffect(.degrees(-12))
                .transition(reduceMotion ? .opacity : .scale(scale: 1.6).combined(with: .opacity))
        } else {
            Circle().stroke(theme.line, style: .init(lineWidth: 1, dash: [3, 3])).frame(width: 36, height: 36)
        }
    }

    private var saveButton: some View {
        let s = summary, any = !entries.isEmpty
        let count: String
        switch s.settlements {
        case 0: count = ""
        case 1: count = " · تُكتب تسوية واحدة"
        case 2: count = " · تُكتب تسويتان"
        case 3...10: count = " · تُكتب " + service.digits.string(s.settlements) + " تسويات"
        default: count = " · تُكتب " + service.digits.string(s.settlements) + " تسوية"
        }
        // AU-43: a refused save is said right above the pinned button, not deep in the page.
        return VStack(alignment: .leading, spacing: 6) {
        if let note { Text(note).font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")).accessibilityIdentifier("money-reconcile-note") }
        Button(action: save) {
            HStack(spacing: 12) {
                PrayerStar().stroke(theme.background, lineWidth: 1.2).frame(width: 26, height: 26).accessibilityHidden(true)
                Text("ثبّت المطابقة" + count).font(MadarTypography.cardTitle()).bold().lineLimit(1).minimumScaleFactor(0.8)
            }.frame(maxWidth: .infinity, minHeight: 60).foregroundStyle(theme.background)
                .background(theme.ink.opacity(any && !saving ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.madarPlain).disabled(!any || saving || !visible).accessibilityIdentifier("money-reconcile-save")
        }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4).background(theme.background.opacity(0.94))
    }

    private var emptyPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("لا حسابات تُطابق بعد").font(MadarTypography.cardTitle())
            Text("تظهر هنا حساباتك بعملتك وبطاقاتك الائتمانية حين يعرفها مدار، فتقارن دفتره برصيد البنك وتسمّي كل فرق.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: RoundedRectangle(cornerRadius: 14)).accessibilityIdentifier("money-reconcile-empty")
    }

    private func inlineDate(_ day: GregorianDay) -> some View {
        let labels = app.dateLabels(day, compact: true)
        return HStack(spacing: 4) { Text(labels.primary).font(MadarTypography.fine()); Text(labels.secondary).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }.fixedSize()
    }

    /// L04: how the book was reached — the last confirmed balance, plus in, minus out — and the dailies not yet accrued.
    private func composition(_ r: MoneyReconcileRow) -> MoneySourceDetail {
        if r.side == .creditCard {
            return .init(id: "book-" + r.id.uuidString, title: "دين مدار على " + r.name, amountMinor: r.expectedMinor,
                explanation: "الكشف المتبقي " + service.amount(r.inMinor) + " وغير المفوتر " + service.amount(r.outMinor) + "، من حركات البطاقة المؤكدة بعد الردود والسداد. هو نفسه ما تجمعه «عليك».")
        }
        if r.side == .installment {
            return .init(id: "book-" + r.id.uuidString, title: "المتبقي في أقساط " + r.name, amountMinor: r.expectedMinor,
                explanation: "قيمة العقد " + service.amount(r.baseMinor ?? 0) + "، سُدّد منها " + service.amount(r.inMinor) + "، وبقي في جدول الأقساط " + service.amount(r.outMinor) + ". يظهر فرق المزود للمراجعة ولا يغيّر جدول السداد.", date: r.baseDay)
        }
        var text = (r.baseIsReconciliation ? "آخر رصيد مؤكد عند المطابقة " : "رصيد البداية ") + service.amount(r.baseMinor ?? 0)
            + "، زاد بعده " + service.amount(r.inMinor) + " ونقص " + service.amount(r.outMinor) + "، فصار " + service.amount(r.expectedMinor) + ". مشتريات البطاقة الائتمانية لا تنقصه قبل سدادها."
        if let future = reading?.notYetAccruedMinor, future > 0 {
            text += " ومن نقدك كله لم يُستحق بعد من يومياتك " + service.amount(future) + "؛ هو جزء من الرصيد، لا فائض ولا فرق."
        }
        return .init(id: "book-" + r.id.uuidString, title: "دفتر مدار لـ" + r.name, amountMinor: r.expectedMinor, explanation: text, date: r.baseDay)
    }

    private func select(_ id: UUID) {
        typing = false; selected = id
        typed = entries[id].map { plain($0.observedMinor) } ?? ""
    }
    private func plain(_ minor: Int) -> String {
        // An overdrawn balance is shown as a sign and its size, so it can be read back as typed.
        if minor < 0 { return "-" + plain(-minor) }
        var scale = 1; for _ in 0..<exponent { scale *= 10 }
        let whole = String(minor / scale), fraction = minor % scale
        return service.digits.string(minor / scale) == whole ? (fraction == 0 ? whole : whole + "." + String(format: "%0\(exponent)d", fraction))
            : service.amount(minor).filter { !"\u{2068}\u{2069}٬".contains($0) }
    }
    // A typed amount that cannot be read says so; the row keeps its last good figure.
    private static let unreadable = "لم أفهم هذا المبلغ؛ اكتب أرقامًا وفاصلة واحدة على الأكثر."
    private func commitTyped(_ r: MoneyReconcileRow) {
        let ascii = String(typed.map { ch -> Character in
            if let v = "٠١٢٣٤٥٦٧٨٩".firstIndex(of: ch) { return Character(String("٠١٢٣٤٥٦٧٨٩".distance(from: "٠١٢٣٤٥٦٧٨٩".startIndex, to: v))) }
            return ch == "٫" || ch == "," ? "." : ch
        }).filter { $0 != "٬" && $0 != " " }
        if ascii.isEmpty { if note == Self.unreadable { note = nil }; if entries[r.id] != nil, typing { entries[r.id] = nil }; return }
        let negative = ascii.first == "-" || ascii.first == "\u{2212}"
        guard let size = MoneyAmountInput.minor(negative ? String(ascii.dropFirst()) : ascii, exponent: exponent) else { note = Self.unreadable; return }
        let value = negative ? -size : size
        if note == Self.unreadable { note = nil }
        if entries[r.id]?.observedMinor != value { set(r, value, at: nil) }
    }
    private func nudge(_ r: MoneyReconcileRow, _ units: Int) {
        let base = entries[r.id]?.observedMinor ?? r.expectedMinor
        set(r, ReconcileEngine.nudge(base, units: units, exponent: exponent), at: nil)
        typed = plain(entries[r.id]!.observedMinor)
    }
    private func set(_ r: MoneyReconcileRow, _ value: Int, at: Date?) {
        note = nil // AU-38: an edited row is a new attempt; the old note no longer applies.
        var entry = entries[r.id] ?? .init(observedMinor: value, at: at, name: nil)
        entry.observedMinor = value; entry.at = at
        // A name that no longer fits the new difference is dropped, never silently turned into spending.
        if let name = entry.name, !ReconcileEngine.names(for: .init(side: r.side, expectedMinor: r.expectedMinor, observedMinor: value)).contains(name) { entry.name = nil }
        entries[r.id] = entry
    }

    private func load() {
        do {
            let next = try service.loadReconcile()
            // Lines the book moved under are dropped; a balance printed in the newest message fills an untouched line.
            var kept: [UUID: Entry] = [:]
            for r in next.rows {
                if let entry = entries[r.id], reading?.rows.first(where: { $0.id == r.id })?.expectedMinor == r.expectedMinor { kept[r.id] = entry }
                else if let s = r.suggestion { kept[r.id] = .init(observedMinor: s.observedMinor, at: s.at, name: nil) }
            }
            entries = kept; reading = next; failure = nil
            if selected == nil || !next.rows.contains(where: { $0.id == selected }) {
                selected = next.rows.first { r in kept[r.id].map { $0.observedMinor != r.expectedMinor } ?? false }?.id ?? next.rows.first?.id
            }
            if let id = selected { typed = kept[id].map { plain($0.observedMinor) } ?? "" }
        } catch { reading = nil; failure = "لم تكتمل قراءة الحسابات. حاول مرة أخرى." }
    }
    private func save() {
        // AU-95: `.disabled` lands a render later; a fast second tap must not send the same reconcile twice.
        guard !saving, let reading else { return }
        note = nil
        let formatter = ISO8601DateFormatter()
        let rows: [MadarCore.JSONValue] = reading.rows.compactMap { r in
            guard let entry = entries[r.id] else { return nil }
            let target = r.side == .account ? "accountID" : r.side == .creditCard ? "cardID" : "obligationID"
            var object: [String: MadarCore.JSONValue] = [target: .string(r.id.uuidString),
                "expectedMinor": .string(String(r.expectedMinor)), "observedMinor": .string(String(entry.observedMinor))]
            if let name = entry.name { object["name"] = .string(name.rawValue) }
            if let at = entry.at { object["at"] = .string(formatter.string(from: at)) }
            return .object(object)
        }
        guard !rows.isEmpty else { return }
        saving = true; typing = false
        Task {
            do { try await app.executeMoneyCommand("money.reconcile", payload: ["rows": .array(rows)]); entries = [:]; note = nil; load() }
            catch { note = "تغيّر دفتر مدار منذ فتحت الصفحة، أو لا يناسب اسمٌ فرقَه. راجع الأرقام ثم ثبّت مرة أخرى."; load() }
            saving = false
        }
    }
}

/// The arch over each column: straight sides, a round head.
struct MoneyArch: Shape {
    func path(in r: CGRect) -> Path {
        let radius = r.width / 2
        return Path { p in
            p.move(to: .init(x: r.minX, y: r.maxY)); p.addLine(to: .init(x: r.minX, y: r.minY + radius))
            p.addArc(center: .init(x: r.midX, y: r.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            p.addLine(to: .init(x: r.maxX, y: r.maxY)); p.closeSubpath()
        }
    }
}

private struct Line: Shape {
    func path(in r: CGRect) -> Path { Path { p in p.move(to: .init(x: r.minX, y: r.midY)); p.addLine(to: .init(x: r.maxX, y: r.midY)) } }
}

/// One square per day since the last check, newest at the end; gold where a confirmed movement touched the line.
private struct MoneyReconcileSquares: View {
    let days: Int
    let active: Set<Int>
    @Environment(\.roomTheme) private var theme
    var body: some View {
        GeometryReader { proxy in
            let shown = min(max(days, 1), 60), width = proxy.size.width / CGFloat(shown)
            HStack(spacing: 0) {
                ForEach(0..<shown, id: \.self) { index in
                    let day = days - shown + 1 + index
                    Rectangle().fill(active.contains(day) ? theme.color("reserve") : theme.color("glass"))
                        .overlay { Rectangle().stroke(theme.color("reserve").opacity(0.55), lineWidth: 0.5) }
                        .frame(width: max(1, width - 1.5)).frame(width: width)
                }
            }
        }
    }
}
