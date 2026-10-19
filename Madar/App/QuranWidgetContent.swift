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
    private func path(_ value: QuranWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("مسار اليوم").font(.system(size: extraLarge ? 22 : 12)).foregroundStyle(theme.secondaryInk)
            if !compact, !type.isAccessibilitySize, value.total > 0 {
                HStack(spacing: 4) { ForEach(0..<value.total, id: \.self) { index in Capsule().fill(index < value.done ? theme.color("hifz") : theme.color("track")).frame(height: 5) } }.accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            Text(value.nextTitle).font(.system(size: extraLarge ? 26 : 13, weight: .semibold)).foregroundStyle(theme.color("hifzText"))
            Text(value.nextDetail).font(.system(size: extraLarge ? 31 : compact ? 13 : 19, design: .serif)).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func week(_ value: QuranWidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: extraLarge ? 48 : 16) {
            weekColumn("الحفظ", today: value.hifzToday, total: value.hifzWeek, fractions: value.days.map(\.hifz), color: theme.color("hifz"))
            if !compact, !type.isAccessibilitySize { weekColumn("المراجعة", today: value.reviewToday, total: value.reviewWeek, fractions: value.days.map(\.review), color: theme.color("review")) }
        }
    }
    private func weekColumn(_ title: String, today: String, total: String, fractions: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: extraLarge ? 22 : 12, weight: .semibold))
            Text(today + " اليوم").font(.system(size: extraLarge ? 30 : 18, design: .serif)).fixedSize(horizontal: false, vertical: true)
            if !compact, !type.isAccessibilitySize { Text("هذا الأسبوع " + total).font(.system(size: 11)).foregroundStyle(theme.secondaryInk) }
            if !type.isAccessibilitySize {
                HStack(spacing: 3) { ForEach(Array(fractions.enumerated()), id: \.offset) { _, fraction in RoundedRectangle(cornerRadius: 3).fill(fraction > 0 ? color.opacity(min(1, 0.4 + fraction * 0.4)) : theme.color("track")).frame(height: extraLarge ? 30 : 18) } }.accessibilityHidden(true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
