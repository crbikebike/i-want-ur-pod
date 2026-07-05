// ParsedFeed — pure value DTO for one feed <channel>. No SwiftData import.
// Field mapping source of truth: docs/spec/feed-field-mapping.md
import Foundation

/// A decoded podcast feed, not yet persisted.
///
/// Foundation-pure and `Sendable`. `episodes` already excludes items skipped
/// per the field-mapping doc (missing both guid and a usable audio
/// enclosure) — an empty array is a valid, successfully-parsed result.
public struct ParsedFeed: Sendable, Hashable {
    /// The URL that was fetched — the natural identity of the show.
    public var feedURL: URL

    /// `<channel><title>`. Required by the parser; a missing title is a
    /// `FeedError.malformedFeed`, never represented here.
    public var title: String

    /// `<itunes:author>` → `<managingEditor>` → `<itunes:owner><itunes:name>` → `""`.
    public var author: String

    /// `<channel><link>` → `nil`.
    public var homeURL: URL?

    /// `<itunes:image href>` → `<image><url>` → `nil`.
    public var artworkURL: URL?

    /// First `<itunes:category text>` → `<category>` → `""`.
    public var category: String

    /// One entry per playable `<item>` (skips already applied).
    public var episodes: [ParsedEpisode]

    public init(
        feedURL: URL,
        title: String,
        author: String = "",
        homeURL: URL? = nil,
        artworkURL: URL? = nil,
        category: String = "",
        episodes: [ParsedEpisode] = []
    ) {
        self.feedURL = feedURL
        self.title = title
        self.author = author
        self.homeURL = homeURL
        self.artworkURL = artworkURL
        self.category = category
        self.episodes = episodes
    }
}
