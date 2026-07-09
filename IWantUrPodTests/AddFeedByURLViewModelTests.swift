// Tests for AddFeedByURLViewModel — Phase 2 Wave 1 of docs/spec/add-feed-by-url.md
// ("New: AddFeedByURLViewModel" + its Verification → Unit tests bullet).
// Reuses the StubFetcher pattern and ModelSchema.makeContainer(inMemory:)
// setup from PodcastDetailViewModelTests. Runs on the iOS simulator
// (SwiftData relationship rules don't fire under host `swift test`).
import XCTest
import SwiftData
import PodcastModels
import FeedParsingKit
@testable import IWantUrPod

/// A canned `FeedFetching` stub so the view model never touches the network.
/// Also records whether `fetch(url:)` was ever invoked, so validation-failure
/// tests can assert the fetcher was never called.
private final class StubFetcher: FeedFetching, @unchecked Sendable {
    let result: Result<ParsedFeed, Error>
    private(set) var fetchCallCount = 0
    private(set) var lastFetchedURL: URL?

    init(result: Result<ParsedFeed, Error>) {
        self.result = result
    }

    func fetch(url: URL) async throws -> ParsedFeed {
        fetchCallCount += 1
        lastFetchedURL = url
        switch result {
        case .success(let feed): return feed
        case .failure(let error): throw error
        }
    }
}

@MainActor
final class AddFeedByURLViewModelTests: XCTestCase {

    private let feedURL = URL(string: "https://feeds.example.com/add-by-url-tests")!

    private func makeContainer() throws -> ModelContainer {
        try ModelSchema.makeContainer(inMemory: true)
    }

    private func makeFeed() -> ParsedFeed {
        ParsedFeed(
            feedURL: feedURL,
            title: "The Premium Hour",
            author: "Narrative Media",
            homeURL: nil,
            artworkURL: URL(string: "https://cdn.example.com/show-art.jpg"),
            category: "Society & Culture",
            summary: "",
            episodes: []
        )
    }

    // MARK: - Happy path

    func test_add_withValidFeed_succeedsAndPersistsSubscribedPodcast() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let fetcher = StubFetcher(result: .success(makeFeed()))

        let viewModel = AddFeedByURLViewModel(modelContext: context, fetcher: fetcher)
        await viewModel.add(urlString: feedURL.absoluteString)

        guard case .success(let resultURL) = viewModel.state else {
            return XCTFail("Expected .success, got \(viewModel.state)")
        }
        XCTAssertEqual(resultURL, feedURL)

        let stored = try context.fetch(FetchDescriptor<Podcast>()).filter { $0.feedURL == feedURL }
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.isSubscribed, true)
    }

    // MARK: - Idempotency

    func test_add_sameURLTwice_doesNotCreateDuplicate() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let fetcher = StubFetcher(result: .success(makeFeed()))

        let firstViewModel = AddFeedByURLViewModel(modelContext: context, fetcher: fetcher)
        await firstViewModel.add(urlString: feedURL.absoluteString)

        let secondViewModel = AddFeedByURLViewModel(modelContext: context, fetcher: fetcher)
        await secondViewModel.add(urlString: feedURL.absoluteString)

        guard case .success = secondViewModel.state else {
            return XCTFail("Expected .success, got \(secondViewModel.state)")
        }
        let stored = try context.fetch(FetchDescriptor<Podcast>()).filter { $0.feedURL == feedURL }
        XCTAssertEqual(stored.count, 1, "Re-adding the same feed URL must not create a duplicate Podcast row.")
    }

    // MARK: - Validation

    func test_add_withEmptyString_setsValidationErrorAndNeverFetches() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let fetcher = StubFetcher(result: .success(makeFeed()))

        let viewModel = AddFeedByURLViewModel(modelContext: context, fetcher: fetcher)
        await viewModel.add(urlString: "   ")

        guard case .error = viewModel.state else {
            return XCTFail("Expected .error, got \(viewModel.state)")
        }
        XCTAssertEqual(fetcher.fetchCallCount, 0, "An empty URL must never reach the fetcher.")
    }

    func test_add_withNonHTTPScheme_setsValidationErrorAndNeverFetches() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let fetcher = StubFetcher(result: .success(makeFeed()))

        let viewModel = AddFeedByURLViewModel(modelContext: context, fetcher: fetcher)
        await viewModel.add(urlString: "ftp://x")

        guard case .error = viewModel.state else {
            return XCTFail("Expected .error, got \(viewModel.state)")
        }
        XCTAssertEqual(fetcher.fetchCallCount, 0, "A non-http(s) scheme must never reach the fetcher.")
    }

    func test_add_normalizesFeedSchemeVariantsToHTTPS() async throws {
        // Both `feed://host/rss` and `feed:https://host/rss` are pseudo-scheme
        // feed links podcast apps hand out; both must normalize to https and
        // reach the fetcher rather than being rejected as an invalid scheme.
        for input in ["feed://feeds.example.com/rss", "feed:https://feeds.example.com/rss"] {
            let container = try makeContainer()
            let context = ModelContext(container)
            let fetcher = StubFetcher(result: .success(makeFeed()))

            let viewModel = AddFeedByURLViewModel(modelContext: context, fetcher: fetcher)
            await viewModel.add(urlString: input)

            XCTAssertEqual(fetcher.fetchCallCount, 1, "\(input) should reach the fetcher.")
            XCTAssertEqual(
                fetcher.lastFetchedURL,
                URL(string: "https://feeds.example.com/rss"),
                "\(input) should be normalized to https before fetching."
            )
        }
    }

    // MARK: - Expired-link (401/403) special-case copy

    func test_add_whenFetchFailsWith401_setsExpiredLinkMessage() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let fetcher = StubFetcher(result: .failure(FeedError.httpStatus(401)))

        let viewModel = AddFeedByURLViewModel(modelContext: context, fetcher: fetcher)
        await viewModel.add(urlString: feedURL.absoluteString)

        guard case .error(let message) = viewModel.state else {
            return XCTFail("Expected .error, got \(viewModel.state)")
        }
        XCTAssertEqual(message, "This link didn’t work. Private feed links can expire — grab a fresh one from the show and try again.")
    }
}
