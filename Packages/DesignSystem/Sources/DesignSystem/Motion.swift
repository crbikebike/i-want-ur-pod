// Motion. Design source: docs/design/direction.md §7 (two easings, four durations).
// Everything collapses under prefers-reduced-motion.
import SwiftUI

/// Easings and durations from direction.md §7, plus reduce-motion helpers.
public enum Motion {

    // MARK: Durations (seconds)

    /// 0.2s — state tint, row press.
    public static let durFast: Double = 0.2
    /// 0.3s — press scale, color change.
    public static let durMid: Double = 0.3
    /// 0.55s — staggered row entrance.
    public static let durRow: Double = 0.55
    /// 0.6s — title / section reveal.
    public static let durRise: Double = 0.6

    // MARK: Easings

    /// `--ease-soft` = cubic-bezier(.22, .61, .36, 1).
    public static func easeSoft(duration: Double = durMid) -> Animation {
        .timingCurve(0.22, 0.61, 0.36, 1, duration: duration)
    }

    /// `--ease-spring` = cubic-bezier(.34, 1.56, .64, 1) — overshoots.
    public static func easeSpring(duration: Double = durMid) -> Animation {
        .timingCurve(0.34, 1.56, 0.64, 1, duration: duration)
    }

    // MARK: Reduce-motion

    /// Returns `animation` unless reduce-motion is on, in which case `nil`
    /// (SwiftUI applies the change with no animation). Reduced motion drops
    /// all durations to ~0 and resets entrance transforms to visible (§7).
    public static func resolve(_ animation: Animation?, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

public extension View {
    /// Apply an animation that automatically collapses under reduce-motion.
    /// Reads `\.accessibilityReduceMotion` from the environment.
    func motion<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(Motion.resolve(animation, reduceMotion: reduceMotion), value: value)
    }
}
