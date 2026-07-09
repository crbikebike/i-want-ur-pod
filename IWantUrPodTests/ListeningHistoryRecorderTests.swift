// ListeningHistoryRecorderTests — Wave 1 backend coverage for episode
// listening history. Runs on the iOS simulator (SwiftData relationship
// precedent, same as QueueStoreTests.swift). Exercises
// `ListeningHistoryRecorder.record(episode:startedAt:listenedSeconds:)`, the
// small app-target type `IWantUrPodApp.init` wires to
// `PlaybackEngine.onDidFinishListening`.
import XCTest
import SwiftData
import PodcastModels
@testable import IWantUrPod

@MainActor
final class ListeningHistoryRecorderTests: XCTestCase {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try ModelSchema.makeContainer(inMemory: true)
    }

    private func makePodcast(_ context: ModelContext, title: String = "Show") -> Podcast {
        let podcast = Podcast(
            title: title,
            feedURL: URL(string: "https://feeds.example.com/\(UUID().uuidString)")!,
            artworkURL: URL(string: "https://cdn.example.com/podcast-art.jpg")
        )
        context.insert(podcast)
        return podcast
    }

    private func makeEpisode(
        _ context: ModelContext,
        guid: String,
        podcast: Podcast,
        remoteArtworkURL: URL? = nil
    ) -> Episode {
        let episode = Episode(
            guid: guid,
            title: "Episode \(guid)",
            audioURL: URL(string: "https://cdn.example.com/\(guid).mp3")!,
            remoteArtworkURL: remoteArtworkURL,
            downloadState: .downloaded,
            podcast: podcast
        )
        context.insert(episode)
        return episode
    }

    // MARK: - Records a PlayEvent with the expected snapshot fields

    func test_record_insertsPlayEventWithSnapshotFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context, title: "Great Show")
        let episode = makeEpisode(
            context,
            guid: "rec-ep-1",
            podcast: podcast,
            remoteArtworkURL: URL(string: "https://cdn.example.com/episode-art.jpg")
        )
        try context.save()

        let recorder = ListeningHistoryRecorder(context: context)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

        recorder.record(episode: episode, startedAt: startedAt, listenedSeconds: 87.5)

        let events = try context.fetch(FetchDescriptor<PlayEvent>())
        XCTAssertEqual(events.count, 1)

        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.playedAt, startedAt)
        XCTAssertEqual(event.listenedSeconds, 87.5, accuracy: 0.0001)
        XCTAssertEqual(event.episodeTitle, "Episode rec-ep-1")
        XCTAssertEqual(event.podcastTitle, "Great Show")
        XCTAssertEqual(event.artworkURL, URL(string: "https://cdn.example.com/episode-art.jpg"), "episode artwork takes priority over the podcast's")
        XCTAssertEqual(event.feedURL, podcast.feedURL)
        XCTAssertEqual(event.episodeGUID, "rec-ep-1")
    }

    func test_record_fallsBackToPodcastArtwork_whenEpisodeHasNone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context, title: "Show With Art")
        let episode = makeEpisode(context, guid: "rec-ep-2", podcast: podcast, remoteArtworkURL: nil)
        try context.save()

        let recorder = ListeningHistoryRecorder(context: context)
        recorder.record(episode: episode, startedAt: .now, listenedSeconds: 10)

        let events = try context.fetch(FetchDescriptor<PlayEvent>())
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.artworkURL, podcast.artworkURL)
    }

    func test_record_persistsAcrossFreshModelContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let episode = makeEpisode(context, guid: "rec-ep-3", podcast: podcast)
        try context.save()

        let recorder = ListeningHistoryRecorder(context: context)
        recorder.record(episode: episode, startedAt: .now, listenedSeconds: 5)

        let freshContext = ModelContext(container)
        let events = try freshContext.fetch(FetchDescriptor<PlayEvent>())
        XCTAssertEqual(events.count, 1, "record must persist (save), not just insert in-memory")
    }

    func test_record_multipleCalls_insertMultipleEvents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let podcast = makePodcast(context)
        let episode = makeEpisode(context, guid: "rec-ep-4", podcast: podcast)
        try context.save()

        let recorder = ListeningHistoryRecorder(context: context)
        recorder.record(episode: episode, startedAt: .now, listenedSeconds: 5)
        recorder.record(episode: episode, startedAt: .now, listenedSeconds: 8)

        let events = try context.fetch(FetchDescriptor<PlayEvent>())
        XCTAssertEqual(events.count, 2, "each play session logs its own PlayEvent row")
    }
}
