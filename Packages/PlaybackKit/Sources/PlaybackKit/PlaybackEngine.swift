// PlaybackEngine — the app-scoped playback service (E4-S2, E4-S3).
// Architecture source: docs/spec/playback-state-machine.md. App-scoped like
// DownloadManager (Packages/DownloadKit/.../DownloadManager.swift) and
// AppSources's SearchCoordinator: created once in IWantUrPodApp and injected
// via `.environment`, never built inside AppShell's tab switch (frozen nav
// contract, definition-of-done.md §5).
//
// PlaybackKit deliberately does NOT depend on DownloadKit (see Package.swift
// — only PodcastModels). Resolving a `.downloaded` episode's local file is
// DownloadKit's job (`DownloadManager.localURL(for:)`); this engine takes
// that resolution as an injected closure (`localURLResolver`) so the two
// packages stay decoupled and `IWantUrPodApp` wires them together
// (`{ downloadManager.localURL(for: $0) }`), the same pattern already used
// for `DownloadManager`'s own `downloader`/`store` seams.
import Foundation
import Observation
import SwiftData
import PodcastModels

@MainActor
@Observable
public final class PlaybackEngine {

    /// Current player state (`playback-state-machine.md`'s transition table).
    public private(set) var state: PlaybackState = .idle

    /// The episode currently loaded (survives into `.paused`/`.finished`/
    /// `.failed` so the UI can tell which row is "current"); `nil` at `.idle`.
    public private(set) var currentEpisode: Episode?

    /// Smooth, per-tick playback position as a fraction (`0...1`) of the
    /// current episode's duration, for in-app UI (E6-S2's Now Playing
    /// scrubber + elapsed label). **Decoupled from the 5s model-persistence
    /// cadence:** `Episode.playbackProgress` is only written every 5s (and on
    /// pause/finish/seek), which makes an in-app bar that reads it stall then
    /// jump every 5 seconds. This value instead updates on every ~1s player
    /// time tick (and on load/seek/pause/finish/idle), so the bar advances
    /// smoothly like the lock screen does, without forcing a model write each
    /// tick. `0` when no episode is loaded.
    public private(set) var displayProgress: Double = 0

    /// Fired after the engine reaches `.finished`, with the episode that just
    /// finished (E5-S3 auto-advance seam, `docs/spec/queue-semantics.md`).
    ///
    /// `PlaybackKit` intentionally has no notion of a queue or `QueueItem`
    /// (its `Package.swift` depends only on `PodcastModels`, not any app-level
    /// queue logic) — this closure is how `IWantUrPodApp` couples the two
    /// without either package depending on the other. The app wires this in
    /// `init()` to a small coordinator that asks the queue store to drop the
    /// finished episode's entry, then either `load(episode:context:)`s the new
    /// head or, if the queue is empty, calls ``returnToIdle()``. Mirrors the
    /// `localURLResolver` seam's decoupling pattern above.
    public var onFinished: ((Episode) -> Void)?

    /// Fired once a play session ends (episode replaced, finished, returned
    /// to idle, or backgrounded) with at least the 2s minimum listened —
    /// listening-history logging seam (episode listening history, Wave 1).
    ///
    /// Like `onFinished`, `PlaybackKit` deliberately has no notion of a
    /// `PlayEvent` or `ModelContext`-backed log — this closure is how
    /// `IWantUrPodApp` couples the two without either package depending on
    /// the other. Emits `(episode, sessionStartedAt, listenedSeconds)`. Both
    /// user-initiated plays and queue auto-advance drive this (both call
    /// `load(episode:context:)`), which is intended.
    public var onDidFinishListening: ((Episode, Date, TimeInterval) -> Void)?

    /// How often progress is written while playing, per the spec's "at least
    /// every 5s while playing" cadence. `var` (not `let`) only so tests can
    /// shrink it; production always uses the 5s default.
    private let persistenceInterval: TimeInterval

    private let player: AudioPlaying
    private let localURLResolver: (Episode) -> URL?
    private let nowPlayingCenter: NowPlayingCenter

    /// Wall-clock provider for listening-session accounting. Defaults to
    /// `Date()` in production; tests inject a controllable clock so
    /// accumulation is deterministic without real sleeps.
    private let now: () -> Date

    private var modelContext: ModelContext?
    private var lastPersistedTime: TimeInterval = 0

    /// The in-progress listening session, if any. `nil` when idle or paused
    /// (no session ever started, or the prior one was already finalized).
    private var sessionEpisode: Episode?
    private var sessionStartedAt: Date?
    private var sessionListenedSeconds: TimeInterval = 0
    /// Wall-clock instant of the last `.playing` tick, used to compute the
    /// delta to accumulate into `sessionListenedSeconds`. `nil` while paused
    /// so paused wall-clock time is never counted.
    private var lastPlayingTick: Date?

    /// Session emits only once at least this many seconds were actually
    /// listened — drops accidental taps.
    private static let minimumListenedSecondsToEmit: TimeInterval = 2
    /// Caps any single accumulated delta so a stall/gap in ticks can't
    /// over-count wall-clock time as listened time.
    private static let maximumTickDelta: TimeInterval = 1.5

    /// - Parameters:
    ///   - player: The playback seam. Defaults to the live
    ///     `AVPlayerAudioPlaying`; tests inject a stub.
    ///   - localURLResolver: Resolves a `.downloaded` episode to its local
    ///     file URL. The app wires this to `DownloadManager.localURL(for:)`;
    ///     tests supply a canned lookup.
    ///   - persistenceInterval: Seconds between progress writes while
    ///     playing. Defaults to the spec's 5s; tests may shrink it.
    ///   - now: Wall-clock provider for listening-session accounting.
    ///     Defaults to `Date()`; tests inject a controllable clock.
    public init(
        player: AudioPlaying = AVPlayerAudioPlaying(),
        localURLResolver: @escaping (Episode) -> URL?,
        persistenceInterval: TimeInterval = 5,
        now: @escaping () -> Date = Date.init
    ) {
        self.player = player
        self.localURLResolver = localURLResolver
        self.persistenceInterval = persistenceInterval
        self.now = now
        self.nowPlayingCenter = NowPlayingCenter()

        self.player.onTimeUpdate = { [weak self] time in
            self?.handleTimeUpdate(time)
        }
        self.player.onFinish = { [weak self] in
            self?.handleFinish()
        }
        self.player.onError = { [weak self] message in
            self?.handleError(message)
        }

        // Safe to capture `self` here: every stored property above is
        // already assigned, so `self` is fully initialized.
        nowPlayingCenter.configureRemoteCommands(
            onPlay: { [weak self] in self?.resume() },
            onPause: { [weak self] in self?.pause() },
            onSkipForward: { [weak self] in self?.skip(by: SkipInterval.forward) },
            onSkipBackward: { [weak self] in self?.skip(by: -SkipInterval.back) },
            onScrub: { [weak self] absoluteSeconds in
                guard let self, let episode = self.currentEpisode, episode.duration > 0 else { return }
                self.seek(toFraction: absoluteSeconds / episode.duration)
            }
        )
    }

    // MARK: - Loading

    /// Loads `episode` for playback.
    ///
    /// **Download-first guard:** if `episode.downloadState` isn't
    /// `.downloaded` (or no local file can be resolved for it), this is a
    /// programmer error the UI must prevent — Play is only ever offered for
    /// downloaded episodes. Rather than trap, the engine lands in
    /// `.failed("not downloaded")`.
    ///
    /// **Resume:** if `0 < episode.playbackProgress < 0.98`, seeks to that
    /// fraction before playing.
    public func load(episode: Episode, context: ModelContext) {
        finalizeSession()
        beginSession(for: episode)

        modelContext = context

        guard episode.downloadState.isDownloaded, let url = localURLResolver(episode) else {
            currentEpisode = episode
            state = .failed("not downloaded")
            return
        }

        currentEpisode = episode
        state = .loading
        publishNowPlaying()

        AudioSessionConfigurator.activatePlaybackSession()

        do {
            try player.load(url: url, knownDuration: episode.duration)
        } catch {
            state = .failed(Self.message(for: error))
            publishNowPlaying()
            return
        }

        if episode.playbackProgress > 0, episode.playbackProgress < 0.98 {
            player.seek(toFraction: episode.playbackProgress)
        }
        lastPersistedTime = player.currentTime
        updateDisplayProgress(seconds: player.currentTime)

        player.play()
        state = .playing
        startPlayingTick()
        publishNowPlaying()
    }

    /// Marks `episode` as the current item while its audio is still
    /// downloading, landing the engine at `.preparing` (mini-player shown,
    /// nothing playable yet) — the spec's
    /// "idle --play(not-downloaded episode)--> preparing" transition.
    ///
    /// **Stays decoupled from DownloadKit**, same as the `localURLResolver`
    /// and `onFinished` seams documented above: `PlaybackKit` has no notion
    /// of a download in progress, so it does not start or track one here.
    /// The app-level coordinator that offers Play for a not-yet-downloaded
    /// episode calls this to reflect the "current but not yet playable" UI
    /// state immediately, kicks off the real download itself
    /// (`DownloadManager`), and then calls `load(episode:context:)` once the
    /// download finishes (or `failPreparation(_:)` if it fails).
    ///
    /// Deliberately does not touch `player` or activate the audio session —
    /// there's no file to hand the player yet.
    public func beginPreparing(episode: Episode, context: ModelContext) {
        modelContext = context
        currentEpisode = episode
        displayProgress = 0
        state = .preparing
        publishNowPlaying()
    }

    /// Reports that the download started by `beginPreparing(episode:context:)`
    /// failed, moving `.preparing --download failed--> failed` per the spec.
    /// A no-op outside `.preparing` (e.g. the user already backed out to
    /// `.idle`, or a stale callback arrives after a newer item replaced this
    /// one) so a late failure can't clobber unrelated state.
    public func failPreparation(_ message: String) {
        guard state == .preparing else { return }
        state = .failed(message)
        publishNowPlaying()
    }

    // MARK: - Transport

    public func pause() {
        guard state == .playing, let episode = currentEpisode else { return }
        player.pause()
        state = .paused
        accumulateListeningTick()
        lastPlayingTick = nil
        persist(episode: episode, time: player.currentTime)
        updateDisplayProgress(seconds: player.currentTime)
        publishNowPlaying()
    }

    public func resume() {
        guard state == .paused, currentEpisode != nil else { return }
        player.play()
        state = .playing
        startPlayingTick()
        publishNowPlaying()
    }

    /// Seeks to `fraction` (`0...1`) of the current episode's duration and
    /// persists immediately (scrubbing is one of the spec's explicit
    /// persistence triggers, not just the 5s cadence).
    public func seek(toFraction fraction: Double) {
        guard let episode = currentEpisode else { return }
        let clamped = min(max(fraction, 0), 1)
        player.seek(toFraction: clamped)
        persist(episode: episode, time: player.currentTime)
        updateDisplayProgress(seconds: player.currentTime)
        publishNowPlaying()
    }

    /// Skips by `seconds` (negative to skip back), clamped to the item's
    /// bounds, and persists immediately (mirrors `seek(toFraction:)`).
    public func skip(by seconds: TimeInterval) {
        guard let episode = currentEpisode, episode.duration > 0 else { return }
        let targetSeconds = min(max(player.currentTime + seconds, 0), episode.duration)
        seek(toFraction: targetSeconds / episode.duration)
    }

    /// Returns the engine to `.idle` with no current episode, publishing an
    /// empty Now Playing state (mini-player hides, per `navigation-map.md`).
    ///
    /// Used by the app's auto-advance coupling (E5-S3) when the just-finished
    /// episode's queue entry is removed and the queue is left empty — the
    /// spec's "finished --queue empty--> idle" transition, which stops
    /// cleanly rather than lingering at `.finished` or erroring.
    public func returnToIdle() {
        finalizeSession()
        currentEpisode = nil
        displayProgress = 0
        state = .idle
        publishNowPlaying()
    }

    /// Call from the app's scene-phase observer on backgrounding. Forces a
    /// persistence write per the spec's "on backgrounding" cadence rule,
    /// independent of the 5s ticking cadence, and finalizes the in-progress
    /// listening session (listening-history logging, Wave 1).
    public func handleAppBackgrounding() {
        finalizeSession()
        guard let episode = currentEpisode, state == .playing || state == .paused else { return }
        persist(episode: episode, time: player.currentTime)
    }

    // MARK: - Player callbacks

    private func handleTimeUpdate(_ time: TimeInterval) {
        guard state == .playing, let episode = currentEpisode else { return }
        accumulateListeningTick()
        if time - lastPersistedTime >= persistenceInterval {
            persist(episode: episode, time: time)
        }
        // Advance the smooth in-app display value on every tick, independent
        // of the 5s persistence write above.
        updateDisplayProgress(seconds: time)
        publishNowPlaying(elapsedOverride: time)
    }

    private func handleFinish() {
        guard let episode = currentEpisode else { return }
        episode.playbackProgress = 1.0
        try? modelContext?.save()
        lastPersistedTime = player.currentTime
        displayProgress = 1.0
        state = .finished
        publishNowPlaying()
        onFinished?(episode)
        finalizeSession()
    }

    /// Recomputes the smooth `displayProgress` fraction from an absolute
    /// `seconds` position and the current episode's duration. A zero/unknown
    /// duration leaves it at `0` (mirrors `persist`'s guard).
    private func updateDisplayProgress(seconds: TimeInterval) {
        guard let episode = currentEpisode, episode.duration > 0 else {
            displayProgress = 0
            return
        }
        displayProgress = min(max(seconds / episode.duration, 0), 1)
    }

    /// The item failed to become playable *after* `load` returned (async
    /// decode/asset failure) — the spec's `loading --error--> failed` for the
    /// real player. Ignored if we've already left the current episode (a
    /// late failure from a replaced item).
    private func handleError(_ message: String) {
        guard currentEpisode != nil, state == .loading || state == .playing || state == .paused else { return }
        state = .failed(message)
        publishNowPlaying()
    }

    // MARK: - Persistence

    /// Writes `time` (seconds) as a fraction of `episode.duration` onto
    /// `episode.playbackProgress` and saves. The model clamps to `0...1`
    /// itself (`Episode.init`/setter), so no duplicate clamping logic here
    /// beyond guarding a zero/unknown duration.
    private func persist(episode: Episode, time: TimeInterval) {
        if episode.duration > 0 {
            episode.playbackProgress = min(max(time / episode.duration, 0), 1)
        }
        try? modelContext?.save()
        lastPersistedTime = time
    }

    // MARK: - Now Playing

    private func publishNowPlaying(elapsedOverride: TimeInterval? = nil) {
        guard let episode = currentEpisode else {
            nowPlayingCenter.clear()
            return
        }
        let elapsed = elapsedOverride ?? (episode.duration * episode.playbackProgress)
        nowPlayingCenter.update(
            episode: episode,
            podcastTitle: episode.podcast?.title ?? "",
            state: state,
            elapsed: elapsed
        )
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Couldn't play this episode."
    }

    // MARK: - Listening-history session tracking (Wave 1)

    /// Starts a fresh listening session for `episode`. Called at the top of
    /// `load(episode:context:)`, after any prior session has been finalized.
    private func beginSession(for episode: Episode) {
        sessionEpisode = episode
        sessionStartedAt = now()
        sessionListenedSeconds = 0
        lastPlayingTick = nil
    }

    /// Marks the instant playback actually starts/resumes, so the next
    /// `accumulateListeningTick()` computes a delta from here rather than
    /// from session start (which may predate the player actually playing).
    private func startPlayingTick() {
        lastPlayingTick = now()
    }

    /// Adds the wall-clock delta since the last playing tick to the
    /// in-progress session, capped at `maximumTickDelta` so a stall/gap in
    /// ticks can't over-count. A `nil` `lastPlayingTick` (first tick since
    /// `startPlayingTick()`) contributes no delta, just anchors the clock.
    private func accumulateListeningTick() {
        let currentInstant = now()
        if let last = lastPlayingTick {
            let delta = max(currentInstant.timeIntervalSince(last), 0)
            sessionListenedSeconds += min(delta, Self.maximumTickDelta)
        }
        lastPlayingTick = currentInstant
    }

    /// Ends the in-progress session (if any), emitting
    /// `onDidFinishListening` only when at least `minimumListenedSecondsToEmit`
    /// was actually listened. Safe to call with no active session (no-op).
    private func finalizeSession() {
        guard let episode = sessionEpisode, let startedAt = sessionStartedAt else { return }
        if lastPlayingTick != nil {
            accumulateListeningTick()
        }
        let listenedSeconds = sessionListenedSeconds

        sessionEpisode = nil
        sessionStartedAt = nil
        sessionListenedSeconds = 0
        lastPlayingTick = nil

        guard listenedSeconds >= Self.minimumListenedSecondsToEmit else { return }
        onDidFinishListening?(episode, startedAt, listenedSeconds)
    }
}
