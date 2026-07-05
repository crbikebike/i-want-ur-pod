// App-wide accessor for the shared PlaybackEngine (E4-S2/E4-S3). Mirrors
// AppDownloads.swift's pattern: PlaybackEngine is itself the app-scoped,
// @Observable service (defined in PlaybackKit) — created once in
// IWantUrPodApp and injected via .environment so PodcastDetailView's
// EpisodeRow (and any later screen, e.g. E6's mini-player/Now Playing sheet)
// reads the same instance. Never constructed inside AppShell's tab switch
// (frozen nav contract, definition-of-done.md §5).
import SwiftUI
import PlaybackKit

public extension View {
    /// Publishes the shared ``PlaybackEngine`` into the environment so any
    /// screen can resolve it via `@Environment(PlaybackEngine.self)`.
    func playbackEngine(_ engine: PlaybackEngine) -> some View {
        environment(engine)
    }
}
