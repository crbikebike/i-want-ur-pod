// Search state machine. Drives design/kit/screens/{search-start,search-typing,
// search-loading,search-results,search-noresults,search-error}.html — one `State`
// per screen. Search flows through DirectoryKit's SearchCoordinator (primary +
// fallback, docs/design/direction.md §12).
//
// The kit is a two-screen flow: while you type, `.typing` shows a live
// *suggestions* list (search-typing.html); committing (keyboard Return →
// `submit()`) promotes to the full `.results` screen (search-results.html) with
// its featured top result. Tapping a suggestion opens the show directly, so the
// full results screen is a deliberate commit, not an auto-transition — the only
// way both kit screens are reachable.
import Foundation
import Observation
import DirectoryKit

/// View model for the Search takeover.
///
/// Owns the debounced search `query`, resolves it to a `State` that maps 1:1
/// onto the kit's search screens, and delegates the actual lookup to an
/// injected ``SearchCoordinator``. Typing debounces then fetches *suggestions*
/// into `.typing(_)`; `submit()` commits to the full `.results` screen (reusing
/// the last fetch when the query is unchanged, else fetching with the
/// loading/error path).
@MainActor
@Observable
public final class DiscoverViewModel {

    /// One state per search screen in the kit.
    public enum State: Equatable, Sendable {
        /// Empty query — the rest/browse state (`search-start.html`).
        case firstRun
        /// Mid-typing: live typeahead suggestions, empty until the first fetch
        /// resolves (`search-typing.html`).
        case typing([SearchResult])
        /// A committed search is in flight (`search-loading.html`).
        case loading
        /// A committed, non-empty result set — top result + "More shows"
        /// (`search-results.html`).
        case results([SearchResult])
        /// A completed search that matched nothing (`search-noresults.html`).
        case noResults
        /// The search failed; carries a human-readable message (`search-error.html`).
        case error(String)
    }

    /// The raw search text bound to the `SearchField`. Mutating it re-drives the
    /// state machine (debounced) via the property observer.
    public var query: String = "" {
        didSet { queryDidChange() }
    }

    /// The current screen state. Read-only to callers; the model owns transitions.
    public private(set) var state: State = .firstRun

    /// The bundled curated "start here" picks (E1-S2), decoded once at init via
    /// DirectoryKit's pure `CuratedListLoader`. Rendered by `DiscoverView` on
    /// the `.firstRun` (empty-query/idle) state, in file order. Empty when the
    /// bundle resource is missing or unreadable — never fatal.
    public private(set) var curatedEntries: [CuratedEntry]

    private let coordinator: SearchCoordinator
    private let debounce: Duration
    private let minimumCharacters: Int

    private var debounceTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    /// The most recent successful fetch and the term it was for, so `submit()`
    /// can promote already-loaded suggestions to the full results screen without
    /// a redundant round-trip when the query hasn't changed.
    private var lastResults: [SearchResult] = []
    private var lastResultsTerm: String?

    /// - Parameters:
    ///   - coordinator: The search orchestrator (primary + fallback sources).
    ///   - debounce: How long to wait after the last keystroke before searching.
    ///   - minimumCharacters: The shortest query that triggers a search.
    ///   - curatedBundle: Where to look up `curated-start-here.json` — overridable
    ///     for previews/tests; defaults to the app's main bundle.
    public init(
        coordinator: SearchCoordinator,
        debounce: Duration = .milliseconds(320),
        minimumCharacters: Int = 2,
        curatedBundle: Bundle = .main
    ) {
        self.coordinator = coordinator
        self.debounce = debounce
        self.minimumCharacters = minimumCharacters
        self.curatedEntries = Self.loadCuratedEntries(from: curatedBundle)
    }

    /// App owns the bundle I/O (per docs/spec/curated-list.schema.md); the
    /// decoding itself stays in DirectoryKit's pure `CuratedListLoader`. A
    /// missing resource or unreadable file resolves to `Data()`, which the
    /// loader maps to `[]` rather than throwing.
    private static func loadCuratedEntries(from bundle: Bundle) -> [CuratedEntry] {
        guard
            let url = bundle.url(forResource: "curated-start-here", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
            return []
        }
        return CuratedListLoader.load(from: data)
    }

    // MARK: - Intents

    /// Commit the current query to the full results screen (keyboard "Search" /
    /// Return). Reuses the last suggestion fetch when it's for the same term,
    /// otherwise runs a fresh search with the loading/error path.
    public func submit() {
        debounceTask?.cancel()
        debounceTask = nil
        let term = trimmedQuery
        guard !term.isEmpty else {
            cancelAll()
            state = .firstRun
            return
        }
        // Already have live suggestions for this exact term → promote straight
        // to results without a redundant round-trip.
        if term == lastResultsTerm {
            searchTask?.cancel()
            searchTask = nil
            state = lastResults.isEmpty ? .noResults : .results(lastResults)
            return
        }
        startSearch(term: term, committed: true)
    }

    /// Re-run the last query — the error state's "Retry" action.
    public func retry() {
        submit()
    }

    /// Clear the query and return to the rest state — the no-results state's
    /// "Clear search" action.
    public func clear() {
        query = ""   // triggers `queryDidChange()` → `.firstRun`
    }

    /// Seed the field with a suggestion and search it.
    public func search(for suggestion: String) {
        query = suggestion
    }

    // MARK: - State machine

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func queryDidChange() {
        cancelAll()
        let term = trimmedQuery

        if term.isEmpty {
            lastResultsTerm = nil
            lastResults = []
            state = .firstRun
            return
        }
        if term.count < minimumCharacters {
            // Too short to fetch — show the suggestions state with nothing yet
            // (the browse rail sits beneath it in the screen).
            state = .typing([])
            return
        }

        // Keep whatever suggestions are already on screen while the next fetch
        // debounces, so the list doesn't flash empty on every keystroke.
        if case .typing = state {} else { state = .typing([]) }
        debounceTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            self.startSearch(term: term, committed: false)
        }
    }

    /// - Parameter committed: `true` for a `submit()`-driven full search (shows
    ///   the loading skeleton, then the results/no-results/error screen);
    ///   `false` for a live typeahead fetch (resolves into `.typing(_)` and
    ///   swallows errors so mid-typing never shows an error card).
    private func startSearch(term: String, committed: Bool) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            await self?.performSearch(term: term, committed: committed)
        }
    }

    private func performSearch(term: String, committed: Bool) async {
        if committed { state = .loading }
        do {
            let results = try await coordinator.search(term: term)
            guard !Task.isCancelled else { return }
            // Ignore a resolution that no longer matches the current query.
            guard term == trimmedQuery else { return }
            lastResults = results
            lastResultsTerm = term
            if committed {
                state = results.isEmpty ? .noResults : .results(results)
            } else {
                state = .typing(results)
            }
        } catch is CancellationError {
            // Superseded by a newer query — leave state to the newer task.
        } catch {
            guard !Task.isCancelled, term == trimmedQuery else { return }
            // Mid-typing failures stay quiet (keep the suggestions/browse view);
            // only a committed search surfaces the error screen.
            if committed {
                state = .error(Self.message(for: error))
            }
        }
    }

    private func cancelAll() {
        debounceTask?.cancel()
        debounceTask = nil
        searchTask?.cancel()
        searchTask = nil
    }

    /// Map a search failure onto the copy shown in the error state.
    private static func message(for error: Error) -> String {
        switch error {
        case SearchError.unavailable:
            return "The search service didn't respond. Check your connection and try again."
        case SearchError.rateLimited:
            return "Too many searches too quickly. Wait a moment and try again."
        case SearchError.noKey:
            return "This source needs an API key. Add one in Settings, or switch sources."
        case SearchError.decoding:
            return "The directory sent back something we couldn't read. Try again."
        default:
            return "Something went wrong reaching the directory. Try again."
        }
    }
}

#if DEBUG
extension DiscoverViewModel {
    /// A fixed set of shows for previews (mirrors the kit's sample library).
    static var sampleResults: [SearchResult] {
        [
            SearchResult(title: "Acquired", author: "Ben Gilbert & David Rosenthal",
                         feedURL: URL(string: "https://feeds.example.com/acquired")!,
                         category: "Business"),
            SearchResult(title: "Behind the Bastards", author: "Cool Zone Media",
                         feedURL: URL(string: "https://feeds.example.com/bastards")!,
                         category: "History"),
            SearchResult(title: "99% Invisible", author: "Roman Mars",
                         feedURL: URL(string: "https://feeds.example.com/99pi")!,
                         category: "Design"),
            SearchResult(title: "Darknet Diaries", author: "Jack Rhysider",
                         feedURL: URL(string: "https://feeds.example.com/darknet")!,
                         category: "Technology"),
            SearchResult(title: "The Rest Is History", author: "Goalhanger",
                         feedURL: URL(string: "https://feeds.example.com/history")!,
                         category: "History"),
        ]
    }

    /// A model pinned to a specific state for static previews (no search runs).
    convenience init(previewState state: State) {
        self.init(coordinator: SearchCoordinator(sources: [FixtureSource(results: DiscoverViewModel.sampleResults)]))
        self.state = state
    }
}
#endif
