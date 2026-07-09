// Tests for ListeningHistoryProvider — the Listening History screen's
// grouping + play-count logic (episode listening history feature). Pure
// `[PlayEvent]` -> data-structure functions, so these run on plain XCTest
// (no simulator-only SwiftData relationship behavior involved — PlayEvent has
// no relationships at all, per its header comment).
import XCTest
import PodcastModels
@testable import IWantUrPod

@MainActor
final class ListeningHistoryProviderTests: XCTestCase {

    private func makeEvent(
        daysAgo: Int,
        now: Date,
        listenedSeconds: TimeInterval = 60,
        episodeTitle: String = "Episode",
        podcastTitle: String = "Podcast",
        episodeGUID: String? = nil
    ) -> PlayEvent {
        let calendar = Calendar.current
        let playedAt = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return PlayEvent(
            playedAt: playedAt,
            listenedSeconds: listenedSeconds,
            episodeTitle: episodeTitle,
            podcastTitle: podcastTitle,
            episodeGUID: episodeGUID
        )
    }

    // MARK: - Day-header labels

    func test_dayHeaderLabel_today() {
        let now = Date.now
        XCTAssertEqual(ListeningHistoryProvider.dayHeaderLabel(for: now, now: now), "Today")
    }

    func test_dayHeaderLabel_yesterday() {
        let now = Date.now
        let event = makeEvent(daysAgo: 1, now: now)
        XCTAssertEqual(ListeningHistoryProvider.dayHeaderLabel(for: event.playedAt, now: now), "Yesterday")
    }

    func test_dayHeaderLabel_threeDaysAgo() {
        let now = Date.now
        let event = makeEvent(daysAgo: 3, now: now)
        XCTAssertEqual(ListeningHistoryProvider.dayHeaderLabel(for: event.playedAt, now: now), "3 days ago")
    }

    func test_dayHeaderLabel_sixDaysAgo() {
        let now = Date.now
        let event = makeEvent(daysAgo: 6, now: now)
        XCTAssertEqual(ListeningHistoryProvider.dayHeaderLabel(for: event.playedAt, now: now), "6 days ago")
    }

    func test_dayHeaderLabel_lastWeek() {
        let now = Date.now
        for daysAgo in [7, 10, 13] {
            let event = makeEvent(daysAgo: daysAgo, now: now)
            XCTAssertEqual(ListeningHistoryProvider.dayHeaderLabel(for: event.playedAt, now: now), "Last week", "daysAgo=\(daysAgo)")
        }
    }

    func test_dayHeaderLabel_beyondLastWeek() {
        let now = Date.now
        let event = makeEvent(daysAgo: 14, now: now)
        XCTAssertEqual(ListeningHistoryProvider.dayHeaderLabel(for: event.playedAt, now: now), "2 weeks ago")
    }

    // MARK: - Day grouping: reverse-chronological order preserved, grouped by day

    func test_groupedByDay_groupsEventsOnTheSameDayTogether() {
        let now = Date.now
        let events = [
            makeEvent(daysAgo: 0, now: now, episodeTitle: "A"),
            makeEvent(daysAgo: 0, now: now, episodeTitle: "B"),
            makeEvent(daysAgo: 1, now: now, episodeTitle: "C"),
        ]

        let sections = ListeningHistoryProvider.groupedByDay(events, now: now)

        XCTAssertEqual(sections.map(\.label), ["Today", "Yesterday"])
        XCTAssertEqual(sections[0].events.map(\.episodeTitle), ["A", "B"])
        XCTAssertEqual(sections[1].events.map(\.episodeTitle), ["C"])
    }

    func test_groupedByDay_preservesReverseChronologicalOrderWithinAndAcrossGroups() {
        let now = Date.now
        // Simulates the @Query's reverse-chronological sort: newest first.
        let events = [
            makeEvent(daysAgo: 0, now: now, episodeTitle: "Newest today"),
            makeEvent(daysAgo: 0, now: now, episodeTitle: "Older today"),
            makeEvent(daysAgo: 3, now: now, episodeTitle: "Three days ago"),
            makeEvent(daysAgo: 8, now: now, episodeTitle: "Last week"),
        ]

        let sections = ListeningHistoryProvider.groupedByDay(events, now: now)

        XCTAssertEqual(sections.map(\.label), ["Today", "3 days ago", "Last week"])
        XCTAssertEqual(sections[0].events.map(\.episodeTitle), ["Newest today", "Older today"])
    }

    func test_groupedByDay_emptyInputReturnsNoSections() {
        XCTAssertTrue(ListeningHistoryProvider.groupedByDay([]).isEmpty)
    }

    // MARK: - Play-count derivation

    func test_playCounts_anEpisodeAppearingThreeTimes_countsThreeOnEachRow() {
        let now = Date.now
        let events = [
            makeEvent(daysAgo: 0, now: now, episodeTitle: "Cold Open, Warm Ending", episodeGUID: "se-1"),
            makeEvent(daysAgo: 3, now: now, episodeTitle: "Cold Open, Warm Ending", episodeGUID: "se-1"),
            makeEvent(daysAgo: 6, now: now, episodeTitle: "Cold Open, Warm Ending", episodeGUID: "se-1"),
        ]

        let counts = ListeningHistoryProvider.playCounts(for: events)

        for event in events {
            XCTAssertEqual(counts[ListeningHistoryProvider.playCountKey(for: event)], 3)
        }
    }

    func test_playCounts_anEpisodePlayedOnce_countsOne() {
        let event = makeEvent(daysAgo: 0, now: .now, episodeGUID: "solo")
        let counts = ListeningHistoryProvider.playCounts(for: [event])

        XCTAssertEqual(counts[ListeningHistoryProvider.playCountKey(for: event)], 1)
    }

    func test_playCounts_fallsBackToEpisodeTitleWhenGUIDIsMissing() {
        let now = Date.now
        let events = [
            makeEvent(daysAgo: 0, now: now, episodeTitle: "No GUID Episode", episodeGUID: nil),
            makeEvent(daysAgo: 1, now: now, episodeTitle: "No GUID Episode", episodeGUID: nil),
        ]

        let counts = ListeningHistoryProvider.playCounts(for: events)

        XCTAssertEqual(counts["No GUID Episode"], 2)
    }

    func test_playCounts_distinctEpisodesAreNotConflated() {
        let now = Date.now
        let events = [
            makeEvent(daysAgo: 0, now: now, episodeTitle: "Episode One", episodeGUID: "guid-1"),
            makeEvent(daysAgo: 0, now: now, episodeTitle: "Episode Two", episodeGUID: "guid-2"),
        ]

        let counts = ListeningHistoryProvider.playCounts(for: events)

        XCTAssertEqual(counts["guid-1"], 1)
        XCTAssertEqual(counts["guid-2"], 1)
    }

    // MARK: - Listened-duration label

    func test_listenedDurationLabel_underAnHour() {
        XCTAssertEqual(ListeningHistoryProvider.listenedDurationLabel(forSeconds: 24 * 60), "24 min listened")
    }

    func test_listenedDurationLabel_atAnHour() {
        XCTAssertEqual(ListeningHistoryProvider.listenedDurationLabel(forSeconds: 60 * 60), "1h 0m listened")
    }

    func test_listenedDurationLabel_overAnHour() {
        XCTAssertEqual(ListeningHistoryProvider.listenedDurationLabel(forSeconds: 72 * 60), "1h 12m listened")
    }

    func test_listenedDurationLabel_zero() {
        XCTAssertEqual(ListeningHistoryProvider.listenedDurationLabel(forSeconds: 0), "0 min listened")
    }
}
