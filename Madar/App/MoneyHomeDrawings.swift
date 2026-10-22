import SwiftUI
import MadarCore
import MadarDesign
import MadarMoney
import MadarCommands

struct MoneyScrollChart: View {
    let cycle: MoneyCycleReading
    let app: AppSession
    let visible: Bool
    var obligations: [MoneyHomeObligation] = []
    @Environment(\.roomTheme) private var theme
    private var service: AppMoneyService { .init(app: app) }
    var body: some View {
        GeometryReader { proxy in
            let rod: CGFloat = 19, paperWidth = proxy.size.width - rod * 2
            ZStack {
                Rectangle().fill(theme.surface).padding(.horizontal, rod / 2).padding(.vertical, 8)
                    .shadow(color: theme.color("rod2").opacity(0.18), radius: 4, y: 1)
                if visible {
                    Canvas { context, size in
                        // The foot keeps three bands apart: due diamonds on the baseline, the day's spend hanging under it, then the dates.
                        let chart = CGRect(x: rod + 8, y: 24, width: paperWidth - 16, height: size.height - 90)
                        let last = max(1, cycle.curve.count - 1)
                        let maxAmount = max(1, cycle.curve.map { max($0.accruedMinor, $0.spentMinor) }.max() ?? 1)
                        func x(_ day: Int) -> CGFloat { chart.maxX - CGFloat(day - 1) / CGFloat(last) * chart.width }
                        func y(_ amount: Int) -> CGFloat { chart.maxY - CGFloat(amount) / CGFloat(maxAmount) * chart.height }
                        let todayX = x(min(cycle.elapsedDays, cycle.curve.count))
                        context.fill(Path(CGRect(x: todayX - 5, y: 10, width: 10, height: size.height - 20)), with: .color(theme.color("reserve").opacity(0.10)))
                        context.draw(Text("اليوم").font(.custom("thmanyahseriftext-Regular", size: 11)).foregroundStyle(theme.secondaryInk), at: CGPoint(x: todayX, y: 18))
                        var baseline = Path(); baseline.move(to: .init(x: chart.minX, y: chart.maxY)); baseline.addLine(to: .init(x: chart.maxX, y: chart.maxY))
                        context.stroke(baseline, with: .color(theme.line), style: .init(lineWidth: 1, dash: [2, 4]))
                        for obligation in obligations {
                            let index = MadarCalendarDays.distance(from: cycle.startDay, to: obligation.due) + 1
                            if index >= 1 && index <= cycle.curve.count {
                                let rect = CGRect(x: x(index) - 5, y: chart.maxY - 6, width: 10, height: 12)
                                context.fill(DiamondMark().path(in: rect), with: .color(theme.surface))
                                context.stroke(DiamondMark().path(in: rect), with: .color(theme.color("reserveText")), lineWidth: 0.8)
                            }
                        }
                        var guide = Path(), actual = Path()
                        for point in cycle.curve {
                            let end = CGPoint(x: x(point.day), y: y(point.accruedMinor))
                            if point.day == 1 { guide.move(to: end) } else { guide.addLine(to: end) }
                            if point.day <= cycle.elapsedDays {
                                let p = CGPoint(x: x(point.day), y: y(point.spentMinor))
                                if point.day == 1 { actual.move(to: p) } else { actual.addLine(to: p) }
                                let width = max(2, min(6, chart.width / CGFloat(last) * 0.6))
                                let height = max(1, min(12, CGFloat(max(0, cycle.spent[point.day] ?? 0)) / CGFloat(maxAmount) * chart.height))
                                context.fill(Path(CGRect(x: x(point.day) - width / 2, y: chart.maxY + 8, width: width, height: height)), with: .color(theme.secondaryInk))
                            }
                        }
                        context.stroke(guide, with: .color(theme.color("reserveText")), style: .init(lineWidth: 1.1, dash: [3, 4]))
                        context.stroke(actual, with: .color(theme.ink), style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        if let point = cycle.curve.last(where: { $0.day <= cycle.elapsedDays }) {
                            let center = CGPoint(x: x(point.day), y: y(point.spentMinor))
                            context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(theme.color("reserve")))
                            context.fill(Path(ellipseIn: CGRect(x: center.x - 1.7, y: center.y - 1.7, width: 3.4, height: 3.4)), with: .color(theme.ink))
                        }
                    }.accessibilityHidden(true)
                    VStack {
                        HStack(alignment: .top) {
                            Color.clear.frame(width: 1, height: 1)
                            Spacer()
                            Text(figure: service.amount(cycle.curve.last?.accruedMinor ?? 0)).font(.custom("thmanyahsans-Regular", size: 11)).foregroundStyle(theme.secondaryInk)
                        }.padding(.horizontal, rod + 8).padding(.top, 13)
                        Spacer()
                        HStack(alignment: .bottom) {
                            MadarDateLabel(app.dateLabels(cycle.startDay, compact: true), primaryFont: .custom("thmanyahsans-Regular", size: 11), secondaryFont: .custom("thmanyahsans-Regular", size: 11))
                            Spacer()
                            MadarDateLabel(app.dateLabels(cycle.expectedEndDay, compact: true), primaryFont: .custom("thmanyahsans-Regular", size: 11), secondaryFont: .custom("thmanyahsans-Regular", size: 11))
                        }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).padding(.horizontal, rod + 8).padding(.bottom, 12)
                    }
                } else {
                    Text("منحنى دورتك").font(MadarTypography.cardTitle()).foregroundStyle(theme.secondaryInk)
                }
                HStack {
                    rodView.frame(width: rod)
                    Spacer(minLength: 0)
                    rodView.frame(width: rod)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("money-scroll-chart")
    }
    private var accessibilitySummary: String {
        guard visible else { return "منحنى الدورة مخفي" }
        let start = app.dateLabels(cycle.startDay, compact: true).combined
        let end = app.dateLabels(cycle.expectedEndDay, compact: true).combined
        return "منحنى الدورة من \(start) إلى \(end)؛ الخط المنقّط استحقاق اليومية، والمتصل ما صُرف."
    }
    private var rodView: some View {
        Capsule().fill(LinearGradient(colors: [theme.color("rod2"), theme.color("rod"), theme.color("rod2")], startPoint: .leading, endPoint: .trailing))
            .overlay(alignment: .leading) { Capsule().fill(theme.color("reserve").opacity(0.14)).frame(width: 2).padding(.vertical, 10) }
    }
}

struct MoneyReserveSquares: View {
    let days: Int
    @Environment(\.roomTheme) private var theme
    var body: some View {
        Canvas { context, size in
            let columns = 30, shown = min(540, max(0, days)), rows = max(8, Int(ceil(Double(shown) / 30)))
            let gap: CGFloat = 1, cellW = (size.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
            let cellH = min(cellW, (size.height - CGFloat(rows - 1) * gap) / CGFloat(rows))
            for index in 0..<shown {
                let x = size.width - cellW - CGFloat(index % columns) * (cellW + gap), y = CGFloat(index / columns) * (cellH + gap)
                let path = Path(CGRect(x: x, y: y, width: cellW, height: cellH))
                context.fill(path, with: .color(theme.color("reserve")))
                context.stroke(path, with: .color(theme.color("reserveText")), lineWidth: 1)
            }
            if shown == 0 {
                let p = Path(CGRect(x: size.width - 12, y: size.height / 2 - 6, width: 12, height: 12))
                context.stroke(p, with: .color(theme.color("reserveText")), style: .init(lineWidth: 1, dash: [2, 2]))
            }
        }.accessibilityHidden(true)
    }
}
struct MoneyWaterfall: View {
    let values: [Int]
    @Environment(\.roomTheme) private var theme
    var body: some View {
        Canvas { context, size in
            var baseline = Path(); baseline.move(to: .init(x: 0, y: size.height * 0.8)); baseline.addLine(to: .init(x: size.width, y: size.height * 0.8))
            context.stroke(baseline, with: .color(theme.color("reserveText")), lineWidth: 0.8)
            let maxValue = max(1, values.map { abs($0) }.max() ?? 1), count = max(1, values.count)
            let step = size.width / CGFloat(count + 1), width = min(15, step * 0.7)
            for (index, value) in values.enumerated() {
                let height = max(2, CGFloat(abs(value)) / CGFloat(maxValue) * size.height * 0.65)
                let x = size.width - CGFloat(index + 1) * step
                context.fill(Path(CGRect(x: x, y: value >= 0 ? size.height * 0.8 - height : size.height * 0.8, width: width, height: value >= 0 ? height : min(height, size.height * 0.18))), with: .color(theme.color("surplus")))
            }
        }.accessibilityHidden(true)
    }
}

struct MoneyEnvelopeLine: View {
    let envelope: MoneyHomeEnvelope
    let app: AppSession
    let visible: Bool
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var color: Color { theme.color(envelope.balanceMinor < 0 ? "debt" : "envelopes") }
    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(envelope.name).font(MadarTypography.body()).lineLimit(2)
                if envelope.balanceMinor < 0 { Text("دين").font(MadarTypography.fine()).foregroundStyle(theme.color("debt")) }
            }.frame(width: 96, alignment: .leading)
            if !dynamicType.isAccessibilitySize && visible {
                GeometryReader { proxy in
                    let target = max(1, envelope.targetMinor ?? max(1, abs(envelope.balanceMinor)))
                    let progress = min(1, Double(abs(envelope.balanceMinor)) / Double(target))
                    ZStack(alignment: .trailing) {
                        Rectangle().stroke(color, style: .init(lineWidth: 0.8, dash: [3, 2])).frame(height: 9)
                        Rectangle().fill(color).frame(width: proxy.size.width * progress, height: 5)
                        Capsule().fill(LinearGradient(colors: [theme.color("rod2"), theme.color("rod"), theme.color("rod2")], startPoint: .leading, endPoint: .trailing)).frame(width: 6, height: 18).offset(x: -proxy.size.width * progress)
                        Rectangle().fill(theme.color("reserveText")).frame(width: 1, height: 17)
                    }.frame(height: proxy.size.height)
                }.frame(height: 23).accessibilityHidden(true)
            }
            Text(visible ? AppMoneyService(app: app).amount(envelope.balanceMinor) : "•••").font(MadarTypography.section())
                .foregroundStyle(envelope.balanceMinor < 0 ? theme.color("debt") : theme.ink).frame(minWidth: 46, alignment: .trailing)
        }.accessibilityElement(children: .combine)
        .accessibilityLabel(envelope.name + (envelope.balanceMinor < 0 ? "، دين، " : "، ") + (visible ? AppMoneyService(app: app).amount(envelope.balanceMinor) : "المبلغ مخفي"))
    }
}
