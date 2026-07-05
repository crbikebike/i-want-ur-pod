// Discover search state machine. Drives design/kit/screens/{first-run,typing,
// loading,no-results,error}.html — one `State` per screen. Search flows through
// DirectoryKit's SearchCoordinator (primary + fallback, docs/design/direction.md §12).
import Foundation
import Observation
import DirectoryKit

/// View model for the Discover screen.
///
/// Owns the debounced search `query`, resolves it to a `State` that maps 1:1
/// onto the kit's Discover screens, and delegates the actual lookup to an
/// injected ``SearchCoordinator``. A query change cancels any in-flight work,
/// debounces, then searches; `submit()` searches immediately.
@MainActor
@Observable
public final class DiscoverViewModel {

    /// One state per Discover screen in the kit.
    public enum State: Equatable, Sendable {
        /// Empty query — the discovery prompt (`first-run.html`).
        case firstRun
        /// A query too short to search yet, or awaiting the debounce (`typing.html`).
        case typing
        /// A search is in flight (`loading.html`).
        case loading
        /// A non-empty result set (the grouped results list).
        case results([SearchResult])
        /// A completed search that matched nothing (`no-results.html`).
        case noResults
        /// The search failed; carries a human-readable message (`error.html`).
        case error(String)
    }

    /// The raw search text bound to the `SearchField`. Mutating it re-drives the
    /// state machine (debounced) via the property observer.
    public var query: String = "" {
        didSet { queryDidChange() }
    }

    /// The current screen state. Read-only to callers; the model owns transitions.
    public private(set) var state: State = .firstRun

    private let coordinator: SearchCoordinator
    private let debounce: Duration
    private let minimumCharacters: Int

    private var debounceTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    /// - Parameters:
    ///   - coordinator: The search orchestrator (primary + fallback sources).
    ///   - debounce: How long to wait after the last keystroke before searching.
    ///   - minimumCharacters: The shortest query that triggers a search.
    public init(
        coordinator: SearchCoordinator,
        debounce: Duration = .milliseconds(320),
        minimumCharacters: Int = 2
    ) {
        self.coordinator = coordinator
        self.debounce = debounce
        self.minimumCharacters = minimumCharacters
    }

    // MARK: - Intents

    /// Search immediately, bypassing the debounce (keyboard "Search" / return).
    public func submit() {
        debounceTask?.cancel()
        let term = trimmedQuery
        guard !term.isEmpty else {
            cancelAll()
            state = .firstRun
            return
        }
        startSearch(term: term)
    }

    /// Re-run the last query — the error state's "Retry" action.
    public func retry() {
        submit()
    }

    /// Clear the query and return to the first-run prompt — the no-results
    /// state's "Clear search" action.
    public func clear() {
        query = ""   // triggers `queryDidChange()` → `.firstRun`
    }

    /// Seed the field with a suggestion and search it (first-run suggestion chips).
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
            state = .firstRun
            return
        }
        if term.count < minimumCharacters {
            state = .typing
            return
        }

        state = .typing
        debounceTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            self.startSearch(term: term)
        }
    }

    private func startSearch(term: String) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            await self?.performSearch(term: term)
        }
    }

    private func performSearch(term: String) async {
        state = .loading
        do {
            let results = try await coordinator.search(term: term)
            guard !Task.isCancelled else { return }
            // Ignore a resolution that no longer matches the current query.
            guard term == trimmedQuery else { return }
            state = results.isEmpty ? .noResults : .results(results)
        } catch is CancellationError {
            // Superseded by a newer query — leave state to the newer task.
        } catch {
            guard !Task.isCancelled, term == trimmedQuery else { return }
            state = .error(Self.message(for: error))
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
