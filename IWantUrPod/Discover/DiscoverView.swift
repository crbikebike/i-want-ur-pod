// Translated from design/kit/screens/{typing,loading,no-results,error}.html.
// NOTE: the `.firstRun` branch below is an interim placeholder, not a
// translation of design/kit/screens/first-run.html — see EmptyStateView.swift
// and design/kit/MANIFEST.md.
// The Discover screen: a display-face "Discover" large title (IBM Plex Mono),
// a DesignSystem `SearchField`, and a body that renders one branch per
// `DiscoverViewModel.State` using LoadingSkeleton, ResultShelf (via
// ShelvesList), and EmptyStateView. Subscribing persists a Podcast into
// SwiftData.
import SwiftUI
import SwiftData
import DesignSystem
import DirectoryKit
import PodcastModels

/// The Discover tab — search the podcast directory and subscribe to shows.
public struct DiscoverView: View {
    @State private var viewModel: DiscoverViewModel

    /// Pushed feed URLs — every entry point (curated shelf, search result)
    /// navigates by pushing a `feedURL`, per navigation-map.md's frozen
    /// contract ("one adaptive screen … keyed by feedURL"). Lives inside this
    /// tab's own `NavigationStack`, not in `AppShell` (whose tab switch stays
    /// a pure view switch).
    @State private var path = NavigationPath()

    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette

    /// Bottom inset so content clears the floating Liquid Glass tab bar.
    private let tabBarClearance: CGFloat = 104

    /// - Parameter coordinator: The search orchestrator injected from the app.
    public init(coordinator: SearchCoordinator) {
        _viewModel = State(initialValue: DiscoverViewModel(coordinator: coordinator))
    }

    /// Inject a pre-built view model (previews / testing).
    init(viewModel: DiscoverViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titleBar

                    SearchField(
                        text: $viewModel.query,
                        placeholder: "Shows, people, topics",
                        onSubmit: { viewModel.submit() }
                    )
                    .padding(.top, Spacing.sp4)   // .search margin-top: --sp-4

                    content
                        .padding(.top, Spacing.sp5)
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.top, Spacing.sp5)
                .padding(.bottom, tabBarClearance)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(palette.groupedBg.ignoresSafeArea())
            // Discover draws its own large title (h1.big above) rather than
            // using UIKit's nav bar chrome — hide the bar on this root screen
            // only; pushed destinations (Podcast Detail) show their own.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: URL.self) { feedURL in
                PodcastDetailScreen(feedURL: feedURL)
            }
        }
    }

    // MARK: - Large title (.titlewrap / h1.big)

    private var titleBar: some View {
        HStack(spacing: Spacing.sp2) {
            Text("Discover")
                .typeStyle(Typography.displayLargeTitleStyle)   // IBM Plex Mono display face
                .foregroundStyle(palette.text)

            // h1.big .pulse-dot — a single coral→mint accent dot.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [palette.accent, palette.accent2],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 11, height: 11)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 2)   // h1.big optical inset
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - State-driven body

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .firstRun:
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
        EmptyStateView(
            kind: .firstRun,
            title: "Find your next listen",
            message: "Search millions of shows by name, host, or topic — or start from a popular pick."
        ) {
            GhostButton(title: "True Crime") { viewModel.search(for: "True Crime") }
            GhostButton(title: "Technology") { viewModel.search(for: "Technology") }
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

#Preview("Discover — first run (dark)") {
    DiscoverView(coordinator: previewCoordinator())
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .modelContainer(ModelSchema.previewContainer())
}

#Preview("Discover — results (dark)") {
    DiscoverView(viewModel: DiscoverViewModel(previewState: .results(DiscoverViewModel.sampleResults)))
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .modelContainer(ModelSchema.previewContainer())
}

#Preview("Discover — loading (light)") {
    DiscoverView(viewModel: DiscoverViewModel(previewState: .loading))
        .themedPalette()
        .environment(\.colorScheme, .light)
        .modelContainer(ModelSchema.previewContainer())
}

#Preview("Discover — no results (dark)") {
    DiscoverView(viewModel: DiscoverViewModel(previewState: .noResults))
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .modelContainer(ModelSchema.previewContainer())
}

#Preview("Discover — error (dark)") {
    DiscoverView(viewModel: DiscoverViewModel(previewState: .error("The search service didn't respond. Check your connection and try again.")))
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .modelContainer(ModelSchema.previewContainer())
}
#endif
