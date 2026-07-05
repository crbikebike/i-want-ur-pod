// App-wide accessor for the shared QueueStore (E5-S1/S2/S3). Mirrors
// AppPlayback.swift's pattern: QueueStore is itself the app-scoped,
// @Observable service (defined in IWantUrPod/UpNext/QueueStore.swift) —
// created once in IWantUrPodApp and injected via .environment so UpNextScreen
// and PodcastDetailView's EpisodeRow ("Add to Up Next") read the same
// instance. Never constructed inside AppShell's tab switch (frozen nav
// contract, definition-of-done.md §5).
import SwiftUI

public extension View {
    /// Publishes the shared ``QueueStore`` into the environment so any screen
    /// can resolve it via `@Environment(QueueStore.self)`.
    func queueStore(_ store: QueueStore) -> some View {
        environment(store)
    }
}
