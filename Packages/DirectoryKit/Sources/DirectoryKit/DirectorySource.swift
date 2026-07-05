// Search source contract. Source model: docs/design/direction.md §12
// (Apple/iTunes primary keyless; PodcastIndex opt-in with user key;
//  PRIMARY + FALLBACK, no merge).
import Foundation

/// Identifies a concrete podcast search backend.
public enum SourceKind: String, Sendable, Hashable, CaseIterable, Codable {
    /// Apple (iTunes) Search API. Keyless, ships ON, primary by default (§12.1).
    case apple
    /// PodcastIndex. Opt-in; inactive until the user supplies their own
    /// API key + secret (§12.2).
    case podcastIndex
}

/// Errors a ``DirectorySource`` can surface from a search.
///
/// These map to the primary + fallback behaviour of §12.3: `.unavailable`,
/// `.rateLimited`, and `.noKey` are all conditions under which the coordinator
/// should fall through to the next enabled source (results are never merged).
public enum SearchError: Error, Sendable, Equatable {
    /// The source could not be reached (network / server unavailable).
    case unavailable
    /// The response could not be decoded into ``SearchResult`` values.
    case decoding
    /// The source rejected the request for exceeding its rate limit.
    case rateLimited
    /// The source requires a user-supplied API key that is not configured.
    case noKey
}

/// A podcast search backend.
///
/// Concrete sources (Apple, PodcastIndex) and the `SearchCoordinator` conform
/// to / consume this contract. Conformers are `Sendable` so they can be held
/// and invoked across concurrency domains.
public protocol DirectorySource: Sendable {

    /// Which backend this source represents.
    var kind: SourceKind { get }

    /// Whether the source is currently enabled and eligible to be searched.
    ///
    /// Per §12, Apple is enabled by default; PodcastIndex stays disabled until
    /// the user adds a key.
    var isEnabled: Bool { get }

    /// Search the source for `term`.
    ///
    /// - Parameter term: The user's raw search query.
    /// - Returns: Matching podcasts from this source only (never merged with
    ///   other sources).
    /// - Throws: ``SearchError`` on failure, signalling the coordinator to fall
    ///   back to the next enabled source.
    func search(term: String) async throws -> [SearchResult]
}
