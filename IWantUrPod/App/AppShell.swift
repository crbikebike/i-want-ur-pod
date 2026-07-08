// Root navigation shell. Design source: docs/design/direction.md §12 (floating
// Liquid Glass tab bar — 2026-07-05 dock IA revision: Home · Shows · Up Next ·
// Search, replacing the prior Discover/Podcasts/Up Next/Downloads/Settings
// five-item bar; bar floats 22pt off the bottom, content reserves 104pt so
// the last row clears it) + docs/spec/navigation-map.md's "Persistent chrome
// placement" (E6-S1's mini-player sits above the tab bar as shell chrome,
// E6-S2's Now Playing sheet presents modally over the whole shell). Settings
// is no longer a tab — it's pushed from a top-right gear on Home/Shows/Up
// Next (E8-S4). Chrome + tokens come from DesignSystem; data flows through
// PodcastModels; live search wiring comes from DirectoryKit (used by the
// Search takeover, via the shared DiscoverViewModel); playback state comes
// from the app-scoped PlaybackEngine (PlaybackKit), injected in
// IWantUrPodApp and only *read* here — never constructed inside the tab
// switch (frozen nav contract, definition-of-done.md §5).
import SwiftUI
import SwiftData
import DesignSystem
import PodcastModels
import DirectoryKit
import PlaybackKit

/// The app's root view: the selected tab's screen drawn full-bleed with the
/// floating `LiquidGlassTabBar` (and, once playback starts, the mini-player)
/// pinned over the bottom. Home, Shows, Up Next, and Search (E8-S1) are real
/// screens; Settings is reached only via the gear on Home/Shows/Up Next
/// (E8-S4), never as a tab.
public struct AppShell: View {

    /// Vertical inset from the bottom safe area to the tab bar (kit `bottom: 22px`).
    static let tabBarBottomInset: CGFloat = 22

    /// Bottom padding each screen reserves so its last row clears the floating
    /// bar (direction.md §12: "`.content` reserves 104px of bottom padding").
    public static let tabBarReservedPadding: CGFloat = 104

    /// The mini-player's own height (E6-S1). Spans the width, sits directly
    /// above the tab bar.
    static let miniPlayerHeight: CGFloat = 64

    /// Gap between the mini-player and the tab bar below it.
    private static let miniPlayerToTabBarSpacing: CGFloat = 8

    /// The combined bottom reserve when the mini-player is visible — the
    /// tab-bar reserve plus the mini-player's height and the gap above the
    /// bar (navigation-map.md: "define the combined reserve as a shell
    /// constant alongside `tabBarReservedPadding`"). `AppShell` applies the
    /// *additional* amount (this minus `tabBarReservedPadding`) to `content`'s
    /// own frame below, so every screen keeps reserving the same 104pt
    /// internally and none of them need to know whether the mini-player is
    /// showing — the cleanest option per navigation-map.md's guidance, and
    /// what keeps this a one-file change instead of touching every screen.
    public static let miniPlayerReservedPadding: CGFloat =
        tabBarReservedPadding + miniPlayerHeight + miniPlayerToTabBarSpacing

    @State private var selection: AppTab = .home
    @State private var isShowingNowPlaying = false

    /// The tab active immediately before Search's takeover began — restored
    /// when the takeover's ✕ is tapped (E8-S1's "restores the previously
    /// active tab" criterion). Updated only on the transition *into*
    /// `.search`, never on other tab switches.
    @State private var previousTab: AppTab = .home

    /// The Search takeover's shared state machine — the same `DiscoverViewModel`
    /// that used to back the standalone Discover tab (E1-S3/E8-S1: "REUSE this
    /// machinery for the takeover, don't rewrite it"). Built once the shared
    /// `AppSources` coordinator is available (environment isn't populated yet
    /// at `init()`, so this is created lazily on first appearance) and reused
    /// for the shell's lifetime so in-flight searches survive dismiss/reopen.
    @State private var searchViewModel: DiscoverViewModel?

    @Environment(\.palette) private var palette
    @Environment(PlaybackEngine.self) private var playbackEngine
    @Environment(AppSources.self) private var appSources

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            palette.groupedBg
                .ignoresSafeArea()

            // The active destination fills the shell; screens scroll their own
            // content beneath the translucent bar (and mini-player, when
            // showing) and reserve the bottom gap themselves. When the
            // mini-player is visible this view shrinks `content`'s own frame
            // by the extra height it needs, on top of each screen's existing
            // 104pt internal reserve — see `miniPlayerReservedPadding` above.
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.bottom, extraBottomReserveForMiniPlayer)

            VStack(spacing: Self.miniPlayerToTabBarSpacing) {
                if isMiniPlayerVisible {
                    MiniPlayer { isShowingNowPlaying = true }
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                LiquidGlassTabBar(
                    selection: tabSelectionBinding,
                    searchQuery: searchQueryBinding,
                    onCancelSearch: { selection = previousTab },
                    onSubmitSearch: { searchViewModel?.submit() }
                )
            }
            .padding(.bottom, Self.tabBarBottomInset)
            .animation(.default, value: isMiniPlayerVisible)
            // Deliberately NOT `.ignoresSafeArea(.keyboard)` — the takeover
            // field must rise with the keyboard (E8-S1's "the takeover field
            // rises to sit just above the keyboard when focused").
        }
        .sheet(isPresented: $isShowingNowPlaying) {
            NowPlayingSheet()
        }
        .onAppear {
            // The shared `AppSources` coordinator isn't readable until the
            // environment is attached, so the takeover's view model is built
            // lazily here rather than in `init()` — see `searchViewModel`'s
            // doc comment.
            if searchViewModel == nil {
                searchViewModel = DiscoverViewModel(coordinator: appSources.coordinator)
            }
        }
    }

    /// Wraps `selection` so entering the Search takeover captures whichever
    /// tab was active immediately before, for the ✕ cancel action to restore.
    /// Every other transition (Home/Shows/Up Next taps, the takeover's pinned
    /// Home glyph) passes through unchanged.
    private var tabSelectionBinding: Binding<AppTab> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == .search && selection != .search {
                    previousTab = selection
                }
                selection = newValue
            }
        )
    }

    /// The takeover field's text, bound to the shared `DiscoverViewModel`'s
    /// `query` once it exists (always true by the time `.search` can be
    /// selected — built in `onAppear` above).
    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { searchViewModel?.query ?? "" },
            set: { searchViewModel?.query = $0 }
        )
    }

    /// E6-S1: shown iff playback isn't idle (navigation-map.md), reading the
    /// exact predicate `MiniPlayer`/`PlaybackTransport` expose as a testable
    /// static so this and `IWantUrPodTests` agree on one definition.
    private var isMiniPlayerVisible: Bool {
        PlaybackTransport.isMiniPlayerPresented(for: playbackEngine.state)
    }

    private var extraBottomReserveForMiniPlayer: CGFloat {
        isMiniPlayerVisible ? Self.miniPlayerReservedPadding - Self.tabBarReservedPadding : 0
    }

    /// Resolve the selected tab to its screen (E8-S1's four-item dock). Home,
    /// Shows, and Up Next are plain view switches per the frozen nav
    /// contract; Search renders the shared `searchViewModel` inside
    /// `SearchScreen` — the same state machine that used to back the
    /// standalone Discover tab, now fed by the takeover bar above instead of
    /// its own inline field.
    @ViewBuilder
    private var content: some View {
        switch selection {
        case .home:
            HomeScreen()
        case .shows:
            PodcastsScreen()
        case .upNext:
            UpNextScreen()
        case .search:
            if let searchViewModel {
                SearchScreen(viewModel: searchViewModel)
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
private func previewQueueStore() -> QueueStore {
    QueueStore(context: ModelContext(ModelSchema.previewContainer()))
}

#Preview("App shell — dark") {
    AppShell()
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .environment(PlaybackEngine(localURLResolver: { _ in nil }))
        .appSources(AppSources())
        .environment(previewQueueStore())
        .modelContainer(ModelSchema.previewContainer())
}

#Preview("App shell — light") {
    AppShell()
        .themedPalette()
        .environment(\.colorScheme, .light)
        .environment(PlaybackEngine(localURLResolver: { _ in nil }))
        .appSources(AppSources())
        .environment(previewQueueStore())
        .modelContainer(ModelSchema.previewContainer())
}
#endif
