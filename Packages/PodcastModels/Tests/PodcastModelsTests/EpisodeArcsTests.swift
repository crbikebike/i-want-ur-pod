// Tests for EpisodeArcs — story-arc derivation from episode-title structure.
// Mirrors scripts/fetch-podcast-episodes.py's `derive_arc`; see
// docs/design/direction.md §11.
import XCTest
@testable import PodcastModels

final class EpisodeArcsTests: XCTestCase {

    // MARK: - derive(fromTitle:)

    func test_derive_pipeStyle_AHT() {
        let result = ArcDerivation.derive(fromTitle: "American Revolution | A Devil of a Whipping | 5")
        XCTAssertEqual(result.arcName, "American Revolution")
        XCTAssertEqual(result.displayTitle, "A Devil of a Whipping")
        XCTAssertEqual(result.part, 5)
    }

    func test_derive_partStyle_Explorers() {
        let result = ArcDerivation.derive(fromTitle: "Magellan - Part 4 - The Strait")
        XCTAssertEqual(result.arcName, "Magellan")
        XCTAssertEqual(result.displayTitle, "The Strait")
        XCTAssertEqual(result.part, 4)
    }

    func test_derive_partStyle_withoutSubtitle_fallsBackToPartLabel() {
        let result = ArcDerivation.derive(fromTitle: "Magellan - Part 4")
        XCTAssertEqual(result.arcName, "Magellan")
        XCTAssertEqual(result.displayTitle, "Part 4")
        XCTAssertEqual(result.part, 4)
    }

    func test_derive_stripsNoisePrefix_thenParsesPipeStyle() {
        let result = ArcDerivation.derive(fromTitle: "Encore: X | Y | 2")
        XCTAssertEqual(result.arcName, "X")
        XCTAssertEqual(result.displayTitle, "Y")
        XCTAssertEqual(result.part, 2)
    }

    func test_derive_noisePrefix_isCaseInsensitiveAndColonOptional() {
        // Only the leading prefix is stripped (single, anchored match) —
        // "New Season" here is left as part of the remaining "Arc - Part N"
        // structure, not stripped again.
        let result = ArcDerivation.derive(fromTitle: "fan favorite New Season - Part 1 - Kickoff")
        XCTAssertEqual(result.arcName, "New Season")
        XCTAssertEqual(result.displayTitle, "Kickoff")
        XCTAssertEqual(result.part, 1)
    }

    func test_derive_plainTitle_hasNoArc() {
        let result = ArcDerivation.derive(fromTitle: "Foul Play")
        XCTAssertNil(result.arcName)
        XCTAssertEqual(result.displayTitle, "Foul Play")
        XCTAssertNil(result.part)
    }

    func test_derive_chapterStyle_BoneValley_hasNoArcName() {
        // Bone Valley has no arc name in the title — grouping comes from
        // itunes:season instead (the groupBySeason fallback).
        let result = ArcDerivation.derive(fromTitle: "Chapter 4 | Dog with a Bone")
        XCTAssertNil(result.arcName)
        XCTAssertEqual(result.displayTitle, "Dog with a Bone")
        XCTAssertEqual(result.part, 4)
    }

    func test_derive_chapterStyle_withColon() {
        let result = ArcDerivation.derive(fromTitle: "Chapter 2: The Investigation")
        XCTAssertNil(result.arcName)
        XCTAssertEqual(result.displayTitle, "The Investigation")
        XCTAssertEqual(result.part, 2)
    }

    func test_derive_trailingParenPart_FallOfCivilizations() {
        let result = ArcDerivation.derive(fromTitle: "19. The Mongols - Terror of the Steppe (Part 2)")
        XCTAssertEqual(result.arcName, "19. The Mongols - Terror of the Steppe")
        XCTAssertEqual(result.displayTitle, "Part 2")
        XCTAssertEqual(result.part, 2)
    }

    func test_derive_trailingBracketPart() {
        let result = ArcDerivation.derive(fromTitle: "The Siege of Vienna [Part 3]")
        XCTAssertEqual(result.arcName, "The Siege of Vienna")
        XCTAssertEqual(result.displayTitle, "Part 3")
        XCTAssertEqual(result.part, 3)
    }

    func test_derive_trailingCommaPart() {
        let result = ArcDerivation.derive(fromTitle: "The Reckoning, Part 2")
        XCTAssertEqual(result.arcName, "The Reckoning")
        XCTAssertEqual(result.displayTitle, "Part 2")
        XCTAssertEqual(result.part, 2)
    }

    func test_derive_trailingEp_Serial() {
        let result = ArcDerivation.derive(fromTitle: "The Last 12 Weeks - Ep. 5")
        XCTAssertEqual(result.arcName, "The Last 12 Weeks")
        XCTAssertEqual(result.displayTitle, "Ep. 5")
        XCTAssertEqual(result.part, 5)
    }

    func test_derive_trailingEp_withoutPeriod() {
        let result = ArcDerivation.derive(fromTitle: "The Last 12 Weeks - Ep 6")
        XCTAssertEqual(result.arcName, "The Last 12 Weeks")
        XCTAssertEqual(result.displayTitle, "Ep. 6")
        XCTAssertEqual(result.part, 6)
    }

    func test_derive_trailingEpisode_spelledOut() {
        let result = ArcDerivation.derive(fromTitle: "The Last 12 Weeks - Episode 7")
        XCTAssertEqual(result.arcName, "The Last 12 Weeks")
        XCTAssertEqual(result.displayTitle, "Ep. 7")
        XCTAssertEqual(result.part, 7)
    }

    func test_derive_existingPartArcPattern_stillWinsOverNewPatterns() {
        // "X - Part 2" must keep hitting the pre-existing partArcPattern
        // (arc="X", no subtitle) rather than any of the new trailing patterns.
        let result = ArcDerivation.derive(fromTitle: "X - Part 2")
        XCTAssertEqual(result.arcName, "X")
        XCTAssertEqual(result.displayTitle, "Part 2")
        XCTAssertEqual(result.part, 2)
    }

    func test_derive_hardcoreHistory_romanNumerals_hasNoArc() {
        // Roman-numeral parts are explicitly excluded from this tier.
        let result = ArcDerivation.derive(fromTitle: "Show 73 - Mania for Subjugation III")
        XCTAssertNil(result.arcName)
        XCTAssertEqual(result.displayTitle, "Show 73 - Mania for Subjugation III")
        XCTAssertNil(result.part)
    }

    func test_derive_unstructuredTitle_hasNoArc() {
        let result = ArcDerivation.derive(fromTitle: "History of Spices (Radio Edit)")
        XCTAssertNil(result.arcName)
        XCTAssertEqual(result.displayTitle, "History of Spices (Radio Edit)")
        XCTAssertNil(result.part)
    }

    func test_derive_midTitleParenPart_doesNotFire() {
        // The trailing "(Part N)" pattern is anchored at $ — a parenthetical
        // that merely mentions "Part N" mid-title must not match.
        let result = ArcDerivation.derive(fromTitle: "Revisiting (Part 2) of the Saga: A Retrospective")
        XCTAssertNil(result.arcName)
        XCTAssertEqual(result.displayTitle, "Revisiting (Part 2) of the Saga: A Retrospective")
        XCTAssertNil(result.part)
    }

    // MARK: - groupIntoArcs

    private func makeEpisode(title: String, publishDate: Date, season: Int? = nil) -> Episode {
        Episode(
            guid: title,
            title: title,
            publishDate: publishDate,
            audioURL: URL(string: "https://cdn.example.com/\(title.hashValue).mp3")!,
            season: season
        )
    }

    func test_groupIntoArcs_groupsMembershipAndOrdersByRecency() {
        // Newest-first input, interspersed with singles — mirrors real feed
        // data where non-arc episodes sit between arc entries.
        let episodes = [
            makeEpisode(title: "American Revolution | A Devil of a Whipping | 5", publishDate: Date(timeIntervalSince1970: 5000), season: 97),
            makeEpisode(title: "American Revolution | Saratoga | 4", publishDate: Date(timeIntervalSince1970: 4000), season: 97),
            makeEpisode(title: "Foul Play", publishDate: Date(timeIntervalSince1970: 3500)),
            makeEpisode(title: "Edison vs. Tesla | Prometheus' Fire | 1", publishDate: Date(timeIntervalSince1970: 3000), season: 96),
            makeEpisode(title: "Edison vs. Tesla | Work of the World | 2", publishDate: Date(timeIntervalSince1970: 2000), season: 96),
        ]

        let arcs = ArcDerivation.groupIntoArcs(episodes)

        XCTAssertEqual(arcs.map(\.name), ["American Revolution", "Edison vs. Tesla"], "Arcs ordered by recency of their newest episode.")
        XCTAssertEqual(arcs[0].episodes.count, 2)
        XCTAssertEqual(arcs[0].season, 97)
        XCTAssertEqual(arcs[1].episodes.count, 2)
        XCTAssertEqual(arcs[1].season, 96)
    }

    func test_groupIntoArcs_excludesSinglePartArcs() {
        // A "1-part arc" isn't a series — only arcs with >= 2 episodes surface.
        let episodes = [
            makeEpisode(title: "Solo Saga | Only Part | 1", publishDate: .now),
            makeEpisode(title: "Plain Single", publishDate: .now),
        ]

        let arcs = ArcDerivation.groupIntoArcs(episodes)

        XCTAssertTrue(arcs.isEmpty, "A single-episode arc and a plain single should both be excluded from the shelf.")
    }

    func test_groupIntoArcs_seasonIsNilWhenFeedDoesNotSetIt() {
        let episodes = [
            makeEpisode(title: "Heinrich Barth - Part 2 - Kingdoms of Africa", publishDate: Date(timeIntervalSince1970: 2000)),
            makeEpisode(title: "Heinrich Barth - Part 1 - Africa Calls", publishDate: Date(timeIntervalSince1970: 1000)),
        ]

        let arcs = ArcDerivation.groupIntoArcs(episodes)

        XCTAssertEqual(arcs.count, 1)
        XCTAssertNil(arcs[0].season, "Explorers-style feeds have no itunes:season — the arc's season should be nil, not 0.")
    }

    func test_groupIntoArcs_seasonFallback_whenTitlesAreUnstructured() {
        // Revolutions-style: numeric-prefix titles with no safe pattern, but
        // itunes:season is set — the title pass yields zero arcs, so the
        // season fallback should kick in.
        let episodes = [
            makeEpisode(title: "11.29-Liberty, Equality, Humanity", publishDate: Date(timeIntervalSince1970: 6000), season: 11),
            makeEpisode(title: "11.28-The Convention", publishDate: Date(timeIntervalSince1970: 5000), season: 11),
            makeEpisode(title: "10.55-The End of the Terror", publishDate: Date(timeIntervalSince1970: 4000), season: 10),
            makeEpisode(title: "10.54-Thermidor", publishDate: Date(timeIntervalSince1970: 3000), season: 10),
            makeEpisode(title: "9.1-Prologue", publishDate: Date(timeIntervalSince1970: 2000), season: 9),
        ]

        let arcs = ArcDerivation.groupIntoArcs(episodes)

        XCTAssertEqual(arcs.map(\.name), ["Season 11", "Season 10"], "Newest season first; the singleton Season 9 is excluded.")
        XCTAssertEqual(arcs[0].episodes.count, 2)
        XCTAssertEqual(arcs[0].season, 11)
        XCTAssertEqual(arcs[1].episodes.count, 2)
        XCTAssertEqual(arcs[1].season, 10)
    }

    func test_groupIntoArcs_seasonFallback_doesNotFireWhenTitleArcsExist() {
        // AHT-style: both signals present (itunes:season set uniformly per
        // arc AND pipe-style titles). Title arcs must win outright — no
        // "Season N" cards alongside the named arcs.
        let episodes = [
            makeEpisode(title: "American Revolution | A Devil of a Whipping | 5", publishDate: Date(timeIntervalSince1970: 5000), season: 97),
            makeEpisode(title: "American Revolution | Saratoga | 4", publishDate: Date(timeIntervalSince1970: 4000), season: 97),
            makeEpisode(title: "Edison vs. Tesla | Prometheus' Fire | 1", publishDate: Date(timeIntervalSince1970: 3000), season: 96),
            makeEpisode(title: "Edison vs. Tesla | Work of the World | 2", publishDate: Date(timeIntervalSince1970: 2000), season: 96),
        ]

        let arcs = ArcDerivation.groupIntoArcs(episodes)

        XCTAssertEqual(arcs.map(\.name), ["American Revolution", "Edison vs. Tesla"])
        XCTAssertTrue(arcs.allSatisfy { !$0.name.hasPrefix("Season ") })
    }

    func test_groupIntoArcs_seasonFallback_excludesEpisodesWithoutSeason() {
        let episodes = [
            makeEpisode(title: "11.29-Liberty, Equality, Humanity", publishDate: Date(timeIntervalSince1970: 3000), season: 11),
            makeEpisode(title: "11.28-The Convention", publishDate: Date(timeIntervalSince1970: 2000), season: 11),
            makeEpisode(title: "Special Announcement", publishDate: Date(timeIntervalSince1970: 1000), season: nil),
        ]

        let arcs = ArcDerivation.groupIntoArcs(episodes)

        XCTAssertEqual(arcs.map(\.name), ["Season 11"])
        XCTAssertEqual(arcs[0].episodes.count, 2)
    }

    func test_groupIntoArcs_unstructuredShow_hasNoArcs() {
        // Dead To Me-style: no title patterns, no season data — no shelf.
        let episodes = [
            makeEpisode(title: "History of Spices (Radio Edit)", publishDate: Date(timeIntervalSince1970: 2000)),
            makeEpisode(title: "A Chat About Nothing", publishDate: Date(timeIntervalSince1970: 1000)),
        ]

        let arcs = ArcDerivation.groupIntoArcs(episodes)

        XCTAssertTrue(arcs.isEmpty)
    }
}
