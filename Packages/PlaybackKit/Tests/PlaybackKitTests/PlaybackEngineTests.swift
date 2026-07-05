// PlaybackEngineTests — E4-S2/E4-S3 determinate coverage, host `swift test`
// (no real audio; StubAudioPlayer stands in for AVPlayer, an in-memory
// ModelContext stands in for the persisted store). Covers ROADMAP E4-S2/S3
// and docs/spec/playback-state-machine.md:
//   - Play offered iff downloaded (download-first guard, no trap).
//   - Progress persists at least every 5s while playing, and on pause/finished.
//   - Scrub to 50% persists ≈0.5 across a fresh ModelContext (relaunch proxy).
//   - Playing to end sets Episode.isPlayed == true.
//   - Resume seeks to the saved fraction before playing.
//   - State-machine transitions per the spec diagram.
import XCTest
import SwiftData
@testable import PlaybackKit
import PodcastModels

@MainActor
final class PlaybackEngineTests: XCTestCase {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try ModelSchema.makeContainer(inMemory: true)
    }

    private func makeEpisode(
        guid: String = "ep-1",
        downloadState: DownloadState = .downloaded,
        playbackProgress: Double = 0,
        duration: TimeInterval = 100
    ) -> Episode {
        Episode(
            guid: guid,
            title: "Test Episode",
            duration: duration,
            audioURL: URL(string: "https://cdn.example.com/\(guid).mp3")!,
            downloadState: downloadState,
            playbackProgress: playbackProgress
        )
    }

    /// The engine's `localURLResolver` under test: resolves any `.downloaded`
    /// episode to a canned local file URL, `nil` otherwise — mirrors
    /// `DownloadManager.localURL(for:)`'s contract without depending on
    /// DownloadKit.
    private func makeResolver() -> (Episode) -> URL? {
        { episode in
            episode.downloadState.isDownloaded
                ? URL(fileURLWithPath: "/tmp/\(episode.guid).audio")
                : nil
        }
    }

    private func makeEngine(
        player: StubAudioPlayer = StubAudioPlayer(),
        persistenceInterval: TimeInterval = 5
    ) -> PlaybackEngine {
        PlaybackEngine(
            player: player,
            localURLResolver: makeResolver(),
            persistenceInterval: persistenceInterval
        )
    }

    // MARK: - Download-first guard

    func test_load_nonDownloadedEpisode_goesToFailed_notDownloaded_noTrap() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode(downloadState: .notDownloaded)
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)

        engine.load(episode: episode, context: context)

        XCTAssertEqual(engine.state, .failed("not downloaded"))
        XCTAssertEqual(stub.loadedURLs.count, 0, "must never touch the player for a non-downloaded episode")
    }

    func test_load_downloadedEpisode_goesToPlaying() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode()
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)

        engine.load(episode: episode, context: context)

        XCTAssertEqual(engine.state, .playing)
        XCTAssertEqual(stub.loadedURLs, [URL(fileURLWithPath: "/tmp/\(episode.guid).audio")])
        XCTAssertEqual(stub.playCallCount, 1)
    }

    // MARK: - Progress persistence cadence

    func test_progressPersists_atLeastEvery5Seconds_andOnPause() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode(duration: 100)
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub, persistenceInterval: 5)
        engine.load(episode: episode, context: context)

        XCTAssertEqual(episode.playbackProgress, 0, accuracy: 0.001)

        // Under the 5s interval: no write yet.
        stub.advanceTime(by: 3)
        XCTAssertEqual(episode.playbackProgress, 0, accuracy: 0.001)

        // Crossing the 5s interval: a write happens.
        stub.advanceTime(by: 2) // cumulative 5s
        XCTAssertEqual(episode.playbackProgress, 0.05, accuracy: 0.001)

        // Another 5s tick: another write.
        stub.advanceTime(by: 5) // cumulative 10s
        XCTAssertEqual(episode.playbackProgress, 0.10, accuracy: 0.001)

        // Pausing forces an immediate write regardless of the interval.
        stub.advanceTime(by: 2) // cumulative 12s, under the next 5s boundary
        engine.pause()
        XCTAssertEqual(engine.state, .paused)
        XCTAssertEqual(episode.playbackProgress, 0.12, accuracy: 0.001)
    }

    // MARK: - Scrub persists across a fresh ModelContext (relaunch proxy)

    func test_scrubTo50Percent_persists_acrossFreshModelContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let episode = makeEpisode(guid: "scrub-ep", duration: 200)
        context.insert(episode)
        try context.save()

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)
        engine.load(episode: episode, context: context)

        engine.seek(toFraction: 0.5)

        XCTAssertEqual(episode.playbackProgress, 0.5, accuracy: 0.001)
        XCTAssertEqual(stub.seekedFractions.last, 0.5)

        // Simulate an app relaunch: read the same guid back from a brand new
        // ModelContext on the same (in-memory) container. Fetch-all-then-
        // filter (rather than a `#Predicate`) sidesteps the macro's
        // non-Sendable KeyPath warning under strict concurrency.
        let freshContext = ModelContext(container)
        let reloaded = try freshContext.fetch(FetchDescriptor<Episode>())
            .filter { $0.guid == "scrub-ep" }
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.playbackProgress ?? -1, 0.5, accuracy: 0.001)
    }

    // MARK: - Smooth display progress (E6-S2), decoupled from the 5s write

    func test_displayProgress_updatesOnEveryTick_withoutRequiringAModelWrite() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode(duration: 100)
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub, persistenceInterval: 5)
        engine.load(episode: episode, context: context)

        XCTAssertEqual(engine.displayProgress, 0, accuracy: 0.001)

        // A ~1s tick under the 5s persistence boundary: the model is NOT
        // written yet, but displayProgress advances smoothly regardless.
        stub.advanceTime(by: 1)
        XCTAssertEqual(episode.playbackProgress, 0, accuracy: 0.001, "no model write under the 5s interval")
        XCTAssertEqual(engine.displayProgress, 0.01, accuracy: 0.001, "displayProgress tracks every tick")

        stub.advanceTime(by: 2) // cumulative 3s, still under 5s
        XCTAssertEqual(episode.playbackProgress, 0, accuracy: 0.001)
        XCTAssertEqual(engine.displayProgress, 0.03, accuracy: 0.001)

        // Crossing 5s: now the model write happens AND displayProgress stays
        // in step (proving they agree, just on different cadences).
        stub.advanceTime(by: 2) // cumulative 5s
        XCTAssertEqual(episode.playbackProgress, 0.05, accuracy: 0.001)
        XCTAssertEqual(engine.displayProgress, 0.05, accuracy: 0.001)
    }

    func test_displayProgress_reflectsSeek_andResetsToZeroOnIdle() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode(duration: 200)
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)
        engine.load(episode: episode, context: context)

        engine.seek(toFraction: 0.5)
        XCTAssertEqual(engine.displayProgress, 0.5, accuracy: 0.001)

        engine.returnToIdle()
        XCTAssertEqual(engine.displayProgress, 0, accuracy: 0.001)
    }

    // MARK: - Play to end -> isPlayed

    func test_playToEnd_setsIsPlayedTrue() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode(duration: 50)
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)
        engine.load(episode: episode, context: context)

        stub.finish()

        XCTAssertEqual(engine.state, .finished)
        XCTAssertEqual(episode.playbackProgress, 1.0, accuracy: 0.0001)
        XCTAssertTrue(episode.isPlayed)
    }

    // MARK: - Resume seek

    func test_load_withSavedProgress_seeksBeforePlaying() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode(duration: 100)
        episode.playbackProgress = 0.5
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)

        engine.load(episode: episode, context: context)

        XCTAssertEqual(stub.seekedFractions, [0.5])
        XCTAssertEqual(stub.playCallCount, 1, "play() must still happen once, after the seek")
        XCTAssertEqual(engine.state, .playing)
    }

    func test_load_atOrAboveIsPlayedThreshold_doesNotReSeek() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode(duration: 100)
        episode.playbackProgress = 0.99
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)

        engine.load(episode: episode, context: context)

        XCTAssertTrue(stub.seekedFractions.isEmpty, "an already-played episode replays from the start, not mid-seek")
        XCTAssertEqual(engine.state, .playing)
    }

    // MARK: - State machine transitions

    func test_pauseAndResume_toggleState() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode()
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)
        engine.load(episode: episode, context: context)
        XCTAssertEqual(engine.state, .playing)

        engine.pause()
        XCTAssertEqual(engine.state, .paused)
        XCTAssertEqual(stub.pauseCallCount, 1)

        engine.resume()
        XCTAssertEqual(engine.state, .playing)
        XCTAssertEqual(stub.playCallCount, 2)
    }

    func test_loadError_goesToFailed() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode()
        context.insert(episode)

        let stub = StubAudioPlayer()
        stub.loadError = StubLoadError()
        let engine = makeEngine(player: stub)

        engine.load(episode: episode, context: context)

        XCTAssertEqual(engine.state, .failed("stub load error"))
    }

    func test_asyncItemFailure_afterLoad_drivesEngineToFailed() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode()
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)
        engine.load(episode: episode, context: context)
        XCTAssertEqual(engine.state, .playing)

        // The item decodes/fails asynchronously *after* load returned — the
        // real AVPlayerItem.status == .failed path.
        stub.failItem("corrupt asset")

        XCTAssertEqual(engine.state, .failed("corrupt asset"))
    }

    func test_failed_thenLoadAnotherDownloadedEpisode_succeeds() throws {
        let context = ModelContext(try makeContainer())
        let badEpisode = makeEpisode(guid: "bad", downloadState: .notDownloaded)
        let goodEpisode = makeEpisode(guid: "good", downloadState: .downloaded)
        context.insert(badEpisode)
        context.insert(goodEpisode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)

        engine.load(episode: badEpisode, context: context)
        XCTAssertEqual(engine.state, .failed("not downloaded"))

        engine.load(episode: goodEpisode, context: context)
        XCTAssertEqual(engine.state, .playing)
        XCTAssertEqual(engine.currentEpisode?.guid, "good")
    }

    func test_loadNewEpisode_whilePlaying_replacesCurrent() throws {
        let context = ModelContext(try makeContainer())
        let first = makeEpisode(guid: "first")
        let second = makeEpisode(guid: "second")
        context.insert(first)
        context.insert(second)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)

        engine.load(episode: first, context: context)
        XCTAssertEqual(engine.currentEpisode?.guid, "first")

        engine.load(episode: second, context: context)
        XCTAssertEqual(engine.state, .playing)
        XCTAssertEqual(engine.currentEpisode?.guid, "second")
        XCTAssertEqual(stub.loadedURLs.count, 2)
    }

    // MARK: - E5-S3 auto-advance seam

    func test_onFinished_firesWithTheFinishedEpisode_afterReachingFinished() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode(guid: "finishing")
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)
        engine.load(episode: episode, context: context)

        var firedWith: Episode?
        engine.onFinished = { finished in firedWith = finished }

        stub.finish()

        XCTAssertEqual(engine.state, .finished, "onFinished must fire after the state machine reaches .finished, not instead of it")
        XCTAssertEqual(firedWith?.guid, "finishing")
    }

    func test_onFinished_isOptional_noCrashWhenUnset() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode()
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)
        engine.load(episode: episode, context: context)

        stub.finish() // no onFinished set — must not trap

        XCTAssertEqual(engine.state, .finished)
    }

    func test_returnToIdle_clearsCurrentEpisodeAndGoesIdle() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode()
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)
        engine.load(episode: episode, context: context)
        stub.finish()
        XCTAssertEqual(engine.state, .finished)

        engine.returnToIdle()

        XCTAssertEqual(engine.state, .idle)
        XCTAssertNil(engine.currentEpisode)
    }
}
