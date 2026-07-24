// Offline catalog. Schema + provenance source: curation/catalog/catalog.schema.md.
// The shipped bundle files are IWantUrPod/Resources/catalog.json and
// IWantUrPod/Resources/themes.json; the app owns the bundle I/O
// (Bundle.main.url(forResource:withExtension:) → Data) and hands the raw
// `Data` to `CatalogLoader` here, keeping decoding pure and host-testable
// (`swift test`, no app target / bundle needed).
import Foundation

/// One bundled catalog show — a superset of ``CuratedEntry`` (and, in turn,
/// ``SearchResult``) so it reuses the same subscribe path. Field names match
/// the schema doc and the fixture wire keys exactly (`feedUrl`/`homeUrl`/
/// `artworkUrl`/`description`), not camelCase URL.
public struct CatalogEntry: Sendable, Hashable, Identifiable, Codable {

    /// Stable identity, mirroring ``SearchResult/id`` — derived from the feed
    /// URL so a catalog entry and a search result for the same show resolve
    /// to the same identity.
    public var id: String { feedURL.absoluteString }

    /// Stable atlas id (wire `id`) — the curation-side identity, distinct
    /// from ``id``, which is the subscribe identity.
    public let atlasID: Int
    public let title: String
    public let author: String
    public let network: String?
    public let feedURL: URL
    public let homeURL: URL?
    public let artworkURL: URL?
    public let category: String?
    public let years: String?

    /// One editorial sentence on why this show is notable.
    public let why: String?

    /// 1–2 sentence show summary.
    public let summary: String?

    /// Theme slugs into ``ThemeArc``'s `slug` (i.e. `arcs[].showIds`
    /// membership in `themes.json`). Empty for the few shows in no curated
    /// arc — always decodes to `[]` when the wire `themes` key is absent.
    public let themes: [String]

    public init(
        atlasID: Int,
        title: String,
        author: String,
        network: String? = nil,
        feedURL: URL,
        homeURL: URL? = nil,
        artworkURL: URL? = nil,
        category: String? = nil,
        years: String? = nil,
        why: String? = nil,
        summary: String? = nil,
        themes: [String] = []
    ) {
        self.atlasID = atlasID
        self.title = title
        self.author = author
        self.network = network
        self.feedURL = feedURL
        self.homeURL = homeURL
        self.artworkURL = artworkURL
        self.category = category
        self.years = years
        self.why = why
        self.summary = summary
        self.themes = themes
    }

    private enum CodingKeys: String, CodingKey {
        case atlasID = "id"
        case title
        case author
        case network
        case feedURL = "feedUrl"
        case homeURL = "homeUrl"
        case artworkURL = "artworkUrl"
        case category
        case years
        case why
        case summary = "description"
        case themes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        atlasID = try container.decode(Int.self, forKey: .atlasID)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decode(String.self, forKey: .author)
        network = try container.decodeIfPresent(String.self, forKey: .network)
        feedURL = try container.decode(URL.self, forKey: .feedURL)
        homeURL = try container.decodeIfPresent(URL.self, forKey: .homeURL)
        artworkURL = try container.decodeIfPresent(URL.self, forKey: .artworkURL)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        years = try container.decodeIfPresent(String.self, forKey: .years)
        why = try container.decodeIfPresent(String.self, forKey: .why)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        themes = try container.decodeIfPresent([String].self, forKey: .themes) ?? []
    }

    /// Projects this catalog entry into a plain ``SearchResult`` — e.g. to
    /// reuse the same subscribe-persistence path Discover's search results
    /// and ``CuratedEntry`` use.
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

/// One curated theme-arc — taxonomy only; per-show membership lives in
/// ``CatalogEntry/themes``.
public struct ThemeArc: Sendable, Hashable, Identifiable, Codable {

    /// Stable identity — the slug is unique across the taxonomy.
    public var id: String { slug }

    public let slug: String
    public let name: String

    /// One-line definition of the theme.
    public let summary: String?

    /// Number of catalog shows in this theme.
    public let showCount: Int

    public init(
        slug: String,
        name: String,
        summary: String? = nil,
        showCount: Int
    ) {
        self.slug = slug
        self.name = name
        self.summary = summary
        self.showCount = showCount
    }

    private enum CodingKeys: String, CodingKey {
        case slug
        case name
        case summary = "description"
        case showCount
    }
}

// MARK: - Loader

/// Decodes the bundled catalog per the schema in
/// `curation/catalog/catalog.schema.md`:
/// - every valid entry renders, in file order;
/// - a malformed entry (missing a required key, or an unparseable URL) is
///   skipped, not fatal;
/// - a missing/empty/garbage file yields an empty array, never a crash.
public enum CatalogLoader {

    /// Decodes `data` into the catalog entries that should render, skipping
    /// any malformed element.
    ///
    /// - Parameter data: The raw bytes of `catalog.json` (or any data shaped
    ///   like it). Pass `Data()` (or the result of a failed bundle lookup)
    ///   for "missing file" — this returns `[]`, never throws.
    public static func loadEntries(from data: Data) -> [CatalogEntry] {
        guard !data.isEmpty else { return [] }
        guard let decoded = try? JSONDecoder().decode([FailableCatalogEntry].self, from: data) else {
            return []
        }
        return decoded.compactMap(\.entry)
    }

    /// Decodes `data` into the theme-arcs that should render, skipping any
    /// malformed element. Same missing/empty/garbage → `[]` contract as
    /// ``loadEntries(from:)``.
    public static func loadThemes(from data: Data) -> [ThemeArc] {
        guard !data.isEmpty else { return [] }
        guard let decoded = try? JSONDecoder().decode([FailableThemeArc].self, from: data) else {
            return []
        }
        return decoded.compactMap(\.arc)
    }

    /// Entries whose ``CatalogEntry/themes`` contains `slug`, in file order.
    public static func shows(inTheme slug: String, from entries: [CatalogEntry]) -> [CatalogEntry] {
        entries.filter { $0.themes.contains(slug) }
    }
}

/// Decodes one array element as a ``CatalogEntry``, swallowing any
/// per-element decoding failure (missing required key, unparseable URL,
/// wrong shape) instead of failing the whole array decode.
private struct FailableCatalogEntry: Decodable {
    let entry: CatalogEntry?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        entry = try? container.decode(CatalogEntry.self)
    }
}

/// Decodes one array element as a ``ThemeArc``, swallowing any per-element
/// decoding failure instead of failing the whole array decode.
private struct FailableThemeArc: Decodable {
    let arc: ThemeArc?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        arc = try? container.decode(ThemeArc.self)
    }
}
