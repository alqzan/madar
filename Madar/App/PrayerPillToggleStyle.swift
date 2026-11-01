import SwiftUI
import MadarDesign

/// «أوترتُ»: a quiet pill that keeps the switch semantics.
struct PrayerPillToggleStyle: ToggleStyle {
    @Environment(\.roomTheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                if configuration.isOn { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)) }
                configuration.label.font(PrayerHomeType.strong)
            }
            .foregroundStyle(configuration.isOn ? theme.color("accentText") : theme.ink)
            .padding(.horizontal, 28).frame(minHeight: 56)
            .background(configuration.isOn ? theme.color("goldSoft") : .clear, in: .rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(configuration.isOn ? theme.accent : theme.ink.opacity(0.14), lineWidth: configuration.isOn ? 1.5 : 1) }
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.madarPlain)
        .accessibilityValue(configuration.isOn ? "1" : "0")
        .accessibilityAddTraits(.isToggle)
    }
}
