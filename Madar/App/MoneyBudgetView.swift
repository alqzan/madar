import SwiftUI
import MadarCore
import MadarData
import MadarDesign

/// F06: the gold strike and receipt stamp. A stamp removes budget charges, never the movement.
struct MoneyBudgetView: View {
    let app: AppSession
    @Binding var revealed: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var reading: MoneyBudgetReading?
    @State private var selected: MoneyBudgetRow?
    @State private var failure: String?
    private var service: AppMoneyService { .init(app: app) }
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private func amount(_ minor: Int) -> String { visible ? service.amount(minor) : "•••" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1) } }
                        .buttonStyle(.madarPlain).accessibilityLabel("إغلاق").accessibilityIdentifier("money-budget-close")
                    Text("تجاهله من الميزانيات").font(.custom("thmanyahserifdisplay-Bold", size: 25, relativeTo: .title)).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                }.padding(.top, 8)
                if let reading {
                    summary(reading)
                    if !visible { Button("أظهر الأرقام") { revealed = true }.frame(minHeight: 44).accessibilityIdentifier("money-budget-reveal") }
                    let byDay = Dictionary(grouping: reading.rows, by: \.day), days = byDay.keys.sorted(by: >)
                    ForEach(days, id: \.description) { day in
                        VStack(alignment: .leading, spacing: 0) {
                            MadarDateLabel(app.dateLabels(day, compact: true, weekday: true), primaryFont: MadarTypography.section(), secondaryFont: MadarTypography.fine())
                                .foregroundStyle(theme.ink).padding(.top, 6).padding(.bottom, 7)
                            ForEach(byDay[day] ?? []) { row in movement(row) }
                        }
                    }
                    if reading.rows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("لا مصروفات في هذه الدورة بعد").font(MadarTypography.cardTitle())
                            Text("بعد اعتماد حركة في رسائل البنك، تستطيع ختمها هنا لتبقى في السجل وتخرج من الميزانيات.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                        }.padding(.vertical, 30)
                    } else {
                        Label("اضغط أي حركة لمعاينة أثر الختم", systemImage: "seal").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).frame(maxWidth: .infinity).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("في السجل دائمًا").font(MadarTypography.cardTitle())
                            Text("المختوم خارج يومك والمظاريف وحدود التصنيفات. يبقى النقد والدين صحيحين، وتستطيع رفع الختم متى أردت.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface)
                            .overlay { RoundedRectangle(cornerRadius: 4).stroke(theme.line, lineWidth: 1) }.padding(.top, 14)
                    }
                } else if let failure { Text(failure).font(MadarTypography.body()); Button("أعِد المحاولة", action: load).frame(minHeight: 44) }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            }.padding(.horizontal, 20).padding(.bottom, 28).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).environment(\.roomTheme, theme)
            .toolbarVisibility(.hidden, for: .navigationBar).accessibilityIdentifier("money-budget")
            .task { load() }.onChange(of: app.prayerRevision) { load() }
            .sheet(item: $selected) { row in MoneyBudgetReceipt(app: app, row: row, revealed: $revealed) }
    }
    private func summary(_ r: MoneyBudgetReading) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("مشطوب، خارج ميزانيتك").font(MadarTypography.caption()).foregroundStyle(theme.color("reserveText"))
                    Text(figure: amount(r.excludedMinor)).font(.custom("thmanyahserifdisplay-Black", size: 42, relativeTo: .largeTitle))
                        .foregroundStyle(theme.color("reserveText")).overlay { MoneyStrike().stroke(theme.color("reserveText"), lineWidth: 1.5).frame(height: 9) }
                        .accessibilityIdentifier("money-budget-excluded-total")
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("احتُسب من يومك").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    Text(figure: amount(r.dailyMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 26, relativeTo: .title2)).accessibilityIdentifier("money-budget-daily-total")
                }
            }
            GeometryReader { proxy in
                let total = max(1, r.excludedMinor + r.dailyMinor)
                // The struck share sits under the struck total (leading); the daily share under «احتُسب من يومك».
                HStack(spacing: 0) {
                    BudgetHatching().stroke(theme.color("reserveText"), lineWidth: 1.5).clipped()
                    Rectangle().fill(theme.ink).frame(width: visible ? proxy.size.width * CGFloat(r.dailyMinor) / CGFloat(total) : proxy.size.width / 2)
                }.clipShape(.capsule).overlay { Capsule().stroke(theme.line, lineWidth: 1) }
            }.frame(height: 12).accessibilityHidden(true)
            HStack {
                Label { Text("في السجل، لا يُخصم") } icon: { MoneyStrike().stroke(theme.color("reserveText"), lineWidth: 1.2).frame(width: 22, height: 5) }.foregroundStyle(theme.secondaryInk)
                Spacer()
                Text("من الحركات المعتمدة").foregroundStyle(theme.color("surplusText"))
            }.font(MadarTypography.fine())
        }.padding(.bottom, 8)
    }
    private func movement(_ row: MoneyBudgetRow) -> some View {
        Button { selected = row } label: {
            HStack(spacing: 10) {
                Image(systemName: "diamond.fill").font(.system(size: 8)).foregroundStyle(theme.color("reserveText"))
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.merchant).font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)).foregroundStyle(row.excluded ? theme.secondaryInk : theme.ink)
                    Text(row.category).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    if let reason = row.reason { Text("لأن: " + reason).font(MadarTypography.fine()).foregroundStyle(theme.color("reserveText")).lineLimit(1) }
                }
                Spacer(minLength: 4)
                if row.excluded {
                    Text("خارج الميزانية").font(MadarTypography.fine()).foregroundStyle(theme.color("accentText")).padding(.horizontal, 8).padding(.vertical, 5)
                        .background(theme.background).overlay { Capsule().stroke(theme.color("accentText"), lineWidth: 1) }.rotationEffect(.degrees(-5))
                }
                Text(figure: amount(row.netMinor)).font(.custom("thmanyahserifdisplay-Bold", size: 20, relativeTo: .title3)).foregroundStyle(row.excluded ? theme.secondaryInk : theme.ink)
            }.padding(.vertical, 9).frame(minHeight: 52)
                .overlay { if row.excluded { MoneyStrike().stroke(theme.color("reserveText"), lineWidth: 1).frame(height: 6).allowsHitTesting(false) } }
                .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 0.7) }.contentShape(Rectangle())
        }.buttonStyle(.madarPlain).accessibilityLabel(row.merchant + "، " + amount(row.netMinor) + (row.excluded ? "، خارج الميزانية" + (row.reason.map { "، لأن " + $0 } ?? "") : "، داخل الميزانية"))
            .accessibilityIdentifier("money-budget-row-" + row.merchant)
    }
    private func load() {
        do { reading = try service.loadBudgetExclusions(); failure = nil }
        // AU-95: a failed reload must not leave old rows on screen with the reason hidden.
        catch { reading = nil; failure = "لم تكتمل قراءة الحركات. حاول مرة أخرى." }
    }
}

private struct MoneyBudgetReceipt: View {
    let app: AppSession
    let row: MoneyBudgetRow
    @Binding var revealed: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var saving = false
    @State private var failure: String?
    @State private var reason = ""
    private var service: AppMoneyService { .init(app: app) }
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private func amount(_ minor: Int) -> String { visible ? service.amount(minor) : "•••" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(row.merchant).font(.custom("thmanyahserifdisplay-Bold", size: 30, relativeTo: .title))
                            Text(row.category + (row.payment.isEmpty ? "" : "، " + row.payment)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            Text(service.time(row.at)).font(MadarTypography.fine()).foregroundStyle(theme.color("surplusText"))
                        }
                        Spacer(minLength: 0)
                        BudgetStamp().foregroundStyle(theme.color("accentText")).frame(width: 108, height: 108).rotationEffect(.degrees(-12))
                    }
                    MadarDateLabel(app.dateLabels(row.day, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    Line().stroke(theme.line, style: .init(lineWidth: 1, dash: [4, 4])).frame(height: 1)
                    HStack(alignment: .firstTextBaseline) {
                        Text(figure: amount(row.amountMinor)).font(.custom("thmanyahserifdisplay-Black", size: 39, relativeTo: .largeTitle))
                            .overlay { if !row.excluded { MoneyStrike().stroke(theme.color("accentText"), lineWidth: 2).frame(height: 10) } }
                        Spacer()
                        Text(row.excluded ? "رفع الختم يعيد أثر الميزانية" : "معاينة قبل اعتماد الختم").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    }
                    effect("من يومك", value: row.dailyMinor)
                    if row.categoryMinor > 0 { effect("من حدّ «" + row.category + "»", value: row.categoryMinor) }
                    HStack { Text("في السجل"); Spacer(); Text("يبقى دائمًا").bold() }.font(MadarTypography.body())
                    if row.netMinor != row.amountMinor { Text("بعد الردود: " + amount(row.netMinor)).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                    // M5-X00 (owner 16 Oct): an optional reason, written on the receipt while the stamp stays.
                    if let stamped = row.reason {
                        HStack(alignment: .firstTextBaseline) { Text("السبب"); Spacer(); Text(stamped).bold().multilineTextAlignment(.trailing) }
                            .font(MadarTypography.body()).foregroundStyle(theme.color("reserveText")).accessibilityIdentifier("money-budget-reason")
                    } else if !row.excluded {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("السبب، إن أردت").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                            TextField("مثل: هدية، أو مصروف عمل يُعوَّض", text: $reason).font(MadarTypography.body()).padding(10)
                                .overlay { Rectangle().stroke(theme.line, lineWidth: 1) }.accessibilityIdentifier("money-budget-reason-field")
                                .onChange(of: reason) { if reason.count > MoneyCommandPayload.maxReasonLength { reason = String(reason.prefix(MoneyCommandPayload.maxReasonLength)) } }
                        }
                    }
                }.padding(20).background(theme.background).clipShape(BudgetReceiptPaper())
                    .overlay { BudgetReceiptPaper().stroke(theme.line, lineWidth: 1) }.shadow(color: theme.ink.opacity(0.08), radius: 9, y: 4)
                    .rotationEffect(.degrees(-1.2)).padding(.horizontal, 4)
                Text(row.excluded ? "تعود الحركة إلى توزيعها الأصلي؛ النقد والدين يبقيان كما هما." : "الختم لهذه الحركة فقط. تخرج من يومك والمظاريف وحدود التصنيفات، وتبقى في حسابك والسجل.")
                    .font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                if !visible { Button("أظهر الأرقام") { revealed = true }.frame(minHeight: 44) }
                if let failure { Text(failure).font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")) }
                Button(action: save) {
                    HStack { if saving { ProgressView() }; Text(row.excluded ? "ارفع الختم وأعدها للميزانية" : "اعتمد الختم · خارج الميزانية") }
                        .font(MadarTypography.body()).bold().frame(maxWidth: .infinity, minHeight: 54).background(theme.ink, in: Capsule()).foregroundStyle(theme.background)
                }.buttonStyle(.madarPlain).disabled(saving).accessibilityIdentifier("money-budget-confirm")
                Button("إلغاء") { dismiss() }.font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 44).disabled(saving)
            }.padding(20).padding(.top, 12).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(theme.surface.ignoresSafeArea()).foregroundStyle(theme.ink).environment(\.roomTheme, theme)
            .presentationDetents([.height(600), .large]).presentationDragIndicator(.visible).interactiveDismissDisabled(saving).accessibilityIdentifier("money-budget-receipt")
    }
    private func effect(_ title: String, value: Int) -> some View {
        HStack { Text(title); Spacer(); Text((row.excluded ? "يعود " : "لا يُخصم ") + amount(value)).bold().foregroundStyle(theme.color("surplusText")) }.font(MadarTypography.body())
    }
    private func save() {
        guard !saving else { return }; saving = true
        Task {
            do {
                var payload: [String: MadarCore.JSONValue] = ["id": .string(row.id.uuidString), "excluded": .bool(!row.excluded), "expectedExcluded": .bool(row.excluded)]
                let note = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                if !row.excluded && !note.isEmpty { payload["reason"] = .string(note) }
                try await app.executeMoneyCommand("money.setBudgetExclusion", payload: payload)
                dismiss()
            } catch { failure = "تغيّرت الحركة أو تعذّر حفظها. أغلق الإيصال وافتحه من جديد."; saving = false }
        }
    }
}

private struct MoneyStrike: Shape {
    func path(in r: CGRect) -> Path { Path { p in p.move(to: .init(x: 0, y: r.minY)); p.addLine(to: .init(x: r.maxX, y: r.minY + 1)); p.move(to: .init(x: 0, y: r.maxY)); p.addLine(to: .init(x: r.maxX, y: r.maxY - 1)) } }
}
private struct Line: Shape {
    func path(in r: CGRect) -> Path { Path { p in p.move(to: .init(x: 0, y: r.midY)); p.addLine(to: .init(x: r.maxX, y: r.midY)) } }
}
private struct BudgetHatching: Shape {
    func path(in r: CGRect) -> Path { Path { p in for x in stride(from: -r.height, to: r.width + r.height, by: 7) { p.move(to: .init(x: x, y: r.maxY)); p.addLine(to: .init(x: x + r.height, y: 0)) } } }
}
private struct BudgetReceiptPaper: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: .zero); p.addLine(to: .init(x: r.maxX, y: 0)); p.addLine(to: .init(x: r.maxX, y: r.maxY - 8))
            let count = 24
            for n in stride(from: count, through: 0, by: -1) { p.addLine(to: .init(x: r.width * CGFloat(n) / CGFloat(count), y: r.maxY - (n.isMultiple(of: 2) ? 8 : 0))) }
            p.closeSubpath()
        }
    }
}
private struct BudgetStamp: View {
    var body: some View {
        ZStack {
            Circle().stroke(lineWidth: 3); Circle().stroke(lineWidth: 0.8).padding(6)
            Circle().stroke(style: .init(lineWidth: 1, dash: [2, 3])).padding(16)
            // A ring of small stars between the rims, as on the canonical seal.
            ForEach(0..<20, id: \.self) { n in
                Image(systemName: "star.fill").font(.system(size: 4)).offset(y: -43).rotationEffect(.degrees(Double(n) * 18))
            }
            Text("خارج\nالميزانية").font(.custom("thmanyahserifdisplay-Bold", size: 17, relativeTo: .headline)).multilineTextAlignment(.center)
        }.accessibilityHidden(true)
    }
}
