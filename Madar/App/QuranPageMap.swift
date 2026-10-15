import SwiftUI
import MadarDesign

/// One native hit target supplies precise page selection without 604 tiny accessibility buttons.
struct QuranPageMap: View {
    let pages: [QuranUIIndexItem]
    var dates: [Int: String] = [:]
    var shades: [Int: Double] = [:]
    var selected: ClosedRange<Int>?
    let choose: (Int) -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var type
    private let columns = 20
    var body: some View {
        if type.isAccessibilitySize {
            LazyVStack(alignment: .leading) { ForEach(pages) { page in Button { choose(page.firstPage) } label: { Text(page.title + "، " + status(page)).font(quranFont(15)).frame(minHeight: 44) } } }
        } else {
            GeometryReader { proxy in
                let gap: CGFloat = 2, width = (proxy.size.width - CGFloat(columns - 1) * gap) / CGFloat(columns), height: CGFloat = 9
                Canvas { context, _ in
                    for (i, page) in pages.enumerated() {
                        let x = proxy.size.width - CGFloat(i % columns + 1) * width - CGFloat(i % columns) * gap
                        let rect = CGRect(x: x, y: CGFloat(i / columns) * (height + gap), width: width, height: height)
                        let path = Path(roundedRect: rect, cornerRadius: 2)
                        let opacity: Double = page.memorized ? (shades[page.firstPage] ?? 1) : page.fraction > 0 ? 0.45 : 0.13
                        context.fill(path, with: .color(theme.color("memorized").opacity(opacity)))
                        if page.fraction > 0 { context.stroke(path, with: .color(theme.color("hifzText")), lineWidth: 0.6) }
                        if page.reviewed { context.fill(Path(ellipseIn: CGRect(x: rect.midX - 1, y: rect.midY - 1, width: 2, height: 2)), with: .color(theme.surface)) }
                        if page.due {
                            var stripe = Path(); stripe.move(to: CGPoint(x: rect.minX + 2, y: rect.maxY - 1)); stripe.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.minY + 1))
                            context.stroke(stripe, with: .color(theme.color("due")), lineWidth: 1)
                        }
                        if selected?.contains(page.firstPage) == true || selected == nil && page.isToday { context.stroke(path, with: .color(theme.color("hifz")), lineWidth: 1.5) }
                    }
                }.onTapGesture { point in
                    let column = Int((proxy.size.width - point.x) / (width + gap)), row = Int(point.y / (height + gap))
                    let index = row * columns + column
                    if pages.indices.contains(index) { choose(pages[index].firstPage) }
                }
                .accessibilityElement().accessibilityLabel("خريطة المصحف، الأقدم يمينًا، اختر وجهًا من محدد الوجه")
            }.frame(height: CGFloat((pages.count + columns - 1) / columns) * 11 - 2)
        }
    }
    private func status(_ p: QuranUIIndexItem) -> String { p.memorized ? "في صدرك" : p.fraction > 0 ? "حفظ جزئي" : "لم تحفظه" }
}
