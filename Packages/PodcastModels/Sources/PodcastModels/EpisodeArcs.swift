// EpisodeArcs — story-arc derivation from episode-title structure.
//
// This is the "A2r3.3" detector: a prefix-clustering + counter-token grammar
// chosen by an offline bake-off of 6 strategies over 315 real podcast feeds,
// scored against LLM-labeled ground truth. On the 50-feed gold set it reaches
// ~99.85% membership precision / 0.27% junk-arc rate / 62.7% arc recall, vs the
// previous exact-string detector's ~40% / 23% / 46%. Full method + evidence:
// curation/arc-bakeoff/ (RECOMMENDATION.md, recap.html); Python reference:
// curation/arc-bakeoff/approaches.py `a2r3_3_final`.
//
// Pipeline (all title-only + itunes:season, no LLM, cheap on-device):
//   1. clean the title (noise prefixes; strip trailing "| #id"; strip a trailing
//      bracket only when it holds no counter),
//   2. extract (stem, part, kind) via priority markers + general Part/Vol
//      (part = digits | canonical Roman | words one..twenty),
//   3. cluster by normalized stem → prefix-merge → split across itunes:season,
//   4. anthology guard (drop "Volume N≥3"), re-release dedup (drop
//      Encore/Redux/Archive when a non-re-release sibling covers that part),
//      scoped chaptered-season handler ("Chapter N | Title" / "S7 E1: Title" →
//      group by itunes:season, named from the season trailer when present),
//   5. keep clusters with ≥2 members.
//
// Pure/Foundation-only so it's unit-testable without SwiftData.
import Foundation

/// One derived narrative arc grouping episodes that belong to the same
/// serialized story within a single feed.
public struct Arc: Sendable, Hashable, Identifiable {
    /// Unique per arc. Title/prefix arcs use the bare `name`; chaptered-season
    /// cards suffix `#<season>` so they can never collide with a title arc's id.
    public var id: String

    /// The arc's display name (e.g. "Juan Ponce de León", "First Ladies").
    public var name: String

    /// The season the arc's episodes share, when the feed sets `itunes:season`
    /// uniformly across them. `nil` when absent or inconsistent.
    public var season: Int?

    /// The arc's member episodes, newest-first (callers pass newest-first).
    public var episodes: [Episode]

    public init(id: String, name: String, season: Int?, episodes: [Episode]) {
        self.id = id
        self.name = name
        self.season = season
        self.episodes = episodes
    }

    fileprivate init(titleArcName name: String, season: Int?, episodes: [Episode]) {
        self.init(id: name, name: name, season: season, episodes: episodes)
    }

    fileprivate init(seasonCardName name: String, season: Int, episodes: [Episode]) {
        self.init(id: "\(name)#\(season)", name: name, season: season, episodes: episodes)
    }
}

/// Derives story arcs from episode-title structure. See file header for the
/// method; `curation/arc-bakeoff/approaches.py` is the validated Python twin.
public enum ArcDerivation {

    // MARK: - Regex building blocks

    /// Hyphen + unicode dashes. **Always place FIRST in a character class** so the
    /// ASCII hyphen stays literal instead of forming a range (a real bug the
    /// bake-off caught: a mid-class hyphen turned `[.-‐]` into a range that ate
    /// letters, collapsing stems to one character).
    private static let dashes = "-‐‑‒–—"

    /// A part counter: Arabic, canonical Roman, or an English word `one`..`twenty`.
    private static let numWord =
        #"(?:\d+|[IVXLCDM]+|zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)"#

    private static func rx(_ pattern: String,
                           _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // swiftlint:disable:next force_try — patterns are fixed literals, verified at authoring time.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    /// Re-release / housekeeping prefixes stripped before matching (applied up to
    /// twice, to peel a stacked prefix like "Encore: Fan Favorite: …").
    private static let noisePrefix = rx(
        #"^(Encore|Fan Favorite|Fan-Favorite|Listen Now|New Season|Introducing|Presenting|Announcing|Update|Bonus|Replay|Revisited)\s*:?\s*"#,
        [.caseInsensitive])

    /// Trailing episode id `… | #457` (an id, not a part counter). Requires the
    /// `#` so it never eats a pipe part counter like AHT's `… | 5`.
    private static let trailingId = rx(#"\s*\|\s*#\d+\s*$"#)

    /// A trailing bracket `(…)` / `[…]`, end-anchored.
    private static let trailingBracket = rx(#"\s*[\[(][^\])]*[\])]\s*$"#)

    /// Does a bracket hold a counter? If so it's kept (`(Part 1)`), not stripped.
    private static let counterInBracket = rx(#"(part|pt|vol|volume|chapter|parte)\b|\d|[IVXLCDM]"#, [.caseInsensitive])

    /// Generic stems that never name a real arc.
    private static let genericStem = rx(#"^(season|episode|ep|part|chapter|vol(ume)?|series|book|no)\b"#, [.caseInsensitive])

    /// A re-release marker anywhere in a title (drives dedup).
    private static let rerelease = rx(
        #"\b(encore|archive|rebroadcast|redux|replay|revisited|throwback|fan[\s-]?favorite|from the vault|classic episode)\b"#,
        [.caseInsensitive])

    /// Strict canonical Roman numeral shape (1–3999); rejects "MILD", "IIII", "VX".
    private static let canonicalRoman = rx(
        #"^M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$"#, [.caseInsensitive])

    /// The counter kind a marker matched, so guards can act on how the number was
    /// expressed (a `Volume 22` is an anthology; a `Part 3` is an arc).
    private enum Kind { case pipe, part, parenStem, pt, hash, ep, chapter, chapterLead, volume }

    /// Priority-ordered markers. Group 1 is the arc stem; group 2 is the counter
    /// token — except `chapterLead` (`Chapter N: Title`), which carries no arc
    /// name in the title and is handled by the chaptered-season pass instead.
    private static let markers: [(NSRegularExpression, Kind)] = [
        (rx(#"^(.+?)\s*\|\s*.+?\s*\|\s*(\d+)\s*$"#), .pipe),
        (rx("^(.+?)\\s*[\(dashes)]\\s*Part\\s+(\(numWord))\\b", [.caseInsensitive]), .part),
        // Arc name inside a trailing parenthetical: "Turning the Lens (Seeing
        // White, Part 1)" (Scene on Radio). Must precede the comma/`, Part N`
        // marker below, which would otherwise take the unique main title as the
        // stem. End-anchored + requires ≥1 char before `Part`, so it never eats a
        // bare `(Part 1)` (handled by the `(Part N)` marker) or a plain `X, Part N`.
        (rx("^.+?\\(\\s*(.+?)\\s*,?\\s*Part\\s+(\(numWord))\\s*\\)\\s*$", [.caseInsensitive]), .parenStem),
        (rx("^(.+?),\\s*Part\\s+(\(numWord))\\b", [.caseInsensitive]), .part),
        (rx("^(.+?)\\s*[(\\[]\\s*Part\\s+(\(numWord))\\s*[)\\]]", [.caseInsensitive]), .part),
        (rx("^(.+?)\\s*,?\\s*\\(?\\s*Pt\\.?\\s+(\(numWord))\\b", [.caseInsensitive]), .pt),
        (rx(#"^(.+?)\s+#\s*(\d+)\b"#), .hash),
        (rx("^(.+?)\\s*[\(dashes)]\\s*Ep(?:isode|\\.)?\\s*(\\d+)\\b", [.caseInsensitive]), .ep),
        (rx("^(.+?)\\s*[\(dashes):]\\s*Chapter\\s+(\(numWord))\\b", [.caseInsensitive]), .chapter),
        (rx("^Chapter\\s+(?:\(numWord))\\s*[|:]\\s*(.+)$", [.caseInsensitive]), .chapterLead),
    ]

    /// General separator-agnostic `…Part/Parte N` (dashes lead the class).
    private static let generalPart = rx("^(.+?)[\(dashes)\\s:,.|]+Part[e]?\\s+(\(numWord))\\b", [.caseInsensitive])
    /// General `…Vol(ume) N`.
    private static let generalVol = rx("^(.+?)[\(dashes)\\s:,.|]*[(\\[]?\\s*Vol(?:ume)?\\.?\\s+(\(numWord))\\b", [.caseInsensitive])

    /// Leading start-anchored `Chapter N | Title` (Bone Valley) — used only to
    /// route an episode to the chaptered-season pass.
    private static let chapterLeadAnchored = rx(#"^Chapter\s*\d+\s*[|:]"#, [.caseInsensitive])

    /// Leading start-anchored season+episode marker `S7 E1: Title` (Scene on
    /// Radio). Like the chaptered lead, the arc name isn't in the title — the
    /// season is the arc — so it routes to the chaptered-season pass too.
    private static let seasonEpisodeLead = rx(#"^S\s*\d+\s*E\s*\d+\b"#, [.caseInsensitive])

    /// Season-theme extractors, tried in order against a season's trailer/intro
    /// title (Scene on Radio names each season only there). Group 1 is the theme.
    private static let seasonThemePatterns: [NSRegularExpression] = [
        rx(#"Season\s+\d+\s+Trailer\s*:\s*(.+)$"#, [.caseInsensitive]),      // "Season 7 Trailer: Capitalism"
        rx(#"Season\s+\d+\s*:\s*(.+?)\s+Trailer\s*$"#, [.caseInsensitive]),  // "…Season 3: MEN Trailer"
        rx(#"Introducing\b.*?:\s*(.+)$"#, [.caseInsensitive]),               // "Introducing Scene on Radio: The News"
    ]

    private static let wordNumbers: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19, "twenty": 20,
    ]

    /// A "Volume N" counter this high is an open-ended anthology, not a bounded arc.
    private static let volumeAnthologyMin = 3

    // MARK: - Title cleaning + extraction

    /// Strips noise prefixes, a trailing `| #id`, and a trailing counter-free bracket.
    private static func clean(_ title: String) -> String {
        var t = title.trimmed
        for _ in 0..<2 { t = stripLeading(noisePrefix, from: t) }
        t = removeMatch(trailingId, in: t)
        if let m = firstMatch(trailingBracket, in: t) {
            let matched = string(t, m, 0)
            if firstMatch(counterInBracket, in: matched) == nil,
               let r = Range(m.range, in: t) {
                t = String(t[..<r.lowerBound]).trimmed
            }
        }
        return t.trimmed
    }

    /// Parses a counter token: Arabic, English word `one`..`twenty`, or canonical Roman.
    private static func parsePart(_ token: String) -> Int? {
        let t = token.trimmed
        if let arabic = Int(t) { return arabic }
        if let word = wordNumbers[t.lowercased()] { return word }
        return romanToInt(t)
    }

    /// The arc stem, part number, and counter kind for a title — or `nil` for a
    /// non-arc single. Tries priority markers, then the general Part/Vol markers;
    /// rejects generic or too-short stems.
    private static func stemPartKind(_ title: String) -> (stem: String, part: Int, kind: Kind)? {
        let t = clean(title)
        for (regex, kind) in markers {
            guard let match = firstMatch(regex, in: t) else { continue }
            if kind == .chapterLead { return nil }
            let stem = string(t, match, 1).trimmingCharacters(in: stemTrim)
            guard let part = parsePart(string(t, match, 2)) else { continue }
            if isValidStem(stem) { return (stem, part, kind) }
        }
        for (regex, kind) in [(generalPart, Kind.part), (generalVol, Kind.volume)] {
            guard let match = firstMatch(regex, in: t) else { continue }
            let stem = string(t, match, 1).trimmingCharacters(in: stemTrim)
            guard let part = parsePart(string(t, match, 2)) else { continue }
            if isValidStem(stem) { return (stem, part, kind) }
        }
        return nil
    }

    private static let stemTrim = CharacterSet(charactersIn: " -‐‑‒–—|:,([#")

    private static func isValidStem(_ stem: String) -> Bool {
        !stem.isEmpty && normalize(stem).count >= 3 && firstMatch(genericStem, in: stem) == nil
    }

    // MARK: - Public API

    /// Derives `(arcName, displayTitle, part)` for one title — used for per-row
    /// arc labels. `arcName` is `nil` for a non-arc single; `displayTitle` is the
    /// episode's title within the arc (the pipe middle, a subtitle, or a bare
    /// "Part N"); `part` is the within-arc number.
    public static func derive(fromTitle title: String) -> (arcName: String?, displayTitle: String, part: Int?) {
        let cleaned = clean(title)
        guard let (stem, part, kind) = stemPartKind(title) else {
            return (nil, cleaned.isEmpty ? title.trimmed : cleaned, nil)
        }
        return (stem, displayTitle(cleaned: cleaned, stem: stem, part: part, kind: kind), part)
    }

    /// Groups `episodes` (newest-first) into arcs, ordered by the recency of each
    /// arc's newest episode. Episodes without a derivable arc are excluded.
    public static func groupIntoArcs(_ episodes: [Episode]) -> [Arc] {
        let ordered = newestFirst(episodes)
        let titleArcs = clusterGuarded(ordered)
        let taken = Set(titleArcs.flatMap(\.episodes).map(\.guid))
        let chapterCards = chapteredSeasonCards(ordered, taken: taken)
        return mergeByRecency(titleArcs, chapterCards)
    }

    // MARK: - Clustering

    /// Prefix-clustering with re-release dedup and the anthology guard.
    private static func clusterGuarded(_ episodes: [Episode]) -> [Arc] {
        var order: [String] = []
        var buckets: [String: [Episode]] = [:]
        var display: [String: String] = [:]
        var partOf: [String: Int] = [:]
        var kindOf: [String: Kind] = [:]
        var rerelOf: [String: Bool] = [:]

        for episode in episodes {
            guard let (stem, part, kind) = stemPartKind(episode.title) else { continue }
            let key = normalize(stem)
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
                display[key] = stem
            }
            buckets[key, default: []].append(episode)
            partOf[episode.guid] = part
            kindOf[episode.guid] = kind
            rerelOf[episode.guid] = firstMatch(rerelease, in: episode.title) != nil
        }

        // Prefix-merge: fold a longer stem into a shorter stem it begins with.
        var canonical: [String: String] = [:]
        for key in order {
            var target = key
            for other in order where other != key && key.hasPrefix(other + " ") && other.count < target.count {
                target = other
            }
            canonical[key] = target
        }
        var mergedOrder: [String] = []
        var merged: [String: [Episode]] = [:]
        for key in order {
            let target = canonical[key] ?? key
            if merged[target] == nil { merged[target] = []; mergedOrder.append(target) }
            merged[target, default: []].append(contentsOf: buckets[key] ?? [])
        }

        var arcs: [Arc] = []
        for key in mergedOrder {
            let members = merged[key] ?? []
            for group in splitBySeason(members) {
                let deduped = dedupeReReleases(group, partOf: partOf, rerelOf: rerelOf)
                guard deduped.count >= 2 else { continue }
                let parts = deduped.compactMap { partOf[$0.guid] }
                let kinds = Set(deduped.compactMap { kindOf[$0.guid] })
                if isAnthology(kind: kinds.count == 1 ? kinds.first : nil, parts: parts) { continue }
                let seasons = Set(deduped.compactMap(\.season))
                let season = seasons.count == 1 ? seasons.first : nil
                arcs.append(Arc(titleArcName: display[key] ?? key, season: season, episodes: deduped))
            }
        }
        return arcs
    }

    /// Splits a cluster across distinct non-nil `itunes:season` values (un-merges
    /// same-named arcs from different seasons); nil-season members ride with the
    /// largest group. One group when a cluster shares (at most) one season.
    private static func splitBySeason(_ members: [Episode]) -> [[Episode]] {
        var bySeason: [Int?: [Episode]] = [:]
        var seenOrder: [Int?] = []
        for e in members {
            if bySeason[e.season] == nil { seenOrder.append(e.season) }
            bySeason[e.season, default: []].append(e)
        }
        let nonNil = seenOrder.compactMap { $0 }
        guard nonNil.count >= 2 else { return [members] }
        var groups: [[Episode]] = nonNil.map { bySeason[$0] ?? [] }
        if let nilMembers = bySeason[Int?.none], !nilMembers.isEmpty,
           let biggest = groups.indices.max(by: { groups[$0].count < groups[$1].count }) {
            groups[biggest].append(contentsOf: nilMembers)
        }
        return groups
    }

    /// Drops a re-release-marked episode when a non-re-release sibling already
    /// covers that part number. Never drops a distinct (unmarked) episode.
    private static func dedupeReReleases(_ members: [Episode],
                                         partOf: [String: Int],
                                         rerelOf: [String: Bool]) -> [Episode] {
        let covered = Set(members.filter { !(rerelOf[$0.guid] ?? false) }.compactMap { partOf[$0.guid] })
        var seenRerelease: Set<Int> = []
        var drop: Set<String> = []
        for e in members where rerelOf[e.guid] ?? false {
            guard let part = partOf[e.guid] else { continue }
            if covered.contains(part) || seenRerelease.contains(part) { drop.insert(e.guid) }
            else { seenRerelease.insert(part) }
        }
        return drop.isEmpty ? members : members.filter { !drop.contains($0.guid) }
    }

    /// A cluster is an anthology (drop it) when its counter is a `Volume N` with
    /// N ≥ 3 — an open-ended anthology, not a bounded arc. Recall-safe: never
    /// fires on ordinary `Part N`, and never on large pipe/episode numbers (shows
    /// like Even the Rich number every real arc by episode number).
    private static func isAnthology(kind: Kind?, parts: [Int]) -> Bool {
        guard let low = parts.min() else { return false }
        return kind == .volume && low >= volumeAnthologyMin
    }

    /// Scoped chaptered-season pass: `Chapter N | Title` (Bone Valley) and `S7 E1:
    /// Title` (Scene on Radio) episodes carry no arc name in the title, so
    /// title-clustering misses them. Group those specific, not-yet-claimed episodes
    /// by `itunes:season`, naming each from the season's trailer/intro title when
    /// present (else "Season N"). Tightly scoped to those two leading shapes, so it
    /// adds none of a blanket season-fallback's junk.
    private static func chapteredSeasonCards(_ episodes: [Episode], taken: Set<String>) -> [Arc] {
        var order: [Int] = []
        var bySeason: [Int: [Episode]] = [:]
        var titlesBySeason: [Int: [String]] = [:]
        for e in episodes {
            guard let season = e.season else { continue }
            // Theme lives on the trailer, which is un-numbered — scan every
            // season member's raw title, not just the numbered episodes.
            titlesBySeason[season, default: []].append(e.title)
            guard !taken.contains(e.guid) else { continue }
            let cleaned = clean(e.title)
            guard firstMatch(chapterLeadAnchored, in: cleaned) != nil
                    || firstMatch(seasonEpisodeLead, in: cleaned) != nil else { continue }
            if bySeason[season] == nil { bySeason[season] = []; order.append(season) }
            bySeason[season, default: []].append(e)
        }
        return order.compactMap { season in
            guard let members = bySeason[season], members.count >= 2 else { return nil }
            let name = seasonTheme(in: titlesBySeason[season] ?? []) ?? "Season \(season)"
            return Arc(seasonCardName: name, season: season, episodes: members)
        }
    }

    /// The season's theme, pulled from its trailer/intro title (Scene on Radio
    /// names each season only there, never in the numbered episode titles). Uses
    /// the raw title — noise-prefix cleaning would strip "Introducing". `nil` when
    /// no trailer grammar matches, so callers fall back to a "Season N" label.
    private static func seasonTheme(in titles: [String]) -> String? {
        for title in titles {
            let t = title.trimmed
            for pattern in seasonThemePatterns {
                guard let match = firstMatch(pattern, in: t) else { continue }
                let theme = string(t, match, 1).trimmingCharacters(in: seasonThemeTrim)
                if !theme.isEmpty { return theme }
            }
        }
        return nil
    }

    private static let seasonThemeTrim = CharacterSet(charactersIn: " \"'“”").union(.whitespaces)

    // MARK: - Ordering

    private static func newestFirst(_ episodes: [Episode]) -> [Episode] {
        episodes.sorted { $0.publishDate > $1.publishDate }
    }

    private static func mergeByRecency(_ lhs: [Arc], _ rhs: [Arc]) -> [Arc] {
        (lhs + rhs).sorted { a, b in
            (a.episodes.first?.publishDate ?? .distantPast) > (b.episodes.first?.publishDate ?? .distantPast)
        }
    }

    // MARK: - Display title

    private static let pipeMiddle = rx(#"^(.+?)\s*\|\s*(.+?)\s*\|\s*\d+\s*$"#)
    private static let leadingCounter = rx(
        "^[\(dashes)\\s:,.|(\\[]*\\s*(?:Part|Pt\\.?|Parte|Ep(?:isode|\\.)?|Chapter|Vol(?:ume)?\\.?|#)?\\s*(?:\(numWord))\\s*[)\\]]?\\s*[\(dashes):|]*\\s*",
        [.caseInsensitive])

    /// The trailing `(Stem, Part N)` parenthetical of a `.parenStem` title — removed
    /// for display so the within-arc row shows the main title ("Turning the Lens").
    private static let trailingParenStem = rx("\\s*\\([^)]*\\bPart\\s+(?:\(numWord))\\s*\\)\\s*$", [.caseInsensitive])

    /// The episode's title within its arc: the pipe middle, else the subtitle left
    /// after removing the stem prefix and a leading counter, else a bare "Part N".
    private static func displayTitle(cleaned: String, stem: String, part: Int, kind: Kind) -> String {
        if kind == .pipe, let m = firstMatch(pipeMiddle, in: cleaned) {
            let middle = string(cleaned, m, 2).trimmed
            if !middle.isEmpty { return middle }
        }
        if kind == .parenStem {
            let main = removeMatch(trailingParenStem, in: cleaned).trimmed
            return main.isEmpty ? "Part \(part)" : main
        }
        var rest = cleaned
        if let r = rest.range(of: stem), r.lowerBound == rest.startIndex {
            rest = String(rest[r.upperBound...])
        }
        rest = stripLeading(leadingCounter, from: rest).trimmed
        return rest.isEmpty ? "Part \(part)" : rest
    }

    // MARK: - Part-number parsing

    private static func romanToInt(_ raw: String) -> Int? {
        let s = raw.uppercased()
        guard !s.isEmpty else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard canonicalRoman.firstMatch(in: s, range: range) != nil else { return nil }
        let values: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000]
        var total = 0, highest = 0
        for character in s.reversed() {
            guard let value = values[character] else { return nil }
            total += value < highest ? -value : value
            highest = max(highest, value)
        }
        return total
    }

    // MARK: - Normalization + regex helpers

    /// Lowercase, strip a leading article, collapse non-alphanumerics to single
    /// spaces — the clustering key (so "The X: A Tale" and "X A Tale" agree).
    private static func normalize(_ s: String) -> String {
        let folded = s.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        let noArticle = firstMatch(leadingArticle, in: folded).flatMap { Range($0.range, in: folded) }
            .map { String(folded[$0.upperBound...]) } ?? folded
        let collapsed = noArticle.unicodeScalars.map { articleAlnum.contains($0) ? Character($0) : " " }
        return String(collapsed).split(separator: " ").joined(separator: " ")
    }

    private static let leadingArticle = rx(#"^(the|a|an)\s+"#, [.caseInsensitive])
    private static let articleAlnum = CharacterSet.alphanumerics

    private static func stripLeading(_ regex: NSRegularExpression, from text: String) -> String {
        guard let match = firstMatch(regex, in: text), match.range.location == 0,
              let r = Range(match.range, in: text) else { return text }
        return String(text[r.upperBound...])
    }

    private static func removeMatch(_ regex: NSRegularExpression, in text: String) -> String {
        guard let match = firstMatch(regex, in: text), let r = Range(match.range, in: text) else { return text }
        return (String(text[..<r.lowerBound]) + String(text[r.upperBound...])).trimmed
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
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
