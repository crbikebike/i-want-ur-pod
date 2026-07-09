// PlayEvent — a logged listening session (episode listening history, Wave 1).
// Model layer for "i want ur pod"; no design source (data type only).
import Foundation
import SwiftData

/// A single logged play session: how long the user actually listened to an
/// episode, starting at a given wall-clock time.
///
/// **Deliberately snapshot-only, no relationship to `Episode`/`Podcast`:**
/// the listening-history log must survive deletion of the episode or its
/// podcast (a user can delete a downloaded episode, or unsubscribe from a
/// show, and still see "you listened to X" in their history). Every
/// episode/podcast-derived field below is therefore a plain snapshot copied
/// at record time, not a live relationship — this also keeps `FeedUpsert`
/// untouched, since it never needs to know about `PlayEvent`.
@Model
public final class PlayEvent {
    /// Stable synthetic identifier.
    @Attribute(.unique) public var id: UUID

    /// When this play session started — the chronological sort key.
    public var playedAt: Date

    /// How long the user actually listened during this session, in seconds.
    public var listenedSeconds: TimeInterval

    /// Snapshot of the episode's title at record time.
    public var episodeTitle: String

    /// Snapshot of the owning podcast's title at record time.
    public var podcastTitle: String

    /// Snapshot artwork URL (episode's own artwork, falling back to the
    /// podcast's) for rendering a history tile without a live relationship.
    public var artworkURL: URL?

    /// Snapshot of the podcast's feed URL, to open Podcast Detail later.
    public var feedURL: URL?

    /// Snapshot of the episode's feed GUID, to group per-episode play counts.
    public var episodeGUID: String?

    public init(
        id: UUID = UUID(),
        playedAt: Date = .now,
        listenedSeconds: TimeInterval = 0,
        episodeTitle: String = "",
        podcastTitle: String = "",
        artworkURL: URL? = nil,
        feedURL: URL? = nil,
        episodeGUID: String? = nil
    ) {
        self.id = id
        self.playedAt = playedAt
        self.listenedSeconds = listenedSeconds
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
        self.artworkURL = artworkURL
        self.feedURL = feedURL
        self.episodeGUID = episodeGUID
    }
}
