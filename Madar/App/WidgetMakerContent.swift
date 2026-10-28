import SwiftUI
import WidgetKit
import MadarCore
import MadarDesign
import MadarSnapshots

/// Shared app preview and real WidgetKit content, rendered only from app-produced JSON values.
struct WidgetMakerContent: View {
    let config: WidgetCatalogSnapshot.Config?
    var family: WidgetFamily = .systemMedium
    var date = Date()
    var locked = false
    var stale = false
    var permitsActions = false
    var usesSystemRendering = false
    var timeZoneID = "Asia/Riyadh"
    var emptyPrompt: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var style: WidgetMakerStyle { config.flatMap { try? JSONDecoder().decode(WidgetMakerStyle.self, from: $0.styleJSON) } ?? .init() }
    private var accessory: Bool { [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(family) }
    private var capacity: Int {
        if #available(iOS 27, *), family == .systemExtraLargePortrait { return WidgetMakerStyle.capacity(for: "extraLargePortrait") }
        switch family { case .systemSmall: return WidgetMakerStyle.capacity(for: "small"); case .systemMedium: return WidgetMakerStyle.capacity(for: "medium"); case .systemLarge: return WidgetMakerStyle.capacity(for: "large"); case .accessoryRectangular: return WidgetMakerStyle.capacity(for: "accessoryRectangular"); default: return 1 }
    }
    private var theme: RoomTheme { Self.theme(style, dark: colorScheme == .dark) }
    private var ink: Color { accessory ? .primary : theme.ink }
    private var accent: Color { Self.accent(style, dark: colorScheme == .dark) }
    private var systemMonochrome: Bool { usesSystemRendering && renderingMode != .fullColor }
    private var rows: [WidgetCatalogSnapshot.Row] {
        config?.visibleRows(at: date, capacity: capacity, smart: style.smartBundle) ?? []
    }
    var body: some View {
        Group {
            if locked { Text("افتح مدار").font(.headline) }
            else if stale { Text("افتح مدار لتحديث الودجة").font(.caption) }
            else if rows.isEmpty {
                if style.hideWhenEmpty { Color.clear }
                else { VStack(spacing: 8) { Image(systemName: "sparkles"); Text(emptyPrompt ?? (config == nil ? "اصنع ودجتك في مدار" : "لا شيء ينتظر هنا الآن")).font(.caption).multilineTextAlignment(.center) } }
            } else if family == .accessoryInline {
                if let row = rows.first { Text(row.title + " " + value(row)).font(.caption).lineLimit(1) }
            } else if accessory {
                VStack(spacing: 4) { ForEach(rows) { row in Link(destination: URL(string: row.route) ?? URL(string: "madar://bahw")!) { HStack(spacing: 4) { if style.showArt { MadarGlyph(row.glyph, size: 15) }; Text(row.title + " " + value(row)).font(.system(size: 12)).lineLimit(2) } } } }
            } else {
                VStack(alignment: .leading, spacing: spacing) {
                    HStack { Text(config?.name ?? "مدار").font(textFont(12, bold: true)).lineLimit(1); Spacer(); Image(systemName: "sparkle").foregroundStyle(accent) }
                    if family == .systemMedium {
                        HStack(alignment: .top, spacing: spacing) { ForEach(rows) { row in tile(row) } }
                    } else { VStack(spacing: spacing) { ForEach(rows) { row in tile(row) } } }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .foregroundStyle(ink).environment(\.layoutDirection, .rightToLeft)
        .privacySensitive(locked)
    }
    private var spacing: CGFloat { style.density == "compact" ? 4 : style.density == "airy" ? 14 : 8 }
    private func textFont(_ size: CGFloat, bold: Bool = false) -> Font { .system(size: size, weight: bold ? .semibold : .regular, design: style.font == "naskh" ? .serif : .default) }
    private func value(_ row: WidgetCatalogSnapshot.Row) -> String {
        if row.money && accessory && style.hideMoney { return "•••" }
        if row.id == "hijriClock" {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .gmt
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return numerals(String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0))
        }
        if let target = row.targetDate {
            let minutes = max(0, Int(target.timeIntervalSince(date) / 60))
            return numerals(String(format: "%d:%02d", minutes / 60, minutes % 60))
        }
        return numerals(row.value)
    }
    private func numerals(_ text: String) -> String {
        let western = Array("0123456789"), hindi = Array("٠١٢٣٤٥٦٧٨٩")
        return String(text.map { character in
            if style.numerals == "western", let i = hindi.firstIndex(of: character) { return western[i] }
            if style.numerals != "western", let i = western.firstIndex(of: character) { return hindi[i] }
            return character
        })
    }
    private func tile(_ row: WidgetCatalogSnapshot.Row) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Link(destination: URL(string: row.route) ?? URL(string: "madar://bahw")!) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        if style.showArt { MadarGlyph(row.glyph, size: 16).foregroundStyle(accent).widgetAccentable() }
                        Text(row.title).font(textFont(11, bold: true)).lineLimit(2)
                    }
                    Text(value(row)).font(textFont(family == .systemMedium ? 18 : 17, bold: true)).lineLimit(2).minimumScaleFactor(0.75)
                    if !row.detail.isEmpty { Text(numerals(row.detail)).font(textFont(11)).lineLimit(2) }
                    if !row.secondDate.isEmpty { Text(numerals(row.secondDate)).font(textFont(11)).lineLimit(1) }
                    if style.showArt, let share = row.share { ProgressView(value: max(0, min(1, share))).tint(accent).widgetAccentable().accessibilityHidden(true) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
            }.buttonStyle(.plain)
            if permitsActions && style.interactive, let id = row.habitID {
                Button(intent: WidgetCompleteHabitIntent(habitID: id)) { Label("سجّل", systemImage: "checkmark").font(textFont(11, bold: true)) }.buttonStyle(.plain)
            }
        }
        .padding(style.density == "compact" ? 5 : 8).frame(maxWidth: .infinity, maxHeight: family == .systemMedium ? .infinity : nil, alignment: .topLeading)
        .background {
            // WidgetKit supplies the glass/tint background in accented modes. Opaque inner
            // rectangles otherwise turn white and hide that material.
            if !systemMonochrome {
                RoundedRectangle(cornerRadius: style.family == "glass" ? 20 : 12)
                    .fill(style.family == "glass" ? theme.background.opacity(0.24) : theme.background)
            }
        }
        .overlay { if style.family == "glass" && !systemMonochrome { RoundedRectangle(cornerRadius: 20).stroke(theme.line, lineWidth: 1) } }
        .privacySensitive(row.money)
    }
    static func theme(_ style: WidgetMakerStyle, dark: Bool) -> RoomTheme {
        .init(room: "bahw", dark: style.family == "ink" || dark)
    }
    static func accent(_ style: WidgetMakerStyle, dark: Bool) -> Color {
        let theme = theme(style, dark: dark)
        let role = switch style.color { case "green": "green"; case "blue": "lapis"; case "clay": "clay"; case "plum": "plum"; case "sepia": "sepia"; case "ink": "ink"; default: "accentFill" }
        return theme.color(role)
    }
    static func background(_ style: WidgetMakerStyle, dark: Bool) -> Color { theme(style, dark: dark).surface }
}

/// Native material for the app's preview, saved cards and lobby. WidgetKit owns its system background.
struct WidgetMakerAppSurface: ViewModifier {
    let style: WidgetMakerStyle
    let dark: Bool
    var cornerRadius: CGFloat = 22
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if style.family == "glass" && style.surface != "lock" && !reduceTransparency {
            if #available(iOS 26, *) {
                content.glassEffect(.regular.interactive(interactive), in: .rect(cornerRadius: cornerRadius))
            } else {
                content.background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content.background(WidgetMakerContent.background(style, dark: dark), in: .rect(cornerRadius: cornerRadius))
        }
    }
}

struct WidgetMakerGlassGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if #available(iOS 26, *) { GlassEffectContainer(spacing: 6) { content } }
        else { content }
    }
}
