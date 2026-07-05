// Composed from docs/design/direction.md tokens — no design/kit source (see
// design/kit/MANIFEST.md). The testable seam behind the Podcasts tab
// (ROADMAP.md E3-S1): subscribed-filtering + newest-first-sort logic lives
// here rather than in `PodcastsScreen`, so it can be exercised directly
// against a `ModelContext` (see `IWantUrPodTests/PodcastsListProviderTests.swift`).
import Foundation
import SwiftData
import PodcastModels

/// Resolves the Podcasts tab's row list: every subscribed `Podcast`, newest
/// (`dateAdded`) first.
///
/// A `#Predicate { $0.isSubscribed }` triggers a non-`Sendable` `KeyPath`
/// warning under this project's `SWIFT_STRICT_CONCURRENCY: complete` setting
/// (an error under Swift 6) — see `PodcastDetailViewModelTests.swift` for the
/// same precedent. Both entry points below fetch (or are handed) the full
/// `[Podcast]` set and filter/sort in plain Swift instead.
@MainActor
public enum PodcastsListProvider {
    /// Fetches every `Podcast` from `context` and returns the subscribed
    /// ones, newest `dateAdded` first.
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
            .sorted { $0.dateAdded > $1.dateAdded }
    }
}
