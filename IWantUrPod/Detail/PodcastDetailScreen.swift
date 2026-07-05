// Composition root for Podcast Detail. Architecture source: navigation-map.md
// ("Podcast Detail is one adaptive screen … keyed by feedURL") — reached
// identically from Discover, search, and (later) the Podcasts list, all of
// which push a `feedURL` via `navigationDestination(for: URL.self)`.
import SwiftUI
import SwiftData
import FeedParsingKit

/// Resolves the shared `modelContext` + a live `FeedFetcher` and hosts
/// `PodcastDetailView`. Builds its view model once (on first appearance) and
/// kicks off the store-first load.
public struct PodcastDetailScreen: View {
    private let feedURL: URL

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: PodcastDetailViewModel?

    public init(feedURL: URL) {
        self.feedURL = feedURL
    }

    public var body: some View {
        Group {
            if let viewModel {
                PodcastDetailView(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard viewModel == nil else { return }
            let vm = PodcastDetailViewModel(feedURL: feedURL, modelContext: modelContext, fetcher: FeedFetcher())
            viewModel = vm
            await vm.load()
        }
    }
}
