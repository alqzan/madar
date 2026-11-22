import SwiftUI

// Owner, 22 Nov 2026: «مليان ايموشنز وتحريكات بتفيد التطبيق خذ منها» — the motion ideas of a web UI kit
// (Magic UI's travelling beam, cards that give under the finger, number tickers, bars that grow in), redrawn
// natively and in Madar's own language. Every effect runs once on an event, never on a loop, and Reduce Motion
// turns each one into its plain end state.

/// The habits room's own mark is the orbit («مدار»): when a habit is completed, a short light travels once
/// around its ring and the phone answers with a light success tap.
struct OrbitCompletionSweep: ViewModifier {
    let done: Bool
    let lineWidth: CGFloat
    @Environment(\.roomTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var runs = 0

    private struct Sweep { var angle = 0.0; var opacity = 0.0; var bloom = 1.0 }

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: Sweep(), trigger: runs) { view, value in
                view
                    .scaleEffect(value.bloom)
                    .overlay {
                        Circle().trim(from: 0, to: 0.22)
                            .stroke(AngularGradient(colors: [theme.accentFill.opacity(0), theme.accentFill, .white.opacity(0.9)],
                                                    center: .center, startAngle: .degrees(0), endAngle: .degrees(80)),
                                    style: .init(lineWidth: lineWidth * 1.5, lineCap: .round))
                            .padding(lineWidth / 2)
                            .rotationEffect(.degrees(value.angle - 90))
                            .opacity(value.opacity)
                            .allowsHitTesting(false)
                    }
            } keyframes: { _ in
                KeyframeTrack(\.angle) {
                    LinearKeyframe(0, duration: 0.01)
                    CubicKeyframe(360, duration: 0.85)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.08)
                    LinearKeyframe(1, duration: 0.6)
                    LinearKeyframe(0, duration: 0.22)
                }
                KeyframeTrack(\.bloom) {
                    LinearKeyframe(1, duration: 0.55)
                    SpringKeyframe(1.08, duration: 0.18, spring: .snappy)
                    SpringKeyframe(1, duration: 0.3, spring: .bouncy)
                }
            }
            .onChange(of: done) { old, new in
                guard new, !old, !reduceMotion else { return }
                runs &+= 1
            }
            .sensoryFeedback(trigger: done) { old, new in new && !old ? .success : nil }
    }
}

extension View {
    func orbitCompletionSweep(done: Bool, lineWidth: CGFloat) -> some View {
        modifier(OrbitCompletionSweep(done: done, lineWidth: lineWidth))
    }

    /// A bar that grows from its start edge (the right in Arabic) the first time it appears, one after another.
    func madarGrowIn(order: Int) -> some View { modifier(MadarGrowIn(order: order)) }

    /// A lobby or room tile that fades up into place, one after another, the first time a screen appears in a launch.
    func madarEntrance(order: Int, shown: Bool) -> some View {
        modifier(MadarEntrance(order: order, shown: shown))
    }
}

struct MadarGrowIn: ViewModifier {
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(x: grown || reduceMotion ? 1 : 0.001, anchor: .leading)
            .onAppear {
                guard !grown, !reduceMotion else { return }
                withAnimation(.smooth(duration: 0.55).delay(Double(min(order, 12)) * 0.035)) { grown = true }
            }
    }
}

struct MadarEntrance: ViewModifier {
    let order: Int
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
        content
            .opacity(visible ? 1 : 0)
            .blur(radius: visible ? 0 : 6)
            .offset(y: visible ? 0 : 12)
            .animation(reduceMotion ? nil : .smooth(duration: 0.45).delay(Double(min(order, 10)) * 0.05), value: shown)
    }
}

/// A tile gives a little under the finger and springs back, like a card being pressed, and keeps the whole tile tappable.
struct MadarPressableTileStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == MadarPressableTileStyle {
    static var madarPressableTile: MadarPressableTileStyle { MadarPressableTileStyle() }
}

/// Magic UI's shimmer, once: a soft band of light crosses a card from its start edge (the right in Arabic) when
/// `trigger` changes — for example when a new step takes the lead in the lobby. Never on first appearance.
struct MadarLightSweep<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    var cornerRadius: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var runs = 0
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    Rectangle().fill(.clear)
                        .keyframeAnimator(initialValue: -0.4, trigger: runs) { view, progress in
                            view.overlay {
                                LinearGradient(colors: [.white.opacity(0), .white.opacity(0.28), .white.opacity(0)],
                                               startPoint: .leading, endPoint: .trailing)
                                    .frame(width: width * 0.45)
                                    .rotationEffect(.degrees(14))
                                    .offset(x: (layoutDirection == .rightToLeft ? -1 : 1) * (progress - 0.5) * width * 1.6)
                                    .opacity(progress <= -0.4 || progress >= 1.4 ? 0 : 1)
                            }
                        } keyframes: { _ in
                            KeyframeTrack {
                                LinearKeyframe(-0.39, duration: 0.01)
                                CubicKeyframe(1.39, duration: 0.95)
                                LinearKeyframe(1.4, duration: 0.01)
                            }
                        }
                }
                .clipShape(.rect(cornerRadius: cornerRadius))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onChange(of: trigger) { _, _ in if !reduceMotion { runs &+= 1 } }
    }
}

extension View {
    func madarLightSweep<T: Equatable>(trigger: T, cornerRadius: CGFloat = 22) -> some View {
        modifier(MadarLightSweep(trigger: trigger, cornerRadius: cornerRadius))
    }
}
