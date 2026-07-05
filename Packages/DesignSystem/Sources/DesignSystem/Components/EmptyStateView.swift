// Translated from design/kit/components/no-results.html and
// design/kit/screens/{no-results,error}.html (SHARED KIT EXTRAS: .state /
// .state-badge / .state-title / .state-sub / .state-actions) — correct and
// confirmed for the `.noResults` and `.error` cases only.
//
// `.firstRun` is an INTERIM PLACEHOLDER, not a translation of anything in the
// kit: design/kit/screens/first-run.html's real content is a multi-step guided
// onboarding wizard (existing-app import, favorite-show picker, topic picker,
// personalized results), which has no Swift implementation and is out of scope
// here. Reusing this generic `.state` block for `.firstRun` is exactly how the
// original mistranslation happened — see design/kit/MANIFEST.md before
// building the real wizard; don't extend this enum further without checking
// there first.
//
// A centered large-state block for the three empty conditions — first run,
// no results, and error — built on the locked token set. An 84px gradient
// badge with a white decorative glyph springs in, followed by a display-face
// title, a dimmed message, and a caller-supplied action row. Colors come only
// from the active ThemePalette + the theme-agnostic Brand ramp; sizing/radius/
// motion/type from Spacing/Radius/Typography/Elevation/Motion (direction.md §1/§3–§7/§9).
import SwiftUI

/// Which large-state this block represents. Owned by the component layer;
/// selects the badge gradient and default glyph (direction.md §9 "State badges").
public enum EmptyKind: Sendable, Hashable, CaseIterable {
    /// First run / cold start — coral→mint "discover" badge.
    ///
    /// PLACEHOLDER: stands in for the unbuilt onboarding wizard
    /// (design/kit/screens/first-run.html). Not a real kit translation.
    case firstRun
    /// A search that matched nothing — grape→coral "empty" badge.
    case noResults
    /// A failed request — coral→coral-deep warm "error" badge.
    case error
}

/// The centered empty / no-results / error state.
///
/// Mirrors the kit's `.state` block:
/// - `.state`: centered column, `--sp-7`/`--sp-4`/`--sp-6` padding, `--sp-3` gaps.
/// - `.state-badge`: 84×84, 26px corner, gradient fill, white glyph, `--elev-card`,
///   an inner top-left highlight, and a spring `badgePop` entrance over `--dur-rise`.
/// - `.state-title`: display face, `--text`, `--sp-2` extra top margin.
/// - `.state-sub`: `--text-dim`, max-width 268, relaxed line height.
/// - `.state-actions`: caller-supplied row, `--sp-4` top margin, `--sp-2` gaps.
public struct EmptyStateView<Actions: View>: View {
    private let kind: EmptyKind
    private let title: String
    private let message: String
    private let actions: Actions

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    public init(
        kind: EmptyKind,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: 0) {
            badge

            Text(title)                                   // .state-title
                .typeStyle(Typography.sectionStyle)       // display face, 800 (≈1.28rem)
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)
                .padding(.top, Spacing.sp3 + Spacing.sp2) // .state gap + .state-title margin-top

            Text(message)                                 // .state-sub
                .typeStyle(Typography.bodyStyle)          // 500, dimmed
                .foregroundStyle(palette.textDim)
                .multilineTextAlignment(.center)
                .lineSpacing(4)                           // line-height 1.45
                .frame(maxWidth: 268)                     // .state-sub max-width
                .padding(.top, Spacing.sp3)               // .state gap

            HStack(spacing: Spacing.sp2) {                // .state-actions (gap --sp-2)
                actions
            }
            .padding(.top, Spacing.sp4)                   // .state-actions margin-top
        }
        // .state padding: --sp-7 (top) --sp-4 (sides) --sp-6 (bottom)
        .padding(.top, Spacing.sp7)
        .padding(.horizontal, Spacing.sp4)
        .padding(.bottom, Spacing.sp6)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .onAppear {
            withAnimation(Motion.resolve(Motion.easeSpring(duration: Motion.durRise),
                                         reduceMotion: reduceMotion)) {
                appeared = true
            }
        }
    }

    // MARK: - Badge (.state-badge)

    /// state-badge corner: 26px — a one-off in the kit, no matching radius token.
    private static var badgeCorner: CGFloat { 26 }
    /// state-badge size: 84×84 — a one-off in the kit, no matching spacing token.
    private static var badgeSize: CGFloat { 84 }

    private var badgeShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.badgeCorner, style: .continuous)
    }

    private var badge: some View {
        badgeShape
            .fill(badgeGradient)
            .frame(width: Self.badgeSize, height: Self.badgeSize)
            .overlay {
                // state-badge::after — inner top-left white highlight.
                badgeShape.fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.4), Color.white.opacity(0)],
                        center: UnitPoint(x: 0.30, y: 0.24),
                        startRadius: 0,
                        endRadius: Self.badgeSize * 0.45
                    )
                )
            }
            .overlay {
                Image(systemName: glyphName)              // white decorative glyph (§9)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
            }
            .clipShape(badgeShape)
            .elevCard(hairline: palette.hairline)         // --elev-card
            // badgePop: opacity 0→1, scale .7→1, translateY 8→0 (spring, --dur-rise).
            .scaleEffect(appeared ? 1 : 0.7)
            .offset(y: appeared ? 0 : 8)
            .opacity(appeared ? 1 : 0)
            .accessibilityHidden(true)
    }

    /// 140deg gradient per kind. `firstRun`/`noResults` map to the kit's
    /// `.badge-discover`/`.badge-empty` (all brand-ramp tokens). `.badge-error`'s
    /// literal orange→pink hex is substituted with the on-brand coral→coral-deep
    /// warm ramp to keep the block hex-free (direction.md §8 accent discipline).
    private var badgeGradient: LinearGradient {
        let colors: [Color]
        switch kind {
        case .firstRun:  colors = [palette.coral, palette.mint]      // coral → mint
        case .noResults: colors = [palette.grape, palette.coral]     // grape → coral
        case .error:     colors = [palette.coral, palette.coralDeep] // warm error ramp
        }
        return LinearGradient(colors: colors,
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing)
    }

    /// Default SF Symbol glyph per kind (currentColor/inline-SVG spirit, §9).
    private var glyphName: String {
        switch kind {
        case .firstRun:  return "sparkles"
        case .noResults: return "magnifyingglass"
        case .error:     return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Preview

#if DEBUG
private struct EmptyStatePreviewHost: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.sp6) {
                EmptyStateView(
                    kind: .firstRun,
                    title: "Find your next listen",
                    message: "Search millions of shows, or tap a suggestion to start exploring."
                ) {
                    PrimaryButton(title: "Browse trending") {}
                }

                EmptyStateView(
                    kind: .noResults,
                    title: "No shows found",
                    message: "Nothing matched your search. Try a different spelling or switch directory source."
                ) {
                    SecondaryButton(title: "Clear search") {}
                    GhostButton(title: "Try PodcastIndex") {}
                }

                EmptyStateView(
                    kind: .error,
                    title: "Couldn't reach the directory",
                    message: "Check your connection and try again in a moment."
                ) {
                    PrimaryButton(title: "Retry") {}
                }
            }
            .padding(.vertical, Spacing.sp5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.groupedBg)
    }
}

#Preview("Empty state — light") {
    EmptyStatePreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Empty state — dark") {
    EmptyStatePreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}
#endif
