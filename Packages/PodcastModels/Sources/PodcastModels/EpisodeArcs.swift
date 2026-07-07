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

    /// `Chapter N | Title` / `Chapter N: Title` (Bone Valley). No arc name
    /// lives in the title here — these shows group by `itunes:season`
    /// instead (see `groupBySeason`), so this pattern only extracts the
    /// display title and part number.
    private static let chapterArcPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^Chapter\s*(\d+)\s*[|:]\s*(.+)$"#, options: [.caseInsensitive])
    }()

    /// Trailing `(Part N)` / `[Part N]` (Fall of Civilizations). Anchored at
    /// `$` so a mid-title `(Part N)` (e.g. inside a longer parenthetical)
    /// can't fire.
    private static let trailingParenPartArcPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^(.+?)\s*[(\[]\s*Part\s*(\d+)\s*[)\]]\s*$"#, options: [.caseInsensitive])
    }()

    /// Trailing `, Part N`.
    private static let trailingCommaPartArcPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^(.+?),\s*Part\s*(\d+)\s*$"#, options: [.caseInsensitive])
    }()

    /// Trailing `- Ep. N` / `- Ep N` / `- Episode N` (Serial).
    private static let trailingEpArcPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^(.+?)\s*-\s*Ep(?:isode|\.)?\s*(\d+)\s*$"#, options: [.caseInsensitive])
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

        if let match = firstMatch(chapterArcPattern, in: cleaned) {
            let part = Int(string(cleaned, match, 1).trimmed)
            let episodeTitle = string(cleaned, match, 2).trimmed
            return (nil, episodeTitle.isEmpty ? cleaned : episodeTitle, part)
        }

        if let match = firstMatch(trailingParenPartArcPattern, in: cleaned) {
            let arc = string(cleaned, match, 1).trimmed
            let part = Int(string(cleaned, match, 2).trimmed)
            let displayTitle = part.map { "Part \($0)" } ?? cleaned
            return (arc.isEmpty ? nil : arc, displayTitle, part)
        }

        if let match = firstMatch(trailingCommaPartArcPattern, in: cleaned) {
            let arc = string(cleaned, match, 1).trimmed
            let part = Int(string(cleaned, match, 2).trimmed)
            let displayTitle = part.map { "Part \($0)" } ?? cleaned
            return (arc.isEmpty ? nil : arc, displayTitle, part)
        }

        if let match = firstMatch(trailingEpArcPattern, in: cleaned) {
            let arc = string(cleaned, match, 1).trimmed
            let part = Int(string(cleaned, match, 2).trimmed)
            let displayTitle = part.map { "Ep. \($0)" } ?? cleaned
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
    ///
    /// **Precedence (ROADMAP E8-S6: "season data, or title patterns"):**
    /// title-derived arcs win whenever there are any. The `itunes:season`
    /// fallback below only runs when the title pass finds **zero** arcs for
    /// the whole show — this is all-or-nothing so a show with both signals
    /// (e.g. American History Tellers, which sets `itunes:season` per arc
    /// *and* has pipe-style titles) never gets junk "Season N" cards sitting
    /// next to its named arcs.
    public static func groupIntoArcs(_ episodes: [Episode]) -> [Arc] {
        let titleArcs = groupByTitle(episodes)
        guard titleArcs.isEmpty else { return titleArcs }
        return groupBySeason(episodes)
    }

    /// Groups episodes into arcs by title structure alone (see `derive(fromTitle:)`).
    private static func groupByTitle(_ episodes: [Episode]) -> [Arc] {
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

    /// Fallback grouping by `itunes:season`, used only when `groupByTitle`
    /// finds no arcs (see the precedence note on `groupIntoArcs`). Episodes
    /// without a season are excluded; groups need **2 or more** members
    /// (same "not a series yet" rule as the title pass); arcs are named
    /// `"Season N"` and ordered newest-season-first.
    private static func groupBySeason(_ episodes: [Episode]) -> [Arc] {
        var order: [Int] = []
        var membersBySeason: [Int: [Episode]] = [:]

        for episode in episodes {
            guard let season = episode.season else { continue }
            if membersBySeason[season] == nil {
                membersBySeason[season] = []
                order.append(season)
            }
            membersBySeason[season, default: []].append(episode)
        }

        return order
            .compactMap { season -> Arc? in
                guard let members = membersBySeason[season], members.count >= 2 else { return nil }
                return Arc(name: "Season \(season)", season: season, episodes: members)
            }
            .sorted { ($0.season ?? Int.min) > ($1.season ?? Int.min) }
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
