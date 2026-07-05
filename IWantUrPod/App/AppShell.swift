// Root navigation shell. Design source: docs/design/direction.md §12 (floating
// Liquid Glass tab bar — Discover · Podcasts · Up Next · Downloads · Settings;
// bar floats 22pt off the bottom, content reserves 104pt so the last row clears
// it). Chrome + tokens come from DesignSystem; data flows through PodcastModels;
// live search wiring comes from DirectoryKit (used by the Discover screen).
import SwiftUI
import SwiftData
import DesignSystem
import PodcastModels
import DirectoryKit

/// The app's root view: the selected tab's screen drawn full-bleed with the
/// floating `LiquidGlassTabBar` pinned over the bottom. For M1 the Discover,
/// Podcasts, and Settings destinations are real screens; Up Next and Downloads
/// are placeholders that arrive in later milestones (see ROADMAP.md).
public struct AppShell: View {

    /// Vertical inset from the bottom safe area to the tab bar (kit `bottom: 22px`).
    static let tabBarBottomInset: CGFloat = 22

    /// Bottom padding each screen reserves so its last row clears the floating
    /// bar (direction.md §12: "`.content` reserves 104px of bottom padding").
    public static let tabBarReservedPadding: CGFloat = 104

    @State private var selection: AppTab = .discover

    @Environment(\.palette) private var palette

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            palette.groupedBg
                .ignoresSafeArea()

            // The active destination fills the shell; screens scroll their own
            // content beneath the translucent bar and reserve the bottom gap.
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            LiquidGlassTabBar(selection: $selection)
                .padding(.bottom, Self.tabBarBottomInset)
        }
    }

    /// Resolve the selected tab to its screen. Discover, Podcasts, and Settings
    /// are the live M1 destinations; the rest are milestone placeholders.
    @ViewBuilder
    private var content: some View {
        switch selection {
        case .discover:
            DiscoverScreen()
        case .podcasts:
            PodcastsScreen()
        case .upNext:
            PlaceholderScreen(tab: .upNext)
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
        .modelContainer(ModelSchema.previewContainer())
}

#Preview("App shell — light") {
    AppShell()
        .themedPalette()
        .environment(\.colorScheme, .light)
        .modelContainer(ModelSchema.previewContainer())
}
#endif
