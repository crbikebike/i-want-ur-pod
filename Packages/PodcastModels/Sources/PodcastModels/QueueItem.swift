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
///
/// **Inverse-relationship fix (E5):** the `.nullify` delete rule for this
/// pairing is declared on `Episode.queueItems` (the to-many/inverse side),
/// matching how `Podcast.episodes` and `Episode.chapters` declare their
/// cascade rules on the to-many side with the to-one side left as a plain
/// property. `episode` below is intentionally *not* annotated with
/// `@Relationship` — the inverse must be declared on exactly one side of the
/// pair, and putting `deleteRule: .nullify` here with no inverse is exactly
/// the bug this fixes: SwiftData had nothing to pair it with, so deleting an
/// `Episode` never actually nulled this reference. See `Episode.queueItems`'s
/// doc comment for the full explanation.
@Model
public final class QueueItem {
    /// Stable synthetic identifier.
    @Attribute(.unique) public var id: UUID

    /// Sort position within the queue (ascending plays sooner).
    public var order: Int

    /// The episode this queue entry will play. Nulled by SwiftData when the
    /// episode is deleted (delete rule declared on `Episode.queueItems`, the
    /// inverse side — see that property's doc comment).
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
