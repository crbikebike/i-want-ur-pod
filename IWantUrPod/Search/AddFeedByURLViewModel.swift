// Add Feed by URL view model. Spec source of truth:
// docs/spec/add-feed-by-url.md ("New: AddFeedByURLViewModel"). Mirrors
// PodcastDetailViewModel's app-level-composition style: injects a
// `FeedFetching` seam + `ModelContext`, orchestrates the existing
// FeedParsingKit pipeline (fetch → upsert → save) unchanged, and owns the
// subscribe intent itself (`FeedUpsert` never writes `isSubscribed`).
import Foundation
import Observation
import SwiftData
import PodcastModels
import FeedParsingKit

/// View model for the shared "Add a feed by URL" sheet (search entry points +
/// Settings entry point, per the spec's Design section).
@MainActor
@Observable
public final class AddFeedByURLViewModel {

    /// The sheet's four states (mirrors `add-feed-url.html`'s `data-state`).
    public enum State: Equatable {
        /// Idle, awaiting input. The initial state.
        case ready
        /// The fetch/upsert is in flight.
        case loading
        /// Validation or fetch/upsert failed. Carries a user-facing message.
        case error(String)
        /// The feed was added and subscribed. Carries its `feedURL` so the
        /// caller can navigate to Podcast Detail.
        case success(URL)
    }

    /// The current sheet state. Read-only to callers; the model owns transitions.
    public private(set) var state: State = .ready

    private let modelContext: ModelContext
    private let fetcher: FeedFetching

    /// - Parameters:
    ///   - modelContext: The shared SwiftData context to upsert into.
    ///   - fetcher: The fetch seam — the live `FeedFetcher` in the app,
    ///     a stub `FeedFetching` in tests.
    public init(modelContext: ModelContext, fetcher: FeedFetching) {
        self.modelContext = modelContext
        self.fetcher = fetcher
    }

    /// Validates `urlString`, fetches + upserts the feed, and subscribes it.
    ///
    /// Validation (trim, normalize a leading `feed://` to `https://`, reject
    /// empty or non-`http`/`https` schemes) happens before any network call —
    /// an invalid string never reaches `fetcher`. On success, `state` becomes
    /// `.success(podcast.feedURL)` with `Podcast.isSubscribed == true`
    /// persisted. Safe to call more than once (e.g. retry after an error).
    public func add(urlString: String) async {
        guard let url = Self.validate(urlString) else {
            state = .error("Enter a valid podcast feed URL.")
            return
        }

        state = .loading
        do {
            let parsed = try await fetcher.fetch(url: url)
            let podcast = try FeedUpsert.upsert(parsed, into: modelContext)
            podcast.isSubscribed = true
            try modelContext.save()
            state = .success(podcast.feedURL)
        } catch {
            state = .error(Self.message(for: error))
        }
    }

    // MARK: - Validation

    /// Trims whitespace, normalizes the `feed:` pseudo-scheme podcast apps hand
    /// out (`feed://host/rss` → `https://host/rss`; `feed:https://host/rss` →
    /// `https://host/rss`), and validates the result as an `http`/`https`
    /// `URL`. Returns `nil` for an empty string or any other scheme.
    private static func validate(_ urlString: String) -> URL? {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        if lower.hasPrefix("feed://") {
            // `feed://host/rss` — the scheme stands in for https.
            trimmed = "https://" + trimmed.dropFirst("feed://".count)
        } else if lower.hasPrefix("feed:") {
            // `feed:https://host/rss` — the feed scheme wraps a full URL.
            trimmed = String(trimmed.dropFirst("feed:".count))
        }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    // MARK: - Errors

    private static func message(for error: Error) -> String {
        if let feedError = error as? FeedError {
            switch feedError {
            case .httpStatus(401), .httpStatus(403):
                // Exact copy from the signed-off kit error state
                // (design/kit/screens/add-feed-url.html) — the sheet displays
                // this string verbatim, so the VM and the mock stay in sync.
                return "This link didn’t work. Private feed links can expire — grab a fresh one from the show and try again."
            default:
                return feedError.errorDescription ?? "This feed couldn't be added."
            }
        }
        return "This feed couldn't be added. Check your connection and try again."
    }
}

#if DEBUG
extension AddFeedByURLViewModel {
    /// Preview convenience: build a view model already pinned to `state`,
    /// skipping the fetch entirely. Mirrors
    /// `PodcastDetailViewModel.init(previewState:modelContext:)`.
    convenience init(previewState state: State, modelContext: ModelContext) {
        self.init(modelContext: modelContext, fetcher: PreviewFeedFetcher())
        self.state = state
    }
}

/// A `FeedFetching` stub that never actually resolves — previews always seed
/// `state` directly via `previewState` instead of fetching.
private struct PreviewFeedFetcher: FeedFetching {
    func fetch(url: URL) async throws -> ParsedFeed {
        ParsedFeed(feedURL: url, title: "Preview Show")
    }
}
#endif
