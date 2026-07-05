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
}
