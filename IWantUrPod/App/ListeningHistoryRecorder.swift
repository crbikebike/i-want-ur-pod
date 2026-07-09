// ListeningHistoryRecorder — logs each play session as a `PlayEvent` (episode
// listening history, Wave 1). Small app-target type with a `ModelContext`,
// mirroring `QueueAutoAdvanceCoordinator`'s shape: `IWantUrPodApp.init` wires
// `PlaybackEngine.onDidFinishListening` to `record(episode:startedAt:
// listenedSeconds:)`, keeping `PlaybackKit` itself decoupled from SwiftData/
// history types (see `PlaybackEngine.onDidFinishListening`'s doc comment).
import Foundation
import SwiftData
import PodcastModels

@MainActor
public final class ListeningHistoryRecorder {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Builds and persists a `PlayEvent` snapshotting `episode` (and its
    /// owning podcast) at the moment a play session ends.
    public func record(episode: Episode, startedAt: Date, listenedSeconds: TimeInterval) {
        let event = PlayEvent(
            playedAt: startedAt,
            listenedSeconds: listenedSeconds,
            episodeTitle: episode.title,
            podcastTitle: episode.podcast?.title ?? "",
            artworkURL: episode.remoteArtworkURL ?? episode.podcast?.artworkURL,
            feedURL: episode.podcast?.feedURL,
            episodeGUID: episode.guid
        )
        context.insert(event)
        try? context.save()
    }
}
