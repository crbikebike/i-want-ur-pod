// App-level smoke tests. The substantive M1 suites live in the SwiftPM packages
// (PodcastModels/Tests, DirectoryKit/Tests) and run via `swift test`; this target
// exists so the generated Xcode scheme has an app-hosted test bundle to run, and
// verifies the package seams the app depends on are reachable from the app target.
import XCTest
import PodcastModels
import DirectoryKit

final class AppSmokeTests: XCTestCase {

    /// The shared SwiftData schema opens in-memory — the same container the app
    /// builds at launch (`ModelSchema.makeContainer`).
    func testModelSchemaOpensInMemory() throws {
        let container = try ModelSchema.makeContainer(inMemory: true)
        XCTAssertFalse(ModelSchema.models.isEmpty, "PodcastModels schema must list its @Model types")
        _ = container
    }

    /// A default coordinator ships with Apple (iTunes) as the enabled primary
    /// source, per direction.md §12.
    @MainActor
    func testDefaultCoordinatorHasApplePrimary() {
        let coordinator = SearchCoordinator()
        XCTAssertEqual(coordinator.orderedSources.first?.kind, .apple)
    }
}
