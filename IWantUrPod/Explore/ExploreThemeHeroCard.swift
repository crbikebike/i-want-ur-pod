// Translated from design/kit/components/explore-hero-card.html — see
// design/kit/MANIFEST.md's "Explore by theme — swipe deck" entry. The Home
// entry point: a full-width coral→coral-deep→grape gradient card ("Explore
// by theme" / "Flip through 30 story-worlds and find your next obsession.",
// a `315 shows`·`30 themes` pill pair, a tilted three-card mini-deck motif,
// and a trailing arrow chip), placed between "New episodes" and "Our
// favorites" in `HomeScreen.swift`. Tapping it pushes `ThemeFeedScreen`
// (Tier 1 of the guided flow — see that file's own header for the rest of
// the funnel).
import SwiftUI
import DesignSystem

/// Routes pushed onto `HomeScreen`'s own `NavigationPath` for the two-tier
/// "Explore by theme" flow — mirrors `SettingsRoute`'s one-case precedent
/// (`SettingsGearButton.swift`): a small `Hashable` enum registered with its
/// own `.navigationDestination(for:)` alongside the screen's existing `URL`/
/// `SettingsRoute` destinations.
enum ExploreRoute: Hashable {
    /// Tier 1 — the vertical theme feed (`ThemeFeedScreen`).
    case themeFeed
    /// Tier 2 — the horizontal show deck for one theme (`ThemeShowDeckScreen`).
    case themeShows(slug: String)
}

/// The Home hero card. Stateless — `showCount`/`themeCount` are supplied by
/// the caller (`HomeScreen` loads them once via `CatalogProvider`, falling
/// back to the kit's own `315`/`30` copy if the bundle lookup ever comes back
/// empty, e.g. in a preview with no bundled catalog).
struct ExploreThemeHeroCard: View {
    let showCount: Int
    let themeCount: Int
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(HeroPressStyle())
        .accessibilityLabel("Explore by theme — flip through \(themeCount) story-worlds and find your next obsession")
        .accessibilityAddTraits(.isButton)
    }

    private var content: some View {
        ZStack(alignment: .topLeading) {
            // .hero — 135° coral → coral-deep → grape gradient.
            LinearGradient(
                colors: [Brand.coral, Brand.coralDeep, Brand.grape],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // .hero::after — a soft top-left highlight + bottom-right shade.
            RadialGradient(
                colors: [Color.white.opacity(0.26), .clear],
                center: UnitPoint(x: 0.12, y: 0.06),
                startRadius: 0,
                endRadius: 260
            )
            RadialGradient(
                colors: [Color.black.opacity(0.28), .clear],
                center: UnitPoint(x: 1.0, y: 1.1),
                startRadius: 0,
                endRadius: 260
            )

            miniDeck
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            copy
                .padding(20)

            arrow
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(16)
        }
        .frame(minHeight: 138)
        .clipShape(RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
        .shadow(color: Brand.coral.opacity(0.35), radius: 20, x: 0, y: 18)
    }

    // MARK: - Copy (.hero-copy)

    private var copy: some View {
        VStack(alignment: .leading, spacing: 0) {
            // .hero-eyebrow
            HStack(spacing: 7) {
                Circle()
                    .fill(Brand.mint)
                    .frame(width: 6, height: 6)
                    .shadow(color: Brand.mint, radius: 4)
                Text("Guided · Swipe to discover")
                    .font(.system(size: 10.24, weight: .heavy))
                    .tracking(1.43)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Color.white.opacity(0.92))

            Text("Explore by theme")   // .hero-title — 1.66rem/700, display face
                .font(.custom(Typography.displayFontName, size: 26.56).weight(.bold))
                .tracking(-0.53)
                .foregroundStyle(.white)
                .padding(.top, 9)

            Text("Flip through \(themeCount) story-worlds and find your next obsession.")   // .hero-sub
                .font(.system(size: 14.08, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {   // .hero-meta
                heroPill("\(showCount) shows")
                heroPill("\(themeCount) themes")
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: 240, alignment: .leading)
    }

    private func heroPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.88, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.vertical, 5)
            .padding(.horizontal, 11)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
            )
    }

    // MARK: - Mini deck-stack motif (.hero-deck / .mini)

    private var miniDeck: some View {
        ZStack {
            miniTile(emoji: "🕵️", colors: [Color(hex: 0x2E8BFF), Color(hex: 0x12324F)], rotation: -15, x: -44, y: -20)
            miniTile(emoji: "🎭", colors: [Color(hex: 0xFF5E9A), Color(hex: 0x7C1D4B)], rotation: -4, x: -26, y: -12)
            miniTile(emoji: "🔎", colors: [Color(hex: 0x22C1A6), Color(hex: 0x046B58)], rotation: 9, x: -6, y: -4)
        }
        .frame(width: 132, height: 138, alignment: .bottomTrailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func miniTile(emoji: String, colors: [Color], rotation: Double, x: CGFloat, y: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 76, height: 100)
            .overlay(Text(emoji).font(.system(size: 32)))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 11, x: 0, y: 10)
            .rotationEffect(.degrees(rotation))
            .offset(x: x, y: y)
    }

    // MARK: - Trailing arrow chip (.arrow)

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Color.white.opacity(0.2), in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.32), lineWidth: 1))
    }
}

/// `.hero:active { transform: scale(.975) }`.
private struct HeroPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(Motion.easeSpring(), value: configuration.isPressed)
    }
}

// MARK: - Preview

#if DEBUG
private struct ExploreThemeHeroCardPreviewHost: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sp5) {
                ExploreThemeHeroCard(showCount: 315, themeCount: 30, action: {})
            }
            .padding(Spacing.gutter)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.groupedBg)
    }
}

#Preview("Explore hero card — dark") {
    ExploreThemeHeroCardPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}

#Preview("Explore hero card — light") {
    ExploreThemeHeroCardPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}
#endif
