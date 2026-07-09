// PlaybackIntentCoordinator — couples PlaybackEngine + DownloadManager +
// QueueStore for the universal "play" intent (E6). Architecture source:
// docs/spec/playback-state-machine.md's "idle --play(not-downloaded
// episode)--> preparing" transition + docs/spec/queue-semantics.md (front
// insertion is the "play now" case the queue spec carves out).
//
// Hitting Play anywhere on a not-downloaded, not-queued episode must: insert
// it at the TOP of Up Next, make it the current (`.preparing`) episode,
// auto-start its download, and auto-play once the download completes. If
// already downloaded, it plays immediately. Both `PlaybackKit` and
// `DownloadKit` deliberately know nothing about each other or about
// `QueueItem`/`QueueStore` (see `PlaybackEngine.beginPreparing`'s and
// `onFinished`'s doc comments) — this app-target coordinator is the glue,
// same precedent as `QueueAutoAdvanceCoordinator` for the finished→auto-
// advance seam. Extracted into its own type (rather than inline call sites)
// so every "Play" control in the app — Podcast Detail, Up Next, Home — can
// share one implementation and it is unit-testable on its own.
import Foundation
import Observation
import SwiftData
import PodcastModels
import PlaybackKit
import DownloadKit

@MainActor
@Observable
public final class PlaybackIntentCoordinator {
    private let playbackEngine: PlaybackEngine
    private let downloadManager: DownloadManager
    private let queueStore: QueueStore

    /// The episode a `play(_:context:)` call is currently waiting on a
    /// download for. Guards `observeDownload(of:context:)`'s re-armed
    /// callback against acting on a stale episode if a newer `play(_:context:)`
    /// call (or an unrelated download) supersedes it before this one's
    /// download finishes.
    private var pendingPlayEpisodeID: UUID?

    /// - Parameters:
    ///   - playbackEngine: The shared engine this coordinator drives into
    ///     `.preparing`/loaded once audio is available.
    ///   - downloadManager: The shared manager this coordinator starts a
    ///     download through when `episode` isn't downloaded yet.
    ///   - queueStore: The shared Up Next store this coordinator inserts
    ///     `episode` into at the front, per the universal play intent.
    public init(playbackEngine: PlaybackEngine, downloadManager: DownloadManager, queueStore: QueueStore) {
        self.playbackEngine = playbackEngine
        self.downloadManager = downloadManager
        self.queueStore = queueStore
    }

    /// The universal play intent: hitting Play anywhere on `episode`.
    ///
    /// - Already `.downloaded`: loads (and thus plays) it immediately — no
    ///   queue mutation, matching `queue-semantics.md`'s "playing from a
    ///   detail screen is not required to queue the episode" rule.
    /// - Not downloaded: inserts `episode` at the front of Up Next (unless
    ///   it's already queued somewhere), marks it current via
    ///   `beginPreparing(episode:context:)` (`.preparing` state, mini-player
    ///   shows immediately), starts its download if one isn't already in
    ///   flight, and arms `observeDownload(of:context:)` to auto-play once
    ///   the download lands.
    public func play(_ episode: Episode, context: ModelContext) {
        if episode.downloadState.isDownloaded {
            playbackEngine.load(episode: episode, context: context)
            return
        }

        if !queueStore.isQueued(episode) {
            queueStore.insertAtFront(episode)
        }
        pendingPlayEpisodeID = episode.id
        playbackEngine.beginPreparing(episode: episode, context: context)
        if !episode.downloadState.isDownloading {
            Task { await downloadManager.download(episode, context: context) }
        }
        observeDownload(of: episode, context: context)
    }

    /// Watches `episode.downloadState` for the transition that resolves this
    /// `play(_:context:)` call, re-arming itself each tick.
    ///
    /// `withObservationTracking`'s `onChange` fires on the *willSet* of the
    /// observed property, before the new value is actually visible — reading
    /// `episode.downloadState` synchronously inside `onChange` would still see
    /// the old value. Hopping to the next main-actor tick (`Task { @MainActor
    /// in … }`) lets the mutation land first, so the `switch` below observes
    /// the state `downloadManager.download(_:context:)` just wrote.
    ///
    /// `pendingPlayEpisodeID == episode.id` guards every branch: if a newer
    /// `play(_:context:)` call (a different episode, or the same one retried)
    /// has since become the pending intent, this stale observation must not
    /// clobber it with an out-of-order load/failure.
    private func observeDownload(of episode: Episode, context: ModelContext) {
        withObservationTracking {
            _ = episode.downloadState
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.pendingPlayEpisodeID == episode.id else { return }
                switch episode.downloadState {
                case .downloaded:
                    self.pendingPlayEpisodeID = nil
                    self.playbackEngine.load(episode: episode, context: context)
                case .failed(let message):
                    self.pendingPlayEpisodeID = nil
                    self.playbackEngine.failPreparation(message ?? "Download failed.")
                default:
                    // Still `.notDownloaded`/`.downloading(progress:)` — keep
                    // watching for the next mutation.
                    self.observeDownload(of: episode, context: context)
                }
            }
        }
    }
}
