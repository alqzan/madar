import SwiftUI

public struct RoomTheme: Sendable {
    public let room: String
    public let dark: Bool
    public let calmPaper: Bool
    public init(room: String = "bahw", dark: Bool = false, calmPaper: Bool = false) {
        self.room = room; self.dark = dark; self.calmPaper = calmPaper
    }
    public func color(_ role: String) -> Color {
        let coreRoles = ["bg", "surface", "card", "surface2", "ink", "ink2", "ink3", "line", "line2", "accent", "accentFill", "accentText", "onAccent"]
        let selected = calmPaper && coreRoles.contains(role) ? "bahw" : room
        let normalized: String = selected == "bahw" ? ["card": "surface", "surface2": "surface", "ink3": "ink2", "line2": "line"][role] ?? role
            // Air-mail travel paper (§7.3) has a smaller palette; small text maps onto its listed contrast pairs.
            : selected == "notes.travel" ? ["card": "surface", "accentText": "accent", "ink3": "ink2", "ink3Text": "ink2", "autoInkText": "ink2", "late": "accent", "pencil": "accent", "ghad": "accent", "highlight": "line", "seal": "accent"][role] ?? role : role
        let path = "rooms.\(selected).\(dark ? "dark" : "light").\(normalized)"
        return MadarToken.colors[path] ?? MadarToken.colors["rooms.\(selected).\(dark ? "dark" : "light").accent"] ?? .primary
    }
    public var background: Color { color("bg") }
    public var surface: Color { color("surface") }
    public var ink: Color { color("ink") }
    public var secondaryInk: Color { color("ink2") }
    public var line: Color { color("line") }
    public var accent: Color { color("accentText") }
    public var accentFill: Color { color("accentFill") }
    public var onAccent: Color { color("onAccent") }
}

public extension EnvironmentValues {
    @Entry var roomTheme = RoomTheme()
}

public enum MadarTypography {
    public static func title() -> Font { .custom("thmanyahserifdisplay-Bold", size: CGFloat(MadarMetric.values["typeScale.roomTitle.size"]!), relativeTo: .largeTitle) }
    public static func cardTitle() -> Font { .custom("thmanyahserifdisplay-Bold", size: CGFloat(MadarMetric.values["typeScale.cardTitle.size"]!), relativeTo: .title2) }
    public static func body() -> Font { .custom("thmanyahsans-Regular", size: CGFloat(MadarMetric.values["typeScale.body.size"]!), relativeTo: .body) }
    public static func caption() -> Font { .custom("thmanyahsans-Regular", size: CGFloat(MadarMetric.values["typeScale.caption.size"]!), relativeTo: .subheadline) }
    public static func section() -> Font { .custom("thmanyahsans-Bold", size: CGFloat(MadarMetric.values["typeScale.sectionHead.size"]!), relativeTo: .headline) }
    public static func fine() -> Font { .custom("thmanyahsans-Bold", size: CGFloat(MadarMetric.values["typeScale.fine.size"]!), relativeTo: .caption2) }
}

public struct MadarCard<Content: View>: View {
    @Environment(\.roomTheme) private var theme
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading).padding(MadarMetric.cardPadding)
            .background(theme.surface, in: .rect(cornerRadius: MadarMetric.cardRadius))
            .overlay { RoundedRectangle(cornerRadius: MadarMetric.cardRadius).stroke(theme.line, lineWidth: 1) }
    }
}

public struct MadarPrimaryButton: ButtonStyle {
    @Environment(\.roomTheme) private var theme
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(MadarTypography.section()).frame(maxWidth: .infinity).padding(.vertical, 16)
            .foregroundStyle(theme.onAccent).background(theme.accentFill, in: .rect(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
