// Composition root for the Discover tab. Design/architecture source:
// docs/design/direction.md §12.3 — Discover's live search must observe the same
// source edits Settings makes, so this screen reads the app-wide shared
// SearchCoordinator (via AppSources) instead of building its own.
import SwiftUI
import DirectoryKit

/// The Discover tab's entry point, referenced by `AppShell` as a no-arg view.
///
/// Reads the shared ``AppSources`` from the environment and threads its single
/// ``SearchCoordinator`` into ``DiscoverView``. Both real directory sources —
/// Apple's iTunes lookup plus the Podcast Index — are already seeded on that one
/// coordinator, so source order and enablement edited in Settings drive exactly
/// what Discover searches (per §12.3).
public struct DiscoverScreen: View {
    @Environment(AppSources.self) private var appSources

    public init() {}

    public var body: some View {
        DiscoverView(coordinator: appSources.coordinator)
    }
}
