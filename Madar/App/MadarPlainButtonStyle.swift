import SwiftUI
import MadarDesign

/// AU-95 (owner, 29 Oct: «مشاكل بالتطبيق بالضغط والازرار»): `.plain` hit-tests only the drawn glyphs and text,
/// so the empty part of a 44 pt frame, a full-width row or a dashed «أضف» box took no tap. This keeps `.plain`'s
/// look (pressed and disabled states included) and makes the whole label frame tappable.
struct MadarPlainButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension PrimitiveButtonStyle where Self == MadarPlainButtonStyle {
    static var madarPlain: MadarPlainButtonStyle { MadarPlainButtonStyle() }
}

/// «Ink Switch» (owner, 23 Nov): every switch in Madar fills with its room's ink from the knob outwards instead of the system green.
/// The whole row takes the tap, and VoiceOver and UI tests still meet a real switch through the accessibility representation.
struct MadarInkToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View { MadarInkToggle(configuration: configuration) }
}

private struct MadarInkToggle: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.roomTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.labelsVisibility) private var labelsVisibility
    var body: some View {
        let on = configuration.isOn
        // A switch with its label hidden takes only the track's width, like the system switch in a narrow slot.
        HStack(spacing: labelsVisibility == .hidden ? 0 : 12) {
            if labelsVisibility != .hidden {
                configuration.label
                Spacer(minLength: 8)
            }
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(theme.ink.opacity(0.13))
                Circle().fill(theme.accentFill).frame(width: 31, height: 31).scaleEffect(on ? 3.6 : 0.01)
                Circle().fill(.white).shadow(color: .black.opacity(0.18), radius: 1.5, y: 1).frame(width: 26, height: 26).padding(2.5)
            }
            .frame(width: 51, height: 31).clipShape(.capsule)
            .animation(reduceMotion ? nil : .spring(duration: 0.38, bounce: 0.3), value: on)
        }
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(.rect)
        .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// «Swipe Confirm» (owner, 23 Nov): a delete that cannot be undone asks for a deliberate slide instead of a second tap.
/// A small sheet names what goes; the knob must travel most of the track, or it springs back.
extension View {
    func madarSwipeConfirm(isPresented: Binding<Bool>, title: String, message: String, action: String, cancel: String = "إلغاء", perform: @escaping () -> Void) -> some View {
        sheet(isPresented: isPresented) {
            MadarSwipeConfirmSheet(title: title, message: message, action: action, cancel: cancel) { perform(); isPresented.wrappedValue = false } dismiss: { isPresented.wrappedValue = false }
                .presentationDragIndicator(.visible)
        }
    }
}

private struct MadarSwipeConfirmSheet: View {
    let title: String, message: String, action: String, cancel: String
    let perform: () -> Void, dismiss: () -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var drag: CGFloat = 0
    @State private var confirmed: Bool?
    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(MadarTypography.cardTitle()).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Text(message).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            GeometryReader { proxy in
                let knob: CGFloat = 50, travel = max(1, proxy.size.width - knob - 8)
                let progress = min(1, max(0, drag / travel))
                let reachedConfirmation = progress >= 0.78
                ZStack(alignment: .trailing) {
                    Capsule().fill(theme.risk.opacity(0.12))
                    Capsule().fill(theme.risk.opacity(0.22)).frame(width: knob + 8 + drag)
                    Text("اسحب: " + action).font(MadarTypography.caption().bold()).foregroundStyle(theme.risk)
                        .frame(maxWidth: .infinity).opacity(1 - progress)
                    Circle().fill(theme.risk).frame(width: knob, height: knob)
                        .overlay { Image(systemName: reachedConfirmation ? "checkmark" : "arrow.left").font(.system(size: 18, weight: .bold)).foregroundStyle(.white).contentTransition(.symbolEffect(.replace)) }
                        .padding(4).offset(x: -drag)
                        .gesture(DragGesture(minimumDistance: 2)
                            .onChanged { value in guard confirmed == nil else { return }; drag = min(travel, max(0, -value.translation.width)) }
                            .onEnded { _ in
                                guard confirmed == nil else { return }
                                if drag >= travel * 0.78 {
                                    finish(confirmed: true)
                                } else { withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.35)) { drag = 0 } }
                            })
                }
                .environment(\.layoutDirection, .leftToRight)
                .sensoryFeedback(.warning, trigger: confirmed == true)
            }
            .frame(height: 58)
            .accessibilityElement(children: .ignore).accessibilityLabel(action).accessibilityAddTraits(.isButton)
            .accessibilityAction { finish(confirmed: true) }
            .accessibilityIdentifier("madar-swipe-confirm")
            Button(cancel) { finish(confirmed: false) }
                .font(MadarTypography.body()).foregroundStyle(theme.ink).frame(minHeight: 44).buttonStyle(.madarPlain)
                .accessibilityIdentifier("madar-swipe-cancel")
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.background)
        // Large text needs the whole height so the slide and «إلغاء» never fall below the sheet's edge.
        .presentationDetents(dynamicTypeSize >= .xxxLarge ? [.large] : [.height(290)])
    }

    private func finish(confirmed: Bool) {
        guard self.confirmed == nil else { return }
        self.confirmed = confirmed
        if confirmed { perform() } else { dismiss() }
    }
}
