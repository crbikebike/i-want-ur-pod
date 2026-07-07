// Locks E8-S1's first criterion: "The tab bar shows exactly four
// destinations, in order: Home, Shows, Up Next, Search." `AppTab` (owned by
// `LiquidGlassTabBar`'s component layer, DesignSystem) drives both the dock's
// rendering order and `AppShell`'s content switch, so pinning `allCases` here
// catches any accidental reordering, addition, or removal of a tab.
import XCTest
import DesignSystem

final class AppTabTests: XCTestCase {

    func test_allCases_isExactlyHomeShowsUpNextSearch_inOrder() {
        XCTAssertEqual(AppTab.allCases, [.home, .shows, .upNext, .search])
    }

    func test_titles_matchTheKitLabels() {
        XCTAssertEqual(AppTab.home.title, "Home")
        XCTAssertEqual(AppTab.shows.title, "Shows")
        XCTAssertEqual(AppTab.upNext.title, "Up Next")
        XCTAssertEqual(AppTab.search.title, "Search")
    }
}
