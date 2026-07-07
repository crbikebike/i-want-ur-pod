// Translated from design/kit/screens/home.html (its bespoke content: the
// large "Home" title with pulse-dot, the top-right `.util-gear` Settings
// button, the "Up Next" and "New episodes" `.sec-head`/`.list`/`.row` groups,
// and the "Shows for you"/"Our favorites" `.shelf`/`.rail`/`.pod` shelves —
// see design/kit/MANIFEST.md's "Home / Shows / Up Next screens" entry; the
// `.tabbar`/`.statusbar`/`.notch`/theme-toggle chrome is the shared kit frame
// AppShell + LiquidGlassTabBar already own, not re-translated here).
//
// ROADMAP.md E8-S2: Home replaces Discover as the first tab destination.
// Renders four sections in kit order — an Up Next peek, a New episodes
// shelf, a Shows-for-you shelf, and an Our-favorites shelf — each rendering
// nothing (no header, no empty chrome) when it has no content. Data sources:
//   - Up Next peek:     the shared `QueueStore` (E5), first few queued items.
//   - New episodes:     `HomeFeedProvider.recentEpisodes` over every
//                        subscribed show's episodes (SwiftData `@Query`).
//   - Shows for you:     the bundled curated list, minus already-subscribed
//                        shows — an honest degrade; see
//                        `HomeFeedProvider.recommendedEntries`'s doc comment
//                        for why (no personalization signal exists yet).
//   - Our favorites:     the bundled curated list, unfiltered (E1-S2's
//                        `curated-start-here.json`, loaded via the same
//                        `CuratedListLoader` DiscoverViewModel uses — not
//                        duplicated, just re-invoked; see
//                        `HomeFeedProvider.loadCuratedEntries`).
// Tapping any show (Up Next peek's owning show, a New-episodes row, or a
// shelf card) pushes its `feedURL` into the same `PodcastDetailScreen` (E2)
// every other screen uses. The top-right gear pushes the existing
// `SettingsScreen()` (E8-S4's entry point).
//
// Kit's `.see-all` trailing links on the Up Next/New-episodes headers are not
// wired to a destination — no "queue" or "all new episodes" screen exists in
// scope (Up Next itself is one tab away, already reachable) — so this
// translation omits them rather than shipping a dead link; `SectionHeader`'s
// title-only variant is used instead of a bespoke header.
import SwiftUI
import SwiftData
import DesignSystem
import DirectoryKit
import PodcastModels

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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette

    @State private var path = NavigationPath()
    @State private var curatedEntries: [CuratedEntry] = []
    /// Transient subscribe-button animation state, keyed by `CuratedEntry.id`
    /// (its feedURL string) — shared across both curated shelves so
    /// subscribing from either one updates the other's card identically.
    @State private var subscribeStates: [String: SubscribeState] = [:]

    /// Gates the once-only first-run explainer (E1-S1). Now shown before Home
    /// (the dock IA's first destination) rather than Discover — Settings'
    /// reset control clears the same `UserDefaults` key this reads on appear.
    private let firstRunGate = FirstRunGate()
    @State private var showFirstRunExplainer = false

    public init() {}

    // MARK: - Derived data

    private var subscribedFeedURLs: Set<URL> {
        Set(allPodcasts.filter(\.isSubscribed).map(\.feedURL))
    }

    private var upNextPeekItems: [QueueItem] {
        Array(queueStore.items.prefix(3))
    }

    private var recentEpisodes: [Episode] {
        HomeFeedProvider.recentEpisodes(from: allEpisodes)
    }

    private var recommendedEntries: [CuratedEntry] {
        HomeFeedProvider.recommendedEntries(from: curatedEntries, subscribedFeedURLs: subscribedFeedURLs)
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .topTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        titleBar

                        upNextPeekSection
                        newEpisodesSection
                        showsForYouSection
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
        }
        .onAppear {
            queueStore.reload()
            if curatedEntries.isEmpty {
                curatedEntries = HomeFeedProvider.loadCuratedEntries()
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

    // MARK: - Up Next peek (.sec-head "Up Next" / .list)

    @ViewBuilder
    private var upNextPeekSection: some View {
        if !upNextPeekItems.isEmpty {
            SectionHeader(title: "Up Next")

            GroupedRowList(items: upNextPeekItems, onSelect: openQueueItem) { item in
                if let episode = item.episode {
                    EpisodeRowContent(
                        episode: episode,
                        subtitle: upNextSubtitle(for: episode)
                    )
                }
            }
        }
    }

    private func upNextSubtitle(for episode: Episode) -> String {
        let show = episode.podcast?.title ?? ""
        guard let duration = HomeFeedProvider.durationLabel(for: episode) else { return show }
        return show.isEmpty ? duration : "\(show) · \(duration)"
    }

    /// Up Next peek rows open the queued episode's show detail — the E2
    /// screen is keyed by `feedURL`, not by episode, so "open the episode"
    /// resolves to its owning show's Podcast Detail (acceptable per E8-S2's
    /// criterion: "opens the E2 Podcast Detail (or the episode...)").
    private func openQueueItem(_ item: QueueItem) {
        guard let feedURL = item.episode?.podcast?.feedURL else { return }
        path.append(feedURL)
    }

    // MARK: - New episodes (.sec-head "New episodes" / .list)

    @ViewBuilder
    private var newEpisodesSection: some View {
        if !recentEpisodes.isEmpty {
            SectionHeader(title: "New episodes")

            GroupedRowList(items: recentEpisodes, onSelect: openEpisodeShow) { episode in
                EpisodeRowContent(episode: episode, subtitle: newEpisodeSubtitle(for: episode))
            }
        }
    }

    private func newEpisodeSubtitle(for episode: Episode) -> String {
        let show = episode.podcast?.title ?? ""
        let when = HomeFeedProvider.relativeDayLabel(for: episode.publishDate)
        return show.isEmpty ? when : "\(show) · \(when)"
    }

    private func openEpisodeShow(_ episode: Episode) {
        guard let feedURL = episode.podcast?.feedURL else { return }
        path.append(feedURL)
    }

    // MARK: - Shows for you (.shelf "Shows for you")

    @ViewBuilder
    private var showsForYouSection: some View {
        if !recommendedEntries.isEmpty {
            curatedShelf(title: "Shows for you", entries: recommendedEntries)
                .padding(.top, Spacing.sp6)
        }
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
            itemArtwork: { ArtworkStyle(seed: seed(for: $0)) }
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

// MARK: - Grouped row list (.list / .row)

/// The kit's `.list`/`.row` grouped-inset-list surface: a rounded `surface`
/// card containing plain rows separated by inset hairlines, mirroring
/// `PodcastsScreen`'s row shape but grouped into one elevated card (as
/// `home.html`'s Up Next/New-episodes sections render, rather than
/// `PodcastsScreen`'s bare vertical stack).
private struct GroupedRowList<Item, RowContent: View>: View {
    let items: [Item]
    let onSelect: (Item) -> Void
    let row: (Item) -> RowContent

    @Environment(\.palette) private var palette

    init(
        items: [Item],
        onSelect: @escaping (Item) -> Void,
        @ViewBuilder row: @escaping (Item) -> RowContent
    ) {
        self.items = items
        self.onSelect = onSelect
        self.row = row
    }

    var body: some View {
        VStack(spacing: 0) {
            // `Item` here is a SwiftData `@Model` (Episode/QueueItem), which
            // does not conform to `Identifiable` in this codebase (see
            // `PodcastsScreen`/`UpNextScreen`'s precedent of always passing an
            // explicit `id:` to `ForEach` rather than relying on it) — index
            // the array instead of requiring an `Identifiable` constraint.
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    onSelect(item)
                } label: {
                    row(item)
                        .padding(.horizontal, Spacing.sp4)
                        .padding(.vertical, Spacing.sp3)
                }
                .buttonStyle(.plain)

                if index != items.count - 1 {
                    Divider()
                        .overlay(palette.separator)
                        .padding(.leading, Spacing.sp4 + 60 + Spacing.sp3)
                }
            }
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
        .elevList(hairline: palette.hairline)
    }
}

// MARK: - Episode row content (.art / .rtitle / .rauthor)

/// One `.row`: a 60pt `RemoteArtwork` tile beside a title + single subtitle
/// line — shared by the Up Next peek and New-episodes sections (their only
/// difference is what the caller composes into `subtitle`).
private struct EpisodeRowContent: View {
    let episode: Episode
    let subtitle: String

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sp3) {
            RemoteArtwork(url: artworkURL, seed: seed, initial: initial)
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(episode.title)
                    .typeStyle(Typography.rowTitleStyle)
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .typeStyle(Typography.subheadStyle)
                        .foregroundStyle(palette.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle.isEmpty ? episode.title : "\(episode.title). \(subtitle)")
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
    HomeScreen()
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .environment(previewQueueStore(populated: true))
        .modelContainer(previewContainer(populated: true))
}

#Preview("Home — populated (light)") {
    HomeScreen()
        .themedPalette()
        .environment(\.colorScheme, .light)
        .environment(previewQueueStore(populated: true))
        .modelContainer(previewContainer(populated: true))
}

#Preview("Home — empty (dark)") {
    HomeScreen()
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .environment(previewQueueStore(populated: false))
        .modelContainer(previewContainer(populated: false))
}
#endif
