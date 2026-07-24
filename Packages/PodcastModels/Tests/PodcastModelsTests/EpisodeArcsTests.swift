// Tests for EpisodeArcs — the "A2r3.3" story-arc detector (prefix-clustering +
// counter-token grammar + re-release dedup + scoped chaptered-season handler).
// Cases are drawn from the real corpus the bake-off validated against; the
// Python twin is curation/arc-bakeoff/approaches.py `a2r3_3_final`.
import XCTest
@testable import PodcastModels

final class EpisodeArcsTests: XCTestCase {

    // MARK: - derive(fromTitle:)

    func test_derive_pipeStyle_AHT() {
        let r = ArcDerivation.derive(fromTitle: "American Revolution | A Devil of a Whipping | 5")
        XCTAssertEqual(r.arcName, "American Revolution")
        XCTAssertEqual(r.displayTitle, "A Devil of a Whipping")
        XCTAssertEqual(r.part, 5)
    }

    func test_derive_partStyle_withSubtitle_Explorers() {
        let r = ArcDerivation.derive(fromTitle: "Magellan - Part 4 - The Strait")
        XCTAssertEqual(r.arcName, "Magellan")
        XCTAssertEqual(r.displayTitle, "The Strait")
        XCTAssertEqual(r.part, 4)
    }

    func test_derive_partStyle_withoutSubtitle_fallsBackToPartLabel() {
        let r = ArcDerivation.derive(fromTitle: "Magellan - Part 4")
        XCTAssertEqual(r.arcName, "Magellan")
        XCTAssertEqual(r.displayTitle, "Part 4")
        XCTAssertEqual(r.part, 4)
    }

    func test_derive_romanNumeral_parsesLikeArabic() {
        let r = ArcDerivation.derive(fromTitle: "Kevin is Next - Part I")
        XCTAssertEqual(r.arcName, "Kevin is Next")
        XCTAssertEqual(r.part, 1)
    }

    func test_derive_nonCanonicalRomanToken_isNotAnArc() {
        // "MILD" is Roman-letters but not a canonical numeral — rejected.
        let r = ArcDerivation.derive(fromTitle: "Sound Lab - Part MILD")
        XCTAssertNil(r.arcName)
        XCTAssertEqual(r.displayTitle, "Sound Lab - Part MILD")
        XCTAssertNil(r.part)
    }

    func test_derive_wordNumberPart() {
        // The Constant: "…, Part One".
        let r = ArcDerivation.derive(fromTitle: "The Valley of Death, Part One")
        XCTAssertEqual(r.arcName, "The Valley of Death")
        XCTAssertEqual(r.part, 1)
    }

    func test_derive_hashCounter_99pi() {
        let r = ArcDerivation.derive(fromTitle: "100 Objects #1: The Century Safe")
        XCTAssertEqual(r.arcName, "100 Objects")
        XCTAssertEqual(r.displayTitle, "The Century Safe")
        XCTAssertEqual(r.part, 1)
    }

    func test_derive_colonSeparatedPart_stripsTrailingEpisodeId() {
        // redhanded: "<arc> Part Two: <subtitle> | #407" — the "| #407" id is stripped.
        let r = ArcDerivation.derive(fromTitle: "JFK Part Two: Deniably Plausible | #407")
        XCTAssertEqual(r.arcName, "JFK")
        XCTAssertEqual(r.displayTitle, "Deniably Plausible")
        XCTAssertEqual(r.part, 2)
    }

    func test_derive_parentheticalPartKept_notEatenAsBracket() {
        let r = ArcDerivation.derive(fromTitle: "The Earliest Englishman (Part 1)")
        XCTAssertEqual(r.arcName, "The Earliest Englishman")
        XCTAssertEqual(r.part, 1)
    }

    func test_derive_parentheticalStem_extractsInnerStemAndMainTitle() {
        // Scene on Radio: arc name lives inside a trailing "(Stem, Part N)".
        let r = ArcDerivation.derive(fromTitle: "Turning the Lens (Seeing White, Part 1)")
        XCTAssertEqual(r.arcName, "Seeing White")
        XCTAssertEqual(r.displayTitle, "Turning the Lens")
        XCTAssertEqual(r.part, 1)
    }

    func test_derive_parentheticalStem_noCommaVariant() {
        let r = ArcDerivation.derive(fromTitle: "A Racial Cleansing in America (Seeing White Part 9)")
        XCTAssertEqual(r.arcName, "Seeing White")
        XCTAssertEqual(r.displayTitle, "A Racial Cleansing in America")
        XCTAssertEqual(r.part, 9)
    }

    func test_derive_tooShortStem_isNotAnArc() {
        // A 1–2 char stem is rejected (avoids junk arcs from initials/numbers).
        let r = ArcDerivation.derive(fromTitle: "X | Y | 2")
        XCTAssertNil(r.arcName)
    }

    func test_derive_plainTitle_hasNoArc() {
        let r = ArcDerivation.derive(fromTitle: "Just a Normal Episode")
        XCTAssertNil(r.arcName)
        XCTAssertEqual(r.displayTitle, "Just a Normal Episode")
        XCTAssertNil(r.part)
    }

    // MARK: - groupIntoArcs — grouping + ordering

    private func makeEpisode(title: String, publishDate: Date, season: Int? = nil) -> Episode {
        Episode(
            guid: title,
            title: title,
            publishDate: publishDate,
            audioURL: URL(string: "https://cdn.example.com/\(abs(title.hashValue)).mp3")!,
            season: season
        )
    }

    private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

    func test_groupIntoArcs_pipeArcs_membershipOrderingAndSeason() {
        let episodes = [
            makeEpisode(title: "American Revolution | A Devil of a Whipping | 5", publishDate: date(5000), season: 97),
            makeEpisode(title: "American Revolution | Saratoga | 4", publishDate: date(4000), season: 97),
            makeEpisode(title: "Foul Play", publishDate: date(3500)),
            makeEpisode(title: "Edison vs. Tesla | Prometheus' Fire | 1", publishDate: date(3000), season: 96),
            makeEpisode(title: "Edison vs. Tesla | Work of the World | 2", publishDate: date(2000), season: 96),
        ]
        let arcs = ArcDerivation.groupIntoArcs(episodes)
        XCTAssertEqual(arcs.map(\.name), ["American Revolution", "Edison vs. Tesla"])
        XCTAssertEqual(arcs[0].episodes.count, 2)
        XCTAssertEqual(arcs[0].season, 97)
        XCTAssertEqual(arcs[1].season, 96)
    }

    func test_groupIntoArcs_excludesSinglePartArcsAndPlainSingles() {
        let episodes = [
            makeEpisode(title: "Great Saga - Part 1 - Only", publishDate: .now),
            makeEpisode(title: "Plain Single", publishDate: .now),
        ]
        XCTAssertTrue(ArcDerivation.groupIntoArcs(episodes).isEmpty)
    }

    func test_groupIntoArcs_wordNumberParts_formOneArc() {
        let episodes = [
            makeEpisode(title: "The Valley of Death, Part Two", publishDate: date(2000)),
            makeEpisode(title: "The Valley of Death, Part One", publishDate: date(1000)),
        ]
        let arcs = ArcDerivation.groupIntoArcs(episodes)
        XCTAssertEqual(arcs.count, 1)
        XCTAssertEqual(arcs[0].name, "The Valley of Death")
        XCTAssertEqual(arcs[0].episodes.count, 2)
    }

    func test_groupIntoArcs_largePipeEpisodeNumbers_areNotGuardedAsAnthology() {
        // Even the Rich numbers every real arc by episode number (…| 212).
        let episodes = [
            makeEpisode(title: "Taylor Swift: Fearless | In Our Swiftie Era | 212", publishDate: date(2000)),
            makeEpisode(title: "Taylor Swift: Fearless | Mastermind | 211", publishDate: date(1000)),
        ]
        let arcs = ArcDerivation.groupIntoArcs(episodes)
        XCTAssertEqual(arcs.count, 1)
        XCTAssertEqual(arcs[0].name, "Taylor Swift: Fearless")
        XCTAssertEqual(arcs[0].episodes.count, 2)
    }

    // MARK: - groupIntoArcs — anthology guard

    func test_groupIntoArcs_volumeAnthology_isDropped() {
        // "Mini-Stories: Volume 19..22" — an open-ended anthology, not an arc.
        let episodes = [
            makeEpisode(title: "Mini-Stories: Volume 22", publishDate: date(4000)),
            makeEpisode(title: "Mini-Stories: Volume 21", publishDate: date(3000)),
            makeEpisode(title: "Mini-Stories: Volume 20", publishDate: date(2000)),
        ]
        XCTAssertTrue(ArcDerivation.groupIntoArcs(episodes).isEmpty)
    }

    func test_groupIntoArcs_lowVolumeCounter_isKept() {
        // "(Volume 1)/(Volume 2)" starts at 1 — a bounded arc, kept.
        let episodes = [
            makeEpisode(title: "This Means War (Volume 2)", publishDate: date(2000)),
            makeEpisode(title: "This Means War (Volume 1)", publishDate: date(1000)),
        ]
        let arcs = ArcDerivation.groupIntoArcs(episodes)
        XCTAssertEqual(arcs.count, 1)
        XCTAssertEqual(arcs[0].name, "This Means War")
    }

    // MARK: - groupIntoArcs — re-release dedup

    func test_groupIntoArcs_dropsReReleaseDuplicate_keepsOriginalRun() {
        let episodes = [
            makeEpisode(title: "Cold Harbor - Part 2", publishDate: date(4000)),
            makeEpisode(title: "Cold Harbor - Part 1", publishDate: date(3000)),
            makeEpisode(title: "Encore: Cold Harbor - Part 2", publishDate: date(2000)),
            makeEpisode(title: "Encore: Cold Harbor - Part 1", publishDate: date(1000)),
        ]
        let arcs = ArcDerivation.groupIntoArcs(episodes)
        XCTAssertEqual(arcs.count, 1)
        XCTAssertEqual(arcs[0].name, "Cold Harbor")
        XCTAssertEqual(arcs[0].episodes.count, 2, "The two Encore re-airings collapse into the original run.")
        XCTAssertFalse(arcs[0].episodes.contains { $0.title.localizedCaseInsensitiveContains("encore") })
    }

    func test_groupIntoArcs_distinctEpisodeSharingPart_isNotDeduped() {
        // A non-re-release episode is never dropped even if it collides on part.
        let episodes = [
            makeEpisode(title: "Redux Studios - Part 1", publishDate: date(2000)),
            makeEpisode(title: "Redux Studios - Part 2", publishDate: date(1000)),
        ]
        let arcs = ArcDerivation.groupIntoArcs(episodes)
        XCTAssertEqual(arcs.count, 1)
        XCTAssertEqual(arcs[0].episodes.count, 2, "'Redux' in a show name must not trigger a false dedup drop.")
    }

    // MARK: - groupIntoArcs — season split + chaptered-season handler

    func test_groupIntoArcs_sameNameDifferentSeasons_split() {
        let episodes = [
            makeEpisode(title: "First Ladies | Michelle Obama | 2", publishDate: date(4000), season: 8),
            makeEpisode(title: "First Ladies | Martha Washington | 1", publishDate: date(3000), season: 8),
            makeEpisode(title: "First Ladies | Betty Ford | 2", publishDate: date(2000), season: 3),
            makeEpisode(title: "First Ladies | Eleanor Roosevelt | 1", publishDate: date(1000), season: 3),
        ]
        let arcs = ArcDerivation.groupIntoArcs(episodes)
        XCTAssertEqual(arcs.count, 2, "Same-named runs in different itunes:seasons split into two arcs.")
        XCTAssertEqual(Set(arcs.compactMap(\.season)), [3, 8])
    }

    func test_groupIntoArcs_chapteredSeason_BoneValley() {
        // "Chapter N | Title" has no arc name in the title → grouped by season.
        let episodes = [
            makeEpisode(title: "Chapter 4 | Dog with a Bone", publishDate: date(4000), season: 2),
            makeEpisode(title: "Chapter 3 | The Confession", publishDate: date(3000), season: 2),
            makeEpisode(title: "Chapter 2 | New Evidence", publishDate: date(2000), season: 1),
            makeEpisode(title: "Chapter 1 | The Call", publishDate: date(1000), season: 1),
        ]
        let arcs = ArcDerivation.groupIntoArcs(episodes)
        XCTAssertEqual(arcs.count, 2)
        XCTAssertEqual(Set(arcs.map(\.name)), ["Season 1", "Season 2"])
        XCTAssertEqual(Set(arcs.compactMap(\.season)), [1, 2])
    }

    func test_groupIntoArcs_seasonEpisodeLead_SceneOnRadio_themeNamed() {
        // "S7 E1: Title" carries no arc name in the title (Scene on Radio) — the
        // season theme lives only in the trailer. Group by itunes:season; name
        // from the trailer. The trailer itself (no S#E# lead) is not a member.
        let episodes = [
            makeEpisode(title: "S7 E3: Ships, Swords, and Fences", publishDate: date(5000), season: 7),
            makeEpisode(title: "S7 E2: BC: Before Capitalism", publishDate: date(4000), season: 7),
            makeEpisode(title: "S7 E1: Market Failure", publishDate: date(3000), season: 7),
            makeEpisode(title: "Season 7 Trailer: Capitalism", publishDate: date(2000), season: 7),
            makeEpisode(title: "Bonus: An Unrelated One-Off", publishDate: date(1000)),
        ]
        let arcs = ArcDerivation.groupIntoArcs(episodes)
        XCTAssertEqual(arcs.count, 1)
        XCTAssertEqual(arcs.first?.name, "Capitalism")
        XCTAssertEqual(arcs.first?.season, 7)
        XCTAssertEqual(arcs.first?.episodes.count, 3, "Trailer has no S#E# lead → names the arc but isn't a member.")
    }

    func test_groupIntoArcs_seasonThemeGrammars_allResolve() {
        // The three trailer/intro grammars Scene on Radio uses across seasons.
        func themedArc(trailer: String, season: Int) -> Arc? {
            ArcDerivation.groupIntoArcs([
                makeEpisode(title: "S\(season) E2: Second", publishDate: date(3000), season: season),
                makeEpisode(title: "S\(season) E1: First", publishDate: date(2000), season: season),
                makeEpisode(title: trailer, publishDate: date(1000), season: season),
            ]).first
        }
        XCTAssertEqual(themedArc(trailer: "Season 4 Trailer: The Land That Never Has Been Yet", season: 4)?.name,
                       "The Land That Never Has Been Yet")
        XCTAssertEqual(themedArc(trailer: "Scene on Radio Season 3: MEN Trailer", season: 3)?.name, "MEN")
        XCTAssertEqual(themedArc(trailer: "Introducing Scene on Radio: The News", season: 8)?.name, "The News")
    }

    func test_groupIntoArcs_seasonEpisodeLead_noTrailer_fallsBackToSeasonLabel() {
        let episodes = [
            makeEpisode(title: "S5 E2: Second", publishDate: date(2000), season: 5),
            makeEpisode(title: "S5 E1: First", publishDate: date(1000), season: 5),
        ]
        XCTAssertEqual(ArcDerivation.groupIntoArcs(episodes).first?.name, "Season 5")
    }

    func test_groupIntoArcs_parentheticalStem_SeeingWhite_clusters() {
        // The arc name is inside "(Seeing White, Part N)" on each unique title;
        // they cluster into one season-2 arc. Includes the no-comma variant.
        let episodes = [
            makeEpisode(title: "A Racial Cleansing in America (Seeing White Part 3)", publishDate: date(3000), season: 2),
            makeEpisode(title: "How Race Was Made (Seeing White, Part 2)", publishDate: date(2000), season: 2),
            makeEpisode(title: "Turning the Lens (Seeing White, Part 1)", publishDate: date(1000), season: 2),
        ]
        let arcs = ArcDerivation.groupIntoArcs(episodes)
        XCTAssertEqual(arcs.count, 1)
        XCTAssertEqual(arcs.first?.name, "Seeing White")
        XCTAssertEqual(arcs.first?.season, 2)
        XCTAssertEqual(arcs.first?.episodes.count, 3)
    }

    func test_groupIntoArcs_parentheticalStem_doesNotHijackBareOrCommaParts() {
        // Guard the marker ordering: a bare "(Part N)" still clusters by its own
        // stem, and a plain "X, Part N" still clusters by its own stem — neither
        // is swallowed by the new inner-parenthetical marker.
        let bareParen = [
            makeEpisode(title: "The Earliest Englishman (Part 2)", publishDate: date(2000)),
            makeEpisode(title: "The Earliest Englishman (Part 1)", publishDate: date(1000)),
        ]
        XCTAssertEqual(ArcDerivation.groupIntoArcs(bareParen).first?.name, "The Earliest Englishman")

        let commaPart = [
            makeEpisode(title: "The Valley of Death, Part 2", publishDate: date(2000)),
            makeEpisode(title: "The Valley of Death, Part 1", publishDate: date(1000)),
        ]
        XCTAssertEqual(ArcDerivation.groupIntoArcs(commaPart).first?.name, "The Valley of Death")
    }

    func test_groupIntoArcs_unstructuredFeed_hasNoArcs() {
        let episodes = [
            makeEpisode(title: "A Conversation with a Chef", publishDate: date(3000)),
            makeEpisode(title: "The State of the Economy", publishDate: date(2000)),
            makeEpisode(title: "Interview: A Novelist", publishDate: date(1000)),
        ]
        XCTAssertTrue(ArcDerivation.groupIntoArcs(episodes).isEmpty)
    }
}
