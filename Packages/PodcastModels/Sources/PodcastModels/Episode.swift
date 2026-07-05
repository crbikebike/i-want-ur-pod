// Episode — a single audio item within a Podcast. SwiftData @Model.
// Model layer for "i want ur pod"; no design source (data type only).
import Foundation
import SwiftData

/// A single episode within a `Podcast`.
///
/// `guid` is the feed's natural identity for the item; `id` is a stable
/// synthetic identifier used for relationships and diffing.
@Model
public final class Episode {
    /// Stable synthetic identifier.
    @Attribute(.unique) public var id: UUID

    /// Feed-provided globally-unique item identifier (`<guid>`).
    @Attribute(.unique) public var guid: String

    /// Episode title.
    public var title: String

    /// Show-notes / description text.
    public var summary: String

    /// Publication date from the feed.
    public var publishDate: Date

    /// Duration in seconds. `0` when unknown.
    public var duration: TimeInterval

    /// Direct URL to the audio enclosure.
    public var audioURL: URL

    /// Optional per-episode artwork URL (falls back to the show artwork).
    public var remoteArtworkURL: URL?

    /// Current download status of the audio asset.
    public var downloadState: DownloadState

    /// Fractional listen progress, clamped to `0...1`.
    public var playbackProgress: Double

    /// Whether the item is flagged explicit.
    public var isExplicit: Bool

    /// The owning show. Nullified detachment is not expected — episodes are
    /// cascade-deleted with their podcast.
    public var podcast: Podcast?

    /// Ordered chapter markers. Deleting an episode cascades to its chapters.
    @Relationship(deleteRule: .cascade, inverse: \Chapter.episode)
    public var chapters: [Chapter]

    /// `QueueItem`s (Up Next entries) referencing this episode.
    ///
    /// **Inverse-relationship fix (E5, deferred defect from M1):** SwiftData's
    /// delete rule is interpreted from the *inverse* (to-many) side, exactly
    /// like `Podcast.episodes` (`.cascade`, inverse `\Episode.podcast`) and
    /// `Episode.chapters` above (`.cascade`, inverse `\Chapter.episode`).
    /// `QueueItem.episode` previously declared `deleteRule: .nullify` on the
    /// to-one side with **no inverse declared at all**, so SwiftData had no
    /// pairing to apply the rule to and the reference was never actually
    /// nulled when an `Episode` was deleted (`QueueItem` survived with a
    /// dangling, non-nil `episode` until the queue store happened to notice).
    /// Declaring the inverse here, on the to-many side, with `.nullify`,
    /// mirrors the working cascade pairs above: deleting an `Episode` nulls
    /// `episode` on every referencing `QueueItem` (the `QueueItem` row itself
    /// is *not* deleted — orphan pruning of such rows remains the queue
    /// store's job, per this file's doc comment and `queue-semantics.md`
    /// invariant 3). `QueueItem.episode` itself stays a plain optional
    /// property (no `@Relationship` macro) — the inverse is declared on
    /// exactly one side, here.
    ///
    /// Additive migration note: a new relationship array with no stored
    /// scalar data; SwiftData's lightweight migration handles this
    /// automatically. `ModelSchema.models` is unchanged (same four types).
    @Relationship(deleteRule: .nullify, inverse: \QueueItem.episode)
    public var queueItems: [QueueItem]

    public init(
        id: UUID = UUID(),
        guid: String,
        title: String,
        summary: String = "",
        publishDate: Date = .now,
        duration: TimeInterval = 0,
        audioURL: URL,
        remoteArtworkURL: URL? = nil,
        downloadState: DownloadState = .notDownloaded,
        playbackProgress: Double = 0,
        isExplicit: Bool = false,
        podcast: Podcast? = nil,
        chapters: [Chapter] = [],
        queueItems: [QueueItem] = []
    ) {
        self.id = id
        self.guid = guid
        self.title = title
        self.summary = summary
        self.publishDate = publishDate
        self.duration = duration
        self.audioURL = audioURL
        self.remoteArtworkURL = remoteArtworkURL
        self.downloadState = downloadState
        self.playbackProgress = min(max(playbackProgress, 0), 1)
        self.isExplicit = isExplicit
        self.podcast = podcast
        self.chapters = chapters
        self.queueItems = queueItems
    }

    /// Whether the episode has been listened to effectively in full.
    public var isPlayed: Bool {
        playbackProgress >= 0.98
    }

    /// Remaining unplayed time in seconds, based on `duration` and progress.
    public var remainingTime: TimeInterval {
        max(duration * (1 - min(max(playbackProgress, 0), 1)), 0)
    }
}
