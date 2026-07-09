// Tests for PodcastsListProvider — the Podcasts tab's list logic (ROADMAP.md
// E3-S1). Runs on the iOS simulator (SwiftData relationship rules don't fire
// under host `swift test` — see docs/spec/definition-of-done.md and the same
// precedent in PodcastDetailViewModelTests.swift).
import XCTest
import SwiftData
import PodcastModels
@testable import IWantUrPod

@MainActor
final class PodcastsListProviderTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try ModelSchema.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    private func makePodcast(
        title: String,
        feedURL: String,
        isSubscribed: Bool,
        dateAdded: Date
    ) -> Podcast {
        Podcast(
            title: title,
            author: "Author of \(title)",
            feedURL: URL(string: feedURL)!,
            isSubscribed: isSubscribed,
            dateAdded: dateAdded
        )
    }

    // MARK: - Subscribing adds a row; an unsubscribed show does not appear

    func test_subscribedPodcast_appearsInList() throws {
        let context = try makeContext()
        let subscribed = makePodcast(title: "Acquired", feedURL: "https://example.com/acquired", isSubscribed: true, dateAdded: .now)
        context.insert(subscribed)
        try context.save()

        let result = try PodcastsListProvider.subscribedPodcasts(from: context)

        XCTAssertEqual(result.map(\.title), ["Acquired"])
    }

    func test_unsubscribedPodcast_doesNotAppearInList() throws {
        let context = try makeContext()
        let unsubscribed = makePodcast(title: "Not Subscribed", feedURL: "https://example.com/not-subscribed", isSubscribed: false, dateAdded: .now)
        context.insert(unsubscribed)
        try context.save()

        let result = try PodcastsListProvider.subscribedPodcasts(from: context)

        XCTAssertTrue(result.isEmpty, "An unsubscribed show must not appear in the Podcasts list")
    }

    // MARK: - Toggling isSubscribed false removes it from the list

    func test_togglingSubscribedFalse_removesItFromList() throws {
        let context = try makeContext()
        let podcast = makePodcast(title: "Behind the Bastards", feedURL: "https://example.com/bastards", isSubscribed: true, dateAdded: .now)
        context.insert(podcast)
        try context.save()

        XCTAssertEqual(try PodcastsListProvider.subscribedPodcasts(from: context).count, 1)

        podcast.isSubscribed = false
        try context.save()

        XCTAssertTrue(try PodcastsListProvider.subscribedPodcasts(from: context).isEmpty)
    }

    // MARK: - Sorted alphabetically by title, dateAdded irrelevant

    func test_list_isSortedAlphabeticallyByTitle() throws {
        let context = try makeContext()
        let zebra = makePodcast(title: "Zebra Cast", feedURL: "https://example.com/zebra", isSubscribed: true, dateAdded: Date(timeIntervalSince1970: 9_000))
        let middle = makePodcast(title: "Middle Show", feedURL: "https://example.com/middle", isSubscribed: true, dateAdded: Date(timeIntervalSince1970: 5_000))
        let acquired = makePodcast(title: "Acquired", feedURL: "https://example.com/acquired3", isSubscribed: true, dateAdded: Date(timeIntervalSince1970: 1_000))
        // Inserted out of alphabetical (and dateAdded) order to verify the
        // sort key, not insertion or dateAdded order.
        for podcast in [zebra, acquired, middle] {
            context.insert(podcast)
        }
        try context.save()

        let result = try PodcastsListProvider.subscribedPodcasts(from: context)

        XCTAssertEqual(result.map(\.title), ["Acquired", "Middle Show", "Zebra Cast"])
    }

    // MARK: - sortKey: article-insensitive, diacritic/case-insensitive

    func test_sortKey_stripsALeadingArticle() {
        XCTAssertEqual(PodcastsListProvider.sortKey(for: makePodcast(title: "The Daily", feedURL: "https://example.com/the-daily", isSubscribed: true, dateAdded: .now)), "daily")
        XCTAssertEqual(PodcastsListProvider.sortKey(for: makePodcast(title: "A History Of", feedURL: "https://example.com/a-history", isSubscribed: true, dateAdded: .now)), "history of")
        XCTAssertEqual(PodcastsListProvider.sortKey(for: makePodcast(title: "An Arm And A Leg", feedURL: "https://example.com/an-arm", isSubscribed: true, dateAdded: .now)), "arm and a leg")
    }

    func test_sortKey_onlyStripsAnArticleWhenFollowedByMoreText() {
        // "A" alone (no trailing word) keeps its leading "a" — it's the whole
        // title, not an article introducing one.
        XCTAssertEqual(PodcastsListProvider.sortKey(for: makePodcast(title: "A", feedURL: "https://example.com/just-a", isSubscribed: true, dateAdded: .now)), "a")
    }

    func test_sortKey_foldsDiacriticsAndCase() {
        XCTAssertEqual(PodcastsListProvider.sortKey(for: makePodcast(title: "Café Society", feedURL: "https://example.com/cafe", isSubscribed: true, dateAdded: .now)), "cafe society")
        XCTAssertEqual(PodcastsListProvider.sortKey(for: makePodcast(title: "ZEBRA", feedURL: "https://example.com/zebra-caps", isSubscribed: true, dateAdded: .now)), "zebra")
    }

    func test_list_articlesAreIgnoredWhenSorting() throws {
        let context = try makeContext()
        let theDaily = makePodcast(title: "The Daily", feedURL: "https://example.com/the-daily2", isSubscribed: true, dateAdded: .now)
        let acquired = makePodcast(title: "Acquired", feedURL: "https://example.com/acquired4", isSubscribed: true, dateAdded: .now)
        for podcast in [theDaily, acquired] {
            context.insert(podcast)
        }
        try context.save()

        let result = try PodcastsListProvider.subscribedPodcasts(from: context)

        // "The Daily" sorts as "Daily" (D), after "Acquired" (A).
        XCTAssertEqual(result.map(\.title), ["Acquired", "The Daily"])
    }

    // MARK: - Empty state: no subscribed shows returns empty

    func test_noSubscribedShows_returnsEmpty() throws {
        let context = try makeContext()

        XCTAssertTrue(try PodcastsListProvider.subscribedPodcasts(from: context).isEmpty)
    }

    // MARK: - sortedSubscribed (pure array function backing the live @Query)

    func test_sortedSubscribed_filtersAndSortsAPlainArray() {
        let zebra = makePodcast(title: "Zebra Cast", feedURL: "https://example.com/zebra2", isSubscribed: true, dateAdded: Date(timeIntervalSince1970: 1_000))
        let acquired = makePodcast(title: "Acquired", feedURL: "https://example.com/acquired5", isSubscribed: true, dateAdded: Date(timeIntervalSince1970: 9_000))
        let notSubscribed = makePodcast(title: "Middle Show", feedURL: "https://example.com/skip2", isSubscribed: false, dateAdded: Date(timeIntervalSince1970: 5_000))

        let result = PodcastsListProvider.sortedSubscribed([zebra, notSubscribed, acquired])

        XCTAssertEqual(result.map(\.title), ["Acquired", "Zebra Cast"])
    }
}
