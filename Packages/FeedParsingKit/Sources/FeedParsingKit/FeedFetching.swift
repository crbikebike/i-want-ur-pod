// FeedFetching — abstraction over FeedFetcher's fetch(url:) so callers (the
// Podcast Detail loader, E2-S1) can inject a stub for deterministic tests
// instead of hitting the network. No SwiftData import.
import Foundation

/// Fetches a feed URL and parses it into a ``ParsedFeed``.
///
/// `FeedFetcher` is the live, `URLSession`-backed implementation; tests inject
/// a stub conforming to this protocol so `PodcastDetailViewModel` (app target)
/// never needs real network access to exercise its store-first loading logic.
public protocol FeedFetching: Sendable {
    /// Fetches and parses `url`.
    ///
    /// - Throws: `FeedError.networkFailure` on a transport-level failure,
    ///   `FeedError.httpStatus` on a non-2xx response, or
    ///   `FeedError.malformedFeed` when the body isn't a usable feed.
    func fetch(url: URL) async throws -> ParsedFeed
}

extension FeedFetcher: FeedFetching {}
