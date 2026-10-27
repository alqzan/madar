import SwiftUI
import MadarDesign
import MadarSnapshots

enum QuranWidgetTemplate: String, CaseIterable, Identifiable, Sendable { case coverage, path, week; var id: String { rawValue } }

/// Shared by the actual WidgetKit extension and the in-app template preview. Data is JSON only.
struct QuranWidgetContent: View {
    let snapshot: QuranWidgetSnapshot?
    let template: QuranWidgetTemplate
    var compact = false
    var extraLarge = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var type
    private var theme: RoomTheme { RoomTheme(room: "quran", dark: scheme == .dark) }
    var body: some View {
        Group {
            if let snapshot {
                switch template {
                case .coverage: coverage(snapshot)
                case .path: path(snapshot)
                case .week: week(snapshot)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) { Text("القرآن").font(.headline); Text("افتح مدار لتحديث وردك").font(.caption) }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .foregroundStyle(theme.ink).environment(\.layoutDirection, .rightToLeft)
    }
    private func coverage(_ value: QuranWidgetSnapshot) -> some View {
        VStack(spacing: extraLarge ? 24 : 10) {
            Text("في صدرك").font(.system(size: extraLarge ? 22 : 12)).foregroundStyle(theme.secondaryInk).frame(maxWidth: .infinity, alignment: .leading)
            if type.isAccessibilitySize || compact {
                Text(value.coverage).font(.system(.title3, design: .serif)).fixedSize(horizontal: false, vertical: true)
            } else {
                ZStack {
                    Circle().stroke(theme.color("hifzTint"), lineWidth: extraLarge ? 12 : 8)
                    Circle().trim(from: 0, to: max(0, min(1, value.fraction))).stroke(theme.color("review"), style: StrokeStyle(lineWidth: extraLarge ? 12 : 8, lineCap: .round)).rotationEffect(.degrees(-90)).scaleEffect(x: -1, y: 1)
                    // The count large, its unit beneath: «١٤» over «جزءًا و٣ أوجه».
                    let parts = coverageParts(value.coverage)
                    VStack(spacing: 0) {
                        Text(parts.number).font(.custom("thmanyahserifdisplay-Bold", size: parts.rest.isEmpty ? (extraLarge ? 34 : 18) : (extraLarge ? 64 : 34), relativeTo: .title))
                            .lineLimit(parts.rest.isEmpty ? 2 : 1).minimumScaleFactor(0.6)
                        if !parts.rest.isEmpty { Text(parts.rest).font(.custom("thmanyahsans-Regular", size: extraLarge ? 18 : 11, relativeTo: .caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.7) }
                    }.multilineTextAlignment(.center).padding(extraLarge ? 28 : 14)
                }.aspectRatio(1, contentMode: .fit).frame(maxHeight: extraLarge ? 250 : 110)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("في صدرك، " + value.coverage)
    }
    /// The canonical «مسار اليوم»: the day's steps as a row of bars, then what comes next in gold and its amount in large serif.
    private func path(_ value: QuranWidgetSnapshot) -> some View {
        let label = value.nextTitle.hasPrefix("التالي: ") ? "التالي · " + value.nextTitle.dropFirst(8) : value.nextTitle
        return VStack(alignment: .leading, spacing: extraLarge ? 10 : 4) {
            Text("مسار اليوم").font(.custom("thmanyahsans-Regular", size: extraLarge ? 20 : 12, relativeTo: .caption2)).foregroundStyle(theme.secondaryInk)
            if !type.isAccessibilitySize, value.total > 0 {
                HStack(spacing: extraLarge ? 8 : 5) {
                    ForEach(0..<min(value.total, 6), id: \.self) { index in
                        Capsule().fill(index < value.done ? theme.color("hifz") : theme.color("hifzTint")).frame(height: extraLarge ? 10 : 7)
                    }
                }.padding(.top, 4).accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            Text(label).font(.custom("thmanyahsans-Bold", size: extraLarge ? 20 : 12, relativeTo: .caption2)).foregroundStyle(theme.color("hifzText")).lineLimit(1).widgetAccentable()
            Text(value.nextDetail).font(.custom("thmanyahserifdisplay-Bold", size: extraLarge ? 44 : compact ? 22 : 26, relativeTo: .title))
                .lineLimit(2).minimumScaleFactor(0.6).fixedSize(horizontal: false, vertical: true)
            if let line = value.dayLine {
                Text(line).font(.custom("thmanyahsans-Regular", size: extraLarge ? 18 : 11, relativeTo: .caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    /// «١٤ جزءًا و٣ أوجه» → («١٤», «جزءًا و٣ أوجه»); a count written in words stays whole.
    private func coverageParts(_ text: String) -> (number: String, rest: String) {
        guard let space = text.firstIndex(of: " "), text[..<space].allSatisfy(\.isNumber) else { return (text, "") }
        return (String(text[..<space]), String(text[text.index(after: space)...]))
    }
    private func week(_ value: QuranWidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: extraLarge ? 48 : 16) {
            weekColumn("الحفظ", today: value.hifzToday, total: value.hifzWeek, fractions: value.days.map(\.hifz), color: theme.color("hifz"))
            if !compact, !type.isAccessibilitySize { weekColumn("المراجعة", today: value.reviewToday, total: value.reviewWeek, fractions: value.days.map(\.review), color: theme.color("review")) }
        }
    }
    /// A count of zero reads «لا أوجه», never «٠ أوجه».
    private func spoken(_ count: String) -> String {
        let digits = count.filter(\.isNumber)
        return !digits.isEmpty && digits.allSatisfy { $0.wholeNumberValue == 0 } ? "لا أوجه" : count
    }
    private func weekColumn(_ title: String, today: String, total: String, fractions: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) { Circle().fill(color).frame(width: extraLarge ? 10 : 7, height: extraLarge ? 10 : 7); Text(title).font(.custom("thmanyahsans-Bold", size: extraLarge ? 22 : 12, relativeTo: .caption)) }
            Text(spoken(today) + " اليوم").font(.custom("thmanyahserifdisplay-Bold", size: extraLarge ? 32 : 20, relativeTo: .title3)).lineLimit(1).minimumScaleFactor(0.7)
            if !compact, !type.isAccessibilitySize { Text(spoken(total) + " هذا الأسبوع").font(.system(size: 11)).foregroundStyle(theme.secondaryInk) }
            if !type.isAccessibilitySize {
                HStack(spacing: 3) { ForEach(Array(fractions.enumerated()), id: \.offset) { _, fraction in RoundedRectangle(cornerRadius: 3).fill(fraction > 0 ? color.opacity(min(1, 0.4 + fraction * 0.4)) : theme.color("track")).frame(height: extraLarge ? 30 : 18) } }.accessibilityHidden(true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
