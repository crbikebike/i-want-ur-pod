// Offline fixture source. Decodes fixtures/sample-podcasts.json into
// [SearchResult]. Source model: docs/design/direction.md §12.1 (identifies as
// the Apple/keyless source so previews + tests exercise the primary path
// without network). Field keys mirror SearchResult / the fixture JSON.
import Foundation

/// A network-free ``DirectorySource`` that serves results from a JSON fixture.
///
/// Backed by `fixtures/sample-podcasts.json` (or any equivalent payload), this
/// source lets SwiftUI previews and unit tests exercise the search UI and
/// coordinator without touching the network. It reports ``SourceKind/apple`` so
/// it can stand in for the primary source of §12.
public struct FixtureSource: DirectorySource {

    public let kind: SourceKind = .apple

    /// Fixtures are always eligible; there is no credential to gate on.
    public let isEnabled: Bool

    /// The decoded fixture entries, filtered per ``search(term:)``.
    private let results: [SearchResult]

    // MARK: - Init

    /// Creates a source from raw JSON `Data`.
    ///
    /// - Parameters:
    ///   - data: JSON matching the fixture shape — an array of objects keyed by
    ///     `title`, `author`, `feedUrl`, `homeUrl`, `artworkUrl`, `category`.
    ///   - isEnabled: Whether the source reports as enabled (default `true`).
    /// - Throws: ``SearchError/decoding`` if `data` cannot be decoded into
    ///   ``SearchResult`` values.
    public init(data: Data, isEnabled: Bool = true) throws {
        do {
            self.results = try JSONDecoder().decode([SearchResult].self, from: data)
        } catch {
            throw SearchError.decoding
        }
        self.isEnabled = isEnabled
    }

    /// Creates a source by loading JSON from a file / bundle URL.
    ///
    /// - Parameters:
    ///   - url: A file URL to a fixture JSON payload (e.g.
    ///     `Bundle.module.url(forResource:withExtension:)`).
    ///   - isEnabled: Whether the source reports as enabled (default `true`).
    /// - Throws: ``SearchError/unavailable`` if the file cannot be read, or
    ///   ``SearchError/decoding`` if its contents cannot be decoded.
    public init(contentsOf url: URL, isEnabled: Bool = true) throws {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SearchError.unavailable
        }
        try self.init(data: data, isEnabled: isEnabled)
    }

    /// Creates a source directly from already-decoded results.
    ///
    /// Useful for tests that want to hand-build a fixture in code.
    public init(results: [SearchResult], isEnabled: Bool = true) {
        self.results = results
        self.isEnabled = isEnabled
    }

    // MARK: - DirectorySource

    /// Returns fixture entries whose title, author, or category contain `term`
    /// (case- and diacritic-insensitive). An empty query yields no results.
    public func search(term: String) async throws -> [SearchResult] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return results.filter { result in
            result.title.localizedCaseInsensitiveContains(trimmed)
                || result.author.localizedCaseInsensitiveContains(trimmed)
                || (result.category?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }
}
