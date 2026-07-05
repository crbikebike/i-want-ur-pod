// Podcast — a subscribable feed. SwiftData @Model.
// Model layer for "i want ur pod"; no design source (data type only).
import Foundation
import SwiftData

/// A podcast feed the user can browse or subscribe to.
///
/// `feedURL` is the natural identity of a podcast (one row per RSS feed);
/// `id` is a stable synthetic identifier used for relationships and diffing.
@Model
public final class Podcast {
    /// Stable synthetic identifier.
    @Attribute(.unique) public var id: UUID

    /// Display title of the show.
    public var title: String

    /// Author / publisher name.
    public var author: String

    /// Canonical RSS feed URL — the natural identity of the show.
    @Attribute(.unique) public var feedURL: URL

    /// Optional website / landing page for the show.
    public var homeURL: URL?

    /// Optional show artwork URL.
    public var artworkURL: URL?

    /// Primary category label (freeform, sourced from the feed).
    public var category: String

    /// Whether the user has subscribed to this show.
    public var isSubscribed: Bool

    /// When this show was first added to the local store.
    public var dateAdded: Date

    /// Episodes belonging to this show. Deleting a podcast cascades to its episodes.
    @Relationship(deleteRule: .cascade, inverse: \Episode.podcast)
    public var episodes: [Episode]

    public init(
        id: UUID = UUID(),
        title: String,
        author: String = "",
        feedURL: URL,
        homeURL: URL? = nil,
        artworkURL: URL? = nil,
        category: String = "",
        isSubscribed: Bool = false,
        dateAdded: Date = .now,
        episodes: [Episode] = []
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.feedURL = feedURL
        self.homeURL = homeURL
        self.artworkURL = artworkURL
        self.category = category
        self.isSubscribed = isSubscribed
        self.dateAdded = dateAdded
        self.episodes = episodes
    }
}
