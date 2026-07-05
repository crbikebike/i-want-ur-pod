// Composed from docs/design/direction.md tokens — no design/kit source (see
// design/kit/MANIFEST.md). ROADMAP.md E3-S1: the Podcasts tab lists the
// user's subscribed shows, newest `dateAdded` first, each row pushing its
// `feedURL` into the same adaptive Podcast Detail screen (E2) the Discover
// tab and search results use (navigation-map.md — "Podcasts (E3) → subscribed
// row → Podcast Detail (E2, subscribed state)").
//
// Mirrors `IWantUrPod/Detail/PodcastDetailView.swift`'s row style (a
// `RemoteArtwork` + title/author `VStack`, composed from tokens — no kit row
// mock exists; see MANIFEST.md's note that the kit's only flat-row pattern
// is a dead/superseded skeleton with no consumer) rather than reusing the
// Discover shelf/grid components, since this is a plain vertical list, not a
// horizontal rail or 2-up poster grid.
import SwiftUI
import SwiftData
import DesignSystem
import PodcastModels

/// The Podcasts tab: every subscribed show, newest-first. Owns its own
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
            Group {
                if subscribedPodcasts.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(palette.groupedBg.ignoresSafeArea())
            // Draws its own large title below, matching Discover's root
            // screen — pushed destinations (Podcast Detail) show their own.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: URL.self) { feedURL in
                PodcastDetailScreen(feedURL: feedURL)
            }
        }
    }

    // MARK: - Populated list

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleBar
                    .padding(.top, Spacing.sp5)
                    .padding(.bottom, Spacing.sp5)

                VStack(spacing: Spacing.sp4) {
                    ForEach(subscribedPodcasts, id: \.id) { podcast in
                        Button {
                            path.append(podcast.feedURL)
                        } label: {
                            PodcastRow(podcast: podcast)
                        }
                        .buttonStyle(.plain)

                        if podcast.id != subscribedPodcasts.last?.id {
                            Divider().overlay(palette.hairline)
                        }
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
                    message: "Subscribe to a show from Discover and it'll show up here."
                ) {
                    EmptyView()
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, AppShell.tabBarReservedPadding)
            .frame(maxWidth: .infinity, minHeight: 500, alignment: .top)
        }
    }

    // MARK: - Large title (mirrors DiscoverView's `.titlewrap` / h1.big)

    private var titleBar: some View {
        Text("Podcasts")
            .typeStyle(Typography.displayLargeTitleStyle)
            .foregroundStyle(palette.text)
            .padding(.horizontal, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Podcast row

/// One subscribed show: artwork + title + author. Same shape as
/// `PodcastDetailView`'s `EpisodeRow` (a `RemoteArtwork` tile beside a
/// leading title/author `VStack`) scaled down to a compact 60pt row.
private struct PodcastRow: View {
    let podcast: Podcast

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sp3) {
            RemoteArtwork(url: podcast.artworkURL, seed: seed, initial: initial)
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.sp1) {
                Text(podcast.title)
                    .typeStyle(Typography.rowTitleStyle)
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !podcast.author.isEmpty {
                    Text(podcast.author)
                        .typeStyle(Typography.subheadStyle)
                        .foregroundStyle(palette.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textFaint)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.sp2)
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
