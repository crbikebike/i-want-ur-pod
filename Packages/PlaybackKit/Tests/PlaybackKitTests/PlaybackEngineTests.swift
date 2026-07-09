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
        persistenceInterval: TimeInterval = 5,
        now: @escaping () -> Date = Date.init
    ) -> PlaybackEngine {
        PlaybackEngine(
            player: player,
            localURLResolver: makeResolver(),
            persistenceInterval: persistenceInterval,
            now: now
        )
    }

    /// A small mutable clock test helper: `advance(by:)` moves wall-clock
    /// time forward deterministically, and the closure captures the box so
    /// the engine reads the current instant on every call to `now()`.
    private final class TestClock {
        private(set) var current: Date
        init(start: Date = Date(timeIntervalSince1970: 1_000_000)) {
            current = start
        }
        func advance(by seconds: TimeInterval) {
            current = current.addingTimeInterval(seconds)
        }
        func now() -> Date { current }
    }

    /// Advances `clock` and `stub` together in ~1s increments (mirroring a
    /// live player's periodic time observer), so accumulated deltas stay
    /// under the engine's per-tick cap rather than landing in one big jump.
    private func advancePlayingClock(_ clock: TestClock, _ stub: StubAudioPlayer, bySeconds seconds: Int) {
        for _ in 0..<seconds {
            clock.advance(by: 1)
            stub.advanceTime(by: 1)
        }
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

    // MARK: - Preparing (download-in-progress) state

    func test_beginPreparing_setsPreparingState_evenForNotDownloadedEpisode() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode(downloadState: .notDownloaded)
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)

        engine.beginPreparing(episode: episode, context: context)

        XCTAssertEqual(engine.state, .preparing)
        XCTAssertEqual(engine.currentEpisode?.guid, episode.guid)
        XCTAssertEqual(engine.displayProgress, 0, accuracy: 0.001)
        XCTAssertEqual(stub.loadedURLs.count, 0, "must never touch the player while merely preparing")
        XCTAssertEqual(stub.playCallCount, 0)
    }

    func test_failPreparation_whilePreparing_movesToFailed() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode(downloadState: .notDownloaded)
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)
        engine.beginPreparing(episode: episode, context: context)

        engine.failPreparation("download failed")

        XCTAssertEqual(engine.state, .failed("download failed"))
    }

    func test_failPreparation_outsidePreparing_isNoOp() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode()
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)
        engine.load(episode: episode, context: context)
        XCTAssertEqual(engine.state, .playing)

        engine.failPreparation("stale failure")

        XCTAssertEqual(engine.state, .playing, "a failure from a superseded preparation must not clobber an unrelated state")
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

    // MARK: - Skip intervals

    func test_skipInterval_constantsAreFifteenAndThirty() {
        XCTAssertEqual(SkipInterval.back, 15)
        XCTAssertEqual(SkipInterval.forward, 30)
    }

    /// The mini-player, sheet, and lock screen all skip by `SkipInterval`.
    /// Proves those distances route through `skip(by:)` and land at the right
    /// absolute position (forward 30 then back 15 from 50s → 65s of 100s).
    func test_skipBySharedInterval_seeksToClampedAbsolutePosition() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode(duration: 100)
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)
        engine.load(episode: episode, context: context)   // currentTime 0
        stub.advanceTime(by: 50)                            // now at 50s

        engine.skip(by: SkipInterval.forward)               // 50 + 30 = 80s → 0.80
        XCTAssertEqual(try XCTUnwrap(stub.seekedFractions.last), 0.80, accuracy: 0.0001)

        engine.skip(by: -SkipInterval.back)                 // 80 - 15 = 65s → 0.65
        XCTAssertEqual(try XCTUnwrap(stub.seekedFractions.last), 0.65, accuracy: 0.0001)
    }

    /// Skipping back past the start clamps to 0, never negative.
    func test_skipBack_clampsAtZero() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode(duration: 100)
        context.insert(episode)

        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub)
        engine.load(episode: episode, context: context)     // currentTime 0
        stub.advanceTime(by: 10)                             // now at 10s

        engine.skip(by: -SkipInterval.back)                  // 10 - 15 → clamp to 0
        XCTAssertEqual(try XCTUnwrap(stub.seekedFractions.last), 0.0, accuracy: 0.0001)
    }

    // MARK: - Listening-history session tracking (Wave 1)

    func test_onDidFinishListening_firesOnceOnFinish_withAccumulatedWallClock() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode(guid: "history-ep", duration: 100)
        context.insert(episode)

        let clock = TestClock()
        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub, now: clock.now)

        var calls: [(Episode, Date, TimeInterval)] = []
        engine.onDidFinishListening = { episode, startedAt, seconds in
            calls.append((episode, startedAt, seconds))
        }

        let loadTime = clock.current
        engine.load(episode: episode, context: context)

        clock.advance(by: 1)
        stub.advanceTime(by: 1)
        clock.advance(by: 1)
        stub.advanceTime(by: 1)
        clock.advance(by: 1)
        stub.advanceTime(by: 1)

        stub.finish()

        XCTAssertEqual(calls.count, 1, "exactly one session must be emitted")
        let (finishedEpisode, startedAt, listenedSeconds) = try XCTUnwrap(calls.first)
        XCTAssertEqual(finishedEpisode.guid, "history-ep")
        XCTAssertEqual(startedAt, loadTime)
        XCTAssertEqual(listenedSeconds, 3, accuracy: 0.01)
    }

    func test_onDidFinishListening_pauseDoesNotAccumulate() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode(duration: 100)
        context.insert(episode)

        let clock = TestClock()
        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub, now: clock.now)

        var calls: [(Episode, Date, TimeInterval)] = []
        engine.onDidFinishListening = { episode, startedAt, seconds in
            calls.append((episode, startedAt, seconds))
        }

        engine.load(episode: episode, context: context)

        clock.advance(by: 1)
        stub.advanceTime(by: 1) // 1s playing

        engine.pause()
        // Simulate wall-clock passing while paused — must not be counted.
        clock.advance(by: 10)

        engine.resume()
        clock.advance(by: 1)
        stub.advanceTime(by: 1) // another 1s playing after resume

        stub.finish()

        XCTAssertEqual(calls.count, 1, "pause/resume must remain ONE session, not split into two")
        let (_, _, listenedSeconds) = try XCTUnwrap(calls.first)
        XCTAssertEqual(listenedSeconds, 2, accuracy: 0.01, "only the two playing seconds count, not the 10s paused gap")
    }

    func test_onDidFinishListening_newLoad_finalizesPriorSession_andStartsFresh() throws {
        let context = ModelContext(try makeContainer())
        let first = makeEpisode(guid: "first-history", duration: 100)
        let second = makeEpisode(guid: "second-history", duration: 100)
        context.insert(first)
        context.insert(second)

        let clock = TestClock()
        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub, now: clock.now)

        var calls: [(Episode, Date, TimeInterval)] = []
        engine.onDidFinishListening = { episode, startedAt, seconds in
            calls.append((episode, startedAt, seconds))
        }

        engine.load(episode: first, context: context)
        advancePlayingClock(clock, stub, bySeconds: 4)

        // Loading a new episode finalizes the prior session.
        engine.load(episode: second, context: context)

        XCTAssertEqual(calls.count, 1, "loading a new episode must finalize the prior session")
        XCTAssertEqual(calls.first?.0.guid, "first-history")
        XCTAssertEqual(calls.first?.2 ?? -1, 4, accuracy: 0.01)

        advancePlayingClock(clock, stub, bySeconds: 6)
        stub.finish()

        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.last?.0.guid, "second-history")
        XCTAssertEqual(calls.last?.2 ?? -1, 6, accuracy: 0.01)
    }

    func test_onDidFinishListening_underTwoSecondThreshold_emitsNothing() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode(duration: 100)
        context.insert(episode)

        let clock = TestClock()
        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub, now: clock.now)

        var calls: [(Episode, Date, TimeInterval)] = []
        engine.onDidFinishListening = { episode, startedAt, seconds in
            calls.append((episode, startedAt, seconds))
        }

        engine.load(episode: episode, context: context)
        clock.advance(by: 1)
        stub.advanceTime(by: 1) // only 1s, below the 2s threshold

        engine.returnToIdle()

        XCTAssertTrue(calls.isEmpty, "a session under the 2s threshold must emit nothing")
    }

    func test_onDidFinishListening_finalizesOnAppBackgrounding() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode(duration: 100)
        context.insert(episode)

        let clock = TestClock()
        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub, now: clock.now)

        var calls: [(Episode, Date, TimeInterval)] = []
        engine.onDidFinishListening = { episode, startedAt, seconds in
            calls.append((episode, startedAt, seconds))
        }

        engine.load(episode: episode, context: context)
        advancePlayingClock(clock, stub, bySeconds: 3)

        engine.handleAppBackgrounding()

        XCTAssertEqual(calls.count, 1, "backgrounding must finalize the in-progress session")
        XCTAssertEqual(calls.first?.2 ?? -1, 3, accuracy: 0.01)
    }

    func test_onDidFinishListening_finalizesOnReturnToIdle() throws {
        let context = ModelContext(try makeContainer())
        let episode = makeEpisode(duration: 100)
        context.insert(episode)

        let clock = TestClock()
        let stub = StubAudioPlayer()
        let engine = makeEngine(player: stub, now: clock.now)

        var calls: [(Episode, Date, TimeInterval)] = []
        engine.onDidFinishListening = { episode, startedAt, seconds in
            calls.append((episode, startedAt, seconds))
        }

        engine.load(episode: episode, context: context)
        advancePlayingClock(clock, stub, bySeconds: 3)

        engine.returnToIdle()

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.2 ?? -1, 3, accuracy: 0.01)
    }
}
