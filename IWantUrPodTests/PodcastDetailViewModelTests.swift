// Tests for PodcastDetailViewModel — the E2 (Podcast Detail) loader.
// Covers ROADMAP E2-S1 (store-first load, newest-first episodes, artwork
// fallback), E2-S2 (subscribe persists across a relaunch), and E2-S3 (played /
// remaining-time mapping). Runs on the iOS simulator (SwiftData relationship
// rules don't fire under host `swift test` — see docs/spec/definition-of-done.md).
import XCTest
import SwiftData
import PodcastModels
import FeedParsingKit
@testable import IWantUrPod

/// A canned `FeedFetching` stub so the loader never touches the network.
private struct StubFetcher: FeedFetching {
    let result: Result<ParsedFeed, Error>

    func fetch(url: URL) async throws -> ParsedFeed {
        switch result {
        case .success(let feed): return feed
        case .failure(let error): throw error
        }
    }
}

@MainActor
final class PodcastDetailViewModelTests: XCTestCase {

    private let feedURL = URL(string: "https://feeds.example.com/detail-tests")!

    private func makeContainer() throws -> ModelContainer {
        try ModelSchema.makeContainer(inMemory: true)
    }

    private func makeFeed(episodes: [ParsedEpisode], summary: String = "") -> ParsedFeed {
        ParsedFeed(
            feedURL: feedURL,
            title: "The Story Hour",
            author: "Narrative Media",
            homeURL: nil,
            artworkURL: URL(string: "https://cdn.example.com/show-art.jpg"),
            category: "Society & Culture",
            summary: summary,
            episodes: episodes
        )
    }

    private func makeEpisode(
        guid: String,
        title: String,
        publishDate: Date,
        remoteArtworkURL: URL? = nil,
        season: Int? = nil
    ) -> ParsedEpisode {
        ParsedEpisode(
            guid: guid,
            title: title,
            summary: "Summary for \(title)",
            publishDate: publishDate,
            duration: 1800,
            audioURL: URL(string: "https://cdn.example.com/\(guid).mp3")!,
            remoteArtworkURL: remoteArtworkURL,
            season: season
        )
    }

    // MARK: - E2-S1: store-first load, upsert, newest-first, artwork fallback

    func test_load_whenNotInStore_fetchesAndUpsertsAndExposesEpisodes() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let oldest = makeEpisode(guid: "ep-1", title: "Episode One", publishDate: Date(timeIntervalSince1970: 1_000))
        let newest = makeEpisode(guid: "ep-2", title: "Episode Two", publishDate: Date(timeIntervalSince1970: 2_000))
        let fetcher = StubFetcher(result: .success(makeFeed(episodes: [oldest, newest])))

        let viewModel = PodcastDetailViewModel(feedURL: feedURL, modelContext: context, fetcher: fetcher)
        await viewModel.load()

        guard case .loaded(let podcast) = viewModel.state else {
            return XCTFail("Expected .loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(podcast.title, "The Story Hour")
        XCTAssertEqual(podcast.feedURL, feedURL)
        XCTAssertGreaterThanOrEqual(viewModel.episodes.count, 1)

        // The upsert actually persisted into the shared context. Fetch
        // everything and filter in Swift rather than `#Predicate` — the
        // macro expansion warns about a non-Sendable `KeyPath<Podcast, URL>`
        // when built inside this test target (not seen from production code
        // in the app/FeedParsingKit targets), and filtering avoids it.
        let stored = try context.fetch(FetchDescriptor<Podcast>()).filter { $0.feedURL == feedURL }
        XCTAssertEqual(stored.count, 1)
    }

    func test_episodes_areExposedNewestFirst() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let oldest = makeEpisode(guid: "old", title: "Old", publishDate: Date(timeIntervalSince1970: 1_000))
        let middle = makeEpisode(guid: "mid", title: "Middle", publishDate: Date(timeIntervalSince1970: 5_000))
        let newest = makeEpisode(guid: "new", title: "New", publishDate: Date(timeIntervalSince1970: 9_000))
        let fetcher = StubFetcher(result: .success(makeFeed(episodes: [oldest, newest, middle])))

        let viewModel = PodcastDetailViewModel(feedURL: feedURL, modelContext: context, fetcher: fetcher)
        await viewModel.load()

        XCTAssertEqual(viewModel.episodes.map(\.guid), ["new", "mid", "old"])
    }

    func test_load_populatesShowDescriptionFromFeedSummary() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let description = "A weekly show that follows one story as far as the tape recorder will let us."
        let fetcher = StubFetcher(result: .success(makeFeed(
            episodes: [makeEpisode(guid: "ep", title: "Ep", publishDate: .now)],
            summary: description
        )))

        let viewModel = PodcastDetailViewModel(feedURL: feedURL, modelContext: context, fetcher: fetcher)
        await viewModel.load()

        guard case .loaded(let podcast) = viewModel.state else {
            return XCTFail("Expected .loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(podcast.summary, description,
                       "The channel description should flow through to the loaded Podcast.summary.")
    }

    func test_artworkURL_fallsBackToShowArtworkWhenEpisodeHasNone() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let withOwnArt = makeEpisode(
            guid: "own-art",
            title: "Has Art",
            publishDate: Date(timeIntervalSince1970: 2_000),
            remoteArtworkURL: URL(string: "https://cdn.example.com/episode-art.jpg")
        )
        let withoutArt = makeEpisode(
            guid: "no-art",
            title: "No Art",
            publishDate: Date(timeIntervalSince1970: 1_000)
        )
        let fetcher = StubFetcher(result: .success(makeFeed(episodes: [withOwnArt, withoutArt])))

        let viewModel = PodcastDetailViewModel(feedURL: feedURL, modelContext: context, fetcher: fetcher)
        await viewModel.load()

        let ownArtEpisode = try XCTUnwrap(viewModel.episodes.first { $0.guid == "own-art" })
        let noArtEpisode = try XCTUnwrap(viewModel.episodes.first { $0.guid == "no-art" })

        XCTAssertEqual(viewModel.artworkURL(for: ownArtEpisode), URL(string: "https://cdn.example.com/episode-art.jpg"))
        XCTAssertEqual(viewModel.artworkURL(for: noArtEpisode), URL(string: "https://cdn.example.com/show-art.jpg"),
                       "An episode with no artwork should fall back to the show artwork.")
    }

    /// Store-first render must be instant even when the background refresh
    /// fails (e.g. offline) — the stored data stands, no `.error` state.
    func test_load_whenAlreadyInStoreWithEpisodes_showsExistingEvenIfRefreshFails() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let cached = Episode(
            guid: "cached-1",
            title: "Cached Episode",
            audioURL: URL(string: "https://cdn.example.com/cached-1.mp3")!
        )
        let existing = Podcast(
            title: "Already Subscribed",
            feedURL: feedURL,
            isSubscribed: true,
            episodes: [cached]
        )
        context.insert(existing)
        try context.save()

        let fetcher = StubFetcher(result: .failure(FeedError.httpStatus(500)))

        let viewModel = PodcastDetailViewModel(feedURL: feedURL, modelContext: context, fetcher: fetcher)
        await viewModel.load()

        guard case .loaded(let podcast) = viewModel.state else {
            return XCTFail("Expected .loaded (stored data survives a failed background refresh), got \(viewModel.state)")
        }
        XCTAssertEqual(podcast.title, "Already Subscribed")
        XCTAssertTrue(podcast.isSubscribed)
        XCTAssertEqual(viewModel.episodes.count, 1)
    }

    /// The Bone Valley case: a stored show with episodes still refreshes from
    /// the feed on `load()`, so feed-derived fields added after the episodes
    /// were first stored (like `season`) get backfilled, and newly published
    /// episodes get appended.
    func test_load_whenAlreadyInStoreWithEpisodes_refreshesFromFeedAndBackfillsSeasonAndAppendsNewEpisodes() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let cached = Episode(
            guid: "cached-1",
            title: "Cached Episode",
            audioURL: URL(string: "https://cdn.example.com/cached-1.mp3")!,
            season: nil
        )
        let existing = Podcast(
            title: "Already Subscribed",
            feedURL: feedURL,
            isSubscribed: true,
            episodes: [cached]
        )
        context.insert(existing)
        try context.save()

        let refreshedCached = makeEpisode(
            guid: "cached-1",
            title: "Cached Episode",
            publishDate: Date(timeIntervalSince1970: 1_000),
            season: 1
        )
        let brandNew = makeEpisode(
            guid: "new-ep",
            title: "New Episode",
            publishDate: Date(timeIntervalSince1970: 2_000),
            season: 1
        )
        let fetcher = StubFetcher(result: .success(makeFeed(episodes: [refreshedCached, brandNew])))

        let viewModel = PodcastDetailViewModel(feedURL: feedURL, modelContext: context, fetcher: fetcher)
        await viewModel.load()

        guard case .loaded(let podcast) = viewModel.state else {
            return XCTFail("Expected .loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(viewModel.episodes.count, 2, "The refresh should append the newly published episode.")
        let refreshed = try XCTUnwrap(podcast.episodes.first { $0.guid == "cached-1" })
        XCTAssertEqual(refreshed.season, 1, "The refresh should backfill season on the previously-stored episode.")
        XCTAssertTrue(podcast.episodes.contains { $0.guid == "new-ep" })
    }

    /// FeedUpsert already guarantees user-owned fields survive a re-upsert;
    /// assert it holds at the view-model level too, since `load()` now always
    /// triggers a refresh for a stored show with episodes.
    func test_load_whenAlreadyInStoreWithEpisodes_refreshPreservesUserOwnedFields() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let cached = Episode(
            guid: "cached-1",
            title: "Cached Episode",
            audioURL: URL(string: "https://cdn.example.com/cached-1.mp3")!,
            playbackProgress: 0.42
        )
        let existing = Podcast(
            title: "Already Subscribed",
            feedURL: feedURL,
            isSubscribed: true,
            episodes: [cached]
        )
        context.insert(existing)
        try context.save()

        let refreshedCached = makeEpisode(
            guid: "cached-1",
            title: "Cached Episode (retitled upstream)",
            publishDate: Date(timeIntervalSince1970: 1_000)
        )
        let fetcher = StubFetcher(result: .success(makeFeed(episodes: [refreshedCached])))

        let viewModel = PodcastDetailViewModel(feedURL: feedURL, modelContext: context, fetcher: fetcher)
        await viewModel.load()

        guard case .loaded(let podcast) = viewModel.state else {
            return XCTFail("Expected .loaded, got \(viewModel.state)")
        }
        XCTAssertTrue(podcast.isSubscribed, "isSubscribed is user-owned and must survive the refresh.")
        let refreshed = try XCTUnwrap(podcast.episodes.first { $0.guid == "cached-1" })
        XCTAssertEqual(refreshed.playbackProgress, 0.42, accuracy: 0.0001,
                        "playbackProgress is user-owned and must survive the refresh.")
        XCTAssertEqual(refreshed.title, "Cached Episode (retitled upstream)",
                        "Feed-derived fields like title ARE updated by the refresh.")
    }

    /// Regression: a show subscribed from Discover/curated is inserted with
    /// metadata only (no episodes). Opening its detail must fetch the feed to
    /// populate episodes — not show an empty list — while preserving the
    /// existing subscription.
    func test_load_whenInStoreButHasNoEpisodes_fetchesToPopulateAndPreservesSubscription() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let bare = Podcast(title: "Subscribed, No Episodes", feedURL: feedURL, isSubscribed: true)
        context.insert(bare)
        try context.save()

        let ep = makeEpisode(guid: "e1", title: "Episode 1", publishDate: Date(timeIntervalSince1970: 1_000))
        let fetcher = StubFetcher(result: .success(makeFeed(episodes: [ep])))

        let viewModel = PodcastDetailViewModel(feedURL: feedURL, modelContext: context, fetcher: fetcher)
        await viewModel.load()

        XCTAssertEqual(viewModel.episodes.count, 1, "A stored show with no episodes must fetch to populate them.")
        XCTAssertTrue(viewModel.isSubscribed, "Populating episodes must not drop the existing subscription.")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Podcast>()).count, 1, "No duplicate Podcast row.")
    }

    func test_load_whenFetchFails_reportsTypedErrorMessage() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let fetcher = StubFetcher(result: .failure(FeedError.httpStatus(404)))

        let viewModel = PodcastDetailViewModel(feedURL: feedURL, modelContext: context, fetcher: fetcher)
        await viewModel.load()

        guard case .error(let message) = viewModel.state else {
            return XCTFail("Expected .error, got \(viewModel.state)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    // MARK: - E2-S2: subscribe toggles and persists across relaunch

    func test_toggleSubscribe_flipsAndReportsSubscribed() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let fetcher = StubFetcher(result: .success(makeFeed(episodes: [
            makeEpisode(guid: "ep", title: "Ep", publishDate: .now)
        ])))

        let viewModel = PodcastDetailViewModel(feedURL: feedURL, modelContext: context, fetcher: fetcher)
        await viewModel.load()
        XCTAssertFalse(viewModel.isSubscribed)

        viewModel.toggleSubscribe()
        XCTAssertTrue(viewModel.isSubscribed)
    }

    func test_subscribe_persistsAcrossANewContextOnTheSameContainer() async throws {
        // Simulates "across relaunch": a fresh ModelContext on the same
        // (would-be reopened) container must see the persisted change.
        let container = try makeContainer()
        let firstContext = ModelContext(container)
        let fetcher = StubFetcher(result: .success(makeFeed(episodes: [
            makeEpisode(guid: "ep", title: "Ep", publishDate: .now)
        ])))

        let viewModel = PodcastDetailViewModel(feedURL: feedURL, modelContext: firstContext, fetcher: fetcher)
        await viewModel.load()
        viewModel.toggleSubscribe()

        let secondContext = ModelContext(container)
        let reloaded = try secondContext.fetch(FetchDescriptor<Podcast>()).first { $0.feedURL == feedURL }
        XCTAssertEqual(reloaded?.isSubscribed, true,
                        "Subscribing should persist so a fresh context on the same store sees it.")
    }

    // MARK: - E2-S3: played / remaining-time mapping (shell)

    func test_playedAndRemainingMapping_matchesPlaybackProgress() throws {
        let unplayed = Episode(guid: "u", title: "Unplayed", duration: 600, audioURL: URL(string: "https://cdn.example.com/u.mp3")!, playbackProgress: 0)
        XCTAssertFalse(unplayed.isPlayed)
        XCTAssertEqual(unplayed.remainingTime, 600, accuracy: 0.001, "No playback yet — the full duration remains.")

        let partial = Episode(guid: "p", title: "Partial", duration: 600, audioURL: URL(string: "https://cdn.example.com/p.mp3")!, playbackProgress: 0.5)
        XCTAssertFalse(partial.isPlayed)
        XCTAssertEqual(partial.remainingTime, 300, accuracy: 0.001)

        let played = Episode(guid: "d", title: "Done", duration: 600, audioURL: URL(string: "https://cdn.example.com/d.mp3")!, playbackProgress: 0.99)
        XCTAssertTrue(played.isPlayed)
    }
}
