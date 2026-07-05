// Tests for FeedFetcher — URLSession fetch entry point mapping HTTP/body
// failures to typed FeedError. Covers ROADMAP E0-S1 determinate criterion 3.
// Uses a stubbed URLProtocol so no real network is hit.
import XCTest
@testable import FeedParsingKit

/// Injects a canned response for every request, keyed by absolute URL string.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let body: Data
        let error: Error?
    }

    static var stubs: [String: Stub] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let stub = Self.stubs[url.absoluteString] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class FeedFetcherTests: XCTestCase {

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override func tearDown() {
        StubURLProtocol.stubs.removeAll()
        super.tearDown()
    }

    func test_404Response_throwsTypedFetchError() async throws {
        let url = URL(string: "https://example.com/missing-feed.xml")!
        StubURLProtocol.stubs[url.absoluteString] = .init(statusCode: 404, body: Data(), error: nil)
        let fetcher = FeedFetcher(session: makeSession())

        do {
            _ = try await fetcher.fetch(url: url)
            XCTFail("Expected FeedError.httpStatus to be thrown")
        } catch FeedError.httpStatus(let code) {
            XCTAssertEqual(code, 404)
        } catch {
            XCTFail("Expected FeedError.httpStatus, got \(error)")
        }
    }

    func test_nonXMLBody_throwsTypedMalformedFeedError() async throws {
        let url = URL(string: "https://example.com/not-a-feed.xml")!
        let body = "<html><body>nope</body></html>".data(using: .utf8)!
        StubURLProtocol.stubs[url.absoluteString] = .init(statusCode: 200, body: body, error: nil)
        let fetcher = FeedFetcher(session: makeSession())

        do {
            _ = try await fetcher.fetch(url: url)
            XCTFail("Expected FeedError.malformedFeed to be thrown")
        } catch FeedError.malformedFeed {
            // expected
        } catch {
            XCTFail("Expected FeedError.malformedFeed, got \(error)")
        }
    }

    func test_networkFailure_throwsTypedFetchError() async throws {
        let url = URL(string: "https://example.com/unreachable-feed.xml")!
        StubURLProtocol.stubs[url.absoluteString] = .init(
            statusCode: 0,
            body: Data(),
            error: URLError(.notConnectedToInternet)
        )
        let fetcher = FeedFetcher(session: makeSession())

        do {
            _ = try await fetcher.fetch(url: url)
            XCTFail("Expected FeedError.networkFailure to be thrown")
        } catch FeedError.networkFailure {
            // expected
        } catch {
            XCTFail("Expected FeedError.networkFailure, got \(error)")
        }
    }

    func test_goodResponse_parsesSuccessfully() async throws {
        let url = URL(string: "https://example.com/good-feed.xml")!
        guard let fixtureURL = Bundle.module.url(forResource: "good-feed", withExtension: "xml") else {
            XCTFail("Missing fixture")
            return
        }
        let body = try Data(contentsOf: fixtureURL)
        StubURLProtocol.stubs[url.absoluteString] = .init(statusCode: 200, body: body, error: nil)
        let fetcher = FeedFetcher(session: makeSession())

        let feed = try await fetcher.fetch(url: url)

        XCTAssertEqual(feed.title, "The Story Hour")
        XCTAssertEqual(feed.feedURL, url)
        XCTAssertEqual(feed.episodes.count, 2)
    }
}
