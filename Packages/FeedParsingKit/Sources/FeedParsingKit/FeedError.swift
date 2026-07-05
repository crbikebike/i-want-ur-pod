// FeedError — typed failure surface for fetch + parse. Never trap.
// Error table source of truth: docs/spec/feed-field-mapping.md (Error model).
import Foundation

/// Typed errors surfaced by `FeedFetcher` and `FeedParser`. Failure paths
/// always throw one of these — they never `fatalError`/force-unwrap.
public enum FeedError: Error, Equatable, Sendable {
    /// The HTTP response was non-2xx. Carries the status code.
    case httpStatus(Int)

    /// The request failed at the network layer (no response at all).
    /// Carries a human-readable description of the underlying failure.
    case networkFailure(String)

    /// The body wasn't a usable feed: not XML, no `<rss>`/`<channel>`, or a
    /// `<channel>` present but missing the required `<title>`. Carries a
    /// short reason for diagnostics.
    case malformedFeed(reason: String)
}

extension FeedError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            return "Feed request failed with HTTP status \(code)."
        case .networkFailure(let message):
            return "Feed request failed: \(message)."
        case .malformedFeed(let reason):
            return "Feed could not be parsed: \(reason)."
        }
    }
}
