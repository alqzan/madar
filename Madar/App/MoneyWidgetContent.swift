import SwiftUI
import WidgetKit
import MadarDesign
import MadarSnapshots

struct MoneyWidgetContent: View {
    let snapshot: RoomWidgetSnapshot?
    var family: WidgetFamily = .systemSmall
    var template = "now"
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var type
    @Environment(\.widgetRenderingMode) private var rendering
    private var extraLargePortrait: Bool { family == .systemExtraLargePortrait }
    private var largeHome: Bool { family == .systemLarge || extraLargePortrait }
    private var accessory: Bool { [.accessoryInline, .accessoryCircular, .accessoryRectangular].contains(family) }
    private func color(_ key: String) -> Color { if rendering != .fullColor { return .primary }; return MadarToken.colors["widgetIdentity.room.mal.\(scheme == .dark ? "dark" : "light").\(key)"] ?? .primary }
    private var hidden: Bool { snapshot?.rows.first?.value == "•••" }
    private var rows: [RoomWidgetSnapshot.Row] {
        let all = snapshot?.rows ?? []
        if largeHome && template != "basis" {
            let expanded = all.filter { ["now", "basis", "reserved"].contains($0.id) } + all.filter { $0.id.hasPrefix("env-") } + all.filter { $0.id.hasPrefix("limit-") } + all.filter { $0.id == "reserve" }
            return extraLargePortrait ? Array(expanded.prefix(7)) : expanded
        }
        // The small card names «يومك» inside its spend line, so the row is not repeated above it.
        let ids = template == "basis" ? ["basis", "reserved", "salary"] : todayLine != nil ? ["now"] : ["now", "daily"]
        let selected = ids.compactMap { id in all.first { $0.id == id } }
        return Array(selected.prefix(type.isAccessibilitySize ? 2 : 3))
    }
    private var todayLine: RoomWidgetSnapshot.Row? {
        guard !hidden, family == .systemSmall, template != "basis", let daily = snapshot?.rows.first(where: { $0.id == "daily" }), !daily.detail.isEmpty else { return nil }
        return daily
    }
    var body: some View {
        Group {
            if accessory {
                // Lock-screen content never reads the amount-bearing rows, even when outside hiding is off.
                if family == .accessoryInline { Text("المال، افتح مدار").font(.caption) }
                else { VStack(spacing: 4) { Image(systemName: "banknote"); Text("المال").font(.caption); if family == .accessoryRectangular { Text("افتح مدار").font(.caption2) } }.frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else {
                VStack(alignment: .leading, spacing: largeHome ? 4 : 6) {
                    Label("المال", systemImage: "banknote").font(MadarTypography.fine()).foregroundStyle(color("accent")).widgetAccentable()
                    if family == .systemMedium, template == "basis", let now = snapshot?.rows.first(where: { $0.id == "now" }) { HStack { Text(now.title); Spacer(); Text(now.value) }.font(MadarTypography.fine()) }
                    if snapshot?.locked == true { Spacer(minLength: 0); Label("افتح مدار", systemImage: "lock").font(MadarTypography.section()); Spacer(minLength: 0) }
                    else if rows.isEmpty { Spacer(minLength: 0); Text(snapshot?.emptyTitle ?? "افتح المال للتحديث").font(MadarTypography.section()); Spacer(minLength: 0) }
                    else {
                        ForEach(rows) { row in
                            if extraLargePortrait && row.id == rows.first?.id {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.title).font(MadarTypography.caption()).lineLimit(1)
                                    displayFigure(row.value, "thmanyahserifdisplay-Bold", size: 38, relativeTo: .largeTitle).lineLimit(1).minimumScaleFactor(0.7)
                                }
                            } else {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(row.title).font(MadarTypography.caption()).lineLimit(1)
                                    Spacer(minLength: 2)
                                    displayFigure(row.value, "thmanyahserifdisplay-Bold", size: family == .systemSmall && row.id == "now" ? 30 : largeHome ? 18 : 19, relativeTo: .title2).lineLimit(1).minimumScaleFactor(0.85)
                                }
                            }
                        }
                        // A row of dots says nothing by itself: name why the amounts are hidden and where they are.
                        if hidden { Text("المبالغ مخفية، افتح المال لتراها").font(MadarTypography.fine()).foregroundStyle(color("ink2")).fixedSize(horizontal: false, vertical: true) }
                        // A bare balance curve with no axis said nothing on the small card; today's spend against «يومك» does.
                        if let daily = todayLine {
                            Spacer(minLength: 4)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("صرفت \(Text(figure: daily.detail).foregroundStyle(color("ink")))\(daily.share > 1 ? " فوق يومك " : " من يومك ")\(Text(figure: daily.value).foregroundStyle(color("ink")))")
                                    .font(MadarTypography.fine()).foregroundStyle(color("ink2")).lineLimit(2).minimumScaleFactor(0.8)
                                GeometryReader { proxy in
                                    HStack(spacing: 0) {
                                        Capsule().fill(daily.share > 1 ? color("ink") : color("accent"))
                                            .frame(width: max(daily.share > 0 ? 5 : 0, proxy.size.width * min(1, daily.share)))
                                        Spacer(minLength: 0)
                                    }.background(color("accent").opacity(0.18), in: .capsule)
                                }.frame(height: 5).accessibilityHidden(true)
                            }.accessibilityElement(children: .combine)
                        }
                        if !hidden && !type.isAccessibilitySize && template != "basis" && family != .systemSmall, let points = snapshot?.periods, points.count > 1 {
                            GeometryReader { proxy in Path { path in
                                for (index, point) in points.enumerated() { let p = CGPoint(x: proxy.size.width * Double(index) / Double(max(1, points.count - 1)), y: proxy.size.height * (1 - min(1, max(-1, point.share))) / 2); if index == 0 { path.move(to: p) } else { path.addLine(to: p) } }
                            }.stroke(color("accent"), lineWidth: 1.5) }.frame(height: family == .systemSmall ? 20 : extraLargePortrait ? 44 : 32).accessibilityHidden(true)
                        }
                        if todayLine == nil { Spacer(minLength: 0) }
                    }
                    if family != .systemSmall || rows.isEmpty { VStack(alignment: .leading, spacing: 2) { Text(snapshot?.datePrimary ?? ""); Text(snapshot?.dateSecondary ?? "") }.font(MadarTypography.fine()).foregroundStyle(color("ink2")) }
                }.foregroundStyle(color("ink")).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).privacySensitive()
            }
        }.environment(\.layoutDirection, .rightToLeft)
    }
}

/// The Thmanyah fonts have no «٬» or «٫», so the system fallback draws them wide («١ , ٣٦٠»). The font licence
/// forbids editing the files, so the marks are drawn with Thmanyah's own glyphs: «٬» as a small raised «،» and «٫»
/// as its «,» — the shapes these marks take in Arabic type. VoiceOver still reads the real figure. Where Thmanyah
/// is not bundled (the widget extension draws in the system font, which has both marks) the string is left alone.
let thmanyahBundled = UIFont(name: "thmanyahsans-Regular", size: 12) != nil

func displayFigure(_ value: String, _ name: String, size: CGFloat, relativeTo style: Font.TextStyle) -> Text {
    figureText(value) { mark in
        mark == "٬" ? Text(verbatim: "،").font(.custom(name, size: size * 0.65, relativeTo: style)).baselineOffset(size * 0.23)
                    : Text(verbatim: ",").font(.custom(name, size: size * 0.9, relativeTo: style))
    } run: { Text(verbatim: $0).font(.custom(name, size: size, relativeTo: style)) }
}

extension Text {
    /// A figure that keeps whatever font the caller applies, with «٬» and «٫» drawn as above.
    init(figure value: String) {
        self = figureText(value) { mark in mark == "٬" ? Text(verbatim: "،").textScale(.secondary) : Text(verbatim: ",") } run: { Text(verbatim: $0) }
    }
}

private func figureText(_ value: String, mark: (Character) -> Text, run make: (String) -> Text) -> Text {
    guard thmanyahBundled, value.contains(where: { $0 == "٬" || $0 == "٫" }) else { return make(value) }
    var text = Text(verbatim: ""), run = ""
    func flush() { guard !run.isEmpty else { return }; text = Text("\(text)\(make(run))"); run = "" }
    for character in value {
        guard character == "٬" || character == "٫" else { run.append(character); continue }
        flush(); text = Text("\(text)\(mark(character))")
    }
    flush(); return text.accessibilityLabel(Text(verbatim: value))
}
