// Translated from design/kit/screens/explore-themes.html — see
// design/kit/MANIFEST.md's "Explore by theme — swipe deck" entry. Tier 1 of
// the guided discovery flow: a full-screen, scroll-snapped VERTICAL feed of
// the 30 curated theme-arcs (`curation/catalog/themes.json` via
// `CatalogLoader.loadThemes`/`DirectoryKit.ThemeArc`) — browsed by swiping
// up/down, never a yes/no swipe (see the MANIFEST section's "why the split
// gesture" note). Each card previews the theme with a per-theme gradient
// wash, a "Theme N of 30" kicker, the theme's name/hook, an "Inside this
// theme" row of up to 5 show-cover thumbnails (`RemoteArtwork` over
// `CatalogLoader.shows(inTheme:)`) + a "+N" chip, and a full-width "Dive in"
// button that pushes Tier 2 (`ThemeShowDeckScreen`, via `onDiveIn`). Tapping
// the `n/30` progress pill presents a "Jump to a theme" sheet — a scrollable
// list of all themes that jumps the feed straight to the tapped one.
//
// Native vertical pager: `ScrollView(.vertical)` + `.scrollTargetBehavior(
// .paging)` + `.scrollTargetLayout()` + `.scrollPosition(id:)` (iOS 17+,
// matches this project's `DesignSystem` package's `.iOS(.v17)` minimum) —
// chosen over the "rotated horizontal TabView" trick because it needs no
// rotation/offset math and `.scrollPosition(id:)`'s binding already gives
// "jump to theme" for free (setting it programmatically scrolls there),
// rather than needing a `ScrollViewProxy` + `.scrollTo` dance.
import SwiftUI
import DesignSystem
import DirectoryKit

/// Tier 1 — the vertical theme feed. Pushed from `ExploreThemeHeroCard` via
/// `HomeScreen`'s `ExploreRoute.themeFeed` destination, which supplies
/// `onDiveIn` so "Dive in" can push `ExploreRoute.themeShows(slug:)` onto the
/// same shared `NavigationPath` (this screen has no path of its own).
struct ThemeFeedScreen: View {
    /// Fired when "Dive in" is tapped on the visible slide, with that
    /// theme's slug. Defaulted so previews keep compiling.
    var onDiveIn: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var themes: [ThemeArc] = []
    @State private var entries: [CatalogEntry] = []
    @State private var currentSlug: String?
    @State private var showJumpSheet = false
    @State private var hasScrolled = false

    var body: some View {
        ZStack {
            feed
            overlayChrome
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: loadIfNeeded)
        .sheet(isPresented: $showJumpSheet) { jumpSheet }
    }

    private func loadIfNeeded() {
        guard themes.isEmpty else { return }
        themes = CatalogProvider.loadThemes()
        entries = CatalogProvider.loadEntries()
        currentSlug = themes.first?.slug
    }

    // MARK: - Feed (scroll-snapped vertical pager)

    private var feed: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(themes.enumerated()), id: \.element.slug) { index, theme in
                    ThemeSlideView(
                        theme: theme,
                        index: index,
                        total: max(themes.count, 30),
                        thumbnails: thumbnails(for: theme),
                        moreCount: moreCount(for: theme),
                        onDiveIn: { onDiveIn(theme.slug) }
                    )
                    .frame(maxWidth: .infinity)
                    .containerRelativeFrame(.vertical)
                    .id(theme.slug)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentSlug)
        .onChange(of: currentSlug) { _, newValue in
            if newValue != nil, newValue != themes.first?.slug { hasScrolled = true }
        }
        .ignoresSafeArea()
    }

    private func thumbnails(for theme: ThemeArc) -> [CatalogEntry] {
        Array(CatalogLoader.shows(inTheme: theme.slug, from: entries).prefix(5))
    }

    private func moreCount(for theme: ThemeArc) -> Int {
        max(theme.showCount - thumbnails(for: theme).count, 0)
    }

    // MARK: - Overlay chrome (back / eyebrow / progress pill / swipe hint)

    private var overlayChrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sp3) {
                circleButton(systemImage: "chevron.left", accessibilityLabel: "Back to Home") {
                    dismiss()
                }

                Spacer(minLength: 0)

                Text("EXPLORE BY THEME")
                    .font(.system(size: 11.52, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.92))

                Spacer(minLength: 0)

                progressPill
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.top, Spacing.sp1)

            if !hasScrolled {
                swipeHint
                    .padding(.top, Spacing.sp7)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, Spacing.sp6)
        .motion(Motion.easeSoft(duration: 0.3), value: hasScrolled)
    }

    private func circleButton(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.32), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    /// `n/30` — tapping opens the "Jump to a theme" sheet.
    private var progressPill: some View {
        Button {
            showJumpSheet = true
        } label: {
            HStack(spacing: 3) {
                Text("\(currentIndex + 1)")
                    .foregroundStyle(.white)
                Text("/\(max(themes.count, 30))")
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 13.12, weight: .heavy))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Color.black.opacity(0.32), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to a theme")
    }

    private var currentIndex: Int {
        guard let currentSlug else { return 0 }
        return themes.firstIndex(where: { $0.slug == currentSlug }) ?? 0
    }

    private var swipeHint: some View {
        VStack(spacing: 4) {
            Image(systemName: "chevron.up")
                .font(.system(size: 16, weight: .bold))
            Text("Swipe up")
                .font(.system(size: 10.56, weight: .heavy))
                .tracking(0.8)
        }
        .foregroundStyle(.white.opacity(0.82))
    }

    // MARK: - Jump-to-a-theme sheet

    private var jumpSheet: some View {
        NavigationStack {
            List(themes) { theme in
                Button {
                    withAnimation { currentSlug = theme.slug }
                    showJumpSheet = false
                } label: {
                    jumpRow(for: theme)
                }
                .listRowBackground(theme.slug == currentSlug ? palette.accent.opacity(0.12) : palette.surface)
            }
            .listStyle(.plain)
            .navigationTitle("Jump to a theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showJumpSheet = false }
                }
            }
        }
        .presentationDetents([.fraction(0.76), .large])
    }

    private func jumpRow(for theme: ThemeArc) -> some View {
        HStack(spacing: Spacing.sp3) {
            RoundedRectangle(cornerRadius: Radius.rIcon13, style: .continuous)
                .fill(ThemeVisuals.gradient(forIndex: themes.firstIndex(where: { $0.slug == theme.slug }) ?? 0))
                .frame(width: 40, height: 40)
                .overlay(Text(ThemeVisuals.emoji(forIndex: themes.firstIndex(where: { $0.slug == theme.slug }) ?? 0)))

            VStack(alignment: .leading, spacing: 1) {
                Text(theme.name)
                    .font(Typography.rowTitle)
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Text("\(theme.showCount) shows")
                    .font(Typography.subhead)
                    .foregroundStyle(palette.textDim)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textFaint)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Theme visuals (shared with `ThemeShowDeckScreen`'s badge/card)
//
// `DirectoryKit.ThemeArc` (Phase A) carries no color/emoji field — the kit's
// per-theme gradient wash and watermark emoji are purely decorative and not
// part of the curated data. This deterministically derives both from a
// theme's position in the (stable, file-order) themes list, cycling through
// the kit's 8 gradient washes (`explore-themes.html`'s `.g0`–`.g7`) and a
// matching set of 8 representative emoji — not a 1:1 mapping to all 30
// themes' real kit emoji (the kit hardcodes those; `ThemeArc` doesn't carry
// them), called out here as a deliberate simplification.
enum ThemeVisuals {
    private static let gradients: [[Color]] = [
        [Color(hex: 0xFF6A4D), Color(hex: 0xCA340F)],   // g0
        [Color(hex: 0x7C6BFF), Color(hex: 0x3B2C8F)],   // g1
        [Color(hex: 0x2E8BFF), Color(hex: 0x12324F)],   // g2
        [Color(hex: 0xFF5E9A), Color(hex: 0x7C1D4B)],   // g3
        [Color(hex: 0x22C1A6), Color(hex: 0x046B58)],   // g4
        [Color(hex: 0xFFB03A), Color(hex: 0xB23A0F)],   // g5
        [Color(hex: 0x34E0C4), Color(hex: 0x1E5F8F)],   // g6
        [Color(hex: 0xA97BFF), Color(hex: 0x6A2C8F)],   // g7
    ]

    private static let emojiSet = ["🕵️", "📜", "🔎", "⚖️", "🧩", "💸", "🎭", "🕯️"]

    static func gradient(forIndex index: Int) -> LinearGradient {
        let stops = gradients[((index % gradients.count) + gradients.count) % gradients.count]
        return LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func emoji(forIndex index: Int) -> String {
        emojiSet[((index % emojiSet.count) + emojiSet.count) % emojiSet.count]
    }
}

// MARK: - One full-screen theme slide

private struct ThemeSlideView: View {
    let theme: ThemeArc
    let index: Int
    let total: Int
    let thumbnails: [CatalogEntry]
    let moreCount: Int
    let onDiveIn: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ThemeVisuals.gradient(forIndex: index)

            // .wm — giant, faded watermark emoji.
            Text(ThemeVisuals.emoji(forIndex: index))
                .font(.system(size: 220))
                .opacity(0.15)
                .rotationEffect(.degrees(-8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 30, y: 40)
                .accessibilityHidden(true)

            // .slide::after — top-left highlight + bottom scrim so the copy
            // stays legible over any gradient.
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.0), Color(hex: 0x06040A, alpha: 0.6)],
                startPoint: .top,
                endPoint: .bottom
            )

            content
                .padding(.horizontal, 22)
                .padding(.bottom, 44)
        }
        .clipped()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text(ThemeVisuals.emoji(forIndex: index))
                Text("THEME \(index + 1) OF \(total)")
                    .tracking(1.4)
            }
            .font(.system(size: 10.56, weight: .heavy))
            .foregroundStyle(.white.opacity(0.9))

            Text(theme.name)   // .name
                .font(.custom(Typography.displayFontName, size: 40).weight(.bold))
                .tracking(-1)
                .foregroundStyle(.white)
                .lineLimit(3)
                .padding(.top, 12)
                .shadow(color: .black.opacity(0.3), radius: 18, x: 0, y: 2)

            if let summary = theme.summary, !summary.isEmpty {
                Text(summary)   // .desc
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(4)
                    .padding(.top, 14)
                    .frame(maxWidth: 340, alignment: .leading)
            }

            if !thumbnails.isEmpty {
                insideThisTheme
                    .padding(.top, 22)
            }

            diveInButton
                .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var insideThisTheme: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("INSIDE THIS THEME")
                .font(.system(size: 10.88, weight: .heavy))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.72))

            HStack(spacing: 9) {
                ForEach(thumbnails) { entry in
                    RemoteArtwork(
                        url: entry.artworkURL,
                        seed: seed(for: entry.title),
                        initial: initial(for: entry.title),
                        cornerRadius: Radius.rSm12
                    )
                    .frame(width: 46, height: 46)
                }

                if moreCount > 0 {
                    Text("+\(moreCount)")
                        .font(.system(size: 12.48, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: Radius.rSm12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.rSm12, style: .continuous).strokeBorder(Color.white.opacity(0.24), lineWidth: 0.5))
                }
            }
        }
    }

    private var diveInButton: some View {
        Button(action: onDiveIn) {
            HStack(spacing: 9) {
                Text("Dive in — swipe the shows")
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
            }
            .font(.system(size: 16.32, weight: .heavy))
            .foregroundStyle(Color(hex: 0x201018))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Color.white, in: Capsule())
            .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 10)
        }
        .buttonStyle(DiveInPressStyle())
    }

    private func seed(for title: String) -> Int {
        title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    }

    private func initial(for title: String) -> String {
        guard let first = title.first(where: { !$0.isWhitespace }) else { return "?" }
        return String(first).uppercased()
    }
}

/// `.dive:active { transform: scale(.97) }`.
private struct DiveInPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Motion.easeSpring(), value: configuration.isPressed)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Theme feed") {
    NavigationStack {
        ThemeFeedScreen()
    }
    .themedPalette()
}
#endif
