import SwiftUI
import MadarCore
import MadarDesign
import MadarMoney

struct MoneyBasisView: View {
    let app: AppSession
    @Binding var revealed: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var reading: MoneyBasisReading?
    @State private var source: MoneySourceDetail?
    @State private var failure: String?
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var service: AppMoneyService { .init(app: app) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    MoneyPageHeader(title: "على أي أساس", close: { dismiss() })
                    if let reading {
                        VStack(alignment: .leading, spacing: 8) {
                            NavigationLink {
                                MoneyCashView(app: app, reading: reading, revealed: $revealed)
                            } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(reading.home.hasKnownBalance ? "لك فعلًا، في حسابك " + amount(reading.home.basis.inAccountMinor) : "لم يُعرف رصيد الحسابات بعد").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(figure: visible && !reading.home.hasKnownBalance ? "—" : amount(reading.home.basis.netMinor)).font(.custom("thmanyahserifdisplay-Black", size: 44, relativeTo: .largeTitle)).accessibilityIdentifier("money-basis-net")
                                        Image(systemName: "arrow.up.left").font(.caption)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .trailing).contentShape(.rect)
                            }.buttonStyle(.plain).accessibilityIdentifier("money-cash-open")
                            if reading.home.unknownBalanceCount > 0 {
                                Text(reading.home.hasKnownBalance ? "الأرقام تخص الأرصدة المعروفة فقط؛ الحسابات التي تنتظر مطابقة لا تدخل في المجموع." : "المحجوز واليومية من السجلات؛ النقد والصافي وغير المخصّص ينتظرون مطابقة مع البنك.")
                                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            }
                            if visible && reading.home.hasKnownBalance && !dynamicType.isAccessibilitySize && reading.home.basis.netMinor > 0
                                && reading.reserved.allSatisfy({ $0.amountMinor >= 0 })
                                && (reading.explanation.cycleRemainderMinor ?? 0) >= 0
                                && (reading.explanation.availableNowMinor ?? 0) >= 0 {
                                MoneyBasisColumn(reading: reading, app: app, onSource: { source = $0 }).frame(height: 500)
                            } else {
                                basisList(reading).padding(.vertical, 20)
                            }
                        }.padding(16).background(theme.surface)
                            .overlay { Rectangle().stroke(theme.color("reserveText"), lineWidth: 1) }
                            .overlay { Rectangle().inset(by: 5).stroke(theme.color("reserveText"), lineWidth: 0.5) }
                    } else if let failure {
                        VStack(alignment: .leading, spacing: 12) { Text(failure).font(MadarTypography.body()); Button("أعِد المحاولة", action: load).frame(minHeight: 44) }.padding(20)
                    } else { ProgressView().frame(maxWidth: .infinity, minHeight: 300) }
                    if !visible { Button("أظهر الأرقام") { revealed = true }.frame(minHeight: 44).accessibilityIdentifier("money-basis-reveal") }
                }.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(item: $source) { MoneySourceView(app: app, detail: $0, visible: visible) }
            .task { load() }
        }
        .environment(\.roomTheme, theme).presentationDetents([.large]).presentationDragIndicator(.hidden)
    }
    private func load() {
        do { reading = try service.loadBasis(); failure = nil }
        catch { reading = nil; failure = "تعذّرت قراءة الأساس الآن. يمكنك إعادة المحاولة." }
    }
    private func basisList(_ reading: MoneyBasisReading) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            basisRow("غير مخصّص", reading.explanation.unallocatedMinor, "money-basis-unallocated", known: reading.home.hasKnownBalance)
            basisRow("المحجوز", reading.explanation.reservedMinor, "money-basis-reserved")
            if let value = reading.explanation.availableNowMinor { basisRow("لك الآن", value, "money-basis-current") }
            if let value = reading.explanation.futureDailyMinor { basisRow("يومياتك القادمة", value, "money-basis-future") }
            if let value = reading.explanation.cycleRemainderMinor { basisRow(reading.home.hasKnownBalance && value < 0 ? "فرق التمويل" : "فائض الدورة", value, "money-basis-remainder", known: reading.home.hasKnownBalance) }
            ForEach(reading.reserved) { piece in
                Button { source = piece.detail } label: { HStack { Text(piece.title); Spacer(); Text(figure: amount(piece.amountMinor)) }.frame(minHeight: 44).contentShape(.rect) }.buttonStyle(.plain)
            }
        }
    }
    private func basisRow(_ title: String, _ value: Int, _ id: String, known: Bool = true) -> some View {
        HStack { Text(title); Spacer(); Text(figure: visible && !known ? "—" : amount(value)).font(MadarTypography.cardTitle()).accessibilityIdentifier(id) }.font(MadarTypography.body())
    }
    private func amount(_ value: Int) -> String { visible ? service.amount(value) : "•••" }
}

struct MoneyPageHeader: View {
    var title: String
    var close: () -> Void
    @Environment(\.roomTheme) private var theme
    var body: some View {
        HStack {
            Text(title).font(MadarTypography.title())
            Spacer()
            Button(action: close) { Image(systemName: "xmark").font(.body).frame(width: 44, height: 44).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1) } }
                .buttonStyle(.plain).accessibilityLabel("إغلاق").accessibilityIdentifier("money-page-close")
        }.frame(minHeight: 48)
    }
}

struct MoneyBasisColumn: View {
    let reading: MoneyBasisReading
    let app: AppSession
    var onSource: (MoneySourceDetail) -> Void
    @Environment(\.roomTheme) private var theme
    private var service: AppMoneyService { .init(app: app) }
    private var columnPieces: [(String, Int, String)] {
        let b = reading.explanation
        var values = reading.reserved.reversed().map { ($0.id, $0.amountMinor, $0.role) }
        if let amount = b.futureDailyMinor { values.append(("future", amount, "reserve")) }
        if let amount = b.availableNowMinor { values.append(("current", amount, "surplus")) }
        if let amount = b.cycleRemainderMinor { values.append(("remainder", amount, "ink2")) }
        if b.futureDailyMinor == nil { values.append(("unallocated", b.unallocatedMinor, "surplus")) }
        return values
    }
    var body: some View {
        GeometryReader { proxy in
            let barX = proxy.size.width - 64, barWidth: CGFloat = 56, base = proxy.size.height - 12, barHeight = proxy.size.height - 76
            let sum = max(1, columnPieces.reduce(0) { $0 + max(0, $1.1) })
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    var y = base
                    for (_, amount, role) in columnPieces where amount > 0 {
                        let h = CGFloat(amount) / CGFloat(sum) * barHeight
                        let rect = CGRect(x: barX, y: y - h, width: barWidth, height: h)
                        context.fill(Path(rect), with: .color(theme.color(role)))
                        var edge = Path(); edge.move(to: .init(x: barX, y: y - h)); edge.addLine(to: .init(x: barX + barWidth, y: y - h))
                        context.stroke(edge, with: .color(theme.surface), lineWidth: 1)
                        y -= h
                    }
                    context.stroke(MoneyCrown().path(in: CGRect(x: barX, y: y - 30, width: barWidth, height: 30)), with: .color(theme.color("reserveText")), lineWidth: 1.1)
                    let reservedFraction = CGFloat(max(0, reading.explanation.reservedMinor)) / CGFloat(sum)
                    let boundary = base - reservedFraction * barHeight
                    var rule = Path(); rule.move(to: .init(x: 0, y: boundary)); rule.addLine(to: .init(x: size.width, y: boundary))
                    context.stroke(rule, with: .color(theme.color("reserveText")), style: .init(lineWidth: 0.9, dash: [3, 3]))
                    for piece in reading.reserved {
                        let labelY: CGFloat = piece.id == "loan" ? base - 18 : piece.id == "bills" ? base - 68 : base * 0.60
                        let targetY: CGFloat = piece.id == "loan" ? base - 4 : piece.id == "bills" ? base - 12 : base * 0.64
                        var leader = Path(); leader.move(to: .init(x: barX - 16, y: labelY + 3)); leader.addLine(to: .init(x: barX - 10, y: labelY + 3)); leader.addLine(to: .init(x: barX - 2, y: targetY))
                        context.stroke(leader, with: .color(theme.secondaryInk), lineWidth: 0.7)
                    }
                    var ground = Path(); ground.move(to: .init(x: barX - 4, y: base)); ground.addLine(to: .init(x: barX + barWidth + 4, y: base))
                    context.stroke(ground, with: .color(theme.ink), lineWidth: 1.3)
                }.accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("غير مخصّص").font(MadarTypography.caption()).foregroundStyle(theme.color("surplusText"))
                    Text(figure: service.amount(reading.explanation.unallocatedMinor)).font(MadarTypography.cardTitle()).foregroundStyle(theme.color("surplusText")).accessibilityIdentifier("money-basis-unallocated")
                    Text(figure: service.amount(reading.explanation.reservedMinor)).font(MadarTypography.cardTitle()).padding(.top, 8).accessibilityIdentifier("money-basis-reserved")
                    Text("المحجوز").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }.frame(width: 108, alignment: .leading).position(x: proxy.size.width - 54, y: 142)
                VStack(alignment: .leading, spacing: 8) {
                    if let value = reading.explanation.cycleRemainderMinor {
                        callout(value < 0 ? "فرق التمويل" : "فائض الدورة", value, role: "ink2", id: "money-basis-remainder")
                    }
                    if let value = reading.explanation.availableNowMinor { callout("لك الآن", value, role: "surplusText", id: "money-basis-current") }
                    if let value = reading.explanation.futureDailyMinor { callout("يومياتك القادمة", value, role: "reserveText", id: "money-basis-future") }
                }.frame(width: 124, alignment: .leading).position(x: proxy.size.width - barX + 74, y: 88)
                ForEach(reading.reserved) { piece in
                    let y: CGFloat = piece.id == "loan" ? base - 18 : piece.id == "bills" ? base - 68 : base * 0.60
                    Button { onSource(piece.detail) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(piece.title).font(MadarTypography.fine()).foregroundStyle(theme.color(piece.role))
                            Text(figure: service.amount(piece.amountMinor)).font(MadarTypography.cardTitle())
                        }.frame(minHeight: 44)
                    }.buttonStyle(.plain).frame(width: 170, alignment: .leading).position(x: proxy.size.width - barX + 90, y: y)
                        .accessibilityIdentifier("money-basis-source-" + piece.id)
                }
            }
        }
    }
    private func callout(_ title: String, _ value: Int, role: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 0) { Text(title).font(MadarTypography.fine()).foregroundStyle(theme.color(role)); Text(figure: service.amount(value)).font(MadarTypography.cardTitle()).accessibilityIdentifier(id) }
    }
}

struct MoneyCrown: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in p.move(to: .init(x: r.minX, y: r.maxY)); p.addQuadCurve(to: .init(x: r.midX, y: r.minY), control: .init(x: r.minX, y: r.height * 0.40 + r.minY)); p.addQuadCurve(to: .init(x: r.maxX, y: r.maxY), control: .init(x: r.maxX, y: r.height * 0.40 + r.minY)); p.closeSubpath() }
    }
}

struct MoneySourceView: View {
    let app: AppSession
    let detail: MoneySourceDetail
    let visible: Bool
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MoneyPageHeader(title: detail.title, close: { dismiss() })
                Text(visible ? detail.valueText ?? AppMoneyService(app: app).amount(detail.amountMinor) : "•••").font(.custom("thmanyahserifdisplay-Black", size: 38, relativeTo: .largeTitle))
                if detail.estimated { Text("تقريبًا، تاريخ القفل مقدّر").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                Text(detail.explanation).font(MadarTypography.body()).fixedSize(horizontal: false, vertical: true)
                if let date = detail.date { MadarDateLabel(app.dateLabels(date)).foregroundStyle(theme.secondaryInk) }
                if let message = detail.message, visible {
                    Divider().overlay(theme.line)
                    Text("الرسالة المصدر").font(MadarTypography.section())
                    Text(message).font(MadarTypography.body()).textSelection(.enabled)
                }
            }.padding(22)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible).accessibilityIdentifier("money-source")
    }
}
