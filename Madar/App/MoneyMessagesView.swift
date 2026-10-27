import SwiftUI
import MadarCore
import MadarData
import MadarDesign
import MadarMoney
import MadarCommands

/// «رسائل البنك» (`mal/07-Z-R18-msg-1`): three arches, the statement waiting for its card, the drafts with ✓/✕,
/// «تحتاج نظرة», one «اعتمد الواضح», and «الصق رسائل» as the fallback channel (§7.5 F09).
struct MoneyMessagesView: View {
    let app: AppSession
    @Binding var revealed: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var reading: MoneyMessagesReading?
    @State private var failure: String?
    @State private var note: String?
    @State private var categorizing: MoneyMessageDraft?
    @State private var rulesOpen = false
    @State private var guideOpen = false
    @State private var budgetOpen = false
    @State private var salary: SalaryRoute?
    private struct SalaryRoute: Identifiable, Hashable { var id: UUID }
    @State private var bigExpense: MoneyBigExpenseRoute?
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var service: AppMoneyService { .init(app: app) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header
                if let reading {
                    HStack(alignment: .firstTextBaseline) {
                        Label(service.digits.string(reading.shortcutToday) + (reading.shortcutToday == 1 ? " رسالة وصلت اليوم عبر الاختصار" : " رسائل وصلت اليوم عبر الاختصار"), systemImage: "checkmark.square")
                            .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-messages-shortcut")
                        Spacer(minLength: 8)
                        MadarDateLabel(app.dateLabels(reading.today, compact: true, weekday: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine())
                            .foregroundStyle(theme.color("reserveText"))
                    }
                    arches(reading)
                    if !visible { Button("أظهر الأرقام") { revealed = true }.font(MadarTypography.caption()).frame(minHeight: 44).accessibilityIdentifier("money-messages-reveal") }
                    ForEach(reading.statements) { statementCard($0) }
                    ForEach(reading.drafts) { draftRow($0) }
                    clearButton(reading)
                    if !reading.looks.isEmpty { looks(reading.looks) }
                    if reading.drafts.isEmpty && reading.statements.isEmpty && reading.looks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("لا شيء ينتظر").font(MadarTypography.cardTitle())
                            Text("كل رسالة وصلت حُسمت. ما يصل عبر الاختصار يظهر هنا للمراجعة.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                        }.padding(.vertical, 24).accessibilityIdentifier("money-messages-empty")
                    }
                    Button("دليل إعداد الاختصار وفحص الوصول") { guideOpen = true }.font(MadarTypography.caption()).frame(minHeight: 44).accessibilityIdentifier("money-guide-open")
                    footer(reading)
                } else if let failure {
                    Text(failure).font(MadarTypography.body()); Button("أعِد المحاولة", action: load).frame(minHeight: 44)
                } else { ProgressView().frame(maxWidth: .infinity, minHeight: 240) }
            }.padding(.horizontal, 16).padding(.bottom, 30).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.clipped().background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
            .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
            .task { load() }.onChange(of: app.prayerRevision) { load() }
            .sheet(item: $categorizing) { MoneyCategorizeSheet(app: app, draft: $0).environment(\.roomTheme, theme) }
            .fullScreenCover(item: $bigExpense) { route in MoneyBigExpenseView(app: app, route: route, revealed: $revealed) { bigExpense = nil; load() } }
            .navigationDestination(isPresented: $guideOpen) { MoneyShortcutGuideView(app: app) }
            .navigationDestination(isPresented: $rulesOpen) { MoneyRulesView(app: app) }
        .navigationDestination(isPresented: $budgetOpen) { MoneyBudgetView(app: app, revealed: $revealed) }
            .navigationDestination(item: $salary) { MoneySalaryView(app: app, salaryID: $0.id) }
            .accessibilityIdentifier("money-messages")
    }
    private var header: some View {
        HStack(spacing: 12) {
            Text("رسائل البنك").font(MadarTypography.title()).accessibilityIdentifier("money-messages-title")
                #if DEBUG
                .accessibilityValue(ProcessInfo.processInfo.environment["MADAR_UI_MONEY_FIXTURE"] == "bankCorpus" ? String(app.bankCorpusImportedInputCount) : "")
                #endif
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.title3).frame(width: 52, height: 52)
                    .overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1.2) }
            }.buttonStyle(.plain).accessibilityLabel("إغلاق").accessibilityIdentifier("money-messages-close")
            Spacer()
        }.padding(.top, 8)
    }
    private func amount(_ minor: Int, currency: String? = nil) -> String { visible ? service.amount(minor, currency: currency) : "•••" }
    private func arches(_ reading: MoneyMessagesReading) -> some View {
        let items: [(String, String, Int, String, Color, Bool)] = [
            ("review", "للمراجعة", reading.pending, "ينتظر قرارك", theme.color("reserveText"), true),
            ("spent", "مصروف", reading.spentCount, reading.spentCount == 0 ? "لم يُعتمد شيء بعد" : amount(reading.spentMinor) + " اعتُمد اليوم", theme.color("dueText"), false),
            ("incoming", "وارد", reading.incomingCount, reading.incomingCount == 0 ? "لم يُعتمد شيء بعد" : amount(reading.incomingMinor) + " اعتُمد اليوم", theme.color("surplusText"), false)]
        return Group {
            if dynamicType.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.0) { item in
                        HStack { Text(item.1).foregroundStyle(item.4); Spacer(); Text(service.digits.string(item.2)) }.font(MadarTypography.cardTitle())
                            .accessibilityIdentifier("money-messages-" + item.0)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ForEach(items, id: \.0) { item in
                        VStack(spacing: 2) {
                            Text(item.1).font(.custom("thmanyahsans-Bold", size: 15, relativeTo: .subheadline)).foregroundStyle(item.4)
                            Text(service.digits.string(item.2)).font(.custom("thmanyahserifdisplay-Black", size: 30, relativeTo: .title))
                            Text(item.3).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(1)
                        }.padding(.top, 22).padding(.bottom, 10).padding(.horizontal, 6).frame(maxWidth: .infinity)
                            .background { MessageArch().fill(item.5 ? theme.surface : .clear) }
                            .overlay { MessageArch().stroke(item.4.opacity(item.5 ? 1 : 0.7), lineWidth: item.5 ? 1.6 : 1) }
                            .overlay { MessageArch().inset(by: 6).stroke(item.4.opacity(0.45), style: .init(lineWidth: 0.8, dash: [1.5, 3])) }
                            .accessibilityElement(children: .combine).accessibilityIdentifier("money-messages-" + item.0)
                    }
                }
            }
        }
    }
    private func avatar(_ sender: String) -> some View {
        let letter = sender.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? "؟"
        let palette = ["reserveText", "bills", "surplusText", "accent"]
        let tint = theme.color(palette[abs(sender.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % palette.count])
        return Text(letter).font(.custom("thmanyahserifdisplay-Bold", size: 20, relativeTo: .headline)).foregroundStyle(tint)
            .frame(width: 40, height: 40).background(tint.opacity(0.1), in: .circle).overlay { Circle().stroke(tint, lineWidth: 1.2) }
            .accessibilityHidden(true)
    }
    /// RU1: «·» never touches a digit.
    private func joined(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.reduce("") { result, next in
            guard !result.isEmpty else { return next }
            let digit: (Character?) -> Bool = { $0.map { $0.isNumber } ?? false }
            return result + (digit(result.last) || digit(next.first) ? "، " : " · ") + next
        }
    }
    private func statementCard(_ s: MoneyMessageStatement) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                avatar(s.sender)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("كشف " + (s.cardName ?? "بطاقة")).font(MadarTypography.cardTitle())
                        Text("كشف بطاقة").font(MadarTypography.fine()).foregroundStyle(theme.color("accent")).padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay { Rectangle().stroke(theme.color("accent"), lineWidth: 1) }
                    }
                    Text(joined([service.time(s.at), s.cardName ?? "", "تنتهي بـ" + service.digits.localized(s.last4)]))
                        .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                figure("المستحق", amount(s.statementMinor), tint: theme.ink)
                figure("الحد الأدنى", s.minimumMinor.map { amount($0) } ?? "—", tint: theme.ink)
                VStack(alignment: .leading, spacing: 4) {
                    Rectangle().fill(theme.color("accent")).frame(height: 2)
                    Text("الاستحقاق").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    if let due = s.due { MadarDateLabel(app.dateLabels(due, compact: true), primaryFont: .custom("thmanyahserifdisplay-Bold", size: 17, relativeTo: .headline), secondaryFont: MadarTypography.fine()).foregroundStyle(theme.color("accent")).lineLimit(1) }
                    else { Text("—").font(MadarTypography.cardTitle()) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let difference = s.differenceMinor, s.cardName != nil {
                Text((difference > 0 ? "يزيد " : "ينقص ") + amount(abs(difference)) + " عن المسجّل على البطاقة منذ الكشف السابق")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-statement-difference")
            }
            if s.cardName == nil {
                Text("لا بطاقة معروفة تنتهي بهذه الأرقام؛ لن تُنشأ بطاقة دون علمك.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }
            HStack(spacing: 12) {
                if s.cardName != nil {
                    Button { run("money.applyStatement", ["id": .string(s.id.uuidString)]) } label: {
                        Text("حدّث البطاقة بالأرقام").font(.custom("thmanyahsans-Bold", size: 17, relativeTo: .headline)).foregroundStyle(theme.background)
                            .frame(maxWidth: .infinity, minHeight: 56).background(theme.ink)
                    }.buttonStyle(.plain).accessibilityIdentifier("money-statement-apply")
                }
                Button { run("money.ignoreMessage", ["id": .string(s.id.uuidString)]) } label: {
                    Text("تجاهل").font(MadarTypography.body()).frame(maxWidth: s.cardName == nil ? .infinity : 150, minHeight: 56)
                        .overlay { Rectangle().stroke(theme.line, lineWidth: 1.2) }
                }.buttonStyle(.plain).accessibilityIdentifier("money-statement-ignore")
            }
        }.padding(16).background(theme.surface).overlay { TicketEdge().stroke(theme.color("reserveText"), lineWidth: 1) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("money-statement")
    }
    private func figure(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(theme.ink).frame(height: 2)
            Text(title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            Text(figure: value).font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title3)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func draftRow(_ d: MoneyMessageDraft) -> some View {
        let sign = d.direction == .out ? "−" : d.direction == .incoming ? "+" : "⇄"
        let tint = d.direction == .neutral ? theme.color("accent") : d.direction == .incoming ? theme.color("surplusText") : theme.ink
        return HStack(alignment: .top, spacing: 12) {
            avatar(d.sender)
            VStack(alignment: .leading, spacing: 5) {
                Text(d.title).font(MadarTypography.cardTitle()).lineLimit(1)
                if d.possibleDuplicate {
                    Text("قد يكون مكرّرًا").font(MadarTypography.fine()).foregroundStyle(theme.color("dueText")).padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay { Rectangle().stroke(theme.color("dueText"), style: .init(lineWidth: 1, dash: [3, 2])) }.accessibilityIdentifier("money-draft-duplicate")
                }
                (Text(d.kindLabel).bold().foregroundStyle(theme.color("accent")) + Text(d.payment.map { (d.kindLabel.last?.isNumber == true || $0.first?.isNumber == true ? "، " : " · ") + $0 } ?? "").foregroundStyle(theme.secondaryInk))
                    .font(MadarTypography.caption())
                if d.canCategorize {
                    Button { categorizing = d } label: {
                        Label(d.categoryName ?? "صنّفها", systemImage: d.categoryName == nil ? "tag" : "arrow.triangle.2.circlepath").font(MadarTypography.fine()).padding(.horizontal, 8).padding(.vertical, 4)
                            .overlay { Rectangle().stroke(theme.color("reserveText"), style: .init(lineWidth: 1, dash: [3, 2])) }
                    }.buttonStyle(.plain).frame(minHeight: 32).accessibilityIdentifier("money-draft-category")
                }
                if let note = d.note {
                    Text(note).font(MadarTypography.fine()).padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay { Rectangle().stroke(theme.color("reserveText"), style: .init(lineWidth: 1, dash: [3, 2])) }
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                Text(visible ? sign + amount(d.amountMinor, currency: d.currency) : "•••").font(.custom("thmanyahserifdisplay-Bold", size: 20, relativeTo: .title3))
                    .foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 8) {
                    if d.isIncomingBankDraft {
                        Menu {
                            Button("اعتمده كدخل") { run("money.confirmTransaction", ["id": .string(d.id.uuidString)]) }
                            Button(d.isSalarySuggestion ? "راجع الراتب المقترح" : "اعتبره راتبًا") { salary = .init(id: d.id) }
                        } label: { draftConfirmGlyph }
                            .accessibilityLabel("خيارات اعتماد " + d.title).accessibilityIdentifier("money-draft-confirm")
                    } else {
                        Button { if d.isSalary { salary = .init(id: d.id) } else if d.isBigExpense { bigExpense = .init(transactionID: d.id) } else { run("money.confirmTransaction", ["id": .string(d.id.uuidString)]) } } label: { draftConfirmGlyph }
                            .buttonStyle(.plain).accessibilityLabel("اعتمد " + d.title).accessibilityIdentifier("money-draft-confirm")
                    }
                    Button { run("money.deleteTransaction", ["id": .string(d.id.uuidString)]) } label: {
                        Image(systemName: "xmark").font(.body).foregroundStyle(theme.secondaryInk).frame(width: 44, height: 44).overlay { Circle().stroke(theme.line, lineWidth: 1.2) }
                    }.buttonStyle(.plain).accessibilityLabel("احذف " + d.title).accessibilityIdentifier("money-draft-delete")
                }.environment(\.layoutDirection, .leftToRight)
            }
        }.padding(.horizontal, 12).padding(.vertical, 10).background(theme.surface).overlay { TicketEdge().stroke(theme.line, lineWidth: 1) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("money-draft-" + d.title)
    }
    private var draftConfirmGlyph: some View {
        Image(systemName: "checkmark").font(.body.bold()).foregroundStyle(theme.background).frame(width: 44, height: 44).background(theme.ink, in: .circle)
    }
    private func looks(_ items: [MoneyMessageLook]) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            HStack { Text("تحتاج نظرة").font(MadarTypography.cardTitle()).foregroundStyle(theme.color("reserveText")); DoubleRule().stroke(theme.color("reserveText"), lineWidth: 0.7).frame(height: 3) }
            Text("رسائل لم يفهمها المحلّل؛ لا تُحسب حتى تحسمها.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 12) {
                    avatar(item.sender)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.excerpt).font(MadarTypography.body()).lineLimit(3)
                        Text(service.time(item.at)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    }
                    Spacer(minLength: 6)
                    Button { run("money.ignoreMessage", ["id": .string(item.id.uuidString)]) } label: {
                        Text("تجاهل").font(MadarTypography.caption()).padding(.horizontal, 14).frame(minHeight: 44).overlay { Capsule().stroke(theme.line, lineWidth: 1) }
                    }.buttonStyle(.plain).accessibilityIdentifier("money-look-ignore")
                }.padding(12).background(theme.surface.opacity(0.6))
            }
        }.padding(.top, 6).accessibilityElement(children: .contain).accessibilityIdentifier("money-looks")
    }
    /// OR-23 (owner: lighter, smoother): the one-tap approval sits right under the messages it approves, not below the guide.
    @ViewBuilder private func clearButton(_ reading: MoneyMessagesReading) -> some View {
        let clear = reading.clearIDs, left = reading.drafts.count - reading.drafts.filter(\.clear).count
        if !clear.isEmpty {
            Button { run("money.confirmClear", ["ids": .array(clear.map { .string($0.uuidString) })]) } label: {
                VStack(spacing: 2) {
                    Text("اعتمد الواضح (" + service.digits.string(clear.count) + ")").font(.custom("thmanyahsans-Bold", size: 17, relativeTo: .headline))
                    if left > 0 { Text("ويبقى " + service.counted(left, ("قرار واحد", "قراران", "قرارات", "قرارًا")) + " لقرارك").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                }.frame(maxWidth: .infinity, minHeight: 60).overlay { Rectangle().stroke(theme.color("reserveText"), lineWidth: 1.2) }
            }.buttonStyle(.plain).accessibilityIdentifier("money-confirm-clear")
        }
    }
    private func footer(_ reading: MoneyMessagesReading) -> some View {
        VStack(spacing: 10) {
            if let note { Text(note).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-messages-note") }
            PasteButton(payloadType: String.self) { strings in
                let parsed = strings.map(AppMoneyService.pastedMessages)
                let messages = parsed.flatMap(\.messages), oversizedCount = parsed.reduce(0) { $0 + $1.oversizedCount }
                if messages.count > 500 {
                    var limitNote = "لصقك يحتوي " + service.digits.string(messages.count) + " رسالة مقبولة. الحد ٥٠٠ في الدفعة؛ لم تُستورد أي رسالة. قسّم النص وأعد لصق كل دفعة."
                    if oversizedCount > 0 {
                        limitNote += " وتُركت " + service.counted(oversizedCount, ("رسالة طويلة واحدة", "رسالتان طويلتان", "رسائل طويلة", "رسالة طويلة")) + " لتجاوزها ٢٠٠٠ حرف."
                    }
                    note = limitNote
                } else if messages.isEmpty {
                    if oversizedCount > 0 {
                        note = "لم تُلصق رسائل؛ " + service.counted(oversizedCount, ("رسالة طويلة واحدة", "رسالتان طويلتان", "رسائل طويلة", "رسالة طويلة")) + " تتجاوز حد ٢٠٠٠ حرف."
                    }
                } else {
                    let successNote = oversizedCount == 0 ? nil : "تُركت " + service.counted(oversizedCount, ("رسالة طويلة واحدة", "رسالتان طويلتان", "رسائل طويلة", "رسالة طويلة")) + " لتجاوزها ٢٠٠٠ حرف."
                    run("money.pasteBankMessages", ["messages": .array(messages.map { .object(["text": .string($0), "sender": .string("")]) })], successNote: successNote)
                }
            }.labelStyle(.titleAndIcon).tint(theme.color("reserveText")).frame(minHeight: 44).accessibilityIdentifier("money-messages-paste")
            Button { budgetOpen = true } label: { Label("تجاهله من الميزانيات", systemImage: "seal").font(MadarTypography.caption()).frame(minHeight: 44) }
                .buttonStyle(.plain).foregroundStyle(theme.color("reserveText")).accessibilityIdentifier("money-budget-open")
            Button { rulesOpen = true } label: { Label("قواعد التاجر", systemImage: "lamp.table").font(MadarTypography.caption()).frame(minHeight: 44) }
                .buttonStyle(.plain).foregroundStyle(theme.color("reserveText")).accessibilityIdentifier("money-rules-open")
            Text("الصق رسائل البنك إن لم تصل عبر الاختصار؛ تُفصل الرسائل بسطر فارغ.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).multilineTextAlignment(.center)
        }.padding(.top, 8)
    }
    private func run(_ name: String, _ payload: [String: MadarCore.JSONValue], successNote: String? = nil) {
        Task {
            do { try await app.executeMoneyCommand(name, payload: payload); note = successNote }
            catch { note = name == "money.applyStatement" ? "المبلغ يختلف عن كشف قريب لهذه البطاقة؛ راجع البطاقة أو تجاهل الرسالة" : "لم يُحفظ: الحركة تحتاج اختيارًا قبل اعتمادها" }
            load()
        }
    }
    private func load() {
        do { reading = try service.loadMessages(); failure = nil } catch { failure = "تعذّرت قراءة الرسائل" }
    }
}

/// A pointed arch with a straight body: the room's arch language for the three counters.
struct MessageArch: InsettableShape {
    var insetAmount: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount), shoulder = r.minY + min(r.height * 0.32, 34)
        var p = Path()
        p.move(to: .init(x: r.minX, y: r.maxY)); p.addLine(to: .init(x: r.minX, y: shoulder))
        p.addQuadCurve(to: .init(x: r.midX, y: r.minY), control: .init(x: r.minX + r.width * 0.06, y: r.minY + 2))
        p.addQuadCurve(to: .init(x: r.maxX, y: shoulder), control: .init(x: r.maxX - r.width * 0.06, y: r.minY + 2))
        p.addLine(to: .init(x: r.maxX, y: r.maxY)); p.closeSubpath()
        return p
    }
    func inset(by amount: CGFloat) -> MessageArch { var copy = self; copy.insetAmount += amount; return copy }
}

/// A slip with a shallow notch along its top edge, as the canonical message cards.
struct TicketEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: rect.minX, y: rect.minY)); p.addLine(to: .init(x: rect.midX, y: rect.minY + 10)); p.addLine(to: .init(x: rect.maxX, y: rect.minY))
        p.addLine(to: .init(x: rect.maxX, y: rect.maxY)); p.addLine(to: .init(x: rect.minX, y: rect.maxY)); p.closeSubpath()
        return p
    }
}
