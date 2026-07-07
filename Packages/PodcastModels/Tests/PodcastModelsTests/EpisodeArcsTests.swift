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
}
