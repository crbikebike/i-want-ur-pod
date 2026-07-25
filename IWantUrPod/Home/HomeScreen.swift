// Translated from design/kit/screens/home.html (its bespoke content: the
// large "Home" title with pulse-dot, the top-right `.util-gear` Settings
// button, the "Up Next" and "New episodes" `.sec-head`/`.rail`/`.pn`/`.ep-card`
// playable rails, and the "Our favorites" `.shelf`/`.rail`/
// `.pod` shelf — see design/kit/MANIFEST.md's "Home / Shows / Up Next
// screens" entry; the `.tabbar`/`.statusbar`/`.notch`/theme-toggle chrome is
// the shared kit frame AppShell + LiquidGlassTabBar already own, not
// re-translated here).
//
// Phase C (2026-07-23) added `exploreThemeSection` — the "Explore by theme"
// hero card between New episodes and Our favorites, translated from
// design/kit/components/explore-hero-card.html and pushing `ExploreRoute`
// onto this screen's own `path` (see `ExploreThemeHeroCard.swift`,
// `ThemeFeedScreen.swift`, `ThemeShowDeckScreen.swift`, and
// design/kit/MANIFEST.md's "Explore by theme — swipe deck" entry).
//
// ROADMAP.md E8-S2: Home replaces Discover as the first tab destination.
// Renders three sections in kit order — an Up Next rail, a New episodes rail,
// and an Our-favorites shelf — each rendering nothing
// (no header, no empty chrome) when it has no content. Data sources:
//   - Up Next rail:     the shared `QueueStore` (E5), the full queue —
//                        `UpNextTile`s (`.pn`) scroll horizontally rather
//                        than being capped to a short vertical peek.
//   - New episodes:     `HomeFeedProvider.recentEpisodes` over every
//                        subscribed show's episodes (SwiftData `@Query`) —
//                        `NewEpisodeCard`s (`.ep-card`) in a horizontal rail.
//   - Our favorites:     the bundled curated list, unfiltered (E1-S2's
//                        `curated-start-here.json`, loaded via the same
//                        `CuratedListLoader` DiscoverViewModel uses — not
//                        duplicated, just re-invoked; see
//                        `HomeFeedProvider.loadCuratedEntries`).
// Both rails' cards are playable: tapping a tile's `PlayButton` fires the
// universal play intent via `PlaybackIntentCoordinator.play(_:context:)` —
// already-downloaded episodes play immediately, otherwise it auto-queues,
// auto-downloads, and auto-plays on completion (E6); tapping the rest of a
// tile opens its owning show. Every other card tap (a shelf's
// `.pod`) pushes its `feedURL` into the same `PodcastDetailScreen` (E2) every
// other screen uses. The top-right gear pushes the existing
// `SettingsScreen()` (E8-S4's entry point).
//
// Kit's `.see-all` trailing link on the Up Next header now switches to the
// Up Next tab (`onSeeAllUpNext`, wired by `AppShell`) — Up Next itself is one
// tab away, already reachable, so this is a real destination unlike the New
// Episodes header's `.see-all` (no "all new episodes" screen exists in
// scope, so that header stays the title-only `SectionHeader` variant with no
// trailing affordance).
import SwiftUI
import SwiftData
import DesignSystem
import DirectoryKit
import PodcastModels
import PlaybackKit
import DownloadKit

/// The Home tab's entry point (ROADMAP.md E8-S2), referenced by `AppShell` as
/// a no-arg view. Owns its own `NavigationStack` (frozen nav contract — every
/// tab's screen owns its own stack; `AppShell`'s tab switch stays a pure view
/// switch) and reserves the floating tab bar's 104pt gap.
public struct HomeScreen: View {
    /// Live SwiftData queries (sorted only — no relationship `#Predicate`,
    /// same rationale as `PodcastsListProvider`'s header comment). Filtering
    /// happens in plain Swift via `HomeFeedProvider`.
    @Query(sort: \Podcast.dateAdded, order: .reverse) private var allPodcasts: [Podcast]
    @Query(sort: \Episode.publishDate, order: .reverse) private var allEpisodes: [Episode]

    @Environment(QueueStore.self) private var queueStore
    @Environment(PlaybackEngine.self) private var playbackEngine
    @Environment(PlaybackIntentCoordinator.self) private var playbackIntent
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette

    @State private var path = NavigationPath()
    @State private var curatedEntries: [CuratedEntry] = []
    /// Explore-by-theme hero card counts (`ExploreThemeHeroCard`'s `315
    /// shows`/`30 themes` pills) — loaded once via `CatalogProvider` and kept
    /// as plain `Int`s rather than the full decoded arrays, since the card
    /// only ever needs the counts. Falls back to the kit's own literal copy
    /// (`315`/`30`) if the bundle lookup ever comes back empty (e.g. a
    /// preview with no bundled catalog).
    @State private var exploreShowCount = 315
    @State private var exploreThemeCount = 30
    @State private var exploreCountsLoaded = false
    /// Transient subscribe-button animation state, keyed by `CuratedEntry.id`
    /// (its feedURL string) — shared across both curated shelves so
    /// subscribing from either one updates the other's card identically.
    @State private var subscribeStates: [String: SubscribeState] = [:]

    /// Gates the once-only first-run explainer (E1-S1). Now shown before Home
    /// (the dock IA's first destination) rather than Discover — Settings'
    /// reset control clears the same `UserDefaults` key this reads on appear.
    private let firstRunGate = FirstRunGate()
    @State private var showFirstRunExplainer = false

    /// Fired by the Up Next header's "See all" (kit `.see-all`) — switches
    /// the app to the Up Next tab. Defaulted so existing no-arg call sites
    /// (previews) keep compiling; `AppShell` supplies the real tab switch.
    private let onSeeAllUpNext: () -> Void

    public init(onSeeAllUpNext: @escaping () -> Void = {}) {
        self.onSeeAllUpNext = onSeeAllUpNext
    }

    // MARK: - Derived data

    private var subscribedFeedURLs: Set<URL> {
        Set(allPodcasts.filter(\.isSubscribed).map(\.feedURL))
    }

    private var recentEpisodes: [Episode] {
        HomeFeedProvider.recentEpisodes(from: allEpisodes)
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .topTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        titleBar

                        upNextSection
                        newEpisodesSection
                        exploreThemeSection
                        ourFavoritesSection
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.top, Spacing.sp5)
                    .padding(.bottom, AppShell.tabBarReservedPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                settingsGearButton
                    .padding(.top, Spacing.sp5)
                    .padding(.trailing, Spacing.gutter)
            }
            .background(palette.groupedBg.ignoresSafeArea())
            // Home draws its own large title (below) rather than UIKit's nav
            // bar chrome, matching Discover/Podcasts/Up Next's precedent.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: URL.self) { feedURL in
                PodcastDetailScreen(feedURL: feedURL)
            }
            .navigationDestination(for: SettingsRoute.self) { _ in
                SettingsScreen()
            }
            .navigationDestination(for: ExploreRoute.self) { route in
                switch route {
                case .themeFeed:
                    ThemeFeedScreen(onDiveIn: { slug in path.append(ExploreRoute.themeShows(slug: slug)) })
                case .themeShows(let slug):
                    ThemeShowDeckScreen(themeSlug: slug)
                }
            }
        }
        .onAppear {
            queueStore.reload()
            if curatedEntries.isEmpty {
                curatedEntries = HomeFeedProvider.loadCuratedEntries()
            }
            if !exploreCountsLoaded {
                let catalogCount = CatalogProvider.loadEntries().count
                let themeCount = CatalogProvider.loadThemes().count
                if catalogCount > 0 { exploreShowCount = catalogCount }
                if themeCount > 0 { exploreThemeCount = themeCount }
                exploreCountsLoaded = true
            }
            // Gate check happens on every appearance (not just launch) so a
            // Settings reset re-shows the explainer the next time Home is
            // visited, without needing to relaunch the app.
            if !firstRunGate.hasSeenFirstRun {
                showFirstRunExplainer = true
            }
        }
        .fullScreenCover(isPresented: $showFirstRunExplainer) {
            FirstRunExplainerView {
                firstRunGate.markSeen()
                showFirstRunExplainer = false
            }
            .themedPalette()
        }
    }

    // MARK: - Large title (h1.big) + gear (.util-gear)

    /// Kit's `.titlewrap` reserves `padding-right: 52px` so the title never
    /// runs under the floating gear button occupying the same row.
    private var titleBar: some View {
        HStack(spacing: Spacing.sp2) {
            Text("Home")
                .typeStyle(Typography.displayLargeTitleStyle)
                .foregroundStyle(palette.text)

            Circle()   // .pulse-dot
                .fill(
                    LinearGradient(
                        colors: [palette.accent, palette.accent2],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 11, height: 11)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 2)
        .padding(.trailing, 50)
        .padding(.bottom, Spacing.sp4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// `.util-gear` — a 40pt chip-fill circle, floating over the scroll
    /// content (kit: `position: absolute; top: 58px; right: var(--gutter)`).
    /// Pushes the existing `SettingsScreen()` (E8-S4). Shared shape/behavior
    /// with Shows/Up Next via `SettingsGearButton`.
    private var settingsGearButton: some View {
        SettingsGearButton { path.append(SettingsRoute.settings) }
    }

    // MARK: - Up Next (.sec-head "Up Next" + .see-all / .rail of .pn)

    @ViewBuilder
    private var upNextSection: some View {
        if !queueStore.items.isEmpty {
            upNextHeader

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Spacing.sp3) {   // .rail { gap: --sp-3 }
                    ForEach(Array(queueStore.items.enumerated()), id: \.offset) { _, item in
                        if let episode = item.episode {
                            UpNextTile(
                                episode: episode,
                                onPlay: { playbackIntent.play(episode, context: modelContext) },
                                onOpenShow: { openQueueItem(item) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 2)   // optical inset matching SectionHeader
            }
        }
    }

    /// `SectionHeader` has no trailing-accessory slot (same limitation
    /// `PodcastDetailView.episodesHeader` works around) — a custom title +
    /// `Spacer` + "See all" row instead, matching kit's `.see-all` link
    /// styling (accent text, no chip/background).
    private var upNextHeader: some View {
        HStack(alignment: .center, spacing: Spacing.sp2) {
            SectionHeader(title: "Up Next")
            Spacer(minLength: 0)
            Button(action: onSeeAllUpNext) {
                Text("See all")
                    .font(Typography.subhead.weight(.bold))
                    .foregroundStyle(palette.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, Spacing.sp1)   // roughly aligns with SectionHeader's own bottom inset
        }
    }

    /// Up Next rows open the queued episode's show detail — the E2 screen is
    /// keyed by `feedURL`, not by episode, so "open the episode" resolves to
    /// its owning show's Podcast Detail (acceptable per E8-S2's criterion:
    /// "opens the E2 Podcast Detail (or the episode...)").
    private func openQueueItem(_ item: QueueItem) {
        guard let feedURL = item.episode?.podcast?.feedURL else { return }
        path.append(feedURL)
    }

    // MARK: - New episodes (.sec-head "New episodes" / .rail of .ep-card)

    @ViewBuilder
    private var newEpisodesSection: some View {
        if !recentEpisodes.isEmpty {
            SectionHeader(title: "New episodes")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Spacing.sp3) {   // .rail { gap: --sp-3 }
                    ForEach(recentEpisodes, id: \.guid) { episode in
                        NewEpisodeCard(
                            episode: episode,
                            onPlay: { playbackIntent.play(episode, context: modelContext) },
                            onOpenShow: { openEpisodeShow(episode) }
                        )
                    }
                }
                .padding(.horizontal, 2)   // optical inset matching SectionHeader
            }
        }
    }

    private func openEpisodeShow(_ episode: Episode) {
        guard let feedURL = episode.podcast?.feedURL else { return }
        path.append(feedURL)
    }

    // MARK: - Explore by theme (.hero — see design/kit/components/explore-hero-card.html)

    /// The guided-discovery hero card, placed between "New episodes" and
    /// "Our favorites" (matching the kit's Home-scroll context slice).
    /// Tapping it pushes `ExploreRoute.themeFeed` (Tier 1 — `ThemeFeedScreen`).
    private var exploreThemeSection: some View {
        ExploreThemeHeroCard(
            showCount: exploreShowCount,
            themeCount: exploreThemeCount,
            action: { path.append(ExploreRoute.themeFeed) }
        )
        .padding(.top, Spacing.sp6)
    }

    // MARK: - Our favorites (.shelf "Our favorites")

    @ViewBuilder
    private var ourFavoritesSection: some View {
        if !curatedEntries.isEmpty {
            curatedShelf(title: "Our favorites", entries: curatedEntries)
                .padding(.top, Spacing.sp6)
        }
    }

    /// Shared rail renderer for both curated shelves — `ResultShelf`'s
    /// poster-card rail (not `CuratedShelf`'s vertical editorial cards),
    /// matching `home.html`'s `.rail`/`.pod` layout for these two sections.
    /// The bundled curated list's *decoding* still runs through
    /// `HomeFeedProvider.loadCuratedEntries` → DirectoryKit's
    /// `CuratedListLoader` — this only reuses the already-decoded entries.
    private func curatedShelf(title: String, entries: [CuratedEntry]) -> some View {
        ResultShelf(
            title: title,
            items: entries,
            onSelect: { entry in path.append(entry.feedURL) },
            itemTitle: { $0.title },
            itemAuthor: { $0.author },
            itemArtwork: { ArtworkStyle(seed: seed(for: $0)) },
            itemArtworkURL: { $0.artworkURL }
        ) { entry in
            SubscribeButton(state: subscribeState(for: entry)) {
                subscribe(entry)
            }
        }
    }

    private func seed(for entry: CuratedEntry) -> Int {
        entry.title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    }

    private func subscribeState(for entry: CuratedEntry) -> SubscribeState {
        if let overridden = subscribeStates[entry.id] { return overridden }
        return subscribedFeedURLs.contains(entry.feedURL) ? .subscribed : .idle
    }

    /// Mirrors `CuratedShelf.subscribe(_:)`'s idle → subscribing → subscribed
    /// dance (for the pulse-ring animation) and `DiscoverView.subscribe(_:)`'s
    /// persistence (insert a subscribed `Podcast`).
    private func subscribe(_ entry: CuratedEntry) {
        switch subscribeState(for: entry) {
        case .idle:
            subscribeStates[entry.id] = .subscribing
            persist(entry)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                subscribeStates[entry.id] = .subscribed
            }
        case .subscribed, .subscribing:
            break
        }
    }

    private func persist(_ entry: CuratedEntry) {
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

// MARK: - Up Next tile (.pn / .pn-art / .pn-play / .pn-meta)

// Translated from design/kit/screens/home.html `.pn` / `.pn-art` / `.pn-play`
// / `.pn-meta` / `.pn-title` / `.pn-time` (the "Up Next: horizontal
// square-tile slider" rail, lines ~589-604 for the CSS, ~717-760 for the
// markup). A private struct (not a standalone file) matching this project's
// explicit-file-reference precedent — the same reason `PodcastPosterCard`
// lives inside `PodcastsScreen.swift` and `GroupedRowList` used to live here.
//
/// One `.pn` tile in the Up Next rail: a 112×112 square of artwork with a
/// centered play button, and a title/time pair beneath it. Playing fires the
/// universal intent (the caller wires `onPlay` to
/// `PlaybackIntentCoordinator.play(_:context:)`); tapping the tile body
/// anywhere else opens the episode's owning show (same "open the show" resolution
/// `HomeScreen`'s prior `.list`/`.row` translation used, since Podcast
/// Detail is keyed by `feedURL`, not by episode).
private struct UpNextTile: View {
    let episode: Episode
    let onPlay: () -> Void
    let onOpenShow: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {   // .pn { gap: 8px }
            ZStack {   // .pn-art — the play button floats centered over the artwork
                RemoteArtwork(url: artworkURL, seed: seed, initial: initial, cornerRadius: Radius.rMd16)
                    .frame(width: 112, height: 112)

                // A real `Button` on top of the tap-target below wins its own
                // hit area — same isolation `ArcCard`'s "Add all" button
                // relies on, just overlapping here instead of a sibling below.
                PlayButton(diameter: 40, accessibilityLabel: "Play \(episode.title)", action: onPlay)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenShow)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(episode.title)
            .accessibilityAddTraits(.isButton)

            VStack(alignment: .leading, spacing: 0) {   // .pn-meta
                Text(episode.title)   // .pn-title
                    .typeStyle(Typography.upNextTileTitleStyle)
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(timeLabel)   // .pn-time { margin-top: 2px }
                    .typeStyle(Typography.upNextTileTimeStyle)
                    .foregroundStyle(palette.textDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 2)
            }
        }
        .frame(width: 112, alignment: .leading)
    }

    /// "· 18 min left" — kit's exact leading-dot copy, from the episode's
    /// remaining (unplayed) whole minutes.
    private var timeLabel: String {
        let minutes = Int((episode.remainingTime / 60).rounded())
        return "· \(minutes) min left"
    }

    private var artworkURL: URL? { episode.remoteArtworkURL ?? episode.podcast?.artworkURL }

    private var seed: Int {
        episode.guid.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    }

    private var initial: String {
        guard let first = episode.title.first(where: { !$0.isWhitespace }) else { return "?" }
        return String(first).uppercased()
    }
}

// MARK: - New episode card (.ep-card / .ep-art / .ep-play / .ep-meta)

// Translated from design/kit/screens/home.html `.ep-card` / `.ep-art` /
// `.ep-play` / `.ep-meta` / `.ep-title` / `.ep-podcast` / `.ep-date` (the
// "New episodes: tall engaging carousel" rail, lines ~606-620 for the CSS,
// ~762-808 for the markup). Also a private struct, same rationale as
// `UpNextTile` above.
//
/// One `.ep-card` in the New Episodes rail: a 200×200 square of artwork with
/// a corner-pinned smart tag and a corner-pinned play button, and a
/// title/podcast/date stack beneath it. Playing fires the universal intent
/// (`PlaybackIntentCoordinator.play(_:context:)`); tapping the card body
/// anywhere else opens the episode's owning show.
private struct NewEpisodeCard: View {
    let episode: Episode
    let onPlay: () -> Void
    let onOpenShow: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {   // .ep-art
                RemoteArtwork(url: artworkURL, seed: seed, initial: initial, cornerRadius: Radius.rMd16)
                    .frame(width: 200, height: 200)

                if let tag {
                    tag
                        .padding(9)   // .ep-art .tag { top: 9px; left: 9px }
                }

                // A real `Button` on top of the tap-target below wins its own
                // hit area — same isolation `UpNextTile`'s overlaid play
                // button relies on.
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        PlayButton(diameter: 38, accessibilityLabel: "Play \(episode.title)", action: onPlay)
                    }
                }
                .padding(9)   // .ep-play { right: 9px; bottom: 9px }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenShow)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(episode.title)
            .accessibilityAddTraits(.isButton)

            VStack(alignment: .leading, spacing: 0) {   // .ep-meta { padding: --sp-2 2px 0 }
                Text(episode.title)   // .ep-title { margin-top: 4px }
                    .typeStyle(Typography.newEpisodeTitleStyle)
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 4)

                Text(podcastName)   // .ep-podcast { margin-top: 4px }
                    .typeStyle(Typography.newEpisodePodcastStyle)
                    .foregroundStyle(palette.textDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 4)

                Text(dateLabel)   // .ep-date { margin-top: 2px }
                    .typeStyle(Typography.newEpisodeDateStyle)
                    .foregroundStyle(palette.textFaint)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 2)
            .padding(.top, Spacing.sp2)
        }
        .frame(width: 200, alignment: .leading)
    }

    // MARK: - Smart tag
    //
    // Precedence: a genuinely new drop (published within the last 48h) beats
    // everything else and gets the `.hot` accent treatment; otherwise a
    // title-derived Story-arc part number (matching Detail's arc shelf); then
    // an `itunes:season`/episode number pair; otherwise no chip at all.
    private var tag: TagChip? {
        if isNew {
            return TagChip("New", style: .hot)
        } else if let arcName {
            return TagChip(arcPart.map { "\(arcName) · Part \($0)" } ?? arcName)
        } else if let season = episode.season, let episodeNumber = episode.episodeNumber {
            return TagChip("S\(season) · E\(episodeNumber)")
        } else {
            return nil
        }
    }

    private var isNew: Bool {
        Date.now.timeIntervalSince(episode.publishDate) < 48 * 60 * 60
    }

    private var arcName: String? {
        ArcDerivation.derive(fromTitle: episode.title).arcName
    }

    private var arcPart: Int? {
        ArcDerivation.derive(fromTitle: episode.title).part
    }

    private var podcastName: String { episode.podcast?.title ?? "" }

    /// "Today" / "Yesterday" / "Nd ago" — same copy `HomeFeedProvider`
    /// already derives for the (now-removed) `.list`/`.row` translation.
    private var dateLabel: String {
        HomeFeedProvider.relativeDayLabel(for: episode.publishDate)
    }

    private var artworkURL: URL? { episode.remoteArtworkURL ?? episode.podcast?.artworkURL }

    private var seed: Int {
        episode.guid.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    }

    private var initial: String {
        guard let first = episode.title.first(where: { !$0.isWhitespace }) else { return "?" }
        return String(first).uppercased()
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
private func previewContainer(populated: Bool) -> ModelContainer {
    let container = ModelSchema.previewContainer()
    guard populated else { return container }
    let context = ModelContext(container)

    let shows: [(String, String, String)] = [
        ("Behind the Bastards", "Cool Zone Media", "bastards"),
        ("Acquired", "Ben Gilbert & David Rosenthal", "acquired"),
    ]
    var podcasts: [Podcast] = []
    for (title, author, slug) in shows {
        let podcast = Podcast(
            title: title,
            author: author,
            feedURL: URL(string: "https://feeds.example.com/\(slug)")!,
            isSubscribed: true
        )
        context.insert(podcast)
        podcasts.append(podcast)
    }

    let episodes = [
        Episode(guid: "home-1", title: "The Fall of the Grifter King", publishDate: .now, duration: 2520, audioURL: URL(string: "https://cdn.example.com/1.mp3")!, playbackProgress: 0.4, podcast: podcasts[0]),
        Episode(guid: "home-2", title: "Building Acquired, Episode 300", publishDate: Date(timeIntervalSinceNow: -86_400), duration: 3600, audioURL: URL(string: "https://cdn.example.com/2.mp3")!, podcast: podcasts[1]),
        Episode(guid: "home-3", title: "A Bonus Episode", publishDate: Date(timeIntervalSinceNow: -2 * 86_400), duration: 1800, audioURL: URL(string: "https://cdn.example.com/3.mp3")!, podcast: podcasts[0]),
    ]
    for episode in episodes { context.insert(episode) }
    context.insert(QueueItem(order: 0, episode: episodes[0]))
    context.insert(QueueItem(order: 1, episode: episodes[1]))

    try? context.save()
    return container
}

@MainActor
private func previewQueueStore(populated: Bool) -> QueueStore {
    QueueStore(context: ModelContext(previewContainer(populated: populated)))
}

#Preview("Home — populated (dark)") {
    let queueStore = previewQueueStore(populated: true)
    let playbackEngine = PlaybackEngine(localURLResolver: { _ in nil })
    let downloadManager = DownloadManager()
    HomeScreen()
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .environment(queueStore)
        .environment(playbackEngine)
        .environment(PlaybackIntentCoordinator(playbackEngine: playbackEngine, downloadManager: downloadManager, queueStore: queueStore))
        .modelContainer(previewContainer(populated: true))
}

#Preview("Home — populated (light)") {
    let queueStore = previewQueueStore(populated: true)
    let playbackEngine = PlaybackEngine(localURLResolver: { _ in nil })
    let downloadManager = DownloadManager()
    HomeScreen()
        .themedPalette()
        .environment(\.colorScheme, .light)
        .environment(queueStore)
        .environment(playbackEngine)
        .environment(PlaybackIntentCoordinator(playbackEngine: playbackEngine, downloadManager: downloadManager, queueStore: queueStore))
        .modelContainer(previewContainer(populated: true))
}

#Preview("Home — empty (dark)") {
    let queueStore = previewQueueStore(populated: false)
    let playbackEngine = PlaybackEngine(localURLResolver: { _ in nil })
    let downloadManager = DownloadManager()
    HomeScreen()
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .environment(queueStore)
        .environment(playbackEngine)
        .environment(PlaybackIntentCoordinator(playbackEngine: playbackEngine, downloadManager: downloadManager, queueStore: queueStore))
        .modelContainer(previewContainer(populated: false))
}
#endif
