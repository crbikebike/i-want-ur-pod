// Apple (iTunes) Search API source. Source model: docs/design/direction.md §12.1
// (keyless, ships ON, primary by default). Endpoint:
// https://itunes.apple.com/search?media=podcast&entity=podcast
import Foundation

/// Keyless podcast search backed by Apple's iTunes Search API.
///
/// This is the primary source of §12: it requires no credentials, ships enabled,
/// and returns Apple's podcast directory results decoded into ``SearchResult``.
public struct ITunesSource: DirectorySource {

    public let kind: SourceKind = .apple

    /// Apple's source ships enabled and needs no key (§12.1).
    public let isEnabled: Bool

    /// Maximum number of results requested from the API.
    private let limit: Int

    /// The URLSession used for requests (injectable for testing).
    private let session: URLSession

    public init(isEnabled: Bool = true, limit: Int = 25, session: URLSession = .shared) {
        self.isEnabled = isEnabled
        self.limit = limit
        self.session = session
    }

    public func search(term: String) async throws -> [SearchResult] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard let url = makeURL(term: trimmed) else {
            throw SearchError.unavailable
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw SearchError.unavailable
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200...299:
                break
            case 403, 429:
                throw SearchError.rateLimited
            default:
                throw SearchError.unavailable
            }
        }

        let payload: ITunesResponse
        do {
            payload = try JSONDecoder().decode(ITunesResponse.self, from: data)
        } catch {
            throw SearchError.decoding
        }

        return payload.results.compactMap { $0.asSearchResult }
    }

    private func makeURL(term: String) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return components?.url
    }
}

// MARK: - Wire model

/// Top-level shape of the iTunes Search API response.
private struct ITunesResponse: Decodable {
    let resultCount: Int
    let results: [ITunesResult]
}

/// A single entry in the iTunes Search API `results` array.
private struct ITunesResult: Decodable {
    let wrapperType: String?
    let collectionName: String?
    let trackName: String?
    let artistName: String?
    let feedUrl: String?
    let collectionViewUrl: String?
    let trackViewUrl: String?
    let artworkUrl600: String?
    let artworkUrl100: String?
    let primaryGenreName: String?

    /// Projects a directory entry into a ``SearchResult``.
    ///
    /// Returns `nil` when the entry lacks a usable feed URL (the subscribe
    /// handle is required), so non-podcast or malformed rows are dropped.
    var asSearchResult: SearchResult? {
        guard
            let feed = feedUrl.flatMap(URL.init(string:))
        else {
            return nil
        }

        let title = collectionName ?? trackName ?? ""
        let home = (collectionViewUrl ?? trackViewUrl).flatMap(URL.init(string:))
        let artwork = (artworkUrl600 ?? artworkUrl100).flatMap(URL.init(string:))

        return SearchResult(
            title: title,
            author: artistName ?? "",
            feedURL: feed,
            homeURL: home,
            artworkURL: artwork,
            category: primaryGenreName
        )
    }
}
