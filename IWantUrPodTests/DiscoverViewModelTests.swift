// Tests for DiscoverViewModel's E1-S2/E1-S3 behavior:
//   - the curated shelf backs the `.firstRun` (idle) state, and a bundle with
//     no `curated-start-here.json` degrades to an empty list, not a crash
//     (docs/spec/curated-list.schema.md's loader behavior, exercised end to
//     end through the view model rather than just DirectoryKit's loader).
//   - an empty query resolves to `.firstRun` (the curated/idle state), not a
//     blank screen (ROADMAP.md E1-S3).
// Runs on the iOS simulator alongside the rest of IWantUrPodTests.
import XCTest
import DirectoryKit
@testable import IWantUrPod

@MainActor
final class DiscoverViewModelTests: XCTestCase {

    private func makeCoordinator() -> SearchCoordinator {
        SearchCoordinator(sources: [
            try! FixtureSource(data: Data("""
            [{"title":"Acquired","author":"Ben Gilbert","feedUrl":"https://example.com/acquired"}]
            """.utf8))
        ])
    }

    func test_initialState_isFirstRun() {
        let viewModel = DiscoverViewModel(coordinator: makeCoordinator())
        XCTAssertEqual(viewModel.state, .firstRun)
    }

    func test_clearingAQuery_returnsToFirstRunIdleState() {
        let viewModel = DiscoverViewModel(coordinator: makeCoordinator())
        viewModel.query = "Acquired"
        XCTAssertNotEqual(viewModel.state, .firstRun)

        viewModel.clear()
        XCTAssertEqual(viewModel.state, .firstRun, "An emptied query must resolve to the curated/idle state, not a blank screen")
    }

    func test_curatedEntries_emptyWhenBundleHasNoCuratedFile() {
        // The test bundle (this file's own bundle) doesn't ship
        // curated-start-here.json — only the app target does — so this
        // exercises the "missing file" path end to end through the view
        // model's bundle lookup, not just DirectoryKit's loader in isolation.
        let viewModel = DiscoverViewModel(
            coordinator: makeCoordinator(),
            curatedBundle: Bundle(for: DiscoverViewModelTests.self)
        )
        XCTAssertEqual(viewModel.curatedEntries, [], "A bundle without the curated resource must degrade to an empty shelf, not crash")
    }

    // MARK: - Two-screen flow (search-typing → search-results)

    /// A query below `minimumCharacters` shows the suggestions screen with an
    /// empty list (the browse rail sits beneath it) — never `.loading`.
    func test_shortQuery_isTypingWithNoSuggestions() {
        let viewModel = DiscoverViewModel(coordinator: makeCoordinator(), minimumCharacters: 2)
        viewModel.query = "A"
        XCTAssertEqual(viewModel.state, .typing([]))
    }

    /// Typing a searchable query debounces then resolves into live suggestions
    /// in `.typing(_)` — NOT the committed `.results` screen (that needs submit).
    func test_typing_resolvesToSuggestions_notResults() async {
        let viewModel = DiscoverViewModel(
            coordinator: makeCoordinator(),
            debounce: .milliseconds(1),
            minimumCharacters: 2
        )
        viewModel.query = "Acq"

        await waitUntil { if case .typing(let s) = viewModel.state { return !s.isEmpty } else { return false } }

        guard case .typing(let suggestions) = viewModel.state else {
            return XCTFail("Expected .typing(matches), got \(viewModel.state)")
        }
        XCTAssertEqual(suggestions.first?.title, "Acquired")
    }

    /// Committing (keyboard Return → `submit()`) promotes the loaded suggestions
    /// to the full results screen.
    func test_submit_promotesSuggestionsToResults() async {
        let viewModel = DiscoverViewModel(
            coordinator: makeCoordinator(),
            debounce: .milliseconds(1),
            minimumCharacters: 2
        )
        viewModel.query = "Acq"
        await waitUntil { if case .typing(let s) = viewModel.state { return !s.isEmpty } else { return false } }

        viewModel.submit()

        guard case .results(let results) = viewModel.state else {
            return XCTFail("Expected .results after submit, got \(viewModel.state)")
        }
        XCTAssertEqual(results.first?.title, "Acquired")
    }

    /// Submitting an empty query returns to the rest state, never a blank search.
    func test_submit_withEmptyQuery_returnsFirstRun() {
        let viewModel = DiscoverViewModel(coordinator: makeCoordinator())
        viewModel.submit()
        XCTAssertEqual(viewModel.state, .firstRun)
    }

    // MARK: - Helpers

    /// Polls `condition` until true or a timeout, yielding between checks so the
    /// view model's debounce + fetch tasks can run.
    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition(), "Timed out waiting for condition", file: file, line: line)
    }
}
