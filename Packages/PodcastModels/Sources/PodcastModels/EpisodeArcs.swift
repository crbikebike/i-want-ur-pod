// EpisodeArcs — story-arc derivation from episode-title structure. Ported
// from scripts/fetch-podcast-episodes.py's `derive_arc` (the design kit's
// "get it from somewhere" heuristic for the Story Arcs shelf — see
// docs/design/direction.md §11's "Podcast Detail screen — real data + story
// arcs" entry). Pure/Foundation-only so it's unit-testable without SwiftData.
import Foundation

/// One derived narrative arc grouping episodes that share a title structure
/// (`Arc | Title | N` or `Arc - Part N - Subtitle`).
public struct Arc: Sendable, Hashable, Identifiable {
    public var id: String { name }

    /// The arc's display name (e.g. "American Revolution", "Heinrich Barth").
    public var name: String

    /// The season the arc's episodes share, when the feed sets `itunes:season`
    /// uniformly across them. `nil` when absent or inconsistent.
    public var season: Int?

    /// The arc's member episodes, in the same order they were passed in
    /// (callers pass newest-first, so this stays newest-first too).
    public var episodes: [Episode]
}

/// Derives story arcs from episode-title structure (`docs/design/direction.md`
/// §11; python reference: `scripts/fetch-podcast-episodes.py`'s `derive_arc`).
public enum ArcDerivation {

    /// Re-release / housekeeping prefixes that pollute an arc name. Mirrors
    /// the python `NOISE_PREFIX` regex exactly (case-insensitive, optional
    /// trailing colon).
    private static let noisePrefix: NSRegularExpression = {
        // swiftlint:disable:next force_try — pattern is a fixed literal, verified at authoring time.
        try! NSRegularExpression(
            pattern: #"^(Encore|Fan Favorite|Listen Now|New Season|Introducing|Presenting)\s*:?\s*"#,
            options: [.caseInsensitive]
        )
    }()

    /// `Arc | Episode Title | N` (art19 / American History Tellers).
    private static let pipeArcPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^(.+?)\s*\|\s*(.+?)\s*\|\s*(\d+)\s*$"#)
    }()

    /// `Arc - Part N - Subtitle` (The Explorers Podcast). Subtitle is optional.
    private static let partArcPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^(.+?)\s*-\s*Part\s*(\d+)\s*(?:-\s*(.*))?$"#, options: [.caseInsensitive])
    }()

    /// Derives `(arcName, displayTitle, part)` from a raw episode title.
    ///
    /// - Returns: `arcName` is `nil` for a "single" (no arc structure
    ///   detected); `displayTitle` is always populated (the arc-stripped
    ///   title, suitable for a row that shows the arc name separately);
    ///   `part` is the parsed part/episode-within-arc number, when present.
    public static func derive(fromTitle title: String) -> (arcName: String?, displayTitle: String, part: Int?) {
        let cleaned = stripNoisePrefix(title)

        if let match = firstMatch(pipeArcPattern, in: cleaned) {
            let arc = string(cleaned, match, 1).trimmed
            let episodeTitle = string(cleaned, match, 2).trimmed
            let part = Int(string(cleaned, match, 3).trimmed)
            return (arc.isEmpty ? nil : arc, episodeTitle.isEmpty ? cleaned : episodeTitle, part)
        }

        if let match = firstMatch(partArcPattern, in: cleaned) {
            let arc = string(cleaned, match, 1).trimmed
            let part = Int(string(cleaned, match, 2).trimmed)
            let subtitle = match.range(at: 3).location != NSNotFound ? string(cleaned, match, 3).trimmed : ""
            let displayTitle: String
            if !subtitle.isEmpty {
                displayTitle = subtitle
            } else if let part {
                // No subtitle to show — fall back to a bare "Part N" rather
                // than repeating the arc name (already shown separately in
                // the row's meta line / arc chip).
                displayTitle = "Part \(part)"
            } else {
                displayTitle = cleaned
            }
            return (arc.isEmpty ? nil : arc, displayTitle, part)
        }

        return (nil, cleaned, nil)
    }

    /// Groups `episodes` (expected newest-first) into arcs, ordered by the
    /// recency of each arc's newest episode. Episodes without a derivable arc
    /// are excluded — they render as singles in the episode list, not as a
    /// shelf card.
    ///
    /// Only arcs with **2 or more** episodes are surfaced: a lone "Part 1"
    /// isn't a series yet (matches `design/kit/data/american-history-tellers.json`'s
    /// `arcs` array, whose entries are already multi-part story groupings —
    /// there is no such thing as a 1-episode "arc" in that data).
    public static func groupIntoArcs(_ episodes: [Episode]) -> [Arc] {
        var order: [String] = []
        var membersByName: [String: [Episode]] = [:]

        for episode in episodes {
            let (arcName, _, _) = derive(fromTitle: episode.title)
            guard let arcName else { continue }
            if membersByName[arcName] == nil {
                membersByName[arcName] = []
                order.append(arcName)
            }
            membersByName[arcName, default: []].append(episode)
        }

        return order.compactMap { name -> Arc? in
            guard let members = membersByName[name], members.count >= 2 else { return nil }
            let seasons = Set(members.compactMap(\.season))
            let season = seasons.count == 1 ? seasons.first : nil
            return Arc(name: name, season: season, episodes: members)
        }
        // `order` was built in encounter order over a newest-first input, so
        // the first episode seen for an arc is its newest — `order` is
        // already sorted by arc recency. No further sort needed.
    }

    // MARK: - Helpers

    private static func stripNoisePrefix(_ title: String) -> String {
        let range = NSRange(title.startIndex..., in: title)
        guard let match = noisePrefix.firstMatch(in: title, range: range) else {
            return title.trimmed
        }
        guard let swiftRange = Range(match.range, in: title) else { return title.trimmed }
        return String(title[swiftRange.upperBound...]).trimmed
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range)
    }

    private static func string(_ text: String, _ match: NSTextCheckingResult, _ groupIndex: Int) -> String {
        let nsRange = match.range(at: groupIndex)
        guard nsRange.location != NSNotFound, let range = Range(nsRange, in: text) else { return "" }
        return String(text[range])
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
