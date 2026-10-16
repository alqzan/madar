import SwiftUI
import MadarCore
import MadarDesign

struct MoneyReserveGrid: View {
    let beforeMinor: Int
    let afterMinor: Int
    let dailyMinor: Int
    let app: AppSession
    @Environment(\.roomTheme) private var theme
    private var cells: Int { min(540, max(0, beforeMinor) / dailyMinor + (max(0, beforeMinor) % dailyMinor == 0 ? 0 : 1)) }
    private var rows: Int { max(1, (cells + 29) / 30) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { row in Text(AppMoneyService(app: app).digits.string(row + 1)).font(.custom("thmanyahsans-Regular", size: 11)).foregroundStyle(theme.secondaryInk).frame(height: 13) }
                }.frame(width: 12).accessibilityHidden(true)
                Canvas { context, size in
                    let gap: CGFloat = 1.5, w = (size.width - 29 * gap) / 30, h: CGFloat = 11.5
                    for index in 0..<cells {
                        let x = size.width - CGFloat(index % 30 + 1) * w - CGFloat(index % 30) * gap, y = CGFloat(index / 30) * 13
                        let full = min(1, max(0, Double(beforeMinor - index * dailyMinor) / Double(dailyMinor)))
                        let remaining = min(full, max(0, Double(afterMinor - index * dailyMinor) / Double(dailyMinor)))
                        let r = CGRect(x: x, y: y, width: w, height: h)
                        if remaining > 0 { context.fill(Path(CGRect(x: r.maxX - w * remaining, y: y, width: w * remaining, height: h)), with: .color(theme.color("reserve"))) }
                        if full > remaining { context.fill(Path(CGRect(x: r.maxX - w * full, y: y, width: w * (full - remaining), height: h)), with: .color(theme.color("due"))) }
                        context.stroke(Path(r), with: .color(theme.color("reserveText")), lineWidth: 1)
                    }
                    if cells == 0 { context.stroke(Path(CGRect(x: size.width - 12, y: 0, width: 12, height: 12)), with: .color(theme.color("reserveText")), style: .init(lineWidth: 1, dash: [2, 2])) }
                }.frame(height: CGFloat(rows) * 13).accessibilityHidden(true)
            }
            if max(0, beforeMinor) / dailyMinor > 540 { Text("المعروض أول " + AppMoneyService(app: app).dailies(540)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
        }.accessibilityElement(children: .ignore).accessibilityLabel("مربعات الاحتياطي، كل مربع يومية واحدة").accessibilityIdentifier("money-reserve-grid")
    }
}

struct MoneySurplusChart: View {
    let points: [MoneySurplusPoint]
    let current: Int
    let next: GregorianDay?
    let app: AppSession
    @Environment(\.roomTheme) private var theme
    private var count: Int { points.count + 2 }
    var body: some View {
        GeometryReader { proxy in
            let step = proxy.size.width / CGFloat(count), barWidth = min(28, step * 0.54), base = proxy.size.height - 48
            let maximum = max(1, max(current, points.map { max($0.balanceMinor, $0.balanceMinor - $0.deltaMinor) }.max() ?? 0))
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    func x(_ index: Int) -> CGFloat { size.width - CGFloat(index + 1) * step + (step - barWidth) / 2 }
                    func y(_ value: Int) -> CGFloat { base - CGFloat(max(0, value)) / CGFloat(maximum) * (base - 20) }
                    var baseline = Path(); baseline.move(to: .init(x: 0, y: base)); baseline.addLine(to: .init(x: size.width, y: base))
                    context.stroke(baseline, with: .color(theme.color("reserveText")), lineWidth: 1)
                    for (index, point) in points.enumerated() {
                        let old = point.balanceMinor - point.deltaMinor, top = min(y(old), y(point.balanceMinor))
                        context.fill(Path(CGRect(x: x(index), y: top, width: barWidth, height: max(1, abs(y(old) - y(point.balanceMinor))))), with: .color(theme.color(point.deltaMinor < 0 ? "due" : "surplus")))
                        var connector = Path(); connector.move(to: .init(x: x(index), y: y(point.balanceMinor))); connector.addLine(to: .init(x: x(index + 1) + barWidth, y: y(point.balanceMinor)))
                        context.stroke(connector, with: .color(theme.secondaryInk), style: .init(lineWidth: 0.7, dash: [2, 2]))
                    }
                    let now = CGRect(x: x(points.count), y: y(current), width: barWidth, height: max(1, base - y(current)))
                    context.fill(Path(now), with: .color(theme.color("surplus"))); context.stroke(Path(now), with: .color(theme.color("surplusText")), lineWidth: 1)
                    if next != nil {
                        let future = CGRect(x: 2, y: max(8, y(current) - 15), width: max(12, barWidth), height: 15)
                        context.stroke(Path(future), with: .color(theme.color("surplusText")), style: .init(lineWidth: 1, dash: [3, 2]))
                    }
                }.accessibilityHidden(true)
                HStack(alignment: .top, spacing: 0) {
                    ForEach(points) { point in
                        VStack(spacing: 1) {
                            Text(AppMoneyService(app: app).amount(point.deltaMinor)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                            if let date = point.date { MadarDateLabel(app.dateLabels(date, compact: true), primaryFont: .custom("thmanyahsans-Regular", size: 11), secondaryFont: .custom("thmanyahsans-Regular", size: 11)) }
                            else { Text("البداية").font(MadarTypography.fine()) }
                        }.frame(width: step)
                    }
                    Text("الآن").font(MadarTypography.fine()).frame(width: step)
                    if next != nil { Text("القادم").font(MadarTypography.fine()).frame(width: step) }
                }.foregroundStyle(theme.secondaryInk).offset(y: base + 5)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("تراكم الفائض من الدورات، والآن " + AppMoneyService(app: app).amount(current))
    }
}

struct MoneyGoalOverview: View {
    let envelope: MoneyHomeEnvelope
    let app: AppSession
    let visible: Bool
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var service: AppMoneyService { .init(app: app) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(envelope.name).font(MadarTypography.cardTitle())
                Spacer()
                Text(visible ? service.amount(envelope.balanceMinor) : "•••").font(MadarTypography.cardTitle()).foregroundStyle(envelope.balanceMinor < 0 ? theme.color("debt") : theme.ink)
            }
            if visible && !dynamicType.isAccessibilitySize {
                GeometryReader { proxy in
                    let progress = envelope.targetMinor.map { $0 > 0 ? min(1, Double(max(0, envelope.balanceMinor)) / Double($0)) : 0 } ?? 0
                    ZStack(alignment: .leading) {
                        Rectangle().stroke(theme.color("accent"), style: .init(lineWidth: 0.9, dash: [3, 2])).frame(height: 12)
                        if progress > 0 { Rectangle().fill(theme.color("accent")).frame(width: proxy.size.width * progress, height: 8) }
                        if envelope.balanceMinor < 0 {
                            Rectangle().stroke(theme.color("debt"), style: .init(lineWidth: 1.4, dash: [4, 2])).frame(width: min(48, proxy.size.width / 4), height: 16)
                        }
                        Capsule().fill(LinearGradient(colors: [theme.color("rod2"), theme.color("rod"), theme.color("rod2")], startPoint: .leading, endPoint: .trailing)).frame(width: 7, height: 25).offset(x: proxy.size.width * progress)
                    }.frame(height: 25)
                }.frame(height: 25).accessibilityHidden(true)
            }
            if let target = envelope.targetMinor { Text("الهدف " + (visible ? service.amount(target) : "•••")).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
            if envelope.balanceMinor < 0 { Text("دين، لم تُحدَّد خطة سداده بعد").font(MadarTypography.caption()).foregroundStyle(theme.color("debt")) }
            if envelope.dailyFundingMinor > 0 { Text("من يومك " + (visible ? service.amount(envelope.dailyFundingMinor) : "•••") + " في اليوم").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
            else if envelope.perSalaryMinor > 0 { Text("من كل راتب " + (visible ? service.amount(envelope.perSalaryMinor) : "•••")).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
            if let due = envelope.due { MadarDateLabel(app.dateLabels(due, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
        }.padding(.vertical, 6).accessibilityElement(children: .combine).accessibilityIdentifier("money-goal-" + envelope.id.uuidString)
    }
}
