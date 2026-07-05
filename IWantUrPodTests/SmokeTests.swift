// Smoke tests for the IWantUrPod app target. Gives IWantUrPodTests a real
// source file so `xcodegen generate` has a non-empty path to attach, and
// sanity-checks that the linked foundation packages import and construct.
import XCTest
import PodcastModels
import DirectoryKit

final class SmokeTests: XCTestCase {

    /// The shared model schema builds an in-memory container.
    func testInMemoryContainerBuilds() throws {
        _ = try ModelSchema.makeContainer(inMemory: true)
    }

    /// The directory search-result contract round-trips its stored fields.
    func testSearchResultHoldsFields() throws {
        let feed = try XCTUnwrap(URL(string: "https://example.com/feed.xml"))
        let result = SearchResult(title: "Show", author: "Host", feedURL: feed)
        XCTAssertEqual(result.title, "Show")
        XCTAssertEqual(result.author, "Host")
        XCTAssertEqual(result.id, feed.absoluteString)
    }
}
