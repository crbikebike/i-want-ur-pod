// QueueStoreTests — E5-S1/S2 determinate coverage. Runs on the iOS simulator
// (SwiftData relationship rules — the QueueItem/Episode nullify inverse this
// story fixed — need the simulator runtime; same precedent as
// PodcastDetailPlaybackTests.swift / PodcastsListProviderTests.swift). Covers
// ROADMAP E5-S1/S2 and docs/spec/queue-semantics.md's invariants + operations.
import XCTest
import SwiftData
import PodcastModels
import PlaybackKit
@testable import IWantUrPod

@MainActor
final class QueueStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try ModelSchema.makeContainer(inMemory: true)
    }

    private func makePodcast(_ context: ModelContext, title: String = "Show") -> Podcast {
        let podcast = Podcast(title: title, feedURL: URL(string: "https://feeds.example.com/\(UUID().uuidString)")!)
        context.insert(podcast)
        return podcast
    }

    private func makeEpisode(
        _ context: ModelContext,
        guid: String,
        podcast: Podcast,
        downloadState: DownloadState = .downloaded
    ) -> Episode {
        let episode = Episode(
            guid: guid,
            title: "Episode \(guid)",
            audioURL: URL(string: "https://cdn.example.com/\(guid).mp3")!,
            downloadState: downloadState,
            podcast: podcast
        )
        context.insert(episode)
        return episode
    }

    // MARK: - Add appends to tail; re-add is a no-op; persists across relaunch

    func test_add_appendsToTail_withContiguousOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let first = makeEpisode(context, guid: "a", podcast: podcast)
        let second = makeEpisode(context, guid: "b", podcast: podcast)
        try context.save()

        let store = QueueStore(context: context)
        store.add(first)
        store.add(second)

        XCTAssertEqual(store.items.map { $0.episode?.guid }, ["a", "b"])
        XCTAssertEqual(store.items.map(\.order), [0, 1])
    }

    func test_add_sameEpisodeTwice_isNoOp() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let episode = makeEpisode(context, guid: "dup", podcast: podcast)
        try context.save()

        let store = QueueStore(context: context)
        XCTAssertTrue(store.add(episode))
        XCTAssertFalse(store.add(episode), "Re-adding an already-queued episode must be a no-op")

        XCTAssertEqual(store.items.count, 1, "The episode must not be duplicated or moved")
    }

    func test_queue_persistsAcrossRelaunch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let episode = makeEpisode(context, guid: "persist", podcast: podcast)
        try context.save()

        let store = QueueStore(context: context)
        store.add(episode)

        // Simulate a relaunch: a fresh ModelContext on the same container, a
        // fresh QueueStore over it.
        let freshContext = ModelContext(container)
        let reloadedStore = QueueStore(context: freshContext)

        XCTAssertEqual(reloadedStore.items.count, 1)
        XCTAssertEqual(reloadedStore.items.first?.episode?.guid, "persist")
    }

    // MARK: - Drag reorder rewrites order contiguously

    func test_move_rewritesOrderContiguously_noGaps() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let episodes = (0..<4).map { makeEpisode(context, guid: "ep-\($0)", podcast: podcast) }
        try context.save()

        let store = QueueStore(context: context)
        for episode in episodes { store.add(episode) }
        XCTAssertEqual(store.items.map { $0.episode?.guid }, ["ep-0", "ep-1", "ep-2", "ep-3"])

        // Drag the item at index 3 ("ep-3") to the front — SwiftUI onMove
        // semantics: fromOffsets is the source index set, toOffset is the
        // destination expressed against the pre-move array.
        store.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)

        XCTAssertEqual(store.items.map { $0.episode?.guid }, ["ep-3", "ep-0", "ep-1", "ep-2"])
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2, 3], "order must stay contiguous ascending with no gaps after a move")
    }

    func test_move_middleToEnd_rewritesOrderContiguously() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let episodes = (0..<3).map { makeEpisode(context, guid: "m-\($0)", podcast: podcast) }
        try context.save()

        let store = QueueStore(context: context)
        for episode in episodes { store.add(episode) }

        // Move index 0 to the end (onMove's toOffset for "move to the end"
        // of a 3-item list is 3, one past the last index).
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        XCTAssertEqual(store.items.map { $0.episode?.guid }, ["m-1", "m-2", "m-0"])
        XCTAssertEqual(store.items.map(\.order), [0, 1, 2])
    }

    // MARK: - Left-swipe remove deletes the QueueItem; the Episode survives

    func test_remove_deletesQueueItem_leavesEpisodeIntact() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let episode = makeEpisode(context, guid: "removable", podcast: podcast)
        try context.save()

        let store = QueueStore(context: context)
        store.add(episode)
        let item = try XCTUnwrap(store.items.first)

        let episodeCountBefore = try context.fetchCount(FetchDescriptor<Episode>())

        store.remove(item)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QueueItem>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Episode>()), episodeCountBefore, "Removing a QueueItem must not delete its Episode")
    }

    func test_remove_renormalizesRemainingOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let episodes = (0..<3).map { makeEpisode(context, guid: "r-\($0)", podcast: podcast) }
        try context.save()

        let store = QueueStore(context: context)
        for episode in episodes { store.add(episode) }
        let middle = store.items[1]

        store.remove(middle)

        XCTAssertEqual(store.items.map { $0.episode?.guid }, ["r-0", "r-2"])
        XCTAssertEqual(store.items.map(\.order), [0, 1], "removing the middle item must close the order gap")
    }

    // MARK: - Removing the current item leaves active audio playing

    func test_removingCurrentItem_leavesPlaybackEngineStateUnchanged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let episode = makeEpisode(context, guid: "current", podcast: podcast)
        try context.save()

        let engine = PlaybackEngine(
            localURLResolver: { _ in URL(fileURLWithPath: "/tmp/current.audio") }
        )
        engine.load(episode: episode, context: context)
        XCTAssertEqual(engine.state, .playing)

        let store = QueueStore(context: context)
        store.add(episode)
        let item = try XCTUnwrap(store.items.first)

        store.remove(item)

        XCTAssertEqual(engine.state, .playing, "removing the current episode's queue entry must not affect active playback")
        XCTAssertEqual(engine.currentEpisode?.guid, "current")
    }

    // MARK: - Orphan pruning (invariant 3, ties to the E5 inverse-relationship fix)

    func test_pruneOrphans_dropsQueueItemsWithNilEpisode() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let survivor = makeEpisode(context, guid: "survivor", podcast: podcast)
        let doomed = makeEpisode(context, guid: "doomed", podcast: podcast)
        try context.save()

        let store = QueueStore(context: context)
        store.add(survivor)
        store.add(doomed)
        XCTAssertEqual(store.items.count, 2)

        // Deleting the episode nullifies the QueueItem.episode reference
        // (E5's Episode.queueItems inverse-relationship fix) rather than
        // leaving it dangling — reload()/pruneOrphans() then drops the row.
        context.delete(doomed)
        try context.save()

        let prunedCount = store.pruneOrphans()

        XCTAssertEqual(prunedCount, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QueueItem>()), 1)
        XCTAssertEqual(store.items.map { $0.episode?.guid }, ["survivor"])
        XCTAssertEqual(store.items.map(\.order), [0], "order stays contiguous after an orphan is pruned")
    }

    func test_reload_pruneOrphansOnLoad() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let episode = makeEpisode(context, guid: "will-be-orphaned", podcast: podcast)
        try context.save()

        let store = QueueStore(context: context)
        store.add(episode)

        context.delete(episode)
        try context.save()

        // A fresh store (simulating "call it on load") must not surface the orphan.
        let reloadedStore = QueueStore(context: ModelContext(container))
        XCTAssertTrue(reloadedStore.items.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QueueItem>()), 0)
    }

    // MARK: - Duplicate-episode healing (invariant 2, on load)

    // A store that already holds multiple QueueItems for the SAME episode —
    // legacy data from a path that bypassed `add()`'s guard — must collapse to
    // one entry per episode on load (keeping the lowest-order/earliest), the
    // same way orphans are healed. Enforcing invariant 2 only at add()-time
    // leaves such duplicates on screen forever.
    func test_reload_collapsesDuplicateEpisodeEntries_keepingLowestOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let dup = makeEpisode(context, guid: "dup", podcast: podcast)
        let other = makeEpisode(context, guid: "other", podcast: podcast)
        try context.save()

        // Insert QueueItems directly (bypassing add()'s isQueued guard) to
        // reproduce the persisted duplicate state: three entries for `dup`
        // interleaved with one for `other`.
        context.insert(QueueItem(order: 0, episode: dup))
        context.insert(QueueItem(order: 1, episode: other))
        context.insert(QueueItem(order: 2, episode: dup))
        context.insert(QueueItem(order: 3, episode: dup))
        try context.save()

        // Fresh store simulates app launch → reload() heals the duplicates.
        let store = QueueStore(context: ModelContext(container))

        XCTAssertEqual(store.items.count, 2, "duplicate-episode entries collapse to one per episode")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QueueItem>()), 2, "the extra rows are deleted from the store, not just hidden")
        XCTAssertEqual(store.items.map { $0.episode?.guid }, ["dup", "other"], "lowest-order entry per episode is kept, in order")
        XCTAssertEqual(store.items.map(\.order), [0, 1], "order renormalizes to contiguous 0,1")
    }
}
