// Translated from design/kit/screens/home.html `.play-btn` ("circular
// accent-gradient play button — same treatment as .sub, play glyph instead
// of plus/check", lines ~547-630). Reuses the exact accent→accent2 gradient
// and drop-shadow idiom already established by `SubscribeButton.swift`
// (`.sub`) and `Buttons.swift`'s primary pill, rather than re-deriving the
// kit's raw `color-mix()` stop.
import SwiftUI

/// A reusable circular accent-gradient play button (`.play-btn`). Used at
/// diameter 40 for the Up Next rail's `.pn-play` and diameter 38 for the
/// New Episodes rail's `.ep-play`; both callers own their own placement
/// (the kit positions `.play-btn` absolutely over artwork) — this view is
/// just the button itself.
///
/// Visual: circular accent→accent2 gradient fill, a drop shadow, an inset
/// white hairline, and an on-accent `play.fill` glyph with a slight optical
/// nudge (kit: `.play-btn svg { margin-left: 1.5px }`). Press scales to 0.86
/// (kit: `.pn-play:active` / `.ep-play:active { transform: scale(.86) }`).
public struct PlayButton: View {
    private let diameter: CGFloat
    private let accessibilityLabel: String
    private let action: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(diameter: CGFloat, accessibilityLabel: String, action: @escaping () -> Void) {
        self.diameter = diameter
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            glyph
                .frame(width: diameter, height: diameter)
                .background(background)
                .clipShape(Circle())
                .overlay(insetRing)
                .shadow(
                    color: Color(hex: 0x000000, alpha: 0.4),
                    radius: 6,
                    x: 0,
                    y: 4
                )
                .contentShape(Circle())
        }
        .buttonStyle(PlayPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Glyph

    private var glyph: some View {
        Image(systemName: "play.fill")
            .font(.system(size: diameter * 0.38, weight: .semibold))
            .foregroundStyle(palette.onAccent)
            .offset(x: diameter * 0.044)   // kit's `margin-left: 1.5px` optical center at 34px
    }

    // MARK: Fill / shadow (matches `SubscribeButton`'s `.sub` idiom exactly)

    private var background: some View {
        Circle().fill(
            LinearGradient(
                colors: [palette.accent, palette.accent2],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var insetRing: some View {
        // inset .5px white @ 28%
        Circle().strokeBorder(Color(hex: 0xFFFFFF, alpha: 0.28), lineWidth: 0.5)
    }
}

// MARK: - Press-scale style (`.pn-play:active` / `.ep-play:active { scale(.86) }`)

private struct PlayPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(
                Motion.resolve(Motion.easeSpring(), reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

// MARK: - Preview

#if DEBUG
private struct PlayButtonPreviewHost: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sp6) {
            Text("Sizes").typeStyle(Typography.groupLabelStyle).foregroundStyle(palette.textFaint)

            HStack(spacing: Spacing.sp5) {
                labeled("40 · Up Next") {
                    artworkCorner(seed: 3, initial: "S", diameter: 40)
                }
                labeled("38 · New episodes") {
                    artworkCorner(seed: 6, initial: "N", diameter: 38)
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

    private func artworkCorner(seed: Int, initial: String, diameter: CGFloat) -> some View {
        ArtworkTile(seed: seed, initial: initial)
            .frame(width: 112, height: 112)
            .overlay(alignment: .bottomTrailing) {
                PlayButton(diameter: diameter, accessibilityLabel: "Play episode") {}
                    .padding(8)
            }
    }
}

#Preview("Play button — light") {
    PlayButtonPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Play button — dark") {
    PlayButtonPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}
#endif
