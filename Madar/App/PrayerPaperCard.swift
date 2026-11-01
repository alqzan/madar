import SwiftUI
import MadarDesign

/// A paper card: the room background with a quiet hairline, as on S1.
struct PrayerPaperCard<Content: View>: View {
    var tinted = false
    @ViewBuilder let content: () -> Content
    @Environment(\.roomTheme) private var theme
    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.vertical, 18)
            .background(tinted ? theme.color("goldSoft") : .clear, in: .rect(cornerRadius: 22))
            .background(theme.background, in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(tinted ? theme.line : theme.ink.opacity(0.1), lineWidth: 1) }
    }
}
