// Chapter — a timed marker within an Episode. SwiftData @Model.
// Model layer for "i want ur pod"; no design source (data type only).
import Foundation
import SwiftData

/// A chapter marker within an `Episode`.
///
/// `startTime` is an offset in seconds from the start of the audio. `endTime`
/// is optional; when absent the chapter runs until the next marker (or the end).
@Model
public final class Chapter {
    /// Stable synthetic identifier.
    @Attribute(.unique) public var id: UUID

    /// Chapter title.
    public var title: String

    /// Start offset in seconds from the beginning of the audio.
    public var startTime: TimeInterval

    /// Optional end offset in seconds. `nil` when open-ended.
    public var endTime: TimeInterval?

    /// Optional chapter artwork URL.
    public var imageURL: URL?

    /// The owning episode. Chapters are cascade-deleted with their episode.
    public var episode: Episode?

    public init(
        id: UUID = UUID(),
        title: String,
        startTime: TimeInterval,
        endTime: TimeInterval? = nil,
        imageURL: URL? = nil,
        episode: Episode? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.imageURL = imageURL
        self.episode = episode
    }
}
