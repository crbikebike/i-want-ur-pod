// Composed from docs/design/direction.md tokens — no design/kit source (see
// design/kit/MANIFEST.md). The testable seam behind the Shows tab
// (ROADMAP.md E3-S1, alpha-sorted per the shows.html poster grid):
// subscribed-filtering + alphabetical-sort logic lives here rather than in
// `PodcastsScreen`, so it can be exercised directly against a `ModelContext`
// (see `IWantUrPodTests/PodcastsListProviderTests.swift`).
import Foundation
import SwiftData
import PodcastModels

/// Resolves the Shows tab's poster-grid list: every subscribed `Podcast`,
/// alphabetized by title (article-insensitive, diacritic-insensitive).
///
/// A `#Predicate { $0.isSubscribed }` triggers a non-`Sendable` `KeyPath`
/// warning under this project's `SWIFT_STRICT_CONCURRENCY: complete` setting
/// (an error under Swift 6) — see `PodcastDetailViewModelTests.swift` for the
/// same precedent. Both entry points below fetch (or are handed) the full
/// `[Podcast]` set and filter/sort in plain Swift instead.
@MainActor
public enum PodcastsListProvider {
    /// Fetches every `Podcast` from `context` and returns the subscribed
    /// ones, alphabetized by title.
    public static func subscribedPodcasts(from context: ModelContext) throws -> [Podcast] {
        let all = try context.fetch(FetchDescriptor<Podcast>())
        return sortedSubscribed(all)
    }

    /// The pure filter + sort, factored out so a live `@Query` result set
    /// (already fetched by SwiftUI) can reuse the exact same logic the
    /// `ModelContext`-based entry point above uses.
    public static func sortedSubscribed(_ podcasts: [Podcast]) -> [Podcast] {
        podcasts
            .filter(\.isSubscribed)
            .sorted { lhs, rhs in
                let lhsKey = sortKey(for: lhs)
                let rhsKey = sortKey(for: rhs)
                if lhsKey != rhsKey { return lhsKey < rhsKey }
                // Stable tiebreak for equal keys (e.g. two shows differing
                // only by an article or diacritics) — fall back to the raw
                // title rather than leaving fetch order undefined.
                return lhs.title < rhs.title
            }
    }

    /// The alphabetization key for `podcast`: its title, diacritic- and
    /// case-folded, with a single leading "the"/"a"/"an" article stripped so
    /// "The Daily" sorts under D, not T — matching how a person alphabetizes
    /// a shelf of shows.
    static func sortKey(for podcast: Podcast) -> String {
        var key = podcast.title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for article in ["the ", "an ", "a "] {
            if key.hasPrefix(article) {
                key.removeFirst(article.count)
                break
            }
        }

        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
