// Translated from design/kit/screens/{search-start,search-typing,search-loading,
// search-noresults,search-error}.html — the takeover's content region (the
// field itself now lives in `LiquidGlassTabBar`'s takeover, per E8-S1).
//
// ROADMAP.md E8-S1: replaces `DiscoverView`/`DiscoverScreen` (deleted). Search
// is no longer a standalone tab screen with its own title + inline field —
// tapping the dock's Search icon turns the tab bar itself into the field
// (`AppShell` wires its text to `DiscoverViewModel.query`), and this screen
// renders only the results region below it, one branch per
// `DiscoverViewModel.State` — reusing that state machine and its
// LoadingSkeleton/ShelvesList/CuratedShelf/EmptyStateView pieces verbatim
// (E1-S3's machinery, "REUSE... don't rewrite it").
import SwiftUI
import SwiftData
import DesignSystem
import DirectoryKit
import PodcastModels

/// The Search takeover's content region, referenced by `AppShell` with the
/// shared `DiscoverViewModel` it also binds to the tab bar's field.
public struct SearchScreen: View {
    @Bindable var viewModel: DiscoverViewModel

    /// Pushed feed URLs — same frozen contract as every other tab (E2's
    /// "one adaptive screen … keyed by feedURL"). Lives inside this screen's
    /// own `NavigationStack`.
    @State private var path = NavigationPath()

    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette

    public init(viewModel: DiscoverViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                content
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.top, Spacing.sp5)
                    .padding(.bottom, AppShell.tabBarReservedPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(palette.groupedBg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: URL.self) { feedURL in
                PodcastDetailScreen(feedURL: feedURL)
            }
        }
    }

    // MARK: - State-driven body

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .firstRun:
            // search-start.html: the takeover's rest state before typing
            // starts — same curated shelf + prompt treatment Discover's
            // first-run/empty state used (MANIFEST.md).
            firstRunState

        case .typing:
            typingHint

        case .loading:
            loadingState

        case .results(let results):
            ShelvesList(
                results: results,
                onSubscribe: subscribe,
                onSelect: { result in path.append(result.feedURL) }
            )

        case .noResults:
            EmptyStateView(
                kind: .noResults,
                title: "No shows found",
                message: "Nothing matched \u{201C}\(viewModel.query)\u{201D}. Try a different spelling or a broader term."
            ) {
                SecondaryButton(title: "Clear search") { viewModel.clear() }
            }

        case .error(let message):
            EmptyStateView(
                kind: .error,
                title: "Couldn't reach the directory",
                message: message
            ) {
                PrimaryButton(title: "Retry") { viewModel.retry() }
            }
        }
    }

    private var firstRunState: some View {
        VStack(alignment: .leading, spacing: 0) {
            // E1-S2: the bundled curated "start here" shelf, in file order.
            // Empty (no entries) is silent — `CuratedShelf` renders nothing —
            // so a missing/unreadable bundle file degrades to just the prompt
            // below rather than an empty gap.
            CuratedShelf(
                entries: viewModel.curatedEntries,
                onSubscribe: subscribe,
                onSelect: { entry in path.append(entry.feedURL) }
            )

            EmptyStateView(
                kind: .firstRun,
                title: "Find your next listen",
                message: "Search millions of shows by name, host, or topic — or start from a popular pick."
            ) {
                GhostButton(title: "True Crime") { viewModel.search(for: "True Crime") }
                GhostButton(title: "Technology") { viewModel.search(for: "Technology") }
            }
            .padding(.top, viewModel.curatedEntries.isEmpty ? 0 : Spacing.sp6)
        }
    }

    private var typingHint: some View {
        HStack(spacing: Spacing.sp2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
            Text("Keep typing to search…")
                .typeStyle(Typography.subheadStyle)
        }
        .foregroundStyle(palette.textFaint)
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.sp6)
    }

    private var loadingState: some View {
        LoadingSkeleton()
    }

    // MARK: - Persistence

    /// Insert a subscribed show into the local SwiftData store.
    private func subscribe(_ result: SearchResult) {
        let podcast = Podcast(
            title: result.title,
            author: result.author,
            feedURL: result.feedURL,
            homeURL: result.homeURL,
            artworkURL: result.artworkURL,
            category: result.category ?? "",
            isSubscribed: true
        )
        modelContext.insert(podcast)
        try? modelContext.save()
    }
}

#if DEBUG
@MainActor private func previewCoordinator() -> SearchCoordinator {
    SearchCoordinator(sources: [FixtureSource(results: DiscoverViewModel.sampleResults)])
}

#Preview("Search — first run (dark)") {
    SearchScreen(viewModel: DiscoverViewModel(coordinator: previewCoordinator()))
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .modelContainer(ModelSchema.previewContainer())
}

#Preview("Search — results (dark)") {
    SearchScreen(viewModel: DiscoverViewModel(previewState: .results(DiscoverViewModel.sampleResults)))
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .modelContainer(ModelSchema.previewContainer())
}

#Preview("Search — loading (light)") {
    SearchScreen(viewModel: DiscoverViewModel(previewState: .loading))
        .themedPalette()
        .environment(\.colorScheme, .light)
        .modelContainer(ModelSchema.previewContainer())
}

#Preview("Search — no results (dark)") {
    SearchScreen(viewModel: DiscoverViewModel(previewState: .noResults))
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .modelContainer(ModelSchema.previewContainer())
}

#Preview("Search — error (dark)") {
    SearchScreen(viewModel: DiscoverViewModel(previewState: .error("The search service didn't respond. Check your connection and try again.")))
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .modelContainer(ModelSchema.previewContainer())
}
#endif
