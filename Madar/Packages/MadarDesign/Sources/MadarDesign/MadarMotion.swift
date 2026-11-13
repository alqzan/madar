import SwiftUI

/// The five motion tokens of `design-tokens.json` (T09). Every animation in the app names one of these;
/// under Reduce Motion each becomes the same short crossfade (`reduced`). Repeated actions are never animated.
public enum MadarMotion: Sendable {
    case quick, standard, settle, celebrate

    private static func value(_ key: String) -> Double { MadarMetric.values[key] ?? 0 }
    private static let ease = (0.2, 0.8, 0.2, 1.0)
    private static let ceremony = (0.4, 0.0, 0.2, 1.0)

    public var animation: Animation {
        switch self {
        case .quick: .timingCurve(Self.ease.0, Self.ease.1, Self.ease.2, Self.ease.3, duration: Self.value("motion.quick.duration"))
        case .standard: .timingCurve(Self.ease.0, Self.ease.1, Self.ease.2, Self.ease.3, duration: Self.value("motion.standard.duration"))
        case .settle: .spring(response: Self.value("motion.settle.response"), dampingFraction: Self.value("motion.settle.dampingFraction"))
        case .celebrate: .timingCurve(Self.ceremony.0, Self.ceremony.1, Self.ceremony.2, Self.ceremony.3, duration: Self.value("motion.celebrate.duration"))
        }
    }
    /// What the token becomes when the person asked for less motion.
    public static var reduced: Animation { .easeInOut(duration: value("motion.reduced.duration")) }
    public func animation(reduceMotion: Bool) -> Animation { reduceMotion ? Self.reduced : animation }
}

private struct MadarAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let motion: MadarMotion
    let value: Value
    func body(content: Content) -> some View { content.animation(motion.animation(reduceMotion: reduceMotion), value: value) }
}

public extension View {
    /// `.animation(_:value:)` that reads Reduce Motion by itself.
    func madarAnimation<Value: Equatable>(_ motion: MadarMotion, value: Value) -> some View {
        modifier(MadarAnimationModifier(motion: motion, value: value))
    }
}
