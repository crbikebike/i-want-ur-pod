// QueueStore — the app-scoped Up Next queue service (E5-S1/S2/S3).
// Architecture source: docs/spec/queue-semantics.md (the invariants and the
// add/reorder/remove/auto-advance rules this type implements) +
// docs/spec/navigation-map.md's frozen contract (shared services are created
// once at app scope and injected — never built inside AppShell's tab switch).
// Mirrors DownloadKit's `DownloadManager` / PlaybackKit's `PlaybackEngine`:
// an `@Observable @MainActor` service wrapping a `ModelContext`, created once
// in `IWantUrPodApp` and injected via `.environment` (see `AppQueue.swift`).
//
// Lives in the app target (not a dedicated package) because it is a thin,
// direct `QueueItem`/`Episode` orchestrator with no independent domain of its
// own — same precedent as `IWantUrPod/Library/PodcastsListProvider.swift`
// (E3), which is also app-target logic operating straight on `PodcastModels`.
import Foundation
import Observation
import SwiftData
import PodcastModels

/// Owns the ordered "Up Next" queue: fetch, add, reorder, remove, and orphan
/// pruning, keeping `queue-semantics.md`'s invariants after every mutation:
///
/// 1. **Contiguous, ascending `order`** (`0, 1, 2, …`, no gaps/dupes).
/// 2. **No duplicate episodes** — ``add(_:)`` is a no-op if already queued.
/// 3. **No orphans** — a `QueueItem` whose `episode` was nullified (E5's
///    inverse-relationship fix, `PodcastModels/Episode.swift`) is pruned.
/// 4. **Persistence** — every mutation calls `context.save()`.
@MainActor
@Observable
public final class QueueStore {
    private let context: ModelContext

    /// The queue, ordered ascending by `order` (index 0 plays next). Kept as
    /// a plain array (not a live `@Query`) so the store's own mutations are
    /// the single source of truth the Up Next screen renders directly.
    public private(set) var items: [QueueItem] = []

    /// - Parameter context: The shared `ModelContext` this store reads and
    ///   writes through. The app wires this to `modelContainer.mainContext`
    ///   so every screen (Up Next, Podcast Detail's "Add to Up Next") sees
    ///   the same data.
    public init(context: ModelContext) {
        self.context = context
        reload()
    }

    /// The item with the smallest `order` — "next to play." `nil` when the
    /// queue is empty.
    public var head: QueueItem? { items.first }

    /// Whether `episode` already has an entry in the queue (invariant 2).
    public func isQueued(_ episode: Episode) -> Bool {
        items.contains { $0.episode?.id == episode.id }
    }

    /// Re-fetches from `context`, pruning orphans first (invariant 3) so
    /// `items` never surfaces a dangling entry. Call after any external
    /// mutation of the store (e.g. app launch) to pick up on-disk state.
    public func reload() {
        // A single fetch: `pruneOrphans` already reads every `QueueItem`,
        // drops the orphans, normalizes, and republishes `items` — reloading
        // is exactly that, so there's no reason to fetch a second time here.
        pruneOrphans()
    }

    // MARK: - Add (E5-S1)

    /// Appends `episode` at the tail (`order = maxOrder + 1`, or `0` if
    /// empty). No-op if `episode` is already queued (invariant 2).
    ///
    /// - Returns: `true` if a new entry was added, `false` for the no-op case
    ///   (lets callers/tests distinguish the two without inspecting `items`).
    @discardableResult
    public func add(_ episode: Episode) -> Bool {
        guard !isQueued(episode) else { return false }
        let nextOrder = (items.map(\.order).max() ?? -1) + 1
        context.insert(QueueItem(order: nextOrder, episode: episode))
        save()
        reload()
        return true
    }

    // MARK: - Reorder — drag (E5-S2)

    /// Applies SwiftUI `onMove`'s index-shift semantics to the queue, then
    /// renormalizes `order` to `0, 1, 2, …` across the whole list (invariant 1).
    public func move(fromOffsets: IndexSet, toOffset: Int) {
        guard !fromOffsets.isEmpty else { return }
        var reordered = items
        let moving = fromOffsets.sorted().map { items[$0] }
        for offset in fromOffsets.sorted(by: >) {
            reordered.remove(at: offset)
        }
        // `onMove`'s `toOffset` is expressed against the *original* array;
        // shift it left by however many moved items sat before it, matching
        // the semantics `Array.move(fromOffsets:toOffset:)` documents.
        let shift = fromOffsets.filter { $0 < toOffset }.count
        let insertionIndex = max(0, min(toOffset - shift, reordered.count))
        reordered.insert(contentsOf: moving, at: insertionIndex)

        normalize(reordered)
        save()
        items = reordered
    }

    // MARK: - Remove — left swipe (E5-S2)

    /// Deletes the `QueueItem` (never the `Episode`) and renormalizes `order`
    /// on what remains. Per `queue-semantics.md`, removing the currently
    /// playing episode's entry does not touch playback — this store has no
    /// reference to `PlaybackEngine` at all, so that's true by construction.
    public func remove(_ item: QueueItem) {
        context.delete(item)
        let remaining = items.filter { $0.id != item.id }
        normalize(remaining)
        save()
        items = remaining
    }

    // MARK: - Orphan pruning (invariant 3)

    /// Drops every `QueueItem` whose `episode` is `nil` (its episode was
    /// deleted — the E5 inverse-relationship fix makes SwiftData actually
    /// nullify the reference; pruning the now-dangling row is this store's
    /// job per `Episode.queueItems`'s doc comment). Renormalizes the survivors.
    ///
    /// - Returns: the number of orphans pruned.
    @discardableResult
    public func pruneOrphans() -> Int {
        let all = (try? context.fetch(FetchDescriptor<QueueItem>())) ?? []
        let orphans = all.filter { $0.episode == nil }
        let remaining = all.filter { $0.episode != nil }.sorted { $0.order < $1.order }

        // Always republish `items` from this one fetch (that's what makes
        // `reload()` a single-fetch call). Only touch the store when there's
        // actually an orphan to delete + renormalize.
        if !orphans.isEmpty {
            for orphan in orphans { context.delete(orphan) }
            normalize(remaining)
            save()
        }
        items = remaining
        return orphans.count
    }

    // MARK: - Private

    private func normalize(_ ordered: [QueueItem]) {
        for (index, item) in ordered.enumerated() where item.order != index {
            item.order = index
        }
    }

    private func save() {
        try? context.save()
    }
}
