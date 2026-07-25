// Translated from design/kit/screens/explore-theme-shows.html — see
// design/kit/MANIFEST.md's "Explore by theme — swipe deck" entry. Tier 2 of
// the guided discovery flow: a HORIZONTAL `SwipeDeck` (DesignSystem) over one
// theme's shows (`CatalogLoader.shows(inTheme:from:)`), already-subscribed
// shows excluded (plain-Swift filter over the live `@Query`, matching
// `PodcastsListProvider`'s no-`#Predicate`-on-a-relationship precedent).
// Right = subscribe (the existing `persist`/`SubscribeState` idle→
// subscribing→subscribed dance every curated shelf uses); left = skip, no
// persistence. Tapping (not swiping) a card presents the real
// `PodcastDetailScreen(feedURL:)` as a `.sheet` — literally the same detail
// screen every other entry point pushes, not a rebuild of it — and
// subscribing from inside that sheet is detected via the live
// `subscribedFeedURLs` set changing, which fires the same `SwipeDeck`
// programmatic-dismiss path a real right-swipe would, so the next card is
// already waiting behind the sheet when it closes. End-of-deck tallies how
// many were subscribed and offers "Back to themes" (`dismiss()`).
import SwiftUI
import SwiftData
import DesignSystem
import DirectoryKit
import PodcastModels

/// Tier 2 — the per-theme show deck. Pushed via `HomeScreen`'s
/// `ExploreRoute.themeShows(slug:)` destination (itself reached from
/// `ThemeFeedScreen`'s "Dive in").
struct ThemeShowDeckScreen: View {
    let themeSlug: String

    @Query(sort: \Podcast.dateAdded, order: .reverse) private var allPodcasts: [Podcast]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var themes: [ThemeArc] = []
    /// Every catalog show tagged with this theme, unfiltered — the progress
    /// denominator (kit's `meta.total`/`pgTotal`).
    @State private var allThemeEntries: [CatalogEntry] = []
    /// What the deck actually shows: `allThemeEntries` minus already-
    /// subscribed shows, shrinking as the person swipes/subscribes.
    @State private var remaining: [CatalogEntry] = []
    @State private var isLoaded = false
    @State private var subscribedCount = 0
    @State private var selectedEntry: CatalogEntry?
    @State private var programmaticAction: SwipeDeckAction?

    private var subscribedFeedURLs: Set<URL> {
        Set(allPodcasts.filter(\.isSubscribed).map(\.feedURL))
    }

    private var theme: ThemeArc? {
        themes.first { $0.slug == themeSlug }
    }

    private var themeIndex: Int {
        themes.firstIndex { $0.slug == themeSlug } ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            progressTrack

            ZStack {
                if remaining.isEmpty {
                    if isLoaded { endState }
                } else {
                    deck
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !remaining.isEmpty {
                hint
                actionDock
            }
        }
        .background(palette.groupedBg.ignoresSafeArea())
        // Immersive takeover: keep AppShell's tab bar + mini-player hidden
        // through Tier 2 as well (the whole explore flow reads as one screen).
        .hidesShellChrome()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: loadIfNeeded)
        .onChange(of: subscribedFeedURLs) { _, newValue in
            advanceFromSheetIfNeeded(subscribed: newValue)
        }
        .sheet(item: $selectedEntry) { entry in
            NavigationStack {
                PodcastDetailScreen(feedURL: entry.feedURL)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { selectedEntry = nil }
                        }
                    }
            }
            .presentationDetents([.fraction(0.86), .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Load

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        themes = CatalogProvider.loadThemes()
        let entries = CatalogProvider.loadEntries()
        allThemeEntries = CatalogLoader.shows(inTheme: themeSlug, from: entries)
        let subscribed = subscribedFeedURLs
        remaining = allThemeEntries.filter { !subscribed.contains($0.feedURL) }
        isLoaded = true
    }

    /// When a subscribe happens from inside the detail sheet (not a real
    /// swipe), fly the same card off behind it so the deck is already
    /// advanced by the time the sheet closes (kit's `subscribeFromSheet()`).
    private func advanceFromSheetIfNeeded(subscribed: Set<URL>) {
        guard
            let selectedEntry,
            subscribed.contains(selectedEntry.feedURL),
            remaining.first?.id == selectedEntry.id,
            programmaticAction == nil
        else { return }
        programmaticAction = .right
    }

    // MARK: - Top bar (.topbar / .progresspill / .track)

    private var topBar: some View {
        HStack(spacing: Spacing.sp3) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .frame(width: 40, height: 40)
                    .background(palette.chip, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to themes")

            VStack(spacing: 1) {
                Text("DIVING INTO")
                    .font(.system(size: 10.24, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(palette.accent)
                Text(theme?.name ?? "")
                    .font(.custom(Typography.displayFontName, size: 16.32).weight(.bold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            progressLabel
        }
        .font(.system(size: 13.12, weight: .heavy))
        .padding(.horizontal, Spacing.gutter)
        .padding(.top, Spacing.sp2)
        .padding(.bottom, Spacing.sp1)
    }

    /// `<b id="pgNow">1</b>/<span id="pgTotal">72</span>` — built as a single
    /// `Text` (rather than two sibling `Text`s in the `HStack`) so the two
    /// colors concatenate onto one line with no extra spacing between them.
    private var progressLabel: Text {
        Text("\(progressNow)").foregroundColor(palette.text)
            + Text("/\(max(allThemeEntries.count, 1))").foregroundColor(palette.textDim)
    }

    private var progressNow: Int {
        min(allThemeEntries.count - remaining.count + (remaining.isEmpty ? 0 : 1), max(allThemeEntries.count, 1))
    }

    private var progressTrack: some View {
        GeometryReader { geo in
            Capsule()
                .fill(palette.chip)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [palette.accent, palette.accent2], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * progressFraction)
                }
        }
        .frame(height: 3)
        .padding(.horizontal, Spacing.gutter)
        .padding(.top, 2)
    }

    private var progressFraction: CGFloat {
        guard allThemeEntries.count > 0 else { return 0 }
        return CGFloat(allThemeEntries.count - remaining.count) / CGFloat(allThemeEntries.count)
    }

    // MARK: - Deck

    private var deck: some View {
        SwipeDeck(
            items: remaining,
            rightStampTitle: "Subscribed ✓",
            leftStampTitle: "Skip",
            programmaticAction: $programmaticAction,
            onSwipeRight: { entry in
                subscribedCount += 1
                if !subscribedFeedURLs.contains(entry.feedURL) { persist(entry) }
                remaining.removeAll { $0.id == entry.id }
            },
            onSwipeLeft: { entry in
                remaining.removeAll { $0.id == entry.id }
            },
            onTap: { entry in
                selectedEntry = entry
            }
        ) { entry in
            ShowCard(entry: entry, themeName: theme?.name ?? "", themeEmoji: ThemeVisuals.emoji(forIndex: themeIndex))
        }
        .frame(width: 310, height: 452)
        .padding(.top, Spacing.sp4)
    }

    private var hint: some View {
        Text("Swipe right to subscribe · left to skip")
            .font(Typography.subhead)
            .foregroundStyle(palette.textFaint)
            .padding(.top, Spacing.sp4)
    }

    // MARK: - Action dock (.actions .skip / .sub)

    private var actionDock: some View {
        HStack(spacing: 26) {
            Button {
                guard !remaining.isEmpty else { return }
                programmaticAction = .left
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(palette.danger)
                    .frame(width: 62, height: 62)
                    .background(palette.surface, in: Circle())
                    .overlay(Circle().strokeBorder(palette.danger.opacity(0.55), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip this show")

            Button {
                guard !remaining.isEmpty else { return }
                programmaticAction = .right
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(palette.onAccent)
                    .frame(width: 74, height: 74)
                    .background(
                        LinearGradient(colors: [palette.accent, palette.accent2], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
                    .shadow(color: palette.accent.opacity(0.5), radius: 14, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Subscribe to this show")
        }
        .padding(.vertical, Spacing.sp2)
        .padding(.bottom, Spacing.sp6)
    }

    // MARK: - End of deck (.endcard)

    private var endState: some View {
        VStack(spacing: Spacing.sp3) {
            RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous)
                .fill(LinearGradient(colors: [palette.accent, palette.accent2], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 82, height: 82)
                .overlay(Text("✅").font(.system(size: 34)))
                .shadow(color: palette.accent.opacity(0.4), radius: 18, x: 0, y: 10)

            Text("You've seen our \(allThemeEntries.count) picks")
                .font(.custom(Typography.displayFontName, size: 22.4).weight(.bold))
                .foregroundStyle(palette.text)

            Text("\(theme?.name ?? "This theme") has \(theme?.showCount ?? allThemeEntries.count) shows in the catalog — come back for more.")
                .font(Typography.subhead)
                .foregroundStyle(palette.textDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            if subscribedCount > 0 {
                Text("＋ \(subscribedCount) added to your Shows")
                    .font(.system(size: 13.12, weight: .heavy))
                    .foregroundStyle(palette.accent2)
            }

            Button {
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                    Text("Back to themes")
                }
                .font(.system(size: 15.36, weight: .heavy))
                .foregroundStyle(palette.onAccent)
                .padding(.horizontal, 24)
                .frame(minHeight: 48)
                .background(
                    LinearGradient(colors: [palette.accent, palette.accent2], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .padding(.top, Spacing.sp2)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Persist (mirrors `HomeScreen.persist(_:)` for a `CatalogEntry`)

    private func persist(_ entry: CatalogEntry) {
        let podcast = Podcast(
            title: entry.title,
            author: entry.author,
            feedURL: entry.feedURL,
            homeURL: entry.homeURL,
            artworkURL: entry.artworkURL,
            category: entry.category ?? "",
            isSubscribed: true
        )
        modelContext.insert(podcast)
        try? modelContext.save()
    }
}

// MARK: - One show card (.card / .art / .scrim / .badge / .body)

private struct ShowCard: View {
    let entry: CatalogEntry
    let themeName: String
    let themeEmoji: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Full-bleed artwork fill — NOT `RemoteArtwork`, which hard-forces
            // a 1:1 aspect ratio (`ArcCard.cover` in `PodcastDetailView.swift`
            // notes the same constraint for its own non-square cover) and
            // would letterbox inside this deck card's 310×452 portrait frame
            // instead of filling it edge-to-edge like the kit's `.art`.
            art

            LinearGradient(
                colors: [Color.black.opacity(0.05), Color.black.opacity(0), Color(hex: 0x08050C, alpha: 0.62), Color(hex: 0x08050C, alpha: 0.92)],
                startPoint: .top,
                endPoint: .bottom
            )

            badge

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                Text(entry.title)
                    .font(.custom(Typography.displayFontName, size: 25.92).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 2)

                Text(entry.author)
                    .font(.system(size: 13.44, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.top, 7)
                    .lineLimit(1)

                if let why = entry.why, !why.isEmpty {
                    Text(why)
                        .font(.system(size: 14.4, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(3)
                        .padding(.leading, 11)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.35)).frame(width: 2)
                        }
                        .padding(.top, 12)
                }
            }
            .padding(EdgeInsets(top: 0, leading: 22, bottom: 24, trailing: 22))
        }
        .frame(width: 310, height: 452)
        .background(Color(hex: 0x241D2C))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 20)
    }

    /// Fills the whole card: the seeded gradient (kit's `.a1`–`.a6`) as a base
    /// so there's never a blank flash, an `AsyncImage` on top when there's a
    /// real artwork URL, and the show's initial glyph only when there is no
    /// URL at all (kit: `.card.hasart .glyph { display: none }`).
    @ViewBuilder
    private var art: some View {
        ZStack {
            ArtworkStyle(seed: seed).gradient

            if let url = entry.artworkURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
            } else {
                Text(initial)
                    .font(.system(size: 90, weight: .black))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
        }
        .frame(width: 310, height: 452)
        .clipped()
    }

    private var badge: some View {
        HStack(spacing: 6) {
            Text(themeEmoji)
            Text(themeName.uppercased())
                .tracking(1)
        }
        .font(.system(size: 10.56, weight: .heavy))
        .foregroundStyle(.white)
        .padding(.vertical, 6)
        .padding(.horizontal, 11)
        .background(Color.black.opacity(0.42), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.26), lineWidth: 1))
        .padding(16)
    }

    private var seed: Int {
        entry.title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    }

    private var initial: String {
        guard let first = entry.title.first(where: { !$0.isWhitespace }) else { return "?" }
        return String(first).uppercased()
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Theme show deck") {
    NavigationStack {
        ThemeShowDeckScreen(themeSlug: "institutional-coverup")
    }
    .themedPalette()
    .modelContainer(ModelSchema.previewContainer())
}
#endif
