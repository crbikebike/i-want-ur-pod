// Shared search-source state. Architecture source: docs/design/direction.md §12
// ("Sources: Apple only for v1 — the keyless iTunes Search API (ITunesSource),
// zero-config, no in-app source picker"). This app-target holder gives the
// Search takeover a single, stable `SearchCoordinator` instance rather than
// building a new one every time the takeover appears.
//
// v1 is Apple-only (E8-S4): `PodcastIndexSource` and the fallback coordinator
// stay in `DirectoryKit` as dormant groundwork per ROADMAP.md's "Key
// decisions" — they are deliberately NOT seeded onto the live roster below,
// and there is no in-app source picker to enable them.
import SwiftUI
import DirectoryKit

/// App-wide holder for the single, shared ``SearchCoordinator``.
///
/// `IWantUrPodApp` creates exactly one `AppSources` and injects it into the
/// environment; `AppShell` reads it once (lazily, in `onAppear`) to build the
/// `DiscoverViewModel` backing the Search takeover.
///
/// The coordinator itself still lives in the app target (never constructed by
/// `AppShell`'s tab switch), preserving the frozen navigation contract.
@Observable
@MainActor
public final class AppSources {

    /// The one coordinator the Search takeover uses.
    ///
    /// Seeded with only the Apple directory (`ITunesSource`, enabled) — v1's
    /// Apple-only roster (§12). `PodcastIndexSource` stays unseeded/dormant.
    public let coordinator: SearchCoordinator

    /// Builds the shared coordinator with the default source roster.
    ///
    /// - Parameter coordinator: Override for previews/tests. Defaults to the
    ///   live Apple-only roster.
    public init(coordinator: SearchCoordinator? = nil) {
        self.coordinator = coordinator ?? SearchCoordinator(sources: [
            ITunesSource()
        ])
    }
}

public extension View {
    /// Publishes the shared ``AppSources`` (and thus its coordinator) into the
    /// environment so `AppShell` resolves the same instance via
    /// `@Environment(AppSources.self)`.
    func appSources(_ sources: AppSources) -> some View {
        environment(sources)
    }
}
