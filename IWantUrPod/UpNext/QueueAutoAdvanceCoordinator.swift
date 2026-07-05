// QueueAutoAdvanceCoordinator — couples PlaybackEngine.onFinished to
// QueueStore (E5-S3). Architecture source: docs/spec/queue-semantics.md's
// "Auto-advance" section + docs/spec/playback-state-machine.md's
// `finished --auto-advance (queue non-empty)--> loading(next)` /
// `finished --queue empty--> idle` transitions.
//
// PlaybackKit deliberately knows nothing about `QueueItem` or `QueueStore`
// (see `PlaybackEngine.onFinished`'s doc comment) — this small, pure
// coordinator is the glue `IWantUrPodApp` wires into that closure. Extracted
// out of the App struct's `init()` (rather than an inline closure body) so it
// is unit-testable on its own, the same way `PodcastsListProvider` extracts
// testable logic out of its screen (E3 precedent).
import SwiftData
import PodcastModels
import PlaybackKit

@MainActor
public enum QueueAutoAdvanceCoordinator {
    /// Handles the episode that just reached `.finished`:
    ///
    /// 1. Removes its `QueueItem`, if present (it's played; per the spec,
    ///    "the just-finished episode's `QueueItem`, if present, is removed").
    /// 2. If the queue now has a head, loads (and thus plays) it.
    /// 3. Otherwise returns the engine to `.idle` — "an empty queue stops
    ///    cleanly (no error), mini-player hides."
    public static func handleFinished(
        _ finishedEpisode: Episode,
        queueStore: QueueStore,
        playbackEngine: PlaybackEngine,
        context: ModelContext
    ) {
        if let finishedItem = queueStore.items.first(where: { $0.episode?.id == finishedEpisode.id }) {
            queueStore.remove(finishedItem)
        }

        if let nextEpisode = queueStore.head?.episode {
            playbackEngine.load(episode: nextEpisode, context: context)
        } else {
            playbackEngine.returnToIdle()
        }
    }
}
