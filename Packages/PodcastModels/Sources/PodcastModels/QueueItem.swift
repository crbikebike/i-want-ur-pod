// QueueItem — an entry in the "Up Next" play queue. SwiftData @Model.
// Model layer for "i want ur pod"; no design source (data type only).
import Foundation
import SwiftData

/// An entry in the user's "Up Next" queue.
///
/// The queue is an ordered list; `order` is the sort key (ascending = plays
/// sooner). Each item points at the `Episode` it will play. If the referenced
/// episode is deleted the reference is nullified, and such orphaned items
/// should be pruned by the queue store.
@Model
public final class QueueItem {
    /// Stable synthetic identifier.
    @Attribute(.unique) public var id: UUID

    /// Sort position within the queue (ascending plays sooner).
    public var order: Int

    /// The episode this queue entry will play.
    @Relationship(deleteRule: .nullify)
    public var episode: Episode?

    public init(
        id: UUID = UUID(),
        order: Int,
        episode: Episode?
    ) {
        self.id = id
        self.order = order
        self.episode = episode
    }
}
