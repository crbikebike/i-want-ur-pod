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

    // MARK: - Sorted by dateAdded, newest first

    func test_list_isSortedByDateAddedNewestFirst() throws {
        let context = try makeContext()
        let oldest = makePodcast(title: "Oldest", feedURL: "https://example.com/oldest", isSubscribed: true, dateAdded: Date(timeIntervalSince1970: 1_000))
        let middle = makePodcast(title: "Middle", feedURL: "https://example.com/middle", isSubscribed: true, dateAdded: Date(timeIntervalSince1970: 5_000))
        let newest = makePodcast(title: "Newest", feedURL: "https://example.com/newest", isSubscribed: true, dateAdded: Date(timeIntervalSince1970: 9_000))
        // Inserted out of order to verify sorting, not insertion order.
        for podcast in [oldest, newest, middle] {
            context.insert(podcast)
        }
        try context.save()

        let result = try PodcastsListProvider.subscribedPodcasts(from: context)

        XCTAssertEqual(result.map(\.title), ["Newest", "Middle", "Oldest"])
    }

    // MARK: - Empty state: no subscribed shows returns empty

    func test_noSubscribedShows_returnsEmpty() throws {
        let context = try makeContext()

        XCTAssertTrue(try PodcastsListProvider.subscribedPodcasts(from: context).isEmpty)
    }

    // MARK: - sortedSubscribed (pure array function backing the live @Query)

    func test_sortedSubscribed_filtersAndSortsAPlainArray() {
        let oldest = makePodcast(title: "Oldest", feedURL: "https://example.com/oldest2", isSubscribed: true, dateAdded: Date(timeIntervalSince1970: 1_000))
        let newest = makePodcast(title: "Newest", feedURL: "https://example.com/newest2", isSubscribed: true, dateAdded: Date(timeIntervalSince1970: 9_000))
        let notSubscribed = makePodcast(title: "Skip", feedURL: "https://example.com/skip2", isSubscribed: false, dateAdded: Date(timeIntervalSince1970: 5_000))

        let result = PodcastsListProvider.sortedSubscribed([oldest, notSubscribed, newest])

        XCTAssertEqual(result.map(\.title), ["Newest", "Oldest"])
    }
}
