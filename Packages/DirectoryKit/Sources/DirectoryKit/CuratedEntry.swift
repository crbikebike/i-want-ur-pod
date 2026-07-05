// Curated "start here" list. Schema + loader behavior source:
// docs/spec/curated-list.schema.md (E1-S2). The shipped bundle file is
// IWantUrPod/Resources/curated-start-here.json; the app owns the bundle I/O
// (Bundle.main.url(forResource:withExtension:) → Data) and hands the raw
// `Data` to `CuratedListLoader.load(from:)` here, keeping decoding pure and
// host-testable (`swift test`, no app target / bundle needed).
import Foundation

/// One hand-curated "start here" pick — a superset of ``SearchResult`` plus an
/// editorial ``blurb``. Field names match the schema doc and the fixture wire
/// keys exactly (`feedUrl`/`homeUrl`/`artworkUrl`), not camelCase URL.
public struct CuratedEntry: Sendable, Hashable, Identifiable, Codable {

    /// Stable identity, mirroring ``SearchResult/id`` — derived from the feed
    /// URL so a curated entry and a search result for the same show resolve to
    /// the same identity.
    public var id: String { feedURL.absoluteString }

    public let title: String
    public let author: String
    public let feedURL: URL
    public let homeURL: URL?
    public let artworkURL: URL?
    public let category: String?

    /// One editorial sentence on why this is a good place to start.
    public let blurb: String?

    public init(
        title: String,
        author: String,
        feedURL: URL,
        homeURL: URL? = nil,
        artworkURL: URL? = nil,
        category: String? = nil,
        blurb: String? = nil
    ) {
        self.title = title
        self.author = author
        self.feedURL = feedURL
        self.homeURL = homeURL
        self.artworkURL = artworkURL
        self.category = category
        self.blurb = blurb
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case author
        case feedURL = "feedUrl"
        case homeURL = "homeUrl"
        case artworkURL = "artworkUrl"
        case category
        case blurb
    }

    /// Projects this curated pick into a plain ``SearchResult`` — e.g. to reuse
    /// the same subscribe-persistence path Discover's search results use.
    public var searchResult: SearchResult {
        SearchResult(
            title: title,
            author: author,
            feedURL: feedURL,
            homeURL: homeURL,
            artworkURL: artworkURL,
            category: category
        )
    }
}

// MARK: - Loader

/// Decodes the bundled curated list per the loader behavior in
/// `docs/spec/curated-list.schema.md`:
/// - every valid entry renders, in file order;
/// - a malformed entry (missing a required key, or an unparseable URL) is
///   skipped, not fatal;
/// - a missing/empty/garbage file yields an empty array, never a crash.
public enum CuratedListLoader {

    /// Decodes `data` into the curated entries that should render, skipping
    /// any malformed element.
    ///
    /// - Parameter data: The raw bytes of `curated-start-here.json` (or any
    ///   data shaped like it). Pass `Data()` (or the result of a failed bundle
    ///   lookup) for "missing file" — this returns `[]`, never throws.
    public static func load(from data: Data) -> [CuratedEntry] {
        guard !data.isEmpty else { return [] }
        guard let decoded = try? JSONDecoder().decode([FailableCuratedEntry].self, from: data) else {
            return []
        }
        return decoded.compactMap(\.entry)
    }
}

/// Decodes one array element as a ``CuratedEntry``, swallowing any per-element
/// decoding failure (missing required key, unparseable URL, wrong shape)
/// instead of failing the whole array decode.
private struct FailableCuratedEntry: Decodable {
    let entry: CuratedEntry?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        entry = try? container.decode(CuratedEntry.self)
    }
}
