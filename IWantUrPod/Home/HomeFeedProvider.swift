// Composed from docs/design/direction.md tokens — no design/kit source of its
// own (this is the testable data seam behind design/kit/screens/home.html;
// see HomeScreen.swift for the screen itself). Mirrors
// `IWantUrPod/Library/PodcastsListProvider.swift`'s precedent: filter/sort
// logic factored out of the screen so it can be exercised directly, and — per
// that file's header note — no `#Predicate` on a relationship keypath (avoids
// the non-`Sendable` `KeyPath` warning/error under this project's strict
// concurrency setting). Screens fetch the full `[Episode]`/`[Podcast]` sets
// via `@Query` (sorted only) and hand them to the pure functions below.
import Foundation
import PodcastModels
import DirectoryKit

@MainActor
public enum HomeFeedProvider {

    // MARK: - New episodes shelf

    /// The newest episodes across every **subscribed** show, newest
    /// `publishDate` first, capped at `limit`. ROADMAP.md E8-S2's
    /// "new-episodes shelf".
    public static func recentEpisodes(from episodes: [Episode], limit: Int = 8) -> [Episode] {
        episodes
            .filter { $0.podcast?.isSubscribed == true }
            .sorted { $0.publishDate > $1.publishDate }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Curated bundle load (mirrors DiscoverViewModel's glue)

    /// Loads the bundled curated list via DirectoryKit's pure
    /// `CuratedListLoader` — same two-line bundle-lookup glue
    /// `DiscoverViewModel.loadCuratedEntries(from:)` uses (per
    /// `CuratedEntry.swift`'s doc comment: "the app owns the bundle I/O",
    /// so each consuming screen does its own lookup rather than sharing a
    /// loaded-entries cache). The actual parsing/skip-malformed behavior
    /// lives once, in `CuratedListLoader` — not duplicated here.
    public static func loadCuratedEntries(from bundle: Bundle = .main) -> [CuratedEntry] {
        guard
            let url = bundle.url(forResource: "curated-start-here", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
            return []
        }
        return CuratedListLoader.load(from: data)
    }

    // MARK: - Row copy helpers

    /// "18 min left" once playback has started, else "42 min" for the full
    /// duration — matches `home.html`'s two Up Next peek rows exactly (one
    /// mid-episode, one untouched). `nil` when the duration is unknown (`0`),
    /// so the row simply omits the trailing detail instead of showing "0 min".
    public static func durationLabel(for episode: Episode) -> String? {
        guard episode.duration > 0 else { return nil }
        if episode.playbackProgress > 0 && !episode.isPlayed {
            let minutes = Int((episode.remainingTime / 60).rounded())
            return "\(minutes) min left"
        }
        let minutes = Int((episode.duration / 60).rounded())
        return "\(minutes) min"
    }

    /// "Today" / "Yesterday" / "Nd ago" — matches `home.html`'s New Episodes
    /// row copy (`Today`, `Yesterday`, `2d ago`) rather than
    /// `RelativeDateTimeFormatter`'s wordier "2 days ago".
    public static func relativeDayLabel(for date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let startOfThat = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startOfThat, to: startOfToday).day ?? 0

        switch days {
        case ..<0, 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(days)d ago"
        }
    }
}
