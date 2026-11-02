import SwiftUI
import MadarDesign

/// One native hit target supplies precise page selection without 604 tiny accessibility buttons.
struct QuranPageMap: View {
    let pages: [QuranUIIndexItem]
    var dates: [Int: String] = [:]
    var shades: [Int: Double] = [:]
    var selected: ClosedRange<Int>?
    var rows: [QuranUIJourneyMapRow]?
    let choose: (Int) -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var type
    private let columns = 20

    var body: some View {
        if type.isAccessibilitySize {
            if let rows {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(rows) { row in
                        DisclosureGroup {
                            ForEach(row.pages) { page in
                                Button { choose(page.firstPage) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(page.title + "، " + status(page)).font(quranFont(14))
                                        if let date = dates[page.firstPage] {
                                            Text("حُفظ في " + date).font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                            }
                        } label: {
                            Text(row.summary).font(quranFont(15)).frame(minHeight: 44, alignment: .leading)
                        }
                    }
                }
            } else {
                LazyVStack(alignment: .leading) {
                    ForEach(pages) { page in
                        Button { choose(page.firstPage) } label: {
                            Text(page.title + "، " + status(page) + (dates[page.firstPage].map { "، حُفظ في " + $0 } ?? ""))
                                .font(quranFont(15)).frame(minHeight: 44)
                        }
                    }
                }
            }
        } else {
            let rowGroups = makeRows()
            let rowCount = rowGroups.count
            let labelGutter: CGFloat = rows == nil ? 0 : 24
            let rowGap: CGFloat = rows == nil ? 2 : 3
            GeometryReader { proxy in
                let gap: CGFloat = 2
                let gridWidth = proxy.size.width - labelGutter
                let height: CGFloat = 9
                Canvas { context, size in
                    for (rowIndex, row) in rowGroups.enumerated() {
                        let cellCount = rows == nil ? columns : max(1, row.count)
                        let width = (gridWidth - CGFloat(cellCount - 1) * gap) / CGFloat(cellCount)
                        for (column, page) in row.enumerated() {
                            let x = gridWidth - CGFloat(column + 1) * width - CGFloat(column) * gap
                            let rect = CGRect(x: x, y: CGFloat(rowIndex) * (height + rowGap), width: width, height: height)
                            let path = Path(roundedRect: rect, cornerRadius: 2)
                            let opacity: Double = page.memorized ? (shades[page.firstPage] ?? 1) : page.fraction > 0 ? 0.45 : 0.13
                            context.fill(path, with: .color(theme.color("memorized").opacity(opacity)))
                            if page.fraction > 0 { context.stroke(path, with: .color(theme.color("hifzText")), lineWidth: 0.6) }
                            if page.reviewed { context.fill(Path(ellipseIn: CGRect(x: rect.midX - 1, y: rect.midY - 1, width: 2, height: 2)), with: .color(theme.surface)) }
                            if page.due {
                                var stripe = Path(); stripe.move(to: CGPoint(x: rect.minX + 2, y: rect.maxY - 1)); stripe.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.minY + 1))
                                context.stroke(stripe, with: .color(theme.color("due")), lineWidth: 1)
                            }
                            if selected?.contains(page.firstPage) == true || selected == nil && page.isToday {
                                context.stroke(path, with: .color(theme.color("hifz")), lineWidth: 1.5)
                            }
                        }
                        if let rows, rows.indices.contains(rowIndex) {
                            context.draw(Text(rows[rowIndex].label).font(quranFont(11)).foregroundStyle(theme.secondaryInk),
                                at: CGPoint(x: gridWidth + labelGutter / 2, y: CGFloat(rowIndex) * (height + rowGap) + height / 2), anchor: .center)
                        }
                    }
                }
                .contentShape(.rect)
                .onTapGesture { point in
                    let rowIndex = Int(point.y / (height + rowGap))
                    guard point.x >= 0, point.x <= gridWidth else { return }
                    guard rowGroups.indices.contains(rowIndex) else { return }
                    let cellCount = rows == nil ? columns : max(1, rowGroups[rowIndex].count)
                    let width = (gridWidth - CGFloat(cellCount - 1) * gap) / CGFloat(cellCount)
                    let column = Int((gridWidth - point.x) / (width + gap))
                    guard rowGroups.indices.contains(rowIndex), rowGroups[rowIndex].indices.contains(column) else { return }
                    let cellX = gridWidth - CGFloat(column + 1) * width - CGFloat(column) * gap
                    guard point.x >= cellX, point.x <= cellX + width else { return }
                    choose(rowGroups[rowIndex][column].firstPage)
                }
                .accessibilityElement()
                .accessibilityIdentifier("quran-journey-map")
                .accessibilityLabel(rows == nil ? "خريطة المصحف، الأقدم يمينًا، اختر وجهًا لعرض تاريخه" : "خريطة المصحف بحسب الأجزاء، الأقدم يمينًا، اختر وجهًا لعرض تاريخه")
            }
            .frame(height: max(0, CGFloat(rowCount) * (9 + rowGap) - rowGap))
        }
    }

    private func makeRows() -> [[QuranUIIndexItem]] {
        if let rows { return rows.map(\.pages) }
        return stride(from: 0, to: pages.count, by: columns).map { start in
            Array(pages[start..<min(start + columns, pages.count)])
        }
    }

    private func status(_ page: QuranUIIndexItem) -> String {
        var labels = [page.memorized ? "في صدرك" : page.fraction > 0 ? "حفظ جزئي" : "لم تحفظه"]
        if page.reviewed { labels.append("مراجَع") }
        if page.due { labels.append("مستحق للمراجعة") }
        if page.isToday { labels.append("ورد اليوم") }
        return labels.joined(separator: "، ")
    }
}
