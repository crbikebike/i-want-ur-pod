// App-wide accessor for the shared DownloadManager (E4-S1). Mirrors
// AppSources.swift's pattern: DownloadManager is itself the app-scoped,
// @Observable service (defined in DownloadKit) — created once in
// IWantUrPodApp and injected via .environment so PodcastDetailView's
// EpisodeRow (and any later screen, e.g. E4-S2 playback resolving the local
// file, or a future Downloads tab) reads the same instance. Never constructed
// inside AppShell's tab switch (frozen nav contract, definition-of-done.md §5).
import SwiftUI
import DownloadKit

public extension View {
    /// Publishes the shared ``DownloadManager`` into the environment so any
    /// screen can resolve it via `@Environment(DownloadManager.self)`.
    func downloadManager(_ manager: DownloadManager) -> some View {
        environment(manager)
    }
}
