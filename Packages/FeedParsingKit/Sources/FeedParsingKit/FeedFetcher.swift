// FeedFetcher — URLSession-based fetch entry point. No SwiftData import.
// Error model source of truth: docs/spec/feed-field-mapping.md (Error model).
import Foundation

/// Fetches a feed URL and parses it into a ``ParsedFeed``.
///
/// Maps non-2xx HTTP responses and network failures to
/// `FeedError.httpStatus` / `FeedError.networkFailure`; hands the body to
/// ``FeedParser`` for the malformed-body cases (non-XML, no
/// `<rss>`/`<channel>`, missing `<title>`).
public struct FeedFetcher: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches and parses `url`.
    ///
    /// - Throws: `FeedError.networkFailure` on a transport-level failure,
    ///   `FeedError.httpStatus` on a non-2xx response, or
    ///   `FeedError.malformedFeed` when the body isn't a usable feed.
    public func fetch(url: URL) async throws -> ParsedFeed {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw FeedError.networkFailure(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedError.networkFailure("No HTTP response received.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw FeedError.httpStatus(httpResponse.statusCode)
        }

        return try FeedParser.parse(data: data, feedURL: url)
    }
}
