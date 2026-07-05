// Tests for FeedParser — pure XML → ParsedFeed/ParsedEpisode decoding.
// Covers ROADMAP E0-S1 determinate criteria 1, 2, 4.
import XCTest
@testable import FeedParsingKit

final class FeedParserTests: XCTestCase {

    private func loadFixture(_ name: String, ext: String = "xml") throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            XCTFail("Missing fixture \(name).\(ext)")
            return Data()
        }
        return try Data(contentsOf: url)
    }

    private let feedURL = URL(string: "https://example.com/feed.xml")!

    // MARK: - Criterion 1: known-good fixture

    func test_knownGoodFixture_parsesChannelLevelFields() throws {
        let data = try loadFixture("good-feed")
        let feed = try FeedParser.parse(data: data, feedURL: feedURL)

        XCTAssertEqual(feed.title, "The Story Hour")
        XCTAssertEqual(feed.author, "Story Hour Media")
        XCTAssertEqual(feed.artworkURL, URL(string: "https://example.com/art.jpg"))
        XCTAssertEqual(feed.category, "Society & Culture")
        XCTAssertEqual(feed.homeURL, URL(string: "https://example.com/story-hour"))
        XCTAssertEqual(feed.episodes.count, 2)
    }

    func test_knownGoodFixture_parsesEpisodeFields() throws {
        let data = try loadFixture("good-feed")
        let feed = try FeedParser.parse(data: data, feedURL: feedURL)

        let ep1 = feed.episodes[0]
        XCTAssertEqual(ep1.guid, "story-hour-ep-1")
        XCTAssertEqual(ep1.title, "Episode One: The Beginning")
        XCTAssertEqual(ep1.summary, "The first episode of our story.")
        XCTAssertEqual(ep1.duration, 3723) // 01:02:03
        XCTAssertEqual(ep1.audioURL, URL(string: "https://example.com/audio/ep1.mp3"))
        XCTAssertFalse(ep1.isExplicit)
        XCTAssertNotEqual(ep1.publishDate, .distantPast)

        let ep2 = feed.episodes[1]
        XCTAssertEqual(ep2.guid, "story-hour-ep-2")
        XCTAssertEqual(ep2.summary, "The middle of the story.")
        XCTAssertEqual(ep2.duration, 45 * 60 + 30) // 45:30
        XCTAssertTrue(ep2.isExplicit)
        XCTAssertEqual(ep2.remoteArtworkURL, URL(string: "https://example.com/art-ep2.jpg"))
    }

    // MARK: - Criterion 2: item with no guid and no enclosure is skipped

    func test_itemWithNoGuidAndNoEnclosure_isSkipped() throws {
        let data = try loadFixture("skip-item-feed")
        let feed = try FeedParser.parse(data: data, feedURL: feedURL)

        XCTAssertEqual(feed.episodes.count, 1)
        XCTAssertEqual(feed.episodes[0].guid, "mixed-bag-ep-1")
    }

    // MARK: - Criterion 4: zero playable items yields empty episodes array

    func test_channelWithNoItems_yieldsEmptyEpisodesArray() throws {
        let data = try loadFixture("empty-feed")
        let feed = try FeedParser.parse(data: data, feedURL: feedURL)

        XCTAssertEqual(feed.title, "Empty Show")
        XCTAssertEqual(feed.episodes, [])
    }

    // MARK: - Error cases at the parse layer

    func test_nonXMLBody_throwsMalformedFeed() throws {
        let data = try loadFixture("not-xml", ext: "txt")

        XCTAssertThrowsError(try FeedParser.parse(data: data, feedURL: feedURL)) { error in
            guard case FeedError.malformedFeed = error else {
                XCTFail("Expected FeedError.malformedFeed, got \(error)")
                return
            }
        }
    }

    func test_channelMissingTitle_throwsMalformedFeed() throws {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0"><channel><link>https://example.com</link></channel></rss>
        """
        let data = xml.data(using: .utf8)!

        XCTAssertThrowsError(try FeedParser.parse(data: data, feedURL: feedURL)) { error in
            guard case FeedError.malformedFeed = error else {
                XCTFail("Expected FeedError.malformedFeed, got \(error)")
                return
            }
        }
    }

    // MARK: - Determinate fallback coverage (feed-field-mapping.md)

    /// Parses an inline RSS body, returning the sole parsed feed.
    private func parseInline(_ channelInner: String) throws -> ParsedFeed {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:content="http://purl.org/rss/1.0/modules/content/">
          <channel>
            <title>Fallback Show</title>
            \(channelInner)
          </channel>
        </rss>
        """
        return try FeedParser.parse(data: Data(xml.utf8), feedURL: feedURL)
    }

    func test_guid_fallsBackToEnclosureURL_whenGuidAbsent() throws {
        let feed = try parseInline("""
        <item>
          <title>No Guid</title>
          <enclosure url="https://example.com/audio/noguid.mp3" type="audio/mpeg"/>
        </item>
        """)
        XCTAssertEqual(feed.episodes.count, 1)
        XCTAssertEqual(feed.episodes[0].guid, "https://example.com/audio/noguid.mp3")
    }

    func test_author_fallsBackToManagingEditor_whenNoItunesAuthor() throws {
        let feed = try parseInline("<managingEditor>editor@example.com (Ed)</managingEditor>")
        XCTAssertEqual(feed.author, "editor@example.com (Ed)")
    }

    func test_author_fallsBackToOwnerName_whenNoAuthorOrManagingEditor() throws {
        let feed = try parseInline("""
        <itunes:owner>
          <itunes:name>Owner Name</itunes:name>
          <itunes:email>owner@example.com</itunes:email>
        </itunes:owner>
        """)
        XCTAssertEqual(feed.author, "Owner Name")
    }

    func test_artwork_fallsBackToImageURL_whenNoItunesImage() throws {
        let feed = try parseInline("<image><url>https://example.com/rss-image.jpg</url></image>")
        XCTAssertEqual(feed.artworkURL, URL(string: "https://example.com/rss-image.jpg"))
    }

    func test_category_fallsBackToPlainCategory_whenNoItunesCategory() throws {
        let feed = try parseInline("<category>True Crime</category>")
        XCTAssertEqual(feed.category, "True Crime")
    }

    func test_episodeTitle_fallsBackToItunesTitle_whenNoTitle() throws {
        let feed = try parseInline("""
        <item>
          <guid>t1</guid>
          <itunes:title>iTunes Title</itunes:title>
          <enclosure url="https://example.com/a.mp3" type="audio/mpeg"/>
        </item>
        """)
        XCTAssertEqual(feed.episodes.first?.title, "iTunes Title")
    }

    func test_episodeTitle_defaultsToUntitled_whenNoTitleAtAll() throws {
        let feed = try parseInline("""
        <item>
          <guid>t2</guid>
          <enclosure url="https://example.com/b.mp3" type="audio/mpeg"/>
        </item>
        """)
        XCTAssertEqual(feed.episodes.first?.title, "Untitled Episode")
    }

    func test_summary_fallsBackToContentEncoded_whenNoDescriptionOrItunesSummary() throws {
        let feed = try parseInline("""
        <item>
          <guid>s1</guid>
          <content:encoded>Rich show notes.</content:encoded>
          <enclosure url="https://example.com/c.mp3" type="audio/mpeg"/>
        </item>
        """)
        XCTAssertEqual(feed.episodes.first?.summary, "Rich show notes.")
    }

    func test_publishDate_defaultsToDistantPast_whenPubDateMissing() throws {
        let feed = try parseInline("""
        <item>
          <guid>d1</guid>
          <enclosure url="https://example.com/d.mp3" type="audio/mpeg"/>
        </item>
        """)
        XCTAssertEqual(feed.episodes.first?.publishDate, .distantPast)
    }

    func test_publishDate_defaultsToDistantPast_whenPubDateUnparseable() throws {
        let feed = try parseInline("""
        <item>
          <guid>d2</guid>
          <pubDate>not a real date</pubDate>
          <enclosure url="https://example.com/d2.mp3" type="audio/mpeg"/>
        </item>
        """)
        XCTAssertEqual(feed.episodes.first?.publishDate, .distantPast)
    }

    func test_isExplicit_defaultsToFalse_whenAbsent() throws {
        let feed = try parseInline("""
        <item>
          <guid>e1</guid>
          <enclosure url="https://example.com/e.mp3" type="audio/mpeg"/>
        </item>
        """)
        XCTAssertEqual(feed.episodes.first?.isExplicit, false)
    }

    func test_duration_parsesPlainSeconds() throws {
        let feed = try parseInline("""
        <item>
          <guid>dur1</guid>
          <itunes:duration>360</itunes:duration>
          <enclosure url="https://example.com/dur1.mp3" type="audio/mpeg"/>
        </item>
        """)
        XCTAssertEqual(feed.episodes.first?.duration, 360)
    }

    func test_duration_defaultsToZero_whenUnparseable() throws {
        let feed = try parseInline("""
        <item>
          <guid>dur2</guid>
          <itunes:duration>about an hour</itunes:duration>
          <enclosure url="https://example.com/dur2.mp3" type="audio/mpeg"/>
        </item>
        """)
        XCTAssertEqual(feed.episodes.first?.duration, 0)
    }
}
