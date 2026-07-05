// QueueAutoAdvanceCoordinatorTests — E5-S3 determinate coverage. Runs on the
// iOS simulator (same SwiftData-relationship precedent as QueueStoreTests.swift).
// Exercises the coupling IWantUrPodApp wires into PlaybackEngine.onFinished,
// per docs/spec/queue-semantics.md's "Auto-advance" section, without
// constructing the app scene.
import XCTest
import SwiftData
import PodcastModels
import PlaybackKit
@testable import IWantUrPod

@MainActor
final class QueueAutoAdvanceCoordinatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try ModelSchema.makeContainer(inMemory: true)
    }

    private func makePodcast(_ context: ModelContext) -> Podcast {
        let podcast = Podcast(title: "Show", feedURL: URL(string: "https://feeds.example.com/\(UUID().uuidString)")!)
        context.insert(podcast)
        return podcast
    }

    private func makeEpisode(_ context: ModelContext, guid: String, podcast: Podcast) -> Episode {
        let episode = Episode(
            guid: guid,
            title: "Episode \(guid)",
            audioURL: URL(string: "https://cdn.example.com/\(guid).mp3")!,
            downloadState: .downloaded,
            podcast: podcast
        )
        context.insert(episode)
        return episode
    }

    private func makeEngine() -> PlaybackEngine {
        PlaybackEngine(localURLResolver: { episode in URL(fileURLWithPath: "/tmp/\(episode.guid).audio") })
    }

    // MARK: - On finished, the head item becomes current and plays

    func test_onFinished_headBecomesCurrentAndPlays() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let current = makeEpisode(context, guid: "current", podcast: podcast)
        let next = makeEpisode(context, guid: "next", podcast: podcast)
        try context.save()

        let store = QueueStore(context: context)
        store.add(current)
        store.add(next)

        let engine = makeEngine()
        engine.load(episode: current, context: context)
        XCTAssertEqual(engine.state, .playing)

        QueueAutoAdvanceCoordinator.handleFinished(current, queueStore: store, playbackEngine: engine, context: context)

        XCTAssertEqual(engine.currentEpisode?.guid, "next", "the new head must become current")
        XCTAssertEqual(engine.state, .playing, "the new head must start playing")
        XCTAssertEqual(store.items.map { $0.episode?.guid }, ["next"], "the finished episode's QueueItem must be removed")
        XCTAssertEqual(store.items.map(\.order), [0], "order stays contiguous after auto-advance removes the head")
    }

    // MARK: - An empty queue stops cleanly at idle (no error)

    func test_onFinished_emptyQueue_returnsToIdle_noError() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let onlyEpisode = makeEpisode(context, guid: "only", podcast: podcast)
        try context.save()

        let store = QueueStore(context: context)
        store.add(onlyEpisode)

        let engine = makeEngine()
        engine.load(episode: onlyEpisode, context: context)
        XCTAssertEqual(engine.state, .playing)

        QueueAutoAdvanceCoordinator.handleFinished(onlyEpisode, queueStore: store, playbackEngine: engine, context: context)

        XCTAssertEqual(engine.state, .idle, "an empty queue must stop cleanly at idle, not .failed or any other state")
        XCTAssertNil(engine.currentEpisode)
        XCTAssertTrue(store.items.isEmpty)
    }

    // MARK: - Finishing an episode that was never queued still checks cleanly

    func test_onFinished_episodeNotQueued_leavesQueueUntouched_andAdvancesToHead() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let unqueuedCurrent = makeEpisode(context, guid: "unqueued", podcast: podcast)
        let queuedNext = makeEpisode(context, guid: "queued-next", podcast: podcast)
        try context.save()

        // Per queue-semantics.md: "tapping Play on an episode from a detail
        // screen plays it as the current item; it is not required to be in
        // the queue." Playing `unqueuedCurrent` without adding it to the
        // queue must not error when it finishes.
        let store = QueueStore(context: context)
        store.add(queuedNext)

        let engine = makeEngine()
        engine.load(episode: unqueuedCurrent, context: context)

        QueueAutoAdvanceCoordinator.handleFinished(unqueuedCurrent, queueStore: store, playbackEngine: engine, context: context)

        XCTAssertEqual(engine.currentEpisode?.guid, "queued-next")
        XCTAssertEqual(engine.state, .playing)
        XCTAssertEqual(store.items.map { $0.episode?.guid }, ["queued-next"], "the never-queued episode must not disturb the existing queue")
    }

    // MARK: - The exact closure IWantUrPodApp.init assigns to onFinished

    /// Proves the coordinator is a drop-in body for `PlaybackEngine.onFinished`
    /// (the shape `IWantUrPodApp.init` wires it as — see `IWantUrPodApp.swift`),
    /// not just callable directly. `PlaybackEngineTests` (PlaybackKit) already
    /// proves `onFinished` fires with the finished episode after a real
    /// state-machine transition via the stub player; this proves *this* body
    /// does the right thing once it fires.
    func test_onFinishedClosureShape_matchesAppWiring() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let current = makeEpisode(context, guid: "wired-current", podcast: podcast)
        let next = makeEpisode(context, guid: "wired-next", podcast: podcast)
        try context.save()

        let store = QueueStore(context: context)
        store.add(current)
        store.add(next)

        let engine = makeEngine()
        // Mirrors IWantUrPodApp.init's exact closure body assigned to
        // playbackEngine.onFinished.
        engine.onFinished = { [weak engine] finishedEpisode in
            guard let engine else { return }
            QueueAutoAdvanceCoordinator.handleFinished(finishedEpisode, queueStore: store, playbackEngine: engine, context: context)
        }

        engine.load(episode: current, context: context)
        engine.onFinished?(current)

        XCTAssertEqual(engine.currentEpisode?.guid, "wired-next")
        XCTAssertEqual(engine.state, .playing)
    }
}
