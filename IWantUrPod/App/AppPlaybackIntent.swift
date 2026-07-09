// App-wide accessor for the shared PlaybackIntentCoordinator (E6). Mirrors
// AppQueue.swift's pattern: PlaybackIntentCoordinator is itself the
// app-scoped, @Observable service (defined in
// IWantUrPod/App/PlaybackIntentCoordinator.swift) — created once in
// IWantUrPodApp and injected via .environment so every "Play" control
// (Podcast Detail, Up Next, Home) resolves the same instance. Never
// constructed inside AppShell's tab switch (frozen nav contract,
// definition-of-done.md §5).
import SwiftUI

public extension View {
    /// Publishes the shared ``PlaybackIntentCoordinator`` into the
    /// environment so any screen can resolve it via
    /// `@Environment(PlaybackIntentCoordinator.self)`.
    func playbackIntent(_ coordinator: PlaybackIntentCoordinator) -> some View {
        environment(coordinator)
    }
}
