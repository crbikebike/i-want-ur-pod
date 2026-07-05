// Shared search-source state. Architecture source: docs/design/direction.md §12.3
// (Settings owns source ordering + enablement via ONE SearchCoordinator; Discover's
// live search must observe those same edits). This app-target holder makes both
// screens read a single coordinator instance so setEnabled/setPrimary/reorder in
// Settings actually change what Discover searches.
import SwiftUI
import DirectoryKit

/// App-wide holder for the single, shared ``SearchCoordinator``.
///
/// Discover (live search) and Settings (the "Sources" checklist) must operate on
/// the *same* coordinator: toggling, promoting, or reordering a source in Settings
/// has to change what Discover searches. If each screen built its own coordinator
/// the two would silently diverge (per §12.3). `IWantUrPodApp` creates exactly one
/// `AppSources` and injects it into the environment; the wrapper screens read it
/// and thread its ``coordinator`` into `DiscoverView` / `SourcesView`.
///
/// The coordinator itself still lives in the app target (never constructed by
/// `AppShell`'s tab switch), preserving the frozen navigation contract.
@Observable
@MainActor
public final class AppSources {

    /// The one coordinator both Discover and Settings share.
    ///
    /// Seeded once with the Apple directory (`ITunesSource`, enabled) followed by
    /// PodcastIndex (`PodcastIndexSource`, disabled until a key is stored). Both
    /// sources are registered up front so the Settings checklist can list and
    /// manage PodcastIndex even before it is configured, per §12.1.
    public let coordinator: SearchCoordinator

    /// Builds the shared coordinator with the default source roster.
    ///
    /// - Parameter coordinator: Override for previews/tests. Defaults to the live
    ///   Apple + PodcastIndex roster.
    public init(coordinator: SearchCoordinator? = nil) {
        self.coordinator = coordinator ?? SearchCoordinator(sources: [
            ITunesSource(),
            PodcastIndexSource()
        ])
    }
}

public extension View {
    /// Publishes the shared ``AppSources`` (and thus its coordinator) into the
    /// environment so `DiscoverScreen` and `SettingsScreen` resolve the same
    /// instance via `@Environment(AppSources.self)`.
    func appSources(_ sources: AppSources) -> some View {
        environment(sources)
    }
}
