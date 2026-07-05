// Tests for DirectoryKit driven by the offline fixture.
// Source/data model: docs/design/direction.md §12 (Apple primary keyless;
// PodcastIndex opt-in; PRIMARY + FALLBACK, never merged). Fixture:
// fixtures/sample-podcasts.json (copied into this test target's resources).
import XCTest
@testable import DirectoryKit

final class DirectoryKitTests: XCTestCase {

    // MARK: - Fixture loading

    /// Loads the bundled `sample-podcasts.json` resource shipped with the test
    /// target (a copy of `fixtures/sample-podcasts.json`).
    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "sample-podcasts", withExtension: "json"),
            "sample-podcasts.json is missing from the test bundle resources"
        )
        return try Data(contentsOf: url)
    }

    // MARK: - FixtureSource decoding + mapping

    func testFixtureDecodesAsSearchResultArray() throws {
        // The fixture is a flat array of SearchResult wire objects; it must
        // decode cleanly (this is exactly what FixtureSource does internally).
        let decoded = try JSONDecoder().decode([SearchResult].self, from: fixtureData())
        XCTAssertEqual(decoded.count, 14)
        XCTAssertEqual(decoded.first?.title, "99% Invisible")
        XCTAssertEqual(decoded.last?.title, "Climbing Gold")

        // And FixtureSource ingests the same data without throwing.
        let source = try FixtureSource(data: fixtureData())
        XCTAssertEqual(source.kind, .apple)
        XCTAssertTrue(source.isEnabled)
    }

    func testFixtureSourceMapsSearchResultFields() async throws {
        let source = try FixtureSource(data: fixtureData())

        let results = try await source.search(term: "99% Invisible")
        let match = try XCTUnwrap(results.first)

        XCTAssertEqual(match.title, "99% Invisible")
        XCTAssertEqual(match.author, "Roman Mars")
        XCTAssertEqual(
            match.feedURL,
            URL(string: "http://feeds.99percentinvisible.org/99percentinvisible")
        )
        XCTAssertEqual(match.homeURL, URL(string: "https://www.siriusxm.com"))
        XCTAssertEqual(match.category, "Design")
        // id is derived from the feed URL (§12 stable identity).
        XCTAssertEqual(match.id, "http://feeds.99percentinvisible.org/99percentinvisible")
    }

    func testFixtureSourceSearchesTitleAuthorAndCategory() async throws {
        let source = try FixtureSource(data: fixtureData())

        // Title match.
        let byTitle = try await source.search(term: "Acquired")
        XCTAssertEqual(byTitle.map(\.title), ["Acquired"])

        // Author match (Pushkin Industries publishes two shows in the fixture).
        let byAuthor = try await source.search(term: "Pushkin")
        XCTAssertEqual(Set(byAuthor.map(\.author)), ["Pushkin Industries"])
        XCTAssertEqual(byAuthor.count, 2)

        // Category match.
        let byCategory = try await source.search(term: "True Crime")
        XCTAssertEqual(byCategory.map(\.title), ["Bone Valley"])
    }

    func testFixtureSourceEmptyQueryReturnsNothing() async throws {
        let source = try FixtureSource(data: fixtureData())
        let empty = try await source.search(term: "   ")
        XCTAssertTrue(empty.isEmpty)
    }

    func testFixtureSourceThrowsDecodingOnGarbage() {
        let garbage = Data("not json".utf8)
        XCTAssertThrowsError(try FixtureSource(data: garbage)) { error in
            XCTAssertEqual(error as? SearchError, .decoding)
        }
    }

    // MARK: - SearchResult Codable

    func testSearchResultDecodesWireKeys() throws {
        let json = Data("""
        {
          "title": "Acquired",
          "author": "Ben Gilbert and David Rosenthal",
          "feedUrl": "https://feeds.transistor.fm/acquired",
          "homeUrl": "https://acquired.fm",
          "artworkUrl": "https://example.com/art.png",
          "category": "Technology"
        }
        """.utf8)

        let result = try JSONDecoder().decode(SearchResult.self, from: json)
        XCTAssertEqual(result.title, "Acquired")
        XCTAssertEqual(result.author, "Ben Gilbert and David Rosenthal")
        XCTAssertEqual(result.feedURL, URL(string: "https://feeds.transistor.fm/acquired"))
        XCTAssertEqual(result.homeURL, URL(string: "https://acquired.fm"))
        XCTAssertEqual(result.artworkURL, URL(string: "https://example.com/art.png"))
        XCTAssertEqual(result.category, "Technology")
    }

    func testSearchResultDecodesWithOptionalsAbsent() throws {
        let json = Data("""
        { "title": "Bare", "author": "Nobody", "feedUrl": "https://example.com/feed" }
        """.utf8)

        let result = try JSONDecoder().decode(SearchResult.self, from: json)
        XCTAssertEqual(result.title, "Bare")
        XCTAssertNil(result.homeURL)
        XCTAssertNil(result.artworkURL)
        XCTAssertNil(result.category)
    }

    // MARK: - SearchCoordinator primary -> fallback (§12.3)

    @MainActor
    func testCoordinatorFallsBackWhenPrimaryThrows() async throws {
        let primary = StubSource(kind: .podcastIndex, behavior: .throwing(.noKey))
        let fallback = try FixtureSource(data: fixtureData()) // .apple

        let coordinator = SearchCoordinator(sources: [primary, fallback])
        let results = try await coordinator.search(term: "Acquired")

        // The throwing primary is skipped; the fixture answers.
        XCTAssertEqual(results.map(\.title), ["Acquired"])
    }

    @MainActor
    func testCoordinatorFallsBackWhenPrimaryReturnsEmpty() async throws {
        let primary = StubSource(kind: .podcastIndex, behavior: .returning([]))
        let fallback = try FixtureSource(data: fixtureData()) // .apple

        let coordinator = SearchCoordinator(sources: [primary, fallback])
        let results = try await coordinator.search(term: "Acquired")

        XCTAssertEqual(results.map(\.title), ["Acquired"])
    }

    @MainActor
    func testCoordinatorDoesNotMergeWhenPrimaryReturnsResults() async throws {
        let onlyFromPrimary = SearchResult(
            title: "Primary Only",
            author: "Primary Author",
            feedURL: URL(string: "https://example.com/primary")!
        )
        let primary = StubSource(kind: .podcastIndex, behavior: .returning([onlyFromPrimary]))
        let fallback = try FixtureSource(data: fixtureData()) // .apple, has "Acquired"

        let coordinator = SearchCoordinator(sources: [primary, fallback])
        let results = try await coordinator.search(term: "Acquired")

        // Primary won: exactly its set, with no fallback entries merged in.
        XCTAssertEqual(results, [onlyFromPrimary])
        XCTAssertFalse(results.contains { $0.title == "Acquired" })
    }

    @MainActor
    func testCoordinatorRethrowsWhenEveryEnabledSourceThrows() async {
        let primary = StubSource(kind: .podcastIndex, behavior: .throwing(.rateLimited))
        let fallback = StubSource(kind: .apple, behavior: .throwing(.unavailable))

        let coordinator = SearchCoordinator(sources: [primary, fallback])
        do {
            _ = try await coordinator.search(term: "anything")
            XCTFail("Expected the last error to be rethrown")
        } catch {
            // The last enabled source's error propagates.
            XCTAssertEqual(error as? SearchError, .unavailable)
        }
    }

    @MainActor
    func testCoordinatorSkipsDisabledPrimary() async throws {
        let disabledPrimary = StubSource(
            kind: .podcastIndex,
            behavior: .returning([
                SearchResult(
                    title: "Should Not Appear",
                    author: "",
                    feedURL: URL(string: "https://example.com/nope")!
                )
            ]),
            isEnabled: false
        )
        let fallback = try FixtureSource(data: fixtureData())

        let coordinator = SearchCoordinator(sources: [disabledPrimary, fallback])
        // Coordinator seeds enablement from isEnabled, so the disabled source is
        // never consulted even though it is first in order.
        XCTAssertFalse(coordinator.isEnabled(.podcastIndex))

        let results = try await coordinator.search(term: "Acquired")
        XCTAssertEqual(results.map(\.title), ["Acquired"])
    }

    // MARK: - iTunes wire decoding (inline sample)

    func testITunesSourceDecodesInlineSample() async throws {
        // A minimal iTunes Search API payload with one well-formed podcast row
        // and one malformed row (no feedUrl) that must be dropped.
        let json = Data("""
        {
          "resultCount": 2,
          "results": [
            {
              "wrapperType": "track",
              "kind": "podcast",
              "collectionName": "Reply All",
              "artistName": "Gimlet",
              "feedUrl": "https://feeds.megaphone.fm/replyall",
              "collectionViewUrl": "https://podcasts.apple.com/us/podcast/reply-all/id941907967",
              "artworkUrl600": "https://example.com/replyall-600.jpg",
              "artworkUrl100": "https://example.com/replyall-100.jpg",
              "primaryGenreName": "Technology"
            },
            {
              "wrapperType": "track",
              "collectionName": "No Feed Here",
              "artistName": "Nobody",
              "primaryGenreName": "Technology"
            }
          ]
        }
        """.utf8)

        let stubbed = try StubURLProtocol.makeSession(returning: json, status: 200)
        let source = ITunesSource(session: stubbed)

        let results = try await source.search(term: "reply all")

        // Only the well-formed row survives; the feed-less row is dropped.
        XCTAssertEqual(results.count, 1)
        let match = try XCTUnwrap(results.first)
        XCTAssertEqual(match.title, "Reply All")
        XCTAssertEqual(match.author, "Gimlet")
        XCTAssertEqual(match.feedURL, URL(string: "https://feeds.megaphone.fm/replyall"))
        XCTAssertEqual(
            match.homeURL,
            URL(string: "https://podcasts.apple.com/us/podcast/reply-all/id941907967")
        )
        // Prefers artworkUrl600 over artworkUrl100.
        XCTAssertEqual(match.artworkURL, URL(string: "https://example.com/replyall-600.jpg"))
        XCTAssertEqual(match.category, "Technology")
    }

    func testITunesSourceMapsRateLimitStatus() async throws {
        let stubbed = try StubURLProtocol.makeSession(returning: Data("{}".utf8), status: 429)
        let source = ITunesSource(session: stubbed)

        do {
            _ = try await source.search(term: "reply all")
            XCTFail("Expected rateLimited")
        } catch {
            XCTAssertEqual(error as? SearchError, .rateLimited)
        }
    }

    // MARK: - SearchCoordinator with the real Apple + PodcastIndex sources (§12.3)

    /// An in-memory `PodcastIndexCredentialProviding` for tests — no Keychain.
    private struct FakeCredentialStore: PodcastIndexCredentialProviding {
        let credentials: PodcastIndexCredentials?
        func podcastIndexCredentials() -> PodcastIndexCredentials? { credentials }
    }

    @MainActor
    func testApplePrimarySuccess_returnsAppleResultsWithoutConsultingPodcastIndex() async throws {
        let appleJSON = Data("""
        { "resultCount": 1, "results": [
          { "wrapperType": "track", "collectionName": "Reply All", "artistName": "Gimlet",
            "feedUrl": "https://feeds.megaphone.fm/replyall" }
        ] }
        """.utf8)
        let session = RoutingStubURLProtocol.makeSession(responses: [
            "itunes.apple.com": .init(data: appleJSON, status: 200),
        ])
        let apple = ITunesSource(session: session)
        // PodcastIndex has no credentials configured; if consulted it would
        // throw .noKey rather than ever return data — this proves the
        // coordinator never falls through when the primary wins.
        let podcastIndex = PodcastIndexSource(isEnabled: true, credentialStore: FakeCredentialStore(credentials: nil))

        let coordinator = SearchCoordinator(sources: [apple, podcastIndex])
        let results = try await coordinator.search(term: "reply all")

        XCTAssertEqual(results.map(\.title), ["Reply All"])
    }

    @MainActor
    func testApplePrimaryFailure_fallsBackToPodcastIndex() async throws {
        let piJSON = Data("""
        { "status": true, "count": 1, "feeds": [
          { "title": "Darknet Diaries", "author": "Jack Rhysider",
            "url": "https://feeds.megaphone.fm/darknetdiaries" }
        ] }
        """.utf8)
        // A single shared session, routed per-host, so Apple's 500 and
        // PodcastIndex's 200 don't stomp on each other's canned response
        // (unlike `StubURLProtocol`, which holds one global response).
        let session = RoutingStubURLProtocol.makeSession(responses: [
            "itunes.apple.com": .init(data: Data("{}".utf8), status: 500),
            "api.podcastindex.org": .init(data: piJSON, status: 200),
        ])
        let apple = ITunesSource(session: session)
        let podcastIndex = PodcastIndexSource(
            isEnabled: true,
            credentialStore: FakeCredentialStore(credentials: PodcastIndexCredentials(key: "k", secret: "s")),
            session: session
        )

        let coordinator = SearchCoordinator(sources: [apple, podcastIndex])
        let results = try await coordinator.search(term: "darknet")

        // Apple (primary) failed; PodcastIndex (fallback) answered — and its
        // result alone, never merged with anything from Apple.
        XCTAssertEqual(results.map(\.title), ["Darknet Diaries"])
    }

    @MainActor
    func testApplePrimaryAndPodcastIndexFallbackBothFail_surfacesError() async {
        let session = RoutingStubURLProtocol.makeSession(responses: [
            "itunes.apple.com": .init(data: Data("{}".utf8), status: 500),
        ])
        let apple = ITunesSource(session: session)
        let podcastIndex = PodcastIndexSource(isEnabled: true, credentialStore: FakeCredentialStore(credentials: nil))

        let coordinator = SearchCoordinator(sources: [apple, podcastIndex])
        do {
            _ = try await coordinator.search(term: "anything")
            XCTFail("Expected every enabled source's failure to surface as an error")
        } catch {
            // Apple's 500 maps to .unavailable; PodcastIndex has no key so it
            // throws .noKey — the last enabled source's error propagates.
            XCTAssertEqual(error as? SearchError, .noKey)
        }
    }

    // MARK: - CuratedEntry / CuratedListLoader (E1-S2)

    func testCuratedListLoader_rendersEveryValidEntryInFileOrder() {
        let json = Data("""
        [
          {"title":"Bone Valley","author":"Lava for Good","feedUrl":"https://example.com/bone-valley","blurb":"Start here."},
          {"title":"Adrift","author":"Blanchard House","feedUrl":"https://example.com/adrift"}
        ]
        """.utf8)

        let entries = CuratedListLoader.load(from: json)

        XCTAssertEqual(entries.map(\.title), ["Bone Valley", "Adrift"])
        XCTAssertEqual(entries.first?.blurb, "Start here.")
        XCTAssertNil(entries.last?.blurb)
    }

    func testCuratedListLoader_skipsAMalformedEntryButKeepsTheRest() {
        let json = Data("""
        [
          {"title":"Bone Valley","author":"Lava for Good","feedUrl":"https://example.com/bone-valley"},
          {"title":"Missing feed URL","author":"Nobody"},
          {"title":"Unparseable URL","author":"Nobody","feedUrl":""},
          {"title":"Adrift","author":"Blanchard House","feedUrl":"https://example.com/adrift"}
        ]
        """.utf8)

        let entries = CuratedListLoader.load(from: json)

        // The two malformed rows (missing required `feedUrl`, and an
        // unparseable empty-string URL) are skipped, not fatal — the rest of
        // the shelf still renders, in file order.
        XCTAssertEqual(entries.map(\.title), ["Bone Valley", "Adrift"])
    }

    func testCuratedListLoader_missingOrEmptyFileYieldsEmptyNotFatal() {
        XCTAssertEqual(CuratedListLoader.load(from: Data()), [])
        XCTAssertEqual(CuratedListLoader.load(from: Data("not json".utf8)), [])
        XCTAssertEqual(CuratedListLoader.load(from: Data("[]".utf8)), [])
    }

    func testCuratedEntry_projectsToSearchResultForSharedSubscribeFlow() {
        let entry = CuratedEntry(
            title: "Bone Valley",
            author: "Lava for Good",
            feedURL: URL(string: "https://example.com/bone-valley")!,
            category: "True Crime",
            blurb: "Start here."
        )
        let result = entry.searchResult
        XCTAssertEqual(result.title, entry.title)
        XCTAssertEqual(result.feedURL, entry.feedURL)
        XCTAssertEqual(result.id, entry.id)
    }
}

// MARK: - Per-host routing stub (Apple + PodcastIndex in the same test)

/// A `URLProtocol` that returns a different canned response per request host,
/// unlike `StubURLProtocol` (above), whose single global response can't
/// represent "Apple fails, PodcastIndex succeeds" in one test without one
/// session's setup clobbering the other's.
private final class RoutingStubURLProtocol: URLProtocol {
    struct Response { let data: Data; let status: Int }

    static var responsesByHost: [String: Response] = [:]

    static func makeSession(responses: [String: Response]) -> URLSession {
        responsesByHost = responses
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RoutingStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(string: "https://example.com")!
        let match = url.host.flatMap { Self.responsesByHost[$0] } ?? Response(data: Data(), status: 404)
        let response = HTTPURLResponse(
            url: url,
            statusCode: match.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: match.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Test doubles

/// A hand-controlled ``DirectorySource`` for coordinator tests.
private struct StubSource: DirectorySource {
    enum Behavior: Sendable {
        case returning([SearchResult])
        case throwing(SearchError)
    }

    let kind: SourceKind
    let isEnabled: Bool
    let behavior: Behavior

    init(kind: SourceKind, behavior: Behavior, isEnabled: Bool = true) {
        self.kind = kind
        self.behavior = behavior
        self.isEnabled = isEnabled
    }

    func search(term: String) async throws -> [SearchResult] {
        switch behavior {
        case let .returning(results):
            return results
        case let .throwing(error):
            throw error
        }
    }
}

/// A `URLProtocol` that returns a canned response, used to decode iTunes JSON
/// without touching the network.
private final class StubURLProtocol: URLProtocol {
    // Canned response for the single in-flight request; tests are serial per
    // XCTestCase instance so a static handoff is sufficient.
    static var stubData: Data = Data()
    static var stubStatus: Int = 200

    static func makeSession(returning data: Data, status: Int) throws -> URLSession {
        stubData = data
        stubStatus = status
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(string: "https://itunes.apple.com/search")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: StubURLProtocol.stubStatus,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: StubURLProtocol.stubData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
