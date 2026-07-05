// Podcast Detail loader. Architecture source: navigation-map.md ("Podcast
// Detail is one adaptive screen … keyed by feedURL") + ROADMAP.md E2-S1/S2.
// App-level composition (like DiscoverViewModel): orchestrates FeedParsingKit
// + SwiftData + presentation. True domain logic (parsing, upsert, the
// user-owned-field rules) stays in FeedParsingKit; this type only decides
// *when* to fetch (store-first) and shapes data for the view.
import Foundation
import Observation
import SwiftData
import PodcastModels
import FeedParsingKit

/// View model for the one adaptive Podcast Detail screen.
///
/// **Store-first**: on `load()`, looks up an existing `Podcast` by `feedURL`
/// in the injected `ModelContext`. If found, shows it immediately with no
/// network call (this is how a subscribed show — reached from the Podcasts
/// tab in E3, or re-visited from Discover — opens instantly). If absent,
/// fetches the feed via the injected `FeedFetching` seam and upserts it via
/// `FeedUpsert` (E0), then shows the freshly-persisted `Podcast`.
@MainActor
@Observable
public final class PodcastDetailViewModel {

    /// The screen's three states.
    public enum State {
        /// The store-first lookup or the fetch/upsert is in flight.
        case loading
        /// A `Podcast` is available (either found in the store, or freshly upserted).
        case loaded(Podcast)
        /// The store-first lookup found nothing and the fetch/upsert failed.
        case error(String)
    }

    /// The current screen state. Read-only to callers; the model owns transitions.
    public private(set) var state: State = .loading

    private let feedURL: URL
    private let modelContext: ModelContext
    private let fetcher: FeedFetching

    /// - Parameters:
    ///   - feedURL: The natural identity of the show (navigation-map.md: the
    ///     detail screen is keyed by this).
    ///   - modelContext: The shared SwiftData context to look up / persist into.
    ///   - fetcher: The fetch seam — the live `FeedFetcher` in the app,
    ///     a stub `FeedFetching` in tests.
    public init(feedURL: URL, modelContext: ModelContext, fetcher: FeedFetching) {
        self.feedURL = feedURL
        self.modelContext = modelContext
        self.fetcher = fetcher
    }

    // MARK: - Loading (E2-S1)

    /// Runs the store-first lookup, falling back to fetch + upsert. Safe to
    /// call more than once (e.g. a pull-to-refresh or retry); always
    /// re-resolves from scratch.
    public func load() async {
        state = .loading
        let feedURL = self.feedURL
        do {
            // Fetch-then-filter rather than `#Predicate { $0.feedURL == feedURL }`:
            // under this app target's `SWIFT_STRICT_CONCURRENCY: complete`, the
            // `#Predicate` macro expansion warns that `KeyPath<Podcast, URL>`
            // isn't `Sendable` (an error under the Swift 6 language mode). The
            // podcast list is local-first and modest in size, so filtering in
            // Swift is the simpler, warning-free option.
            let existing = try modelContext.fetch(FetchDescriptor<Podcast>()).first(where: { $0.feedURL == feedURL })

            // Store-first fast path — but ONLY when the stored show already has
            // its episodes. A show subscribed from Discover/curated is inserted
            // metadata-only (no episodes) by the subscribe flow, so an existing
            // row with an empty `episodes` must still fetch the feed to populate
            // them. `FeedUpsert` is idempotent and preserves user-owned fields
            // (isSubscribed/dateAdded/downloadState/playbackProgress), so
            // upserting onto the existing row fills in episodes without dropping
            // the subscription.
            if let existing, !existing.episodes.isEmpty {
                state = .loaded(existing)
                return
            }

            do {
                let parsed = try await fetcher.fetch(url: feedURL)
                let podcast = try FeedUpsert.upsert(parsed, into: modelContext)
                try modelContext.save()
                state = .loaded(podcast)
            } catch {
                // A refresh failed (e.g. offline). If we have a cached row —
                // even a bare, episode-less one — show it so the header still
                // renders, rather than an error screen.
                if let existing {
                    state = .loaded(existing)
                } else {
                    state = .error(Self.message(for: error))
                }
            }
        } catch {
            state = .error(Self.message(for: error))
        }
    }

    /// Episodes for the loaded podcast, **newest-first** by `publishDate`
    /// (ROADMAP E2-S1). Empty while loading/erroring.
    public var episodes: [Episode] {
        guard case .loaded(let podcast) = state else { return [] }
        return podcast.episodes.sorted { $0.publishDate > $1.publishDate }
    }

    /// The artwork URL to render for `episode`: its own artwork, falling back
    /// to the show's (ROADMAP E2-S1: "An episode with no artwork falls back
    /// to the show artwork").
    public func artworkURL(for episode: Episode) -> URL? {
        guard case .loaded(let podcast) = state else { return episode.remoteArtworkURL }
        return episode.remoteArtworkURL ?? podcast.artworkURL
    }

    // MARK: - Subscribe (E2-S2)

    /// Whether the loaded podcast is subscribed. `false` while loading/erroring.
    public var isSubscribed: Bool {
        guard case .loaded(let podcast) = state else { return false }
        return podcast.isSubscribed
    }

    /// Toggles `Podcast.isSubscribed` and persists immediately so the change
    /// survives a relaunch (ROADMAP E2-S2).
    ///
    /// If the save throws, the in-memory toggle is reverted so the UI never
    /// diverges from what's actually persisted (the button reflects the store,
    /// not an optimistic change that didn't land).
    public func toggleSubscribe() {
        guard case .loaded(let podcast) = state else { return }
        podcast.isSubscribed.toggle()
        do {
            try modelContext.save()
        } catch {
            podcast.isSubscribed.toggle()   // revert — the save didn't land
        }
    }

    // MARK: - Errors

    private static func message(for error: Error) -> String {
        if let feedError = error as? FeedError {
            return feedError.errorDescription ?? "This show couldn't be loaded."
        }
        return "This show couldn't be loaded. Check your connection and try again."
    }
}

#if DEBUG
extension PodcastDetailViewModel {
    /// Preview/test convenience: build a view model already pinned to
    /// `.loaded(podcast)`, skipping the fetch entirely.
    convenience init(previewPodcast podcast: Podcast, modelContext: ModelContext) {
        self.init(feedURL: podcast.feedURL, modelContext: modelContext, fetcher: PreviewFetcher())
        state = .loaded(podcast)
    }

    convenience init(previewState state: State, modelContext: ModelContext) {
        self.init(
            feedURL: URL(string: "https://feeds.example.com/preview")!,
            modelContext: modelContext,
            fetcher: PreviewFetcher()
        )
        self.state = state
    }
}

/// A `FeedFetching` stub that never actually resolves — previews always seed
/// `state` directly via `previewPodcast`/`previewState` instead of fetching.
private struct PreviewFetcher: FeedFetching {
    func fetch(url: URL) async throws -> ParsedFeed {
        ParsedFeed(feedURL: url, title: "Preview Show")
    }
}
#endif
