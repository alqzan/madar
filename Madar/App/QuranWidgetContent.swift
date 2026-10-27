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
                    Circle().stroke(theme.color("track"), lineWidth: 6)
                    Circle().trim(from: 0, to: max(0, min(1, value.fraction))).stroke(theme.color("review"), style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90)).scaleEffect(x: -1, y: 1)
                    Text(value.coverage).font(.system(size: extraLarge ? 38 : 20, weight: .medium, design: .serif)).multilineTextAlignment(.center).padding(extraLarge ? 24 : 10)
                }.aspectRatio(1, contentMode: .fit).frame(maxHeight: extraLarge ? 250 : 106)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("في صدرك، " + value.coverage)
    }
    /// X1 «رصّة ذكية»: the room's mark, what comes next, the amount in large serif, and today's steps as a column of beads.
    private func path(_ value: QuranWidgetSnapshot) -> some View {
        let label = value.nextTitle.hasPrefix("التالي: ") ? String(value.nextTitle.dropFirst(8)) : value.nextTitle
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: extraLarge ? 10 : 4) {
                HStack(spacing: 5) {
                    Image(systemName: "book").font(.system(size: extraLarge ? 20 : 12, weight: .semibold))
                    Text("القرآن").font(.custom("thmanyahsans-Bold", size: extraLarge ? 22 : 14, relativeTo: .caption))
                }.foregroundStyle(theme.color("hifzText")).widgetAccentable()
                Spacer(minLength: 0)
                Text(label).font(.custom("thmanyahsans-Regular", size: extraLarge ? 20 : 12, relativeTo: .caption2)).foregroundStyle(theme.secondaryInk).lineLimit(1)
                Text(value.nextDetail).font(.custom("thmanyahserifdisplay-Bold", size: extraLarge ? 44 : compact ? 24 : 28, relativeTo: .title))
                    .lineLimit(2).minimumScaleFactor(0.6).fixedSize(horizontal: false, vertical: true)
                if let line = value.dayLine {
                    // The beads alone read as empty; say where the day stands.
                    Text(line).font(.custom("thmanyahsans-Bold", size: extraLarge ? 18 : 11, relativeTo: .caption2)).foregroundStyle(theme.ink.opacity(0.8)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !type.isAccessibilitySize, value.total > 0 {
                VStack(spacing: extraLarge ? 8 : 5) {
                    ForEach(0..<min(value.total, 6), id: \.self) { index in
                        Capsule().fill(index < value.done ? theme.color("hifz") : theme.color("track"))
                            .frame(width: extraLarge ? 10 : 7, height: index == value.done ? (extraLarge ? 30 : 20) : (extraLarge ? 10 : 7))
                    }
                }.accessibilityHidden(true)
            }
        }
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
            Text(title).font(.system(size: extraLarge ? 22 : 12, weight: .semibold))
            Text(spoken(today) + " اليوم").font(.system(size: extraLarge ? 30 : 18, design: .serif)).fixedSize(horizontal: false, vertical: true)
            if !compact, !type.isAccessibilitySize { Text(spoken(total) + " هذا الأسبوع").font(.system(size: 11)).foregroundStyle(theme.secondaryInk) }
            if !type.isAccessibilitySize {
                HStack(spacing: 3) { ForEach(Array(fractions.enumerated()), id: \.offset) { _, fraction in RoundedRectangle(cornerRadius: 3).fill(fraction > 0 ? color.opacity(min(1, 0.4 + fraction * 0.4)) : theme.color("track")).frame(height: extraLarge ? 30 : 18) } }.accessibilityHidden(true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
