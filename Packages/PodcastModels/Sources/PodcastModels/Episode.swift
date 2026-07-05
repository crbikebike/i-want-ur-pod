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
        chapters: [Chapter] = []
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
