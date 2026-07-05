// PodcastIndex search source. Source model: docs/design/direction.md §12.2
// (opt-in, user-supplied API key + secret kept in Keychain, never committed).
// Endpoint: https://api.podcastindex.org/api/1.0/search/byterm?q=<term>
import Foundation
import CryptoKit

// MARK: - Credentials

/// A PodcastIndex API key + secret pair supplied by the user.
///
/// The secret is never logged or included in any diagnostic output (§12.2).
public struct PodcastIndexCredentials: Sendable, Hashable {

    /// The PodcastIndex API key (`X-Auth-Key`).
    public let key: String

    /// The PodcastIndex API secret. Used only to compute the `Authorization`
    /// hash; it is never transmitted or logged.
    public let secret: String

    public init(key: String, secret: String) {
        self.key = key
        self.secret = secret
    }
}

/// Supplies PodcastIndex credentials to the source.
///
/// Abstracts the concrete ``KeychainStore`` so the source can be tested without
/// touching the system keychain.
public protocol PodcastIndexCredentialProviding: Sendable {
    /// The stored PodcastIndex credentials, or `nil` when none are configured.
    func podcastIndexCredentials() -> PodcastIndexCredentials?
}

// The concrete keychain-backed conformer of `PodcastIndexCredentialProviding`
// is `KeychainStore`, defined in KeychainStore.swift (a single canonical type
// for the module). Its `PodcastIndexCredentialProviding` conformance lives
// alongside that declaration.

// MARK: - Auth

/// Builds the PodcastIndex authentication headers (§12.2).
///
/// PodcastIndex signs each request with `X-Auth-Key`, `X-Auth-Date` (a unix
/// timestamp in seconds), and an `Authorization` header equal to the lowercase
/// hex SHA-1 of `key + secret + date`. The secret is only ever consumed here to
/// produce the hash; it is never logged or transmitted directly.
public struct PodcastIndexAuth: Sendable {

    /// The `User-Agent` sent with each request.
    public let userAgent: String

    public init(userAgent: String = "iWantUrPod/1.0 (+https://github.com/i-want-ur-pod)") {
        self.userAgent = userAgent
    }

    /// Computes the signed headers for `credentials` at `date`.
    ///
    /// - Parameters:
    ///   - credentials: The user's PodcastIndex key + secret.
    ///   - date: The request time; defaults to now. Injectable for testing.
    /// - Returns: A header dictionary ready to apply to a `URLRequest`.
    public func headers(
        for credentials: PodcastIndexCredentials,
        date: Date = Date()
    ) -> [String: String] {
        let unixSeconds = String(Int(date.timeIntervalSince1970))
        let signature = Self.authorization(
            key: credentials.key,
            secret: credentials.secret,
            date: unixSeconds
        )
        return [
            "X-Auth-Key": credentials.key,
            "X-Auth-Date": unixSeconds,
            "Authorization": signature,
            "User-Agent": userAgent,
        ]
    }

    /// Lowercase hex SHA-1 of `key + secret + date`.
    static func authorization(key: String, secret: String, date: String) -> String {
        let payload = Data((key + secret + date).utf8)
        let digest = Insecure.SHA1.hash(data: payload)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Source

/// Opt-in podcast search backed by the PodcastIndex API (§12.2).
///
/// Disabled until the user supplies their own API key + secret. When no
/// credentials are configured, `search(term:)` throws ``SearchError/noKey`` so
/// the coordinator can fall back to the primary (Apple) source.
public struct PodcastIndexSource: DirectorySource {

    public let kind: SourceKind = .podcastIndex

    /// PodcastIndex is opt-in; it is only eligible once the user enables it.
    public let isEnabled: Bool

    /// Maximum number of results requested from the API.
    private let limit: Int

    /// Supplies the user's credentials (defaults to the system keychain).
    private let credentialStore: any PodcastIndexCredentialProviding

    /// Signs requests with the PodcastIndex auth headers.
    private let auth: PodcastIndexAuth

    /// The URLSession used for requests (injectable for testing).
    private let session: URLSession

    public init(
        isEnabled: Bool = false,
        limit: Int = 25,
        credentialStore: any PodcastIndexCredentialProviding = KeychainStore(),
        auth: PodcastIndexAuth = PodcastIndexAuth(),
        session: URLSession = .shared
    ) {
        self.isEnabled = isEnabled
        self.limit = limit
        self.credentialStore = credentialStore
        self.auth = auth
        self.session = session
    }

    public func search(term: String) async throws -> [SearchResult] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard let credentials = credentialStore.podcastIndexCredentials() else {
            throw SearchError.noKey
        }

        guard let url = makeURL(term: trimmed) else {
            throw SearchError.unavailable
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (field, value) in auth.headers(for: credentials) {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SearchError.unavailable
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200...299:
                break
            case 401, 403:
                // Rejected credentials: surface as missing-key so the coordinator
                // falls back rather than retrying a bad signature.
                throw SearchError.noKey
            case 429:
                throw SearchError.rateLimited
            default:
                throw SearchError.unavailable
            }
        }

        let payload: PodcastIndexResponse
        do {
            payload = try JSONDecoder().decode(PodcastIndexResponse.self, from: data)
        } catch {
            throw SearchError.decoding
        }

        return payload.feeds.compactMap { $0.asSearchResult }
    }

    private func makeURL(term: String) -> URL? {
        var components = URLComponents(string: "https://api.podcastindex.org/api/1.0/search/byterm")
        components?.queryItems = [
            URLQueryItem(name: "q", value: term),
            URLQueryItem(name: "max", value: String(limit)),
        ]
        return components?.url
    }
}

// MARK: - Wire model

/// Top-level shape of the PodcastIndex `search/byterm` response.
private struct PodcastIndexResponse: Decodable {
    let status: PodcastIndexStatus?
    let count: Int?
    let feeds: [PodcastIndexFeed]

    enum CodingKeys: String, CodingKey {
        case status, count, feeds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try? container.decode(PodcastIndexStatus.self, forKey: .status)
        self.count = try? container.decode(Int.self, forKey: .count)
        self.feeds = (try? container.decode([PodcastIndexFeed].self, forKey: .feeds)) ?? []
    }
}

/// PodcastIndex reports `status` as either the string "true"/"false" or a bool.
private struct PodcastIndexStatus: Decodable {
    let ok: Bool

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let flag = try? single.decode(Bool.self) {
            self.ok = flag
        } else if let text = try? single.decode(String.self) {
            self.ok = text.caseInsensitiveCompare("true") == .orderedSame
        } else {
            self.ok = false
        }
    }
}

/// A single entry in the PodcastIndex `feeds` array.
private struct PodcastIndexFeed: Decodable {
    let title: String?
    let author: String?
    let ownerName: String?
    let url: String?
    let link: String?
    let image: String?
    let artwork: String?
    let categories: [String: String]?

    /// Projects a directory entry into a ``SearchResult``.
    ///
    /// Returns `nil` when the entry lacks a usable feed URL (the subscribe
    /// handle is required), so malformed rows are dropped.
    var asSearchResult: SearchResult? {
        guard let feed = url.flatMap(URL.init(string:)) else {
            return nil
        }

        let home = link.flatMap(URL.init(string:))
        let art = (artwork ?? image).flatMap(URL.init(string:))
        let category = categories?.values.sorted().first

        return SearchResult(
            title: title ?? "",
            author: author ?? ownerName ?? "",
            feedURL: feed,
            homeURL: home,
            artworkURL: art,
            category: category
        )
    }
}
