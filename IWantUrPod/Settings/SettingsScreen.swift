// Composition root for the Settings tab. Design source: docs/design/direction.md §12
// (Settings → Sources) + §12.3. Referenced by AppShell as a no-arg view; reads the
// app-wide shared SearchCoordinator (via AppSources) so edits made in the Sources
// checklist mutate the same coordinator Discover's live search observes.
import SwiftUI
import DesignSystem
import DirectoryKit

/// The Settings tab's entry point, referenced by `AppShell` as a no-arg view.
///
/// Reads the shared ``AppSources`` from the environment and hands its single
/// ``SearchCoordinator`` to ``SourcesView``, which owns the scrolling surface,
/// background, and the bottom padding that clears the floating tab bar. That
/// coordinator is seeded up front with both real directory sources — Apple's
/// iTunes lookup plus the Podcast Index (credentials via `KeychainStore`) — so
/// their order and enablement are manageable, and every edit is observed by
/// Discover (per §12.3).
public struct SettingsScreen: View {
    @Environment(AppSources.self) private var appSources

    public init() {}

    public var body: some View {
        SourcesView(coordinator: appSources.coordinator)
    }
}

// MARK: - Preview

#if DEBUG
import PodcastModels
import SwiftData

#Preview("Settings — dark") {
    SettingsScreen()
        .appSources(AppSources())
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .modelContainer(ModelSchema.previewContainer())
}

#Preview("Settings — light") {
    SettingsScreen()
        .appSources(AppSources())
        .themedPalette()
        .environment(\.colorScheme, .light)
        .modelContainer(ModelSchema.previewContainer())
}
#endif
