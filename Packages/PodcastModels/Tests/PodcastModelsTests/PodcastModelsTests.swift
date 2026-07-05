// PodcastModelsTests — SwiftData model-layer unit tests.
// Model layer for "i want ur pod"; no design source (data type only).
import XCTest
import SwiftData
@testable import PodcastModels

@MainActor
final class PodcastModelsTests: XCTestCase {

    // MARK: - Helpers

    /// A fresh in-memory container + context for each assertion group.
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try ModelSchema.makeContainer(inMemory: true)
        return (container, ModelContext(container))
    }

    private func makeFeedURL(_ slug: String = "example") -> URL {
        URL(string: "https://feeds.example.com/\(slug).xml")!
    }

    private func makeAudioURL(_ slug: String = "ep") -> URL {
        URL(string: "https://cdn.example.com/\(slug).mp3")!
    }

    // MARK: - Container / schema

    func testMakeContainerRegistersAllModels() throws {
        let (container, _) = try makeContext()
        let entityNames = Set(container.schema.entities.map(\.name))
        XCTAssertTrue(entityNames.contains("Podcast"))
        XCTAssertTrue(entityNames.contains("Episode"))
        XCTAssertTrue(entityNames.contains("Chapter"))
        XCTAssertTrue(entityNames.contains("QueueItem"))
        XCTAssertEqual(ModelSchema.models.count, 4)
    }

    // MARK: - Relationships

    func testInsertPodcastWithEpisodesAndChapters() throws {
        let (_, context) = try makeContext()

        let chapter1 = Chapter(title: "Intro", startTime: 0, endTime: 60)
        let chapter2 = Chapter(title: "Deep dive", startTime: 60, endTime: 900)

        let episode = Episode(
            guid: "guid-1",
            title: "First Episode",
            audioURL: makeAudioURL("ep1"),
            chapters: [chapter1, chapter2]
        )

        let podcast = Podcast(
            title: "The Show",
            author: "Host",
            feedURL: makeFeedURL("show"),
            isSubscribed: true,
            episodes: [episode]
        )

        context.insert(podcast)
        try context.save()

        // Relationship wiring: podcast -> episodes -> chapters and inverses.
        XCTAssertEqual(podcast.episodes.count, 1)
        let fetchedEpisode = try XCTUnwrap(podcast.episodes.first)
        XCTAssertEqual(fetchedEpisode.guid, "guid-1")
        XCTAssertIdentical(fetchedEpisode.podcast, podcast)

        XCTAssertEqual(fetchedEpisode.chapters.count, 2)
        let startTimes = Set(fetchedEpisode.chapters.map(\.startTime))
        XCTAssertEqual(startTimes, [0, 60])
        for chapter in fetchedEpisode.chapters {
            XCTAssertIdentical(chapter.episode, fetchedEpisode)
        }
    }

    func testFetchPodcastFromStore() throws {
        let (_, context) = try makeContext()

        let podcast = Podcast(
            title: "Fetchable",
            author: "Author",
            feedURL: makeFeedURL("fetchable")
        )
        context.insert(podcast)
        try context.save()

        let descriptor = FetchDescriptor<Podcast>()
        let all = try context.fetch(descriptor)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "Fetchable")
    }

    // MARK: - Cascade delete

    func testDeletePodcastCascadesToEpisodesAndChapters() throws {
        let (_, context) = try makeContext()

        let chapter = Chapter(title: "Only", startTime: 0)
        let episode = Episode(
            guid: "cascade-guid",
            title: "Doomed",
            audioURL: makeAudioURL("doomed"),
            chapters: [chapter]
        )
        let podcast = Podcast(
            title: "Doomed Show",
            feedURL: makeFeedURL("doomed"),
            episodes: [episode]
        )
        context.insert(podcast)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Podcast>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Episode>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Chapter>()), 1)

        context.delete(podcast)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Podcast>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Episode>()), 0, "Deleting a podcast should cascade to its episodes.")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Chapter>()), 0, "Deleting a podcast should cascade to episode chapters.")
    }

    func testDeleteEpisodeCascadesToChapters() throws {
        let (_, context) = try makeContext()

        let chapter = Chapter(title: "Chapter", startTime: 0)
        let episode = Episode(
            guid: "ep-cascade",
            title: "Episode",
            audioURL: makeAudioURL("epc"),
            chapters: [chapter]
        )
        let podcast = Podcast(
            title: "Show",
            feedURL: makeFeedURL("epcascade"),
            episodes: [episode]
        )
        context.insert(podcast)
        try context.save()

        context.delete(episode)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Podcast>()), 1, "Deleting an episode must not remove its podcast.")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Episode>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Chapter>()), 0, "Deleting an episode should cascade to its chapters.")
    }

    // MARK: - QueueItem orphaning

    func testDeleteEpisodeLeavesOrphanedQueueItemForStoreToPrune() throws {
        let (_, context) = try makeContext()

        let episode = Episode(
            guid: "queued",
            title: "Queued Episode",
            audioURL: makeAudioURL("queued")
        )
        let podcast = Podcast(
            title: "Show",
            feedURL: makeFeedURL("queue"),
            episodes: [episode]
        )
        context.insert(podcast)

        let item = QueueItem(order: 0, episode: episode)
        context.insert(item)
        try context.save()

        XCTAssertIdentical(item.episode, episode)

        context.delete(episode)
        try context.save()

        // Deleting an episode does not cascade to its queue entry: the QueueItem survives.
        // NOTE: QueueItem.episode is .nullify with no inverse, so the reference is not auto-nulled by SwiftData. Per the QueueItem model doc, orphan pruning is the queue store's responsibility — see E5. TODO(E5): add inverse relationship or queue-store pruning, then assert the reference is cleared.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QueueItem>()), 1, "Deleting an episode should not delete the queue entry.")
    }

    // MARK: - QueueItem ordering

    func testQueueItemOrdering() throws {
        let (_, context) = try makeContext()

        let podcast = Podcast(title: "Show", feedURL: makeFeedURL("order"))
        context.insert(podcast)

        // Insert out of order to prove the sort works.
        for index in [2, 0, 3, 1] {
            let episode = Episode(
                guid: "order-\(index)",
                title: "Episode \(index)",
                audioURL: makeAudioURL("order-\(index)"),
                podcast: podcast
            )
            context.insert(episode)
            context.insert(QueueItem(order: index, episode: episode))
        }
        try context.save()

        let descriptor = FetchDescriptor<QueueItem>(
            sortBy: [SortDescriptor(\.order, order: .forward)]
        )
        let ordered = try context.fetch(descriptor)
        XCTAssertEqual(ordered.map(\.order), [0, 1, 2, 3])
        XCTAssertEqual(ordered.compactMap(\.episode?.title), [
            "Episode 0", "Episode 1", "Episode 2", "Episode 3"
        ])
    }

    // MARK: - DownloadState round-trip

    func testDownloadStatePersistsAcrossFetch() throws {
        let (_, context) = try makeContext()

        let states: [DownloadState] = [
            .notDownloaded,
            .downloading(progress: 0.42),
            .downloaded,
            .failed(message: "network lost")
        ]

        for (index, state) in states.enumerated() {
            let episode = Episode(
                guid: "state-\(index)",
                title: "State \(index)",
                audioURL: makeAudioURL("state-\(index)"),
                downloadState: state
            )
            context.insert(episode)
        }
        try context.save()

        let descriptor = FetchDescriptor<Episode>(
            sortBy: [SortDescriptor(\.guid, order: .forward)]
        )
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.map(\.downloadState), states)

        // Spot-check the associated value survives the round-trip.
        let downloading = try XCTUnwrap(fetched.first { $0.downloadState.isDownloading })
        XCTAssertEqual(downloading.downloadState.fractionComplete, 0.42, accuracy: 0.0001)

        let failed = try XCTUnwrap(fetched.first {
            if case .failed = $0.downloadState { return true }
            return false
        })
        if case let .failed(message) = failed.downloadState {
            XCTAssertEqual(message, "network lost")
        } else {
            XCTFail("Expected a .failed download state.")
        }
    }

    func testDownloadStateCodableRoundTrip() throws {
        let states: [DownloadState] = [
            .notDownloaded,
            .downloading(progress: 0.75),
            .downloaded,
            .failed(message: nil)
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for state in states {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(DownloadState.self, from: data)
            XCTAssertEqual(decoded, state)
        }
    }

    // MARK: - Model invariants

    func testPlaybackProgressIsClampedOnInit() throws {
        let over = Episode(guid: "over", title: "Over", audioURL: makeAudioURL("over"), playbackProgress: 1.5)
        let under = Episode(guid: "under", title: "Under", audioURL: makeAudioURL("under"), playbackProgress: -0.5)
        XCTAssertEqual(over.playbackProgress, 1.0)
        XCTAssertEqual(under.playbackProgress, 0.0)
    }

    func testEpisodeDerivedProperties() throws {
        let played = Episode(guid: "p", title: "Played", duration: 100, audioURL: makeAudioURL("p"), playbackProgress: 1.0)
        XCTAssertTrue(played.isPlayed)
        XCTAssertEqual(played.remainingTime, 0, accuracy: 0.0001)

        let half = Episode(guid: "h", title: "Half", duration: 100, audioURL: makeAudioURL("h"), playbackProgress: 0.25)
        XCTAssertFalse(half.isPlayed)
        XCTAssertEqual(half.remainingTime, 75, accuracy: 0.0001)
    }

    func testUniqueFeedURLUpsertsPodcast() throws {
        let (_, context) = try makeContext()

        let feed = makeFeedURL("unique")
        context.insert(Podcast(title: "First", feedURL: feed))
        try context.save()

        // Inserting a second podcast with the same unique feedURL upserts
        // rather than producing a duplicate row.
        context.insert(Podcast(title: "Second", feedURL: feed))
        try context.save()

        let all = try context.fetch(FetchDescriptor<Podcast>())
        XCTAssertEqual(all.count, 1, "The @unique feedURL constraint should collapse duplicate feeds.")
    }
}
