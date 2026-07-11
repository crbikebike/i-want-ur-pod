// Composed from docs/design/direction.md tokens, matched exactly against
// design/kit/screens/shows.html's `.cardgrid` of `.pod` poster cards.
// ROADMAP.md E3-S1: the Podcasts tab lists the user's subscribed shows,
// alphabetized by title, each card pushing its `feedURL` into the same
// adaptive Podcast Detail screen (E2) the search takeover uses
// (navigation-map.md — "Podcasts (E3) → subscribed card → Podcast Detail
// (E2, subscribed state)").
//
// ROADMAP.md E8-S3: the dock IA renames this surface "Shows" (label + large
// title only — no route/model/persisted-state changes). E8-S4 adds the
// top-right gear pushing `SettingsScreen()`, matching Home's `.util-gear`.
//
// A 2-up `LazyVGrid` of `PodcastPosterCard`s (`.pod-art` square artwork +
// `.pod-meta` title/author, gap `--sp-3` between cards) — the kit's own
// `.cardgrid`/`.pod` pattern for "Your shows", not a flat row list.
import SwiftUI
import SwiftData
import DesignSystem
import PodcastModels

/// The Podcasts tab: every subscribed show, alphabetized. Owns its own
/// `NavigationStack` (per the frozen nav contract — `AppShell`'s tab switch
/// stays a pure view switch) and reserves the floating tab bar's 104pt gap.
public struct PodcastsScreen: View {
    /// Live SwiftData query, sorted only (no predicate — see
    /// `PodcastsListProvider`'s header for why a `#Predicate` on
    /// `isSubscribed` is avoided). The subscribed-only filter is applied by
    /// `PodcastsListProvider.sortedSubscribed`, which also backs the
    /// `ModelContext`-based entry point the tests exercise directly.
    @Query(sort: \Podcast.dateAdded, order: .reverse) private var allPodcasts: [Podcast]

    @State private var path = NavigationPath()

    @Environment(\.palette) private var palette

    public init() {}

    private var subscribedPodcasts: [Podcast] {
        PodcastsListProvider.sortedSubscribed(allPodcasts)
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if subscribedPodcasts.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }

                SettingsGearButton { path.append(SettingsRoute.settings) }
                    .padding(.top, Spacing.sp5)
                    .padding(.trailing, Spacing.gutter)
            }
            .background(palette.groupedBg.ignoresSafeArea())
            // Draws its own large title below, matching the search takeover's
            // root — pushed destinations (Podcast Detail) show their own.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: URL.self) { feedURL in
                PodcastDetailScreen(feedURL: feedURL)
            }
            .navigationDestination(for: SettingsRoute.self) { _ in
                SettingsScreen()
            }
        }
    }

    // MARK: - Populated grid

    /// Two flexible columns, `--sp-3` gap on both axes — `.cardgrid { grid-
    /// template-columns: 1fr 1fr; gap: var(--sp-3) }`.
    private static let gridColumns = [
        GridItem(.flexible(), spacing: Spacing.sp3),
        GridItem(.flexible(), spacing: Spacing.sp3)
    ]

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleBar
                    .padding(.top, Spacing.sp5)
                    .padding(.bottom, Spacing.sp5)

                LazyVGrid(columns: Self.gridColumns, spacing: Spacing.sp3) {
                    ForEach(subscribedPodcasts, id: \.id) { podcast in
                        Button {
                            path.append(podcast.feedURL)
                        } label: {
                            PodcastPosterCard(podcast: podcast)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, AppShell.tabBarReservedPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleBar
                    .padding(.top, Spacing.sp5)

                EmptyStateView(
                    kind: .firstRun,
                    title: "No shows yet",
                    message: "Subscribe to a show from Search and it'll show up here."
                ) {
                    EmptyView()
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, AppShell.tabBarReservedPadding)
            .frame(maxWidth: .infinity, minHeight: 500, alignment: .top)
        }
    }

    // MARK: - Large title (shows.html's `.titlewrap` / h1.big; `padding-right:
    // 52px` reserves room for the floating gear on the same row)

    private var titleBar: some View {
        Text("Shows")
            .typeStyle(Typography.displayLargeTitleStyle)
            .foregroundStyle(palette.text)
            .padding(.horizontal, 2)
            .padding(.trailing, 50)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Podcast poster card

/// One subscribed show as a poster tile: square artwork over a title/author
/// meta block — `shows.html`'s `.pod` (`.pod-art` + `.pod-meta`). No
/// subscribe control (unlike the Discover/Search `PodCard`): everything in
/// this grid is already subscribed.
private struct PodcastPosterCard: View {
    let podcast: Podcast

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {   // .pod { gap: 9px }
            RemoteArtwork(url: podcast.artworkURL, seed: seed, initial: initial, cornerRadius: Radius.rMd16)
                .overlay {
                    // .pod-art { box-shadow: inset 0 0 0 .5px rgba(255,255,255,.16), ... }
                    // — the app's existing inset-hairline idiom (SettingsGearButton,
                    // SourcesChecklistRow) stands in for the kit's literal white
                    // inset + drop shadow rather than a new one-off shadow token.
                    RoundedRectangle(cornerRadius: Radius.rMd16, style: .continuous)
                        .strokeBorder(palette.hairline, lineWidth: 0.5)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {   // .pod-meta, .pod-studio margin-top: 3px
                Text(podcast.title)
                    .typeStyle(Typography.showCardTitleStyle)   // .pod-title
                    .foregroundStyle(palette.text)
                    // Reserve two lines even for 1-line titles so every card is
                    // the same height and the grid rows stay aligned (a 1-line
                    // title next to a 2-line one otherwise makes the grid ragged).
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !podcast.author.isEmpty {
                    Text(podcast.author)
                        .typeStyle(Typography.showCardStudioStyle)   // .pod-studio
                        .foregroundStyle(palette.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 2)   // .pod-meta { padding: 0 2px }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(podcast.title), \(podcast.author)")
    }

    private var seed: Int {
        podcast.feedURL.absoluteString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    }

    private var initial: String {
        guard let first = podcast.title.first(where: { !$0.isWhitespace }) else { return "?" }
        return String(first).uppercased()
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
private func previewContainer(withSubscriptions: Bool) -> ModelContainer {
    let container = ModelSchema.previewContainer()
    if withSubscriptions {
        let context = ModelContext(container)
        let shows: [(String, String, TimeInterval)] = [
            ("Behind the Bastards", "Cool Zone Media", 3_000),
            ("Acquired", "Ben Gilbert & David Rosenthal", 2_000),
            ("99% Invisible", "Roman Mars", 1_000)
        ]
        for (title, author, offset) in shows {
            let podcast = Podcast(
                title: title,
                author: author,
                feedURL: URL(string: "https://feeds.example.com/\(title.replacingOccurrences(of: " ", with: "-"))")!,
                isSubscribed: true,
                dateAdded: Date(timeIntervalSince1970: offset)
            )
            context.insert(podcast)
        }
        try? context.save()
    }
    return container
}

#Preview("Podcasts — populated (dark)") {
    PodcastsScreen()
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .modelContainer(previewContainer(withSubscriptions: true))
}

#Preview("Podcasts — populated (light)") {
    PodcastsScreen()
        .themedPalette()
        .environment(\.colorScheme, .light)
        .modelContainer(previewContainer(withSubscriptions: true))
}

#Preview("Podcasts — empty (dark)") {
    PodcastsScreen()
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .modelContainer(previewContainer(withSubscriptions: false))
}

#Preview("Podcasts — empty (light)") {
    PodcastsScreen()
        .themedPalette()
        .environment(\.colorScheme, .light)
        .modelContainer(previewContainer(withSubscriptions: false))
}
#endif
