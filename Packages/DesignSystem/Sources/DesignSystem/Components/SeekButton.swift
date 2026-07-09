// Translated from design/kit/components/seek-button.html (.seek-btn / .arc /
// .secs / .dir-fwd / .size-mini / .size-sheet).
// An icon-only curved-arrow transport control — rewind (counter-clockwise
// arc) or skip-ahead (clockwise arc) — with the seconds numeral centered
// inside the arc as real, data-driven text so one component serves both
// SkipInterval.back (15) and SkipInterval.forward (30). All color/motion
// come only from the active ThemePalette and the Spacing/Typography/Motion
// tokens.
import SwiftUI

// MARK: - Direction

/// Which way the control seeks (kit: base `.seek-btn` = backward, `.dir-fwd`
/// mirrors the same arc art horizontally).
public enum SeekDirection: Sendable, Hashable {
    case backward
    case forward
}

// MARK: - Press-scale style (.seek-btn:active { scale .86 })

private struct SeekPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(
                Motion.resolve(Motion.easeSpring(), reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

// MARK: - Seek button (public)

/// The icon-only rewind / skip-ahead control from the kit. `diameter` sizes
/// the whole hit target (mini-player ~30pt via `.size-mini`, Now Playing
/// sheet ~44pt via `.size-sheet`); the arrow glyph and seconds numeral scale
/// together off it. Stateless — the parent supplies `seconds` (from
/// `SkipInterval`) and handles the seek in `action`.
public struct SeekButton: View {
    private let direction: SeekDirection
    private let seconds: Int
    private let diameter: CGFloat
    private let accessibilityLabel: String
    private let action: () -> Void

    @Environment(\.palette) private var palette

    public init(
        direction: SeekDirection,
        seconds: Int,
        diameter: CGFloat,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.direction = direction
        self.seconds = seconds
        self.diameter = diameter
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                // SF Symbol curved arrow (empty center by design — the `.15`/
                // `.30` baked variants are NOT used since the numeral must be
                // data-driven, not fixed art).
                Image(systemName: direction == .backward ? "gobackward" : "goforward")
                    .font(.system(size: diameter * 0.9, weight: .semibold))
                    .foregroundStyle(palette.text)

                Text("\(seconds)")
                    .typeStyle(numeralStyle)
                    .foregroundStyle(palette.text)
                    .allowsHitTesting(false)
            }
            .frame(width: diameter, height: diameter)
            // ≥44pt hit target even when the visual diameter (mini, ~30pt)
            // is smaller (kit .seek-btn.size-mini::before inset -7px).
            .contentShape(Circle().inset(by: -max(0, (44 - diameter) / 2)))
        }
        .buttonStyle(SeekPressStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    /// The kit's `.secs` numeral is `--font-display` (the same brand mono
    /// face every other display-role token uses — see `Typography.display`)
    /// at `font-weight: 700`, and the kit itself scales the numeral's own
    /// size per control size (`.size-mini .secs` = .52rem, `.size-sheet
    /// .secs` = .76rem) rather than using one fixed size — so no single
    /// existing `Typography` role fits both the mini (~30pt) and sheet
    /// (~44pt) controls. This mirrors the kit's own two-size numeral scale
    /// (not a near-miss of a fixed token) by driving the display face off
    /// `diameter` the same way the arrow glyph already is, at `.bold` (700)
    /// to match the kit's weight exactly (not `.heavy`/800, which every
    /// fixed-size display role in `Typography` uses instead).
    private var numeralStyle: TypeStyle {
        TypeStyle(font: .custom(Typography.displayFontName, size: diameter * 0.26).weight(.bold))
    }
}

// MARK: - Preview

#if DEBUG
private struct SeekButtonPreviewHost: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sp6) {
            Text("Mini (30pt)")
                .typeStyle(Typography.groupLabelStyle)
                .foregroundStyle(palette.textFaint)

            HStack(spacing: Spacing.sp6) {
                labeled("Rewind 15") {
                    SeekButton(direction: .backward, seconds: 15, diameter: 30, accessibilityLabel: "Skip back 15 seconds") {}
                }
                labeled("Skip 30") {
                    SeekButton(direction: .forward, seconds: 30, diameter: 30, accessibilityLabel: "Skip forward 30 seconds") {}
                }
            }

            Text("Sheet (44pt)")
                .typeStyle(Typography.groupLabelStyle)
                .foregroundStyle(palette.textFaint)

            HStack(spacing: Spacing.sp6) {
                labeled("Rewind 15") {
                    SeekButton(direction: .backward, seconds: 15, diameter: 44, accessibilityLabel: "Skip back 15 seconds") {}
                }
                labeled("Skip 30") {
                    SeekButton(direction: .forward, seconds: 30, diameter: 44, accessibilityLabel: "Skip forward 30 seconds") {}
                }
            }
        }
        .padding(Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.groupedBg)
    }

    private func labeled(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: Spacing.sp2) {
            content()
            Text(title)
                .typeStyle(Typography.tagStyle)
                .foregroundStyle(palette.textDim)
        }
    }
}

#Preview("Seek button — light") {
    SeekButtonPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Seek button — dark") {
    SeekButtonPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}
#endif
