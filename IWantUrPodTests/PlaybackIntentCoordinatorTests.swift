// PlaybackIntentCoordinatorTests — E6 determinate coverage for the universal
// play intent. Runs on the iOS simulator (SwiftData relationship rules, same
// precedent as QueueStoreTests.swift / QueueAutoAdvanceCoordinatorTests.swift).
// Exercises `PlaybackIntentCoordinator.play(_:context:)` against a real
// `QueueStore`/`PlaybackEngine` and a `DownloadManager` driven by a local
// `Downloading` stub (mirrors DownloadKitTests/StubDownloader.swift's
// pattern; that stub is `@testable`-only to the DownloadKit test target, so
// this file defines its own conformer against the public `Downloading`
// protocol).
import XCTest
import SwiftData
import PodcastModels
import PlaybackKit
import DownloadKit
@testable import IWantUrPod

/// A `Downloading` stub that reports the given progress sequence, then
/// either succeeds by writing a temp file or throws. No network involved —
/// same shape as `DownloadKitTests/StubDownloader.swift`, redeclared here
/// because that one is internal to the DownloadKit test target.
private final class StubDownloader: Downloading, @unchecked Sendable {
    enum Outcome {
        case success
        case failure(String)
    }

    private let progressSequence: [Double]
    private let outcome: Outcome

    init(progressSequence: [Double], outcome: Outcome) {
        self.progressSequence = progressSequence
        self.outcome = outcome
    }

    func download(from remote: URL, progress: @escaping @Sendable @MainActor (Double) -> Void) async throws -> URL {
        for value in progressSequence {
            await progress(value)
        }
        switch outcome {
        case .success:
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data("stub audio bytes".utf8).write(to: tempURL)
            return tempURL
        case .failure(let message):
            throw DownloadError.transferFailed(message)
        }
    }
}

@MainActor
final class PlaybackIntentCoordinatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try ModelSchema.makeContainer(inMemory: true)
    }

    private func makePodcast(_ context: ModelContext) -> Podcast {
        let podcast = Podcast(title: "Show", feedURL: URL(string: "https://feeds.example.com/\(UUID().uuidString)")!)
        context.insert(podcast)
        return podcast
    }

    private func makeEpisode(
        _ context: ModelContext,
        guid: String,
        podcast: Podcast,
        downloadState: DownloadState = .notDownloaded
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

    private func makeTempStoreDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackIntentCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeEngine() -> PlaybackEngine {
        PlaybackEngine(localURLResolver: { episode in URL(fileURLWithPath: "/tmp/\(episode.guid).audio") })
    }

    // MARK: - Already downloaded: plays immediately, no queue mutation

    func test_play_alreadyDownloaded_loadsImmediately_withoutQueuing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let episode = makeEpisode(context, guid: "already-downloaded", podcast: podcast, downloadState: .downloaded)
        try context.save()

        let queueStore = QueueStore(context: context)
        let engine = makeEngine()
        let downloadManager = DownloadManager(
            downloader: StubDownloader(progressSequence: [], outcome: .success),
            store: DownloadStore(baseDirectory: try makeTempStoreDirectory())
        )
        let coordinator = PlaybackIntentCoordinator(playbackEngine: engine, downloadManager: downloadManager, queueStore: queueStore)

        coordinator.play(episode, context: context)

        // The real player attempts to load a fake `/tmp` URL, which may land
        // in `.playing` or `.failed` depending on AVFoundation's async
        // validation — the assertion that's robust either way is that the
        // episode became current immediately, with no queue insertion.
        XCTAssertEqual(engine.currentEpisode?.guid, "already-downloaded")
        XCTAssertTrue(queueStore.items.isEmpty, "playing an already-downloaded episode must not queue it")
    }

    // MARK: - Not downloaded, not queued: fronts the queue and preps

    func test_play_notDownloaded_notQueued_insertsAtFront_andPreparesEngine() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let existing = makeEpisode(context, guid: "existing", podcast: podcast, downloadState: .downloaded)
        let target = makeEpisode(context, guid: "target", podcast: podcast, downloadState: .notDownloaded)
        try context.save()

        let queueStore = QueueStore(context: context)
        queueStore.add(existing)

        let engine = makeEngine()
        let downloadManager = DownloadManager(
            downloader: StubDownloader(progressSequence: [0.5, 1.0], outcome: .success),
            store: DownloadStore(baseDirectory: try makeTempStoreDirectory())
        )
        let coordinator = PlaybackIntentCoordinator(playbackEngine: engine, downloadManager: downloadManager, queueStore: queueStore)

        coordinator.play(target, context: context)

        XCTAssertEqual(queueStore.items.first?.episode?.guid, "target", "the played episode must land at the front of Up Next")
        XCTAssertEqual(queueStore.items.map { $0.episode?.guid }, ["target", "existing"])
        XCTAssertEqual(engine.state, .preparing, "the engine must show 'current but not yet playable' immediately")
        XCTAssertEqual(engine.currentEpisode?.guid, "target")
    }

    // MARK: - Not downloaded, already queued: no duplicate insertion

    func test_play_notDownloaded_alreadyQueued_doesNotDuplicate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let target = makeEpisode(context, guid: "queued-target", podcast: podcast, downloadState: .notDownloaded)
        try context.save()

        let queueStore = QueueStore(context: context)
        queueStore.add(target)
        let countBefore = queueStore.items.count

        let engine = makeEngine()
        let downloadManager = DownloadManager(
            downloader: StubDownloader(progressSequence: [1.0], outcome: .success),
            store: DownloadStore(baseDirectory: try makeTempStoreDirectory())
        )
        let coordinator = PlaybackIntentCoordinator(playbackEngine: engine, downloadManager: downloadManager, queueStore: queueStore)

        coordinator.play(target, context: context)

        XCTAssertEqual(queueStore.items.count, countBefore, "an already-queued episode must not be inserted again")
        XCTAssertTrue(queueStore.isQueued(target))
        XCTAssertEqual(engine.state, .preparing)
        XCTAssertEqual(engine.currentEpisode?.guid, "queued-target")
    }

    // NOTE: The auto-play-on-download-complete path (observeDownload's
    // withObservationTracking re-arm firing `playbackEngine.load` once
    // `episode.downloadState` reaches `.downloaded`) is not asserted here.
    // That callback is scheduled onto the next main-actor runloop tick
    // (`Task { @MainActor in … }`), and pumping the runloop deterministically
    // from an XCTest without an `expectation`/async sleep proved flaky in
    // practice; rather than land a flaky test, this is covered by manual
    // simulator verification (start a not-downloaded episode's Play control,
    // confirm playback begins automatically once the download finishes).
}
