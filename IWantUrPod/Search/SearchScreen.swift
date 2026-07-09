// Translated from design/kit/screens/{search-start,search-typing,search-loading,
// search-results,search-noresults,search-error}.html — the takeover's content
// region (the field itself lives in `LiquidGlassTabBar`'s takeover, per E8-S1).
//
// One branch per `DiscoverViewModel.State`, each mapping to a kit screen:
// `.firstRun` → search-start's browse rails; `.typing` → search-typing's live
// suggestions list (`SearchResultRow` in a `GroupedList`) over those same rails;
// `.loading` → search-loading's "Searching for …" header + `LoadingSkeleton`;
// `.results` → search-results' featured `TopResultCard` + flat "More shows"
// list; `.noResults`/`.error` → the `EmptyStateView` cards. The field's Return
// (`AppShell` → `submit()`) is what commits typing → results.
//
// ROADMAP.md E8-S1: replaces `DiscoverView`/`DiscoverScreen` (deleted). Search
// is no longer a standalone tab screen with its own title + inline field —
// tapping the dock's Search icon turns the tab bar itself into the field
// (`AppShell` wires its text to `DiscoverViewModel.query`).
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

    /// Per-result subscribe state for the typeahead/results rows (moved here
    /// from the deleted `ShelvesList` now that results is a flat list). Keyed
    /// by `SearchResult.id` (the feed URL), same pattern the curated rail uses.
    @State private var subscribeStates: [String: SubscribeState] = [:]

    /// Drives the `AddFeedSheet` presentation from either the `.firstRun`
    /// `.urlcta` row or the `.noResults` "Add a direct link" empty-state
    /// action (search-start.html:707, search-noresults.html:654).
    @State private var isAddingFeed = false

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
            .sheet(isPresented: $isAddingFeed) {
                // `AddFeedSheet` dismisses itself on success (see its own
                // `.task`-driven `onChange(of: viewModel.state)`); appending
                // to `path` here — rather than also flipping
                // `isAddingFeed = false` — avoids racing that self-dismiss
                // with our own, so the push still lands once the sheet is
                // gone.
                AddFeedSheet(onSubscribed: { feedURL in path.append(feedURL) })
            }
        }
    }

    // MARK: - State-driven body

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .firstRun:
            // search-start.html: the rest/browse state — a hint line over the
            // curated browse rails (no headline/badge/chips; those were an
            // invented empty-state treatment, not in the kit).
            firstRunState

        case .typing(let suggestions):
            // search-typing.html: live typeahead suggestions over the browse rails.
            typingState(suggestions)

        case .loading:
            // search-loading.html: "Searching for <query>…" over the shelf skeleton.
            loadingState

        case .results(let results):
            // search-results.html: featured top result + flat "More shows" list.
            resultsState(results)

        case .noResults:
            // search-noresults.html:649-660: message mentions the direct-link
            // fallback, and `.state-actions` leads with `.btn-primary "Add a
            // direct link"` before `.btn-secondary "Clear search"`.
            EmptyStateView(
                kind: .noResults,
                title: "No shows found",
                message: "Nothing matched \u{201C}\(viewModel.query)\u{201D}. Try a different spelling \u{2014} or, if you have a direct link to the show, add it."
            ) {
                PrimaryButton(title: "Add a direct link", systemImage: "link") { isAddingFeed = true }
                NeutralButton(title: "Clear search") { viewModel.clear() }
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

    // MARK: - Rest state (search-start.html)

    private var firstRunState: some View {
        VStack(alignment: .leading, spacing: 0) {
            // .sec-sub hint — the kit leads straight into it (no title/badge).
            Text("Search millions of shows by name, host, or topic. Start typing below.")
                .typeStyle(Typography.subheadStyle)
                .foregroundStyle(palette.textFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
                .padding(.bottom, Spacing.sp5)

            browseRails

            // `.urlcta` (search-start.html:644-654, 707-711): a quiet
            // grouped-inset row under the browse shelves for people who
            // already hold a direct/private feed link.
            urlCTAButton
                .padding(.top, Spacing.sp6)
                .padding(.bottom, Spacing.sp2)
        }
    }

    /// `.urlcta` — full-width row, `--surface` fill, `--r-md` corner,
    /// `--elev-list`, accent-colored label between a link glyph and a
    /// trailing chevron (search-start.html:644-654).
    private var urlCTAButton: some View {
        Button {
            isAddingFeed = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "link")
                    .font(.system(size: 15, weight: .semibold))
                Text("Have a podcast URL? Add it directly")
                    .typeStyle(Typography.urlCTALabelStyle)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(palette.accent)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, Spacing.sp4)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.rMd16, style: .continuous))
            .elevList(hairline: palette.hairline)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a podcast by URL")
    }

    /// The bundled curated "start here" picks as the kit's browse shelf/rails
    /// (E1-S2, in file order). Empty (no entries) is silent — `CuratedShelf`
    /// renders nothing — so a missing/unreadable bundle degrades to just the
    /// hint above rather than an empty gap. Shared by the rest state and the
    /// typing state (the kit keeps these rails visible beneath suggestions).
    private var browseRails: some View {
        CuratedShelf(
            entries: viewModel.curatedEntries,
            onSubscribe: persist,
            onSelect: { entry in path.append(entry.feedURL) }
        )
    }

    // MARK: - Typing / suggestions (search-typing.html)

    @ViewBuilder
    private func typingState(_ suggestions: [SearchResult]) -> some View {
        // Cap the live list to a handful — a typeahead, not the full result set.
        let shown = Array(suggestions.prefix(8))
        VStack(alignment: .leading, spacing: 0) {
            if !shown.isEmpty {
                SectionHeader(title: "Suggestions")

                GroupedList(items: shown, id: \.id) { result in
                    Button {
                        path.append(result.feedURL)
                    } label: {
                        SearchResultRow(
                            title: result.title,
                            author: result.author,
                            artworkURL: result.artworkURL,
                            matchPrefix: viewModel.query
                        ) {
                            suggestionChevron
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // The browse rails stay visible beneath the suggestions (kit `.under`).
            browseRails
                .padding(.top, shown.isEmpty ? 0 : Spacing.sp6)
        }
    }

    private var suggestionChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.textFaint)
            .accessibilityHidden(true)
    }

    // MARK: - Loading (search-loading.html)

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Searching for \u{201C}\(viewModel.query)\u{201D}\u{2026}")
            LoadingSkeleton()
        }
    }

    // MARK: - Results (search-results.html)

    @ViewBuilder
    private func resultsState(_ results: [SearchResult]) -> some View {
        let more = Array(results.dropFirst())
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Results for \u{201C}\(viewModel.query)\u{201D}")

            if let top = results.first {
                TopResultCard(
                    result: top,
                    subscribeState: subscribeStates[top.id] ?? .idle,
                    onSubscribe: { subscribe(top) },
                    onTap: { path.append(top.feedURL) }
                )
                .padding(.top, Spacing.sp3)
            }

            if !more.isEmpty {
                SectionHeader(title: "More shows")

                // Kit `.reslist .sug` is `cursor: default` — these rows aren't
                // navigable, only their trailing circular Subscribe is
                // interactive (unlike the tappable typing suggestions above).
                GroupedList(items: more, id: \.id) { result in
                    SearchResultRow(
                        title: result.title,
                        author: result.author,
                        artworkURL: result.artworkURL
                    ) {
                        SubscribeButton(state: subscribeStates[result.id] ?? .idle) {
                            subscribe(result)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subscribe

    /// Drive the row's subscribe control state and persist on the leading edge —
    /// the same idle→subscribing→subscribed rhythm the curated rail uses.
    private func subscribe(_ result: SearchResult) {
        switch subscribeStates[result.id] ?? .idle {
        case .idle:
            subscribeStates[result.id] = .subscribing
            persist(result)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                subscribeStates[result.id] = .subscribed
            }
        case .subscribed:
            subscribeStates[result.id] = .idle
        case .subscribing:
            break
        }
    }

    /// Insert a subscribed show into the local SwiftData store.
    private func persist(_ result: SearchResult) {
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
