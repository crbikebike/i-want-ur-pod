// Tests for CatalogEntry / ThemeArc / CatalogLoader (offline catalog).
// Schema/provenance source: curation/catalog/catalog.schema.md. Inline JSON
// only — the real bundled catalog.json/themes.json are app resources, not
// this test target's, so fixtures are expressed as literal wire JSON here
// (matching DirectoryKitTests's `testSearchResultDecodesWireKeys` style).
import XCTest
@testable import DirectoryKit

final class CatalogLoaderTests: XCTestCase {

    // MARK: - CatalogEntry decoding

    func testCatalogLoader_decodesAllFieldsIncludingWireKeysAndThemes() throws {
        let json = Data("""
        [
          {
            "id": 0,
            "title": "Revisionist History",
            "author": "Pushkin Industries",
            "network": "Pushkin Industries",
            "feedUrl": "https://example.com/revisionist-history.rss",
            "homeUrl": "https://podcasts.apple.com/us/podcast/revisionist-history",
            "artworkUrl": "https://example.com/art.jpg",
            "category": "Society & Culture",
            "years": "2016–",
            "why": "Pushkin's flagship launch title.",
            "description": "Malcolm Gladwell revisits overlooked events.",
            "themes": ["institutional-coverup", "historical-reconstruction"]
          }
        ]
        """.utf8)

        let entries = CatalogLoader.loadEntries(from: json)

        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.atlasID, 0)
        XCTAssertEqual(entry.title, "Revisionist History")
        XCTAssertEqual(entry.author, "Pushkin Industries")
        XCTAssertEqual(entry.network, "Pushkin Industries")
        XCTAssertEqual(entry.feedURL, URL(string: "https://example.com/revisionist-history.rss"))
        XCTAssertEqual(entry.homeURL, URL(string: "https://podcasts.apple.com/us/podcast/revisionist-history"))
        XCTAssertEqual(entry.artworkURL, URL(string: "https://example.com/art.jpg"))
        XCTAssertEqual(entry.category, "Society & Culture")
        XCTAssertEqual(entry.years, "2016–")
        XCTAssertEqual(entry.why, "Pushkin's flagship launch title.")
        XCTAssertEqual(entry.summary, "Malcolm Gladwell revisits overlooked events.")
        XCTAssertEqual(entry.themes, ["institutional-coverup", "historical-reconstruction"])
        // Subscribe identity mirrors the feed URL, like SearchResult/CuratedEntry.
        XCTAssertEqual(entry.id, "https://example.com/revisionist-history.rss")
    }

    func testCatalogLoader_entryWithNoThemesKeyDecodesEmptyArray() throws {
        let json = Data("""
        [
          {"id": 1, "title": "No Arc Show", "author": "Nobody", "feedUrl": "https://example.com/no-arc.rss"}
        ]
        """.utf8)

        let entries = CatalogLoader.loadEntries(from: json)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.themes, [])
    }

    func testCatalogLoader_skipsAMalformedEntryButKeepsTheRest() {
        let json = Data("""
        [
          {"id": 1, "title": "Good Show", "author": "Someone", "feedUrl": "https://example.com/good.rss"},
          {"id": 2, "title": "Missing feed URL", "author": "Nobody"},
          "not an object",
          {"id": 3, "title": "Another Good Show", "author": "Someone Else", "feedUrl": "https://example.com/another.rss"}
        ]
        """.utf8)

        let entries = CatalogLoader.loadEntries(from: json)

        XCTAssertEqual(entries.map(\.title), ["Good Show", "Another Good Show"])
    }

    func testCatalogLoader_missingOrEmptyOrGarbageFileYieldsEmptyNotFatal() {
        XCTAssertEqual(CatalogLoader.loadEntries(from: Data()), [])
        XCTAssertEqual(CatalogLoader.loadEntries(from: Data("not json".utf8)), [])
        XCTAssertEqual(CatalogLoader.loadEntries(from: Data("[]".utf8)), [])
    }

    // MARK: - shows(inTheme:from:)

    func testShowsInTheme_returnsOnlyMatchingEntriesInFileOrder() {
        let json = Data("""
        [
          {"id": 1, "title": "A", "author": "A", "feedUrl": "https://example.com/a.rss", "themes": ["institutional-coverup"]},
          {"id": 2, "title": "B", "author": "B", "feedUrl": "https://example.com/b.rss", "themes": ["historical-reconstruction"]},
          {"id": 3, "title": "C", "author": "C", "feedUrl": "https://example.com/c.rss", "themes": ["institutional-coverup", "historical-reconstruction"]}
        ]
        """.utf8)
        let entries = CatalogLoader.loadEntries(from: json)

        let inTheme = CatalogLoader.shows(inTheme: "institutional-coverup", from: entries)

        XCTAssertEqual(inTheme.map(\.title), ["A", "C"])
    }

    // MARK: - CatalogEntry.searchResult projection

    func testCatalogEntry_projectsToSearchResultForSharedSubscribeFlow() {
        let entry = CatalogEntry(
            atlasID: 0,
            title: "Bone Valley",
            author: "Lava for Good",
            feedURL: URL(string: "https://example.com/bone-valley")!,
            category: "True Crime"
        )
        let result = entry.searchResult
        XCTAssertEqual(result.title, entry.title)
        XCTAssertEqual(result.feedURL, entry.feedURL)
        XCTAssertEqual(result.id, entry.id)
    }

    // MARK: - ThemeArc decoding

    func testThemeArc_decodesSlugNameDescriptionAndShowCount() throws {
        let json = Data("""
        [
          {
            "slug": "institutional-coverup",
            "name": "The Institutional Cover-Up",
            "description": "An investigation exposes how a powerful institution hid wrongdoing.",
            "showCount": 72
          }
        ]
        """.utf8)

        let arcs = CatalogLoader.loadThemes(from: json)

        XCTAssertEqual(arcs.count, 1)
        let arc = try XCTUnwrap(arcs.first)
        XCTAssertEqual(arc.slug, "institutional-coverup")
        XCTAssertEqual(arc.name, "The Institutional Cover-Up")
        XCTAssertEqual(arc.summary, "An investigation exposes how a powerful institution hid wrongdoing.")
        XCTAssertEqual(arc.showCount, 72)
        XCTAssertEqual(arc.id, "institutional-coverup")
    }

    func testThemeArc_skipsMalformedEntry() {
        let json = Data("""
        [
          {"slug": "good-arc", "name": "Good Arc", "showCount": 5},
          {"name": "Missing slug", "showCount": 3}
        ]
        """.utf8)

        let arcs = CatalogLoader.loadThemes(from: json)

        XCTAssertEqual(arcs.map(\.slug), ["good-arc"])
    }

    func testCatalogLoader_loadThemesMissingOrEmptyOrGarbageFileYieldsEmptyNotFatal() {
        XCTAssertEqual(CatalogLoader.loadThemes(from: Data()), [])
        XCTAssertEqual(CatalogLoader.loadThemes(from: Data("not json".utf8)), [])
        XCTAssertEqual(CatalogLoader.loadThemes(from: Data("[]".utf8)), [])
    }
}
