import SwiftUI
import MadarCore
import MadarDesign
import MadarMoney

struct MoneyAccountsView: View {
    let app: AppSession
    @Binding var revealed: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reading: MoneyAccountsReading?
    @State private var selected: MoneyAccountEdit?
    @State private var selectedSource: MoneyAccountRow?
    @State private var errorMessage: String?
    @State private var appeared = false
    @State private var reconcileOpen = false
    #if DEBUG
    @State private var injectedReadFailure = false
    #endif
    private var service: AppMoneyService { .init(app: app) }
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private func amount(_ n: Int, currency: String? = nil) -> String { visible ? service.amount(n, currency: currency) : "•••" }
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1) } }.accessibilityLabel("إغلاق").accessibilityIdentifier("money-accounts-close")
                    Text("الحسابات").font(.custom("thmanyahserifdisplay-Bold", size: 24, relativeTo: .title2)); Spacer()
                    Button(action: addAccount) { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("أضف حسابًا").accessibilityIdentifier("money-accounts-add")
                }
                if let errorMessage, reading != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(errorMessage).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            .accessibilityIdentifier("money-accounts-read-error")
                        Button("أعد المحاولة", action: load).frame(minHeight: 44)
                            .accessibilityIdentifier("money-accounts-retry")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(theme.surface, in: .rect(cornerRadius: 12))
                }
                if let r = reading {
                    if !visible { Button("أظهر الأرقام") { revealed = true }.frame(minHeight: 44).accessibilityIdentifier("money-accounts-reveal") }
                    VStack(spacing: 0) {
                        tree(r)
                        ledger(r)
                    }
                    if r.rows.contains(where: { $0.side == .cash && $0.amountMinor == nil }) {
                        Text("لم يُعرف رصيدها بعد؛ الحسابات المجهولة لا تدخل في المجموع.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        Button("المطابقة مع البنك") { reconcileOpen = true }.frame(minHeight: 44).accessibilityIdentifier("money-accounts-unknown-reconcile")
                    }
                    if let basis = r.basis {
                        if !(r.rows.contains { $0.side == .cash && $0.amountMinor == nil } && !r.rows.contains { $0.side == .cash && $0.amountMinor != nil }) {
                        HStack { Text(figure: "كاش " + amount(basis.inAccountMinor) + "، عليك " + amount(basis.owedMinor)).font(MadarTypography.caption()); Spacer(); Text(figure: amount(basis.netMinor)).font(MadarTypography.cardTitle()).foregroundStyle(theme.color("surplusText")) }.padding(12).background(theme.surface)
                        }
                    } else { Text("لا نجمع عملات مختلفة بلا سعر صرف. أرصدة الحسابات أدناه بعملاتها.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                    if r.rows.isEmpty {
                        // Audit 28 Oct: the empty tree offers its first account right where it asks for one.
                        VStack(alignment: .leading, spacing: 10) {
                            Text("من هنا تبدأ الجذور. أضف حسابك ورصيده، ثم تصله رسائل البنك.").font(MadarTypography.body()).accessibilityIdentifier("money-accounts-empty")
                            Button(action: addAccount) { Label("أضف أول حساب", systemImage: "plus").font(MadarTypography.body().bold()).padding(.horizontal, 18).frame(minHeight: 44).foregroundStyle(theme.onAccent).background(theme.color("accent"), in: Capsule()) }.buttonStyle(.madarPlain).accessibilityIdentifier("money-accounts-empty-add")
                        }.padding(.vertical, 20)
                    }
                    HStack(spacing: 8) {
                        Label(r.shortcutAt == nil ? "لم تصل رسالة عبر الاختصار بعد" : "رسائل عبر الاختصار", systemImage: r.shortcutAt == nil ? "tray" : "checkmark.circle").font(MadarTypography.caption())
                        Spacer(minLength: 0)
                        if r.shortcutCount > 0 { Text(service.counted(r.shortcutCount, ("وصلت رسالة واحدة", "وصلت رسالتان", "رسائل وصلت", "رسالةً وصلت"))).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                    }.padding(14).frame(maxWidth: .infinity).overlay { Capsule().stroke(theme.line, lineWidth: 1) }
                } else if let errorMessage {
                    Text(errorMessage).accessibilityIdentifier("money-accounts-read-error")
                    Button("أعِد المحاولة", action: load).accessibilityIdentifier("money-accounts-retry")
                }
                else { ProgressView().frame(height: 250) }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).buttonStyle(.madarPlain).toolbar(.hidden, for: .navigationBar, .tabBar)
            .task { load(); withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { appeared = true } }.onChange(of: app.prayerRevision) { load() }
            .sheet(item: $selected) { MoneyAccountSheet(app: app, original: $0, visible: visible, revealed: $revealed) }.sheet(item: $selectedSource) { source($0) }
            .navigationDestination(isPresented: $reconcileOpen) { MoneyReconcileView(app: app, revealed: $revealed) }
            .accessibilityIdentifier("money-accounts")
    }
    private func tree(_ r: MoneyAccountsReading) -> some View {
        ZStack {
            if !dynamicType.isAccessibilitySize {
                Ellipse().fill(theme.color("surplus").opacity(0.13)).frame(width: 224, height: 145).rotationEffect(.degrees(-12))
                MoneyAccountCrown().fill(theme.color("surplus").opacity(0.16)).overlay { MoneyAccountCrown().stroke(theme.color("surplusText").opacity(0.45), lineWidth: 1) }.frame(width: 234, height: 230).scaleEffect(appeared ? 1 : 0.94)
                Path { p in p.move(to: .init(x: 7, y: 105)); p.addLine(to: .init(x: 18, y: 0)); p.addLine(to: .init(x: 28, y: 105)); p.closeSubpath() }.fill(theme.color("reserveText")).frame(width: 36, height: 80).offset(y: 85)
            }
            VStack(spacing: 5) {
                Text("لك فعلًا").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                displayFigure(r.basis.flatMap { b in r.rows.contains { $0.side == .cash && $0.amountMinor == nil } && !r.rows.contains { $0.side == .cash && $0.amountMinor != nil } ? nil : amount(b.netMinor) } ?? "—", "thmanyahserifdisplay-Black", size: 42, relativeTo: .largeTitle).foregroundStyle(theme.color("surplusText")).accessibilityIdentifier("money-accounts-net")
                Text("الجذور تغذّي، والديون تسحب").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }.padding(15).frame(maxWidth: 240).background(theme.background).clipShape(.rect(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.color("reserveText"), lineWidth: 1) }
        }.frame(maxWidth: .infinity).frame(minHeight: dynamicType.isAccessibilitySize ? 150 : 250)
    }
    @ViewBuilder private func ledger(_ r: MoneyAccountsReading) -> some View {
        if dynamicType.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 16) { ForEach(r.rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    Button(row.name) { if let edit = row.edit { selected = edit } else { selectedSource = row } }.font(MadarTypography.cardTitle()).frame(minHeight: 44)
                    Text(row.amountMinor == nil ? "لم يُعرف رصيدها بعد" : row.subtitle + (row.counted ? "، يُحتسب" : "، خارج الحساب")).font(MadarTypography.body())
                    Text(figure: row.amountMinor.map { amount($0, currency: row.currency) } ?? "—").font(MadarTypography.body())
                    Button("مصدر الرصيد") { selectedSource = row }.frame(minHeight: 44)
                }
            } }
        } else {
        VStack(spacing: 0) {
            HStack { Text("الحساب").frame(maxWidth: .infinity, alignment: .leading); Text("المبلغ").frame(width: 90); Text("ملكي؟").frame(width: 38); Text("في المجموع").frame(width: 55).lineLimit(1).minimumScaleFactor(0.85) }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).padding(.vertical, 8)
            ForEach(r.rows) { row in
                HStack(spacing: 5) {
                    Circle().fill(tint(row)).frame(width: 7, height: 7)
                    Button { if let edit = row.edit { selected = edit } else { selectedSource = row } } label: {
                        VStack(alignment: .leading, spacing: 2) { Text(row.name).font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)); Text(row.amountMinor == nil ? "لم يُعرف رصيدها بعد" : row.subtitle + (row.currency == app.string("core.currency") ? "" : "، " + row.currency)).font(MadarTypography.fine()).foregroundStyle(tint(row)) }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.accessibilityIdentifier("money-account-" + row.name)
                    Text(figure: row.amountMinor.map { (row.side == .cash ? "" : "(") + amount($0, currency: row.currency) + (row.side == .cash ? "" : ")") } ?? "—").font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)).foregroundStyle(row.counted ? theme.ink : theme.secondaryInk).frame(width: 90).strikethrough(!row.counted)
                    Image(systemName: row.counted ? "checkmark" : "minus").font(.system(size: 15, weight: .semibold)).foregroundStyle(row.counted ? theme.color("surplusText") : theme.secondaryInk).frame(width: 38).accessibilityLabel(row.counted ? "يُحتسب" : "خارج الحساب")
                    Button { selectedSource = row } label: { VStack(spacing: 2) { Circle().fill(row.counted ? theme.color("surplusText") : theme.color("reserveText")).frame(width: 5, height: 5); Text(row.amountMinor == nil ? "مجهول" : row.counted ? "تُحتسب" : "تُتجاهل").font(MadarTypography.fine()) }.frame(width: 55, height: 44) }.accessibilityLabel("مصدر " + row.name).accessibilityIdentifier("money-account-source-" + row.name)
                }.padding(.vertical, 8).padding(.horizontal, 8).frame(minHeight: 60)
                .anchorPreference(key: MoneyAccountRowBounds.self, value: .bounds) { [row.id: $0] }
                .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 0.7) }
                .overlay(alignment: .leading) { if !dynamicType.isAccessibilitySize { Rectangle().fill(tint(row)).frame(width: row.counted ? 2 : 1).opacity(row.counted ? 0.7 : 0.25) } }
            }
        }.padding(.horizontal, 6).padding(.leading, 24).background(theme.surface).overlay { Rectangle().stroke(theme.line, lineWidth: 1) }
            .padding(.top, 24)
            .overlayPreferenceValue(MoneyAccountRowBounds.self) { bounds in
                GeometryReader { proxy in
                    Canvas { context, size in
                        for (index, row) in r.rows.enumerated() {
                            guard let anchor = bounds[row.id] else { continue }
                            let frame = proxy[anchor]
                            let rail = size.width - 5 - CGFloat(min(index, 8)) * 1.5
                            var root = Path()
                            root.move(to: .init(x: size.width / 2, y: 0))
                            root.addCurve(to: .init(x: rail, y: 24),
                                          control1: .init(x: size.width * 0.7, y: 12),
                                          control2: .init(x: rail, y: 12))
                            root.addLine(to: .init(x: rail, y: frame.midY))
                            root.addLine(to: .init(x: frame.maxX + 2, y: frame.midY))
                            context.stroke(root, with: .color(tint(row).opacity(0.7)),
                                           style: StrokeStyle(lineWidth: row.counted ? 1.4 : 1, dash: row.counted ? [] : [2, 3]))
                        }
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
    }
    }
    private func tint(_ r: MoneyAccountRow) -> Color { !r.counted ? theme.color("reserveText") : r.side == .cash ? theme.color("accentText") : r.side == .creditCard ? theme.color("dueText") : theme.secondaryInk }
    private func source(_ r: MoneyAccountRow) -> some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            Text(r.name).font(MadarTypography.title()); Text(r.subtitle).font(MadarTypography.body())
            Text(service.counted(r.messageCount, ("رسالة واحدة مرتبطة", "رسالتان مرتبطتان", "رسائل مرتبطة", "رسالةً مرتبطة"))).font(MadarTypography.body())
            if let s = r.source {
                Text(sourceTitle(s)).font(MadarTypography.cardTitle())
                MadarDateLabel(app.dateLabels(.containing(s.at, in: app.activePlace.timeZone)), primaryFont: MadarTypography.body(), secondaryFont: MadarTypography.caption())
                Text(service.time(s.at)).font(MadarTypography.caption())
                if case .messageDiffers(_, let printed, let difference) = s { Text(figure: "ورد في الرسالة " + amount(printed, currency: r.currency) + "؛ الفرق عن الدفتر " + amount(abs(difference), currency: r.currency)).font(MadarTypography.body()) }
            } else { Text("من دفتر الحركات والكشوف؛ لا نضع رصيدًا بدلًا عن البنك.").font(MadarTypography.body()) }
            if r.amountMinor == nil { Text("الرصيد مجهول؛ الحركات محفوظة، والحساب خارج مجموع الأرصدة حتى المطابقة مع البنك.").font(MadarTypography.body()) }
            else if !r.counted { Text("هذا الجذر خارج النقد ولك فعلًا والزكاة. رسائله لا تدخل المصروفات.").font(MadarTypography.body()) }
        }.padding(24) }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).presentationDetents([.medium, .large])
    }
    private func sourceTitle(_ source: AccountBalanceSource) -> String { switch source { case .entered: "رصيد بداية أدخلته"; case .reconciled: "من مطابقة اعتمدتها"; case .message: "رصيد رسالة يطابق الدفتر"; case .messageDiffers: "رصيد رسالة يختلف عن الدفتر" } }
    private func addAccount() { selected = .init(id: UUID(), isNew: true, name: "", bank: "", last4: "", kind: "current", ownership: "mine", currency: app.string("core.currency"), openingMinor: 0, openingAt: app.prayerNow(), senderIDs: [], tracked: true, zakatInclude: true, fixedCheckpoint: false) }
    private func load() {
        do {
            #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if !injectedReadFailure, environment["MADAR_UI_MONEY_ACCOUNTS_READ_FAILURE_ONCE"] == "1",
               environment["MADAR_UI_MONEY_FIXTURE"] == "accounts", environment["MADAR_UI_STORE_ID"] != nil {
                injectedReadFailure = true
                throw CocoaError(.fileReadUnknown)
            }
            #endif
            reading = try service.loadAccounts(); errorMessage = nil
        } catch {
            errorMessage = reading == nil ? "لم تكتمل قراءة الحسابات. أعد المحاولة." : "تعذّر تحديث الحسابات؛ تعرض آخر قراءة ناجحة. أعد المحاولة."
        }
    }
}

private struct MoneyAccountCrown: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); let c = CGPoint(x: r.midX, y: r.midY)
        for i in 0..<16 { let a = Double(i) * .pi / 8 - .pi / 2, radius = i.isMultiple(of: 2) ? 0.5 : 0.37; let point = CGPoint(x: c.x + cos(a) * r.width * radius, y: c.y + sin(a) * r.height * radius); if i == 0 { p.move(to: point) } else { p.addLine(to: point) } }; p.closeSubpath(); return p
    }
}

/// Resolve root endpoints from the laid-out rows: long names can make any row taller.
private struct MoneyAccountRowBounds: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
