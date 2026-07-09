// EpisodeArcs — story-arc derivation from episode-title structure. Ported
// from scripts/fetch-podcast-episodes.py's `derive_arc` (the design kit's
// "get it from somewhere" heuristic for the Story Arcs shelf — see
// docs/design/direction.md §11's "Podcast Detail screen — real data + story
// arcs" entry). Pure/Foundation-only so it's unit-testable without SwiftData.
import Foundation

/// One derived narrative arc grouping episodes that share a title structure
/// (`Arc | Title | N` or `Arc - Part N - Subtitle`).
public struct Arc: Sendable, Hashable, Identifiable {
    /// Unique per arc even when a title arc and a season-fallback card land on
    /// the same `name` (theoretically possible — e.g. a title arc called
    /// "Season 4" colliding with a literal `Season 4` fallback card). Title
    /// arcs use a bare `name`; season-fallback cards suffix `#<season>` so
    /// they can never collide with a title arc's id.
    public var id: String

    /// The arc's display name (e.g. "American Revolution", "Heinrich Barth").
    public var name: String

    /// The season the arc's episodes share, when the feed sets `itunes:season`
    /// uniformly across them. `nil` when absent or inconsistent.
    public var season: Int?

    /// The arc's member episodes, in the same order they were passed in
    /// (callers pass newest-first, so this stays newest-first too).
    public var episodes: [Episode]

    public init(id: String, name: String, season: Int?, episodes: [Episode]) {
        self.id = id
        self.name = name
        self.season = season
        self.episodes = episodes
    }

    /// Convenience for title arcs, whose `id` is just the (unique-by-construction) name.
    fileprivate init(titleArcName name: String, season: Int?, episodes: [Episode]) {
        self.init(id: name, name: name, season: season, episodes: episodes)
    }

    /// Convenience for season-fallback cards, whose `id` is suffixed with the
    /// season to guarantee no collision with a title arc's id.
    fileprivate init(seasonCardName name: String, season: Int, episodes: [Episode]) {
        self.init(id: "\(name)#\(season)", name: name, season: season, episodes: episodes)
    }
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
    /// The part number is Arabic **or** Roman (`Part I`, `Part IV`) — Bone
    /// Valley's "Kevin is Next" bonus mixes the two styles across its parts, so
    /// both must parse to the same `Int` (via `parsePart`) for the pair to form
    /// one arc and render consistently. A Roman-looking token that isn't a
    /// canonical numeral is rejected by `parsePart` and the match falls
    /// through (see `derive`).
    private static let partArcPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^(.+?)\s*-\s*Part\s*(\d+|[IVXLCDM]+)\s*(?:-\s*(.*))?$"#, options: [.caseInsensitive])
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

    /// Trailing `- Chapter N` (Serial's serialized-book seasons, e.g. "The
    /// Idiot - Chapter 1"). End-anchored so it can't fire on the pre-existing
    /// start-anchored `chapterArcPattern` (`^Chapter N | Title` — Bone
    /// Valley), which is checked first and extracts no arc name; this one
    /// does extract an arc name, since here it's the part before "Chapter"
    /// that names the arc.
    private static let trailingChapterArcPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^(.+?)\s*-\s*Chapter\s*(\d+)\s*$"#, options: [.caseInsensitive])
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

        // Only treat this as a "Part N" arc when the captured token is a real
        // number (Arabic or canonical Roman). A Roman-letter token that isn't
        // a valid numeral (e.g. "MILD") fails `parsePart`, so the whole `if`
        // is false and we fall through to the patterns below.
        if let match = firstMatch(partArcPattern, in: cleaned),
           let part = parsePart(string(cleaned, match, 2).trimmed) {
            let arc = string(cleaned, match, 1).trimmed
            let subtitle = match.range(at: 3).location != NSNotFound ? string(cleaned, match, 3).trimmed : ""
            // No subtitle to show — fall back to a bare "Part N" (Arabic,
            // so a Roman "Part I" normalizes to "Part 1" and matches an
            // Arabic sibling) rather than repeating the arc name (already
            // shown separately in the row's meta line / arc chip).
            let displayTitle = subtitle.isEmpty ? "Part \(part)" : subtitle
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

        if let match = firstMatch(trailingChapterArcPattern, in: cleaned) {
            let arc = string(cleaned, match, 1).trimmed
            let part = Int(string(cleaned, match, 2).trimmed)
            let displayTitle = part.map { "Chapter \($0)" } ?? cleaned
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
    /// **Precedence (ROADMAP E8-S6: "season data, or title patterns"),
    /// per-season since 2026-07-07:** title-derived arcs (`groupByTitle`) win
    /// unconditionally — their membership, names, and order are untouched by
    /// what follows. The `itunes:season` fallback then runs **per season**,
    /// not all-or-nothing for the whole show: a season is only eligible for
    /// a fallback card when **none** of its episodes already belong to a
    /// title arc. This fixes teaser feeds like Serial, where most seasons
    /// carry one full episode + a trailer (never reaching the title pass's
    /// 2-episode threshold) alongside a few seasons that *do* form title
    /// arcs — under the old all-or-nothing rule, the one title arc that
    /// existed suppressed the season fallback for every other season,
    /// collapsing the whole show to a single arc. It still protects shows
    /// like American History Tellers (which sets `itunes:season` per arc
    /// *and* has pipe-style titles, plus ~2-3 cross-promo episodes per
    /// season that aren't part of the arc): because AHT's arc-bearing
    /// seasons always have a title-arc member, they're ineligible for a
    /// fallback card, so the cross-promo leftovers stay singles rather than
    /// forming junk "Season N" cards. See `groupBySeason` for the per-season
    /// eligibility and naming rules, and `mergeByRecency` for how the two
    /// arc lists are combined into one shelf ordering.
    public static func groupIntoArcs(_ episodes: [Episode]) -> [Arc] {
        let titleArcs = groupByTitle(episodes)
        let titleArcMemberGUIDs = Set(titleArcs.flatMap(\.episodes).map(\.guid))
        let seasonCards = groupBySeason(episodes, arcMemberGUIDs: titleArcMemberGUIDs)
        return mergeByRecency(titleArcs, seasonCards)
    }

    /// Merges two newest-first-ordered arc lists into one, ordered by the
    /// recency of each arc's newest episode. Both `groupByTitle` and
    /// `groupBySeason` build their members by iterating a newest-first
    /// input, so `episodes.first` is always an arc's newest episode.
    private static func mergeByRecency(_ lhs: [Arc], _ rhs: [Arc]) -> [Arc] {
        (lhs + rhs).sorted { arcA, arcB in
            let dateA = arcA.episodes.first?.publishDate ?? .distantPast
            let dateB = arcB.episodes.first?.publishDate ?? .distantPast
            return dateA > dateB
        }
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
            return Arc(titleArcName: name, season: season, episodes: members)
        }
        // `order` was built in encounter order over a newest-first input, so
        // the first episode seen for an arc is its newest — `order` is
        // already sorted by arc recency. No further sort needed.
    }

    /// Fallback grouping by `itunes:season`, per-season since 2026-07-07 and
    /// **dominance-based since 2026-07-08** (see the precedence note on
    /// `groupIntoArcs`). For each season, its episodes that already belong to a
    /// title arc are counted (`arcMemberGUIDs`):
    ///
    /// - When those title-arc members cover **at least half** the season, the
    ///   season is considered fully represented by its arc(s) and gets **no**
    ///   fallback card. This protects AHT/Serial arc-seasons (the arc dominates)
    ///   from sprouting a redundant "Season N" card next to the real arc, and
    ///   keeps their cross-promo/trailer leftovers as singles.
    /// - Otherwise the title arc is only a **minority bonus** within a season
    ///   that has its own larger run (e.g. Bone Valley S2: a 2-part "Kevin is
    ///   Next" bonus alongside six chapters). The season still earns a card,
    ///   built from its **non-arc leftovers only** — the arc episodes live in
    ///   their own arc and are not double-listed here.
    ///
    /// Episodes without a season are always excluded. A card needs **2 or more**
    /// leftover members (same "not a series yet" rule as the title pass).
    ///
    /// Naming: a season card is named after the **most frequent non-nil
    /// `arcName`** that `derive(fromTitle:)` extracts from its members, but only
    /// when that name covers **at least half** of them (see `seasonCardName`) —
    /// this recovers a real series name (e.g. Serial's "The Preventionist", one
    /// full episode + a trailer) without letting a lone minority episode hijack
    /// the label. Otherwise it falls back to the generic `"Season N"`.
    private static func groupBySeason(_ episodes: [Episode], arcMemberGUIDs: Set<String>) -> [Arc] {
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
                guard let members = membersBySeason[season] else { return nil }
                let arcMemberCount = members.lazy.filter { arcMemberGUIDs.contains($0.guid) }.count
                // Arc(s) cover at least half the season → fully represented, no card.
                guard arcMemberCount * 2 < members.count else { return nil }
                // Minority bonus arc(s): card from the non-arc leftovers only.
                let leftovers = members.filter { !arcMemberGUIDs.contains($0.guid) }
                guard leftovers.count >= 2 else { return nil }
                return Arc(seasonCardName: seasonCardName(for: leftovers, season: season), season: season, episodes: leftovers)
            }
            .sorted { ($0.season ?? Int.min) > ($1.season ?? Int.min) }
    }

    /// The most frequent non-nil `arcName` `derive(fromTitle:)` extracts
    /// across `members` — but only when it represents the card, i.e. it covers
    /// **at least half** of them. `"Season N"` on a tie, when no member derives
    /// a name, or when the top name is only a minority (so a single bonus
    /// episode can't hijack a whole season card's label).
    private static func seasonCardName(for members: [Episode], season: Int) -> String {
        var counts: [String: Int] = [:]
        for member in members {
            let (arcName, _, _) = derive(fromTitle: member.title)
            guard let arcName else { continue }
            counts[arcName, default: 0] += 1
        }
        let maxCount = counts.values.max() ?? 0
        let topNames = counts.filter { $0.value == maxCount }.keys
        guard maxCount > 0, topNames.count == 1, maxCount * 2 >= members.count, let winner = topNames.first else {
            return "Season \(season)"
        }
        return winner
    }

    // MARK: - Part-number parsing

    /// Strict, canonical Roman-numeral shape (1–3999). Anchored so partial /
    /// malformed sequences (e.g. "MILD", "IIII", "VX") are rejected — only
    /// well-formed numerals count as a part number.
    private static let canonicalRoman: NSRegularExpression = {
        // swiftlint:disable:next force_try — fixed literal, verified at authoring time.
        try! NSRegularExpression(
            pattern: #"^M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$"#,
            options: [.caseInsensitive]
        )
    }()

    /// Parses a part token captured by `partArcPattern` as Arabic (`4`) or a
    /// canonical Roman numeral (`IV` → 4). Returns `nil` for anything else so
    /// the caller can fall through rather than invent a spurious arc.
    private static func parsePart(_ token: String) -> Int? {
        if let arabic = Int(token) { return arabic }
        return romanToInt(token)
    }

    /// Converts a canonical Roman numeral to its value; `nil` if `raw` isn't a
    /// well-formed numeral. The `canonicalRoman` gate runs first, so the
    /// value-accumulation loop only ever sees the seven Roman letters.
    private static func romanToInt(_ raw: String) -> Int? {
        let s = raw.uppercased()
        guard !s.isEmpty else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard canonicalRoman.firstMatch(in: s, range: range) != nil else { return nil }
        let values: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000]
        var total = 0
        var highestSeen = 0
        for character in s.reversed() {
            guard let value = values[character] else { return nil }
            total += value < highestSeen ? -value : value
            highestSeen = max(highestSeen, value)
        }
        return total
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
