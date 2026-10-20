import SwiftUI
import MadarCore
import MadarDesign

struct MoneyCashView: View {
    let app: AppSession
    let reading: MoneyBasisReading
    @Binding var revealed: Bool
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var source: MoneySourceDetail?
    private var service: AppMoneyService { .init(app: app) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MoneyPageHeader(title: "على أي أساس", close: { dismiss() })
                Text("حسابك يبيّن النقد، و«لك فعلًا» يخصم ما عليك في البطاقات والأقساط.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                if visible && !dynamicType.isAccessibilitySize && reading.home.basis.inAccountMinor > 0 && reading.home.basis.netMinor >= 0 {
                    MoneyCashColumns(reading: reading, app: app, onSource: { source = $0 }).frame(height: 450)
                } else {
                    HStack { Text("في حسابك"); Spacer(); Text(figure: amount(reading.home.basis.inAccountMinor)) }
                    HStack { Text("لك فعلًا"); Spacer(); Text(figure: amount(reading.home.basis.netMinor)) }
                    if reading.home.basis.netMinor < 0 { Text("ما عليك أكثر من النقد المسجّل.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("يومك وحدودك يسجّلان الشراء يومه، ولو بالائتمان؛ والسداد ينقص النقد والدين معًا، فلا يُحسب مصروفًا مرة أخرى.")
                    Text("من «لك فعلًا» محجوز " + amount(reading.home.basis.reservedMinor) + "، وغير مخصّص " + amount(reading.home.basis.unallocatedMinor) + ".")
                }.font(MadarTypography.body()).fixedSize(horizontal: false, vertical: true).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface).overlay(alignment: .leading) { Rectangle().fill(theme.color("surplusText")).frame(width: 3) }
                Text("مصادر النقد").font(MadarTypography.cardTitle())
                ForEach(reading.accounts) { item in sourceButton(item) }
                if !reading.debts.isEmpty {
                    Text("مصادر «عليك»").font(MadarTypography.cardTitle())
                    ForEach(reading.debts) { item in sourceButton(item) }
                }
                if !visible { Button("أظهر الأرقام") { revealed = true }.frame(minHeight: 44) }
            }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 24).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(item: $source) { MoneySourceView(app: app, detail: $0, visible: visible) }
            .accessibilityIdentifier("money-cash")
    }
    private func sourceButton(_ item: MoneySourceDetail) -> some View {
        Button { source = item } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(MadarTypography.body())
                    if item.estimated { Text("تقريبًا").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                    if let date = item.date { MadarDateLabel(app.dateLabels(date, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                }
                Spacer()
                Text(figure: amount(item.amountMinor)).font(MadarTypography.cardTitle())
                Image(systemName: "chevron.left").font(.caption).padding(.top, 5)
            }.padding(.vertical, 10).frame(minHeight: 44).overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
        }.buttonStyle(.plain).accessibilityIdentifier("money-source-" + item.id)
    }
    private func amount(_ value: Int) -> String { visible ? service.amount(value) : "•••" }
}

private struct MoneyCashColumns: View {
    let reading: MoneyBasisReading
    let app: AppSession
    var onSource: (MoneySourceDetail) -> Void
    @Environment(\.roomTheme) private var theme
    private var service: AppMoneyService { .init(app: app) }
    var body: some View {
        GeometryReader { proxy in
            let width: CGFloat = 54, base = proxy.size.height - 8, height = proxy.size.height - 92
            let netX = proxy.size.width * 0.22, cashX = proxy.size.width * 0.60
            let cash = max(1, reading.home.basis.inAccountMinor), netHeight = max(0, min(height, CGFloat(reading.home.basis.netMinor) / CGFloat(cash) * height))
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let netRect = CGRect(x: netX, y: base - netHeight, width: width, height: netHeight)
                    context.fill(Path(netRect), with: .color(theme.color("surplus")))
                    context.stroke(MoneyCrown().path(in: .init(x: netX, y: base - netHeight - 30, width: width, height: 30)), with: .color(theme.color("reserveText")), lineWidth: 1.1)
                    let cashRect = CGRect(x: cashX, y: base - height, width: width, height: height)
                    context.stroke(Path(cashRect), with: .color(theme.color("reserveText")), lineWidth: 1.1)
                    context.stroke(MoneyCrown().path(in: .init(x: cashX, y: base - height - 30, width: width, height: 30)), with: .color(theme.color("reserveText")), lineWidth: 1.1)
                    var y = base - height
                    for item in reading.debts where item.amountMinor > 0 {
                        let h = CGFloat(item.amountMinor) / CGFloat(cash) * height
                        let rect = CGRect(x: cashX + 1, y: y, width: width - 2, height: h)
                        context.fill(Path(rect), with: .color(theme.color(item.id.hasPrefix("bnpl:") ? "reserve" : item.id.hasPrefix("unbilled:") ? "bills" : "accent")))
                        context.stroke(Path(rect), with: .color(theme.surface), lineWidth: 0.6); y += h
                    }
                    var link = Path(); link.move(to: .init(x: netX + width, y: base - netHeight)); link.addLine(to: .init(x: cashX, y: base - netHeight))
                    context.stroke(link, with: .color(theme.secondaryInk), style: .init(lineWidth: 0.8, dash: [3, 3]))
                    var ground = Path(); ground.move(to: .init(x: netX - 18, y: base)); ground.addLine(to: .init(x: cashX + width + 18, y: base))
                    context.stroke(ground, with: .color(theme.ink), lineWidth: 1.6)
                }.accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) { Text("في حسابك").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk); Text(figure: service.amount(reading.home.basis.inAccountMinor)).font(MadarTypography.cardTitle()).accessibilityIdentifier("money-cash-total") }
                    .frame(width: 150, alignment: .leading).position(x: 75, y: 22)
                VStack(alignment: .leading, spacing: 2) { Text("لك فعلًا").font(MadarTypography.caption()).foregroundStyle(theme.color("surplusText")); Text(figure: service.amount(reading.home.basis.netMinor)).font(MadarTypography.cardTitle()).foregroundStyle(theme.color("surplusText")).accessibilityIdentifier("money-cash-net") }
                    .frame(width: 140, alignment: .leading).position(x: proxy.size.width - 70, y: 64)
                ForEach(Array(reading.debts.prefix(4))) { item in
                    let index = reading.debts.firstIndex { $0.id == item.id } ?? 0
                    Button { onSource(item) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(2)
                            Text(figure: service.amount(-item.amountMinor)).font(MadarTypography.section())
                            if item.estimated { Text("تقريبًا").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                            if let date = item.date { MadarDateLabel(app.dateLabels(date, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                        }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
                    }.buttonStyle(.plain).frame(width: max(76, proxy.size.width - cashX - width - 8))
                        .position(x: (proxy.size.width - cashX - width - 8) / 2, y: 104 + CGFloat(index) * 86)
                        .accessibilityIdentifier("money-cash-debt-" + item.id)
                }
            }
        }.accessibilityElement(children: .contain)
    }
}
