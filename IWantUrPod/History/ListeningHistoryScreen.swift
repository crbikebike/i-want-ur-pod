// Translated from design/kit/screens/listening-history.html — a PUSHED
// screen reached from Settings' new "History" row (settings.html's
// `.srow-history`; see `SettingsScreen.swift`'s `historySection`). Like
// `SettingsScreen` itself, this is pushed inside whichever tab's
// `NavigationStack` the gear was tapped from, so it gets the system back
// chevron rather than a hand-drawn "Done" button — the kit's `.done-btn` is
// explicitly noted as "same push pattern as settings.html itself", and
// `SettingsScreen.swift` already established that pattern degrades to the
// system chevron (no literal Done button in Swift).
//
// Content: `h1.big` title, then the reverse-chronological log grouped by day
// (`.lh-daygroup`/`.lh-daylabel`) built on `ListeningHistoryProvider.groupedByDay`,
// each row (`.lh-row`) an artwork tile + episode/podcast title stack + an
// optional "Played N×" chip (`.lh-playcount`) + a trailing "when"/duration
// stack (`.lh-trail`). The empty state is `EmptyStateView` (clock glyph over
// the grape→coral `.badge-empty` gradient) + a `NeutralButton` ("Browse your
// shows" — kit's `.btn-secondary`, a chip fill, matches `NeutralButton`'s
// variant, not `SecondaryButton`'s accent outline). The kit's intro `.lede`
// and closing `.foot-note` were dropped as unnecessary (per user).
import SwiftUI
import SwiftData
import PodcastModels
import DesignSystem

public struct ListeningHistoryScreen: View {
    /// Sort-only `@Query` (this repo's convention: never filter/group in a
    /// `#Predicate`) — grouping and play-count derivation happen in plain
    /// Swift via `ListeningHistoryProvider`.
    @Query(sort: \PlayEvent.playedAt, order: .reverse) private var events: [PlayEvent]

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    public init() {}

    private var daySections: [ListeningHistoryProvider.DaySection] {
        ListeningHistoryProvider.groupedByDay(events)
    }

    private var playCounts: [String: Int] {
        ListeningHistoryProvider.playCounts(for: events)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleBar

                if events.isEmpty {
                    emptyState
                        .padding(.top, Spacing.sp6)
                } else {
                    ForEach(daySections) { section in
                        daygroup(section)
                            .padding(.top, section.id == daySections.first?.id ? Spacing.sp3 : Spacing.sp6)
                    }
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.top, Spacing.sp4)
            .padding(.bottom, AppShell.tabBarReservedPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.groupedBg.ignoresSafeArea())
        // Pushed screen, same chrome precedent as SettingsScreen: system back
        // chevron, no duplicate UIKit nav title (this screen draws its own
        // `h1.big` below).
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .navigationDestination(for: URL.self) { feedURL in
            PodcastDetailScreen(feedURL: feedURL)
        }
    }

    // MARK: - Header (h1.big "Listening history")

    private var titleBar: some View {
        Text("Listening history")
            .typeStyle(Typography.displayLargeTitleStyle)
            .foregroundStyle(palette.text)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 2)
    }

    // MARK: - Day group (.lh-daygroup / .lh-daylabel / .lh-list)

    private func daygroup(_ section: ListeningHistoryProvider.DaySection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.label)
                .typeStyle(Typography.groupLabelStyle)
                .foregroundStyle(palette.textFaint)
                .padding(.horizontal, Spacing.sp4)
                .padding(.bottom, Spacing.sp2)
                .frame(maxWidth: .infinity, alignment: .leading)

            GroupedList(items: section.events, id: \.id) { event in
                row(for: event)
            }
        }
    }

    // MARK: - Row (.lh-row)

    /// A `NavigationLink(value:)` targeting this screen's own
    /// `.navigationDestination(for: URL.self)` when `event.feedURL` is
    /// known (mirrors `HomeScreen`/`PodcastsScreen`/`SearchScreen`'s
    /// identical per-screen `URL`-keyed destination, each independently
    /// declared rather than shared). Rows with no captured feed URL render
    /// the same content but aren't tappable.
    @ViewBuilder
    private func row(for event: PlayEvent) -> some View {
        if let feedURL = event.feedURL {
            NavigationLink(value: feedURL) {
                rowContent(for: event)
            }
            .buttonStyle(.plain)
        } else {
            rowContent(for: event)
        }
    }

    private func rowContent(for event: PlayEvent) -> some View {
        Group {
            HStack(alignment: .center, spacing: Spacing.sp3) {
                RemoteArtwork(url: event.artworkURL, seed: seed(for: event), initial: initial(for: event))
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.sp1) {
                    Text(event.episodeTitle)
                        .typeStyle(Typography.rowTitleStyle)
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(event.podcastTitle)
                        .typeStyle(Typography.subheadStyle)
                        .foregroundStyle(palette.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if playCount(for: event) > 1 {
                        playCountChip(playCount(for: event))
                            .padding(.top, 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(HomeFeedProvider.relativeDayLabel(for: event.playedAt))
                        .typeStyle(Typography.lhWhenLabelStyle)
                        .foregroundStyle(palette.text)
                        .lineLimit(1)

                    Text(ListeningHistoryProvider.listenedDurationLabel(forSeconds: event.listenedSeconds))
                        .typeStyle(Typography.lhDurationLabelStyle)
                        .foregroundStyle(palette.textFaint)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.vertical, Spacing.sp3)
            .padding(.horizontal, Spacing.sp4)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: event))
    }

    // MARK: - Play-count chip (.lh-playcount "Played N×")

    private func playCountChip(_ count: Int) -> some View {
        Text("Played \(count)\u{00d7}")
            .typeStyle(Typography.playCountLabelStyle)
            .foregroundStyle(palette.accent2)
            .padding(.vertical, 2)
            .padding(.horizontal, 8)
            .background(
                Capsule(style: .continuous).fill(palette.accent2.opacity(0.15))
            )
    }

    // MARK: - Empty state (.lh-empty)

    private var emptyState: some View {
        EmptyStateView(
            kind: .noResults,   // grape→coral badge gradient, matching the kit's `.badge-empty`
            title: "No listening history yet",
            message: "Episodes you play will show up here, along with how long you listened.",
            systemImage: "clock"   // kit's clock glyph, over the grape→coral badge
        ) {
            // This screen has no direct route to the Shows tab (it's pushed
            // inside whichever tab's stack the Settings gear was tapped
            // from, same as `SettingsScreen`) — the closest honest action is
            // popping back to Settings, from which every tab is reachable.
            NeutralButton(title: "Browse your shows") {
                dismiss()
            }
        }
    }

    // MARK: - Row helpers

    private func playCount(for event: PlayEvent) -> Int {
        playCounts[ListeningHistoryProvider.playCountKey(for: event)] ?? 0
    }

    private func seed(for event: PlayEvent) -> Int {
        (event.episodeGUID ?? event.episodeTitle).unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    }

    private func initial(for event: PlayEvent) -> String {
        guard let first = event.episodeTitle.first(where: { !$0.isWhitespace }) else { return "?" }
        return String(first).uppercased()
    }

    private func accessibilityLabel(for event: PlayEvent) -> String {
        var label = "\(event.episodeTitle), \(event.podcastTitle), \(HomeFeedProvider.relativeDayLabel(for: event.playedAt)), \(ListeningHistoryProvider.listenedDurationLabel(forSeconds: event.listenedSeconds))"
        let count = playCount(for: event)
        if count > 1 {
            label += ", played \(count) times"
        }
        return label
    }

}

// MARK: - Preview

#if DEBUG
@MainActor
private func previewContainer(populated: Bool) -> ModelContainer {
    let container = ModelSchema.previewContainer()
    guard populated else { return container }
    let context = ModelContext(container)

    let now = Date.now
    let calendar = Calendar.current
    func daysAgo(_ n: Int) -> Date {
        calendar.date(byAdding: .day, value: -n, to: now) ?? now
    }

    let dailyFeed = URL(string: "https://feeds.example.com/the-daily")!
    let songExploderFeed = URL(string: "https://feeds.example.com/song-exploder")!
    let hertzFeed = URL(string: "https://feeds.example.com/20k-hertz")!
    let acquiredFeed = URL(string: "https://feeds.example.com/acquired")!
    let boneValleyFeed = URL(string: "https://feeds.example.com/bone-valley")!
    let restIsHistoryFeed = URL(string: "https://feeds.example.com/rest-is-history")!
    let ninetyninePIFeed = URL(string: "https://feeds.example.com/99pi")!

    let sample: [PlayEvent] = [
        PlayEvent(playedAt: daysAgo(0), listenedSeconds: 24 * 60, episodeTitle: "The Fed's Next Move", podcastTitle: "The Daily", feedURL: dailyFeed, episodeGUID: "daily-fed"),
        PlayEvent(playedAt: daysAgo(0), listenedSeconds: 48 * 60, episodeTitle: "Cold Open, Warm Ending", podcastTitle: "Song Exploder", feedURL: songExploderFeed, episodeGUID: "se-cold-open"),
        PlayEvent(playedAt: daysAgo(1), listenedSeconds: 42 * 60, episodeTitle: "The Sample-Rate Wars", podcastTitle: "Twenty Thousand Hertz", feedURL: hertzFeed, episodeGUID: "20k-sample-rate"),
        PlayEvent(playedAt: daysAgo(1), listenedSeconds: 72 * 60, episodeTitle: "Building Acquired, Episode 300", podcastTitle: "Acquired", feedURL: acquiredFeed, episodeGUID: "acquired-300"),
        PlayEvent(playedAt: daysAgo(3), listenedSeconds: 11 * 60, episodeTitle: "Cold Open, Warm Ending", podcastTitle: "Song Exploder", feedURL: songExploderFeed, episodeGUID: "se-cold-open"),
        PlayEvent(playedAt: daysAgo(3), listenedSeconds: 39 * 60, episodeTitle: "The Sardine Collapse", podcastTitle: "Bone Valley", feedURL: boneValleyFeed, episodeGUID: "bone-valley-sardine"),
        PlayEvent(playedAt: daysAgo(6), listenedSeconds: 58 * 60, episodeTitle: "Rome's Last Good Emperor", podcastTitle: "The Rest Is History", feedURL: restIsHistoryFeed, episodeGUID: "rih-rome"),
        PlayEvent(playedAt: daysAgo(7), listenedSeconds: 31 * 60, episodeTitle: "The Beauty of Bike Lanes", podcastTitle: "99% Invisible", feedURL: ninetyninePIFeed, episodeGUID: "99pi-bike-lanes"),
    ]
    for event in sample { context.insert(event) }
    try? context.save()
    return container
}

#Preview("Listening history — populated (dark)") {
    NavigationStack {
        ListeningHistoryScreen()
    }
    .themedPalette()
    .environment(\.colorScheme, .dark)
    .modelContainer(previewContainer(populated: true))
}

#Preview("Listening history — populated (light)") {
    NavigationStack {
        ListeningHistoryScreen()
    }
    .themedPalette()
    .environment(\.colorScheme, .light)
    .modelContainer(previewContainer(populated: true))
}

#Preview("Listening history — empty (dark)") {
    NavigationStack {
        ListeningHistoryScreen()
    }
    .themedPalette()
    .environment(\.colorScheme, .dark)
    .modelContainer(previewContainer(populated: false))
}

#Preview("Listening history — empty (light)") {
    NavigationStack {
        ListeningHistoryScreen()
    }
    .themedPalette()
    .environment(\.colorScheme, .light)
    .modelContainer(previewContainer(populated: false))
}
#endif
