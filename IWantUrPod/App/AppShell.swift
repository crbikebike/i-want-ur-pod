// Root navigation shell. Design source: docs/design/direction.md §12 (floating
// Liquid Glass tab bar — Discover · Podcasts · Up Next · Downloads · Settings;
// bar floats 22pt off the bottom, content reserves 104pt so the last row clears
// it) + docs/spec/navigation-map.md's "Persistent chrome placement" (E6-S1's
// mini-player sits above the tab bar as shell chrome, E6-S2's Now Playing
// sheet presents modally over the whole shell). Chrome + tokens come from
// DesignSystem; data flows through PodcastModels; live search wiring comes
// from DirectoryKit (used by the Discover screen); playback state comes from
// the app-scoped PlaybackEngine (PlaybackKit), injected in IWantUrPodApp and
// only *read* here — never constructed inside the tab switch (frozen nav
// contract, definition-of-done.md §5).
import SwiftUI
import SwiftData
import DesignSystem
import PodcastModels
import DirectoryKit
import PlaybackKit

/// The app's root view: the selected tab's screen drawn full-bleed with the
/// floating `LiquidGlassTabBar` (and, once playback starts, the mini-player)
/// pinned over the bottom. Discover, Podcasts, Settings, and (as of E5) Up
/// Next are real screens; Downloads remains a placeholder that arrives in a
/// later milestone (see ROADMAP.md).
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

    @State private var selection: AppTab = .discover
    @State private var isShowingNowPlaying = false

    @Environment(\.palette) private var palette
    @Environment(PlaybackEngine.self) private var playbackEngine

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

                LiquidGlassTabBar(selection: $selection)
            }
            .padding(.bottom, Self.tabBarBottomInset)
            .animation(.default, value: isMiniPlayerVisible)
        }
        .sheet(isPresented: $isShowingNowPlaying) {
            NowPlayingSheet()
        }
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

    /// Resolve the selected tab to its screen. Discover, Podcasts, Up Next,
    /// and Settings are live; Downloads remains a milestone placeholder.
    @ViewBuilder
    private var content: some View {
        switch selection {
        case .discover:
            DiscoverScreen()
        case .podcasts:
            PodcastsScreen()
        case .upNext:
            UpNextScreen()
        case .downloads:
            PlaceholderScreen(tab: .downloads)
        case .settings:
            SettingsScreen()
        }
    }
}

// MARK: - Milestone placeholder

/// A tidy stand-in for the tabs whose features ship after M1. Reuses the
/// DesignSystem empty-state block so the placeholder still reads as part of the
/// system rather than a blank pane, and reserves the tab-bar gap at the bottom.
struct PlaceholderScreen: View {
    let tab: AppTab

    @Environment(\.palette) private var palette

    var body: some View {
        EmptyStateView(
            kind: .firstRun,
            title: tab.title,
            message: "This tab arrives in a later milestone.",
            actions: { EmptyView() }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, AppShell.tabBarReservedPadding)
        .background(palette.groupedBg)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("App shell — dark") {
    AppShell()
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .environment(PlaybackEngine(localURLResolver: { _ in nil }))
        .modelContainer(ModelSchema.previewContainer())
}

#Preview("App shell — light") {
    AppShell()
        .themedPalette()
        .environment(\.colorScheme, .light)
        .environment(PlaybackEngine(localURLResolver: { _ in nil }))
        .modelContainer(ModelSchema.previewContainer())
}
#endif
