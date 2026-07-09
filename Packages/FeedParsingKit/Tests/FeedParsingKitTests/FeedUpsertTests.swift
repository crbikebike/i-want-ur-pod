// Tests for the SwiftData upsert layer — matches Podcast by feedURL and
// Episode by guid, never clobbering user-owned fields.
// Covers ROADMAP E0-S2's determinate criterion.
import XCTest
import SwiftData
import PodcastModels
@testable import FeedParsingKit

final class FeedUpsertTests: XCTestCase {

    private let feedURL = URL(string: "https://example.com/feed.xml")!

    private func makeFeed(episodeTitle: String, podcastTitle: String, summary: String = "Original summary text") -> ParsedFeed {
        ParsedFeed(
            feedURL: feedURL,
            title: podcastTitle,
            author: "Original Author",
            homeURL: nil,
            artworkURL: URL(string: "https://example.com/art.jpg"),
            category: "Society & Culture",
            summary: summary,
            episodes: [
                ParsedEpisode(
                    guid: "ep-1",
                    title: episodeTitle,
                    summary: "Original summary",
                    publishDate: Date(timeIntervalSince1970: 1_000_000),
                    duration: 100,
                    audioURL: URL(string: "https://example.com/audio/ep1.mp3")!,
                    remoteArtworkURL: nil,
                    isExplicit: false
                )
            ]
        )
    }

    private func makeEpisode(guid: String, title: String, audioURL: URL? = nil) -> ParsedEpisode {
        ParsedEpisode(
            guid: guid,
            title: title,
            summary: "",
            publishDate: Date(timeIntervalSince1970: 1_000_000),
            duration: 100,
            audioURL: audioURL ?? URL(string: "https://example.com/audio/\(guid).mp3")!,
            remoteArtworkURL: nil,
            isExplicit: false
        )
    }

    @MainActor
    func test_reparsingSameFeed_preservesUserOwnedFieldsAndUpdatesFeedDerivedFields() throws {
        let container = try ModelSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)

        // First upsert.
        let firstFeed = makeFeed(episodeTitle: "Original Title", podcastTitle: "Original Show", summary: "Original show summary.")
        let podcast = try FeedUpsert.upsert(firstFeed, into: context)
        XCTAssertEqual(podcast.summary, "Original show summary.")

        // Simulate user-owned state accruing after the first import.
        podcast.isSubscribed = true
        let originalDateAdded = Date(timeIntervalSince1970: 500_000)
        podcast.dateAdded = originalDateAdded
        XCTAssertEqual(podcast.episodes.count, 1)
        let episode = podcast.episodes[0]
        episode.downloadState = .downloaded
        episode.playbackProgress = 0.42
        try context.save()

        // Second upsert: feed-derived fields changed, identities the same.
        let secondFeed = makeFeed(episodeTitle: "Updated Title", podcastTitle: "Updated Show", summary: "Updated show summary.")
        let podcastAgain = try FeedUpsert.upsert(secondFeed, into: context)

        // No duplicate rows.
        let allPodcasts = try context.fetch(FetchDescriptor<Podcast>())
        XCTAssertEqual(allPodcasts.count, 1)
        XCTAssertEqual(podcastAgain.episodes.count, 1)

        // Feed-derived fields updated.
        XCTAssertEqual(podcastAgain.title, "Updated Show")
        XCTAssertEqual(podcastAgain.summary, "Updated show summary.")
        let updatedEpisode = podcastAgain.episodes[0]
        XCTAssertEqual(updatedEpisode.title, "Updated Title")
        XCTAssertEqual(updatedEpisode.guid, "ep-1")

        // User-owned fields preserved.
        XCTAssertTrue(podcastAgain.isSubscribed)
        XCTAssertEqual(podcastAgain.dateAdded, originalDateAdded)
        XCTAssertEqual(updatedEpisode.playbackProgress, 0.42, accuracy: 0.0001)
        XCTAssertEqual(updatedEpisode.downloadState, .downloaded)
    }

    // Item 1: two items in the SAME parse resolving to the same guid must
    // upsert to exactly one Episode row (keep-first) and not throw on save.
    @MainActor
    func test_intraBatchDuplicateGuid_upsertsToSingleEpisodeAndIsIdempotent() throws {
        let container = try ModelSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let feed = ParsedFeed(
            feedURL: feedURL,
            title: "Dup Show",
            episodes: [
                makeEpisode(guid: "dup", title: "First"),
                makeEpisode(guid: "dup", title: "Second")
            ]
        )

        let podcast = try FeedUpsert.upsert(feed, into: context)
        try context.save()

        XCTAssertEqual(podcast.episodes.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Episode>()).count, 1)
        // Keep-first wins.
        XCTAssertEqual(podcast.episodes[0].title, "First")

        // Re-upserting the same batch stays idempotent (still one row).
        let again = try FeedUpsert.upsert(feed, into: context)
        try context.save()
        XCTAssertEqual(again.episodes.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Episode>()).count, 1)
    }

    // Item 2: re-parsing the same feedURL with an additional new-guid episode
    // adds the new Episode while leaving existing rows / user-owned fields and
    // the podcast row untouched.
    @MainActor
    func test_reparsingWithAddedEpisode_appendsNewEpisodeAndPreservesExisting() throws {
        let container = try ModelSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let firstFeed = ParsedFeed(
            feedURL: feedURL,
            title: "Growing Show",
            episodes: [makeEpisode(guid: "ep-1", title: "First")]
        )
        let podcast = try FeedUpsert.upsert(firstFeed, into: context)
        podcast.isSubscribed = true
        podcast.episodes[0].playbackProgress = 0.3
        try context.save()

        let secondFeed = ParsedFeed(
            feedURL: feedURL,
            title: "Growing Show",
            episodes: [
                makeEpisode(guid: "ep-1", title: "First"),
                makeEpisode(guid: "ep-2", title: "Second")
            ]
        )
        let podcastAgain = try FeedUpsert.upsert(secondFeed, into: context)
        try context.save()

        // No duplicate podcast row.
        XCTAssertEqual(try context.fetch(FetchDescriptor<Podcast>()).count, 1)
        // The extra episode is present; total is 2.
        XCTAssertEqual(podcastAgain.episodes.count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Episode>()).count, 2)
        XCTAssertTrue(podcastAgain.episodes.contains { $0.guid == "ep-2" })

        // Existing row's user-owned field untouched.
        let existing = podcastAgain.episodes.first { $0.guid == "ep-1" }
        XCTAssertEqual(existing?.playbackProgress ?? -1, 0.3, accuracy: 0.0001)
        XCTAssertTrue(podcastAgain.isSubscribed)
    }

    // Bone Valley Season 3 shape: the feed lists the same episode twice with
    // identical audio (same enclosure URL) under two different guids. That's
    // one real episode, so it must upsert to exactly one Episode row.
    @MainActor
    func test_sameAudioDifferentGuid_upsertsToSingleEpisode() throws {
        let container = try ModelSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let sharedAudio = URL(string: "https://example.com/audio/chapter-1.mp3")!
        let feed = ParsedFeed(
            feedURL: feedURL,
            title: "Re-ingested Show",
            episodes: [
                makeEpisode(guid: "guid-original", title: "Chapter 1", audioURL: sharedAudio),
                makeEpisode(guid: "guid-reissue", title: "Chapter 1", audioURL: sharedAudio)
            ]
        )

        let podcast = try FeedUpsert.upsert(feed, into: context)
        try context.save()

        XCTAssertEqual(podcast.episodes.count, 1, "Two items sharing one audio URL are one episode.")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Episode>()).count, 1)
        // Keep-first by audio.
        XCTAssertEqual(podcast.episodes[0].guid, "guid-original")

        // A later refresh still listing both guids must not re-introduce the
        // duplicate (the second guid maps onto the survivor by audio URL).
        let again = try FeedUpsert.upsert(feed, into: context)
        try context.save()
        XCTAssertEqual(again.episodes.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Episode>()).count, 1)
    }

    // Self-heal: a store already carrying two rows for one audio URL (persisted
    // before dedupe shipped) is pruned to one on the next upsert — keeping the
    // copy the user has touched (downloaded) so queue/download state survives.
    @MainActor
    func test_preexistingDuplicateRows_prunedToSingle_keepingUserState() throws {
        let container = try ModelSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let sharedAudio = URL(string: "https://example.com/audio/chapter-1.mp3")!

        // Seed the store the way a pre-dedupe import would have: one Podcast
        // with two Episode rows, same audio, different guids. The downloaded
        // one is the copy the user cares about.
        let podcast = Podcast(title: "Legacy Show", feedURL: feedURL)
        context.insert(podcast)
        let plain = Episode(guid: "guid-a", title: "Chapter 1", publishDate: Date(timeIntervalSince1970: 1_000_000), duration: 100, audioURL: sharedAudio, podcast: podcast)
        let downloaded = Episode(guid: "guid-b", title: "Chapter 1", publishDate: Date(timeIntervalSince1970: 1_000_000), duration: 100, audioURL: sharedAudio, podcast: podcast)
        downloaded.downloadState = .downloaded
        context.insert(plain)
        context.insert(downloaded)
        podcast.episodes.append(contentsOf: [plain, downloaded])
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Episode>()).count, 2)

        // Any subsequent upsert of the feed triggers the prune.
        let feed = ParsedFeed(
            feedURL: feedURL,
            title: "Legacy Show",
            episodes: [makeEpisode(guid: "guid-b", title: "Chapter 1", audioURL: sharedAudio)]
        )
        let result = try FeedUpsert.upsert(feed, into: context)
        try context.save()

        XCTAssertEqual(result.episodes.count, 1, "The duplicate pair collapses to one row.")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Episode>()).count, 1)
        let survivor = result.episodes[0]
        XCTAssertEqual(survivor.guid, "guid-b", "The downloaded copy is the one kept.")
        XCTAssertEqual(survivor.downloadState, .downloaded)
    }
}
