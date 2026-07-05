// Primary + fallback search orchestration. Source model: docs/design/direction.md §12
// (§12.3: try the primary source; on throw OR empty, fall through to the next
//  ENABLED source in order — results are NEVER merged). Settings owns ordering
//  and enablement via this coordinator.
import Foundation
import Observation

/// Orchestrates podcast search across an ordered list of ``DirectorySource``s
/// using the primary + fallback model of §12.3.
///
/// The first eligible (enabled) source is the *primary*. ``search(term:)`` tries
/// it first; if it throws **or** returns an empty result set, the coordinator
/// falls through to the next enabled source in order. Results are never merged —
/// the first source to return a non-empty set wins.
///
/// The coordinator also owns the ordering and per-source enablement that the
/// Settings "Sources" checklist edits (`setPrimary`, `move`, `setEnabled`).
///
/// Enablement is tracked here (seeded from each source's intrinsic
/// ``DirectorySource/isEnabled``) so the user's toggle survives independently of
/// a source's own readiness — a source that is user-enabled but not yet
/// configured (e.g. PodcastIndex with no key) simply throws ``SearchError/noKey``
/// and the chain falls through, per §12.3.
@Observable
@MainActor
public final class SearchCoordinator {

    /// The search sources in priority order (primary first).
    ///
    /// Editing this drives the Settings checklist ordering. Use ``setPrimary(_:)``
    /// and ``move(fromOffsets:toOffset:)`` to mutate it so enablement stays in
    /// sync.
    public private(set) var orderedSources: [any DirectorySource]

    /// User-facing enable/disable state keyed by ``SourceKind``.
    ///
    /// Seeded from each source's intrinsic ``DirectorySource/isEnabled`` at
    /// construction; the Settings toggle overrides it thereafter.
    private var enabledStates: [SourceKind: Bool]

    /// Creates a coordinator over the given sources in priority order.
    ///
    /// - Parameter sources: The ordered sources, primary first. Defaults to a
    ///   single keyless ``ITunesSource`` (Apple), matching §12.1.
    public init(sources: [any DirectorySource] = [ITunesSource()]) {
        self.orderedSources = sources
        var states: [SourceKind: Bool] = [:]
        for source in sources {
            states[source.kind] = source.isEnabled
        }
        self.enabledStates = states
    }

    // MARK: - Search

    /// Searches the enabled sources in priority order, returning the first
    /// non-empty result set (§12.3).
    ///
    /// Each enabled source is tried in order. A source that throws or returns an
    /// empty set is skipped and the next enabled source is tried. Results are
    /// never merged across sources.
    ///
    /// - Parameter term: The user's raw search query.
    /// - Returns: The first non-empty result set, or `[]` if every enabled source
    ///   returned empty without error.
    /// - Throws: The last ``SearchError`` encountered if *every* enabled source
    ///   threw (and none returned results).
    public func search(term: String) async throws -> [SearchResult] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var lastError: Error?
        for source in orderedSources where isEnabled(source.kind) {
            do {
                let results = try await source.search(term: trimmed)
                if !results.isEmpty {
                    return results
                }
                // Empty result set: fall through to the next enabled source.
            } catch {
                lastError = error
                // Failure: fall through to the next enabled source.
            }
        }

        if let lastError {
            throw lastError
        }
        return []
    }

    // MARK: - Enablement

    /// Whether the source for `kind` is currently enabled.
    ///
    /// Returns `false` for a kind the coordinator does not manage.
    public func isEnabled(_ kind: SourceKind) -> Bool {
        enabledStates[kind] ?? false
    }

    /// Enables or disables the source for `kind`.
    ///
    /// No-op when the coordinator holds no source of that kind.
    public func setEnabled(_ enabled: Bool, for kind: SourceKind) {
        guard enabledStates[kind] != nil else { return }
        enabledStates[kind] = enabled
    }

    /// Flips the enabled state of the source for `kind`.
    public func toggleEnabled(_ kind: SourceKind) {
        setEnabled(!isEnabled(kind), for: kind)
    }

    /// The current primary source: the first enabled source in priority order,
    /// or `nil` when no source is enabled.
    public var primarySource: (any DirectorySource)? {
        orderedSources.first { isEnabled($0.kind) }
    }

    // MARK: - Ordering

    /// Promotes the source for `kind` to the front of the priority order,
    /// making it the primary.
    ///
    /// No-op when the coordinator holds no source of that kind.
    public func setPrimary(_ kind: SourceKind) {
        guard let index = orderedSources.firstIndex(where: { $0.kind == kind }) else { return }
        let source = orderedSources.remove(at: index)
        orderedSources.insert(source, at: 0)
    }

    /// Reorders the sources, mirroring SwiftUI `List` `onMove` semantics.
    ///
    /// - Parameters:
    ///   - source: The offsets to move.
    ///   - destination: The insertion offset.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        orderedSources.move(fromOffsets: source, toOffset: destination)
    }

    /// Replaces the priority order with `kinds`.
    ///
    /// Kinds not currently held are ignored; held kinds omitted from `kinds` are
    /// appended in their existing relative order so no source is dropped.
    public func reorder(to kinds: [SourceKind]) {
        var remaining = orderedSources
        var reordered: [any DirectorySource] = []
        for kind in kinds {
            if let index = remaining.firstIndex(where: { $0.kind == kind }) {
                reordered.append(remaining.remove(at: index))
            }
        }
        reordered.append(contentsOf: remaining)
        orderedSources = reordered
    }
}
