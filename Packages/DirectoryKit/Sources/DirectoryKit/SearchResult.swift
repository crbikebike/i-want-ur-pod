// Result shape mirrors fixtures/sample-podcasts.json (title, author, feedUrl,
// homeUrl, artworkUrl, category). Source model: docs/design/direction.md §12.
import Foundation

/// A single podcast returned by a ``DirectorySource`` search.
///
/// Field names mirror the fixture keys in `fixtures/sample-podcasts.json`.
/// The type is Foundation-pure and `Sendable` so it can cross actor and
/// concurrency boundaries between sources and the coordinator.
public struct SearchResult: Sendable, Hashable, Identifiable, Codable {

    /// Stable identity for the result.
    ///
    /// Derived from the feed URL (the canonical, source-independent handle for
    /// a podcast) so the same show from different sources — or across searches —
    /// resolves to the same identity. This keeps SwiftUI list diffing stable
    /// under the primary + fallback (no-merge) model of §12.
    public var id: String { feedURL.absoluteString }

    /// Display title of the podcast.
    public let title: String

    /// Author / publisher of the podcast.
    public let author: String

    /// The RSS feed URL. Required — this is the subscribe handle.
    public let feedURL: URL

    /// Optional website / home page URL for the show.
    public let homeURL: URL?

    /// Optional artwork URL (typically a high-resolution square image).
    public let artworkURL: URL?

    /// Optional primary category / genre label.
    public let category: String?

    public init(
        title: String,
        author: String,
        feedURL: URL,
        homeURL: URL? = nil,
        artworkURL: URL? = nil,
        category: String? = nil
    ) {
        self.title = title
        self.author = author
        self.feedURL = feedURL
        self.homeURL = homeURL
        self.artworkURL = artworkURL
        self.category = category
    }

    /// Maps to the fixture / wire JSON keys exactly
    /// (`feedUrl`, `homeUrl`, `artworkUrl`).
    private enum CodingKeys: String, CodingKey {
        case title
        case author
        case feedURL = "feedUrl"
        case homeURL = "homeUrl"
        case artworkURL = "artworkUrl"
        case category
    }
}
