// Translated from design/kit/components/result-row.html's category-shelf
// gallery (.shelf/.rail/.pod + "View all" → grid), the real design for search
// results (see design/kit/MANIFEST.md — there is no flat-list design anywhere
// in the current kit).
// Groups a flat `[SearchResult]` into one `ResultShelf` per `category`
// (preserving first-seen order; uncategorized results fall into "More"), each
// carrying a trailing `SubscribeButton` whose per-item state lives here.
// Subscribing persists via the `onSubscribe` closure the Discover screen
// supplies. "View all" opens the same shelf's items as a `PodGrid` sheet — the
// kit's grid destination has no separate chrome spec, so this uses a plain
// `NavigationStack` + toolbar Close button.
import SwiftUI
import DesignSystem
import DirectoryKit

struct ShelvesList: View {
    let results: [SearchResult]
    /// Called the moment an item is subscribed — the parent persists the show.
    var onSubscribe: (SearchResult) -> Void = { _ in }
    /// Called when a card (not its subscribe button) is tapped.
    var onSelect: (SearchResult) -> Void = { _ in }

    @State private var states: [String: SubscribeState] = [:]
    @State private var viewAllShelf: Shelf?

    private struct Shelf: Identifiable {
        let id: String   // category name
        let items: [SearchResult]
    }

    /// Groups `results` by `category`, preserving first-seen category order.
    private var shelves: [Shelf] {
        var order: [String] = []
        var groups: [String: [SearchResult]] = [:]
        for result in results {
            let category = (result.category?.isEmpty == false) ? result.category! : "More"
            if groups[category] == nil {
                order.append(category)
                groups[category] = []
            }
            groups[category, default: []].append(result)
        }
        return order.map { Shelf(id: $0, items: groups[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sp6) {   // .shelf + .shelf margin-top
            ForEach(shelves) { shelf in
                ResultShelf(
                    title: shelf.id,
                    items: shelf.items,
                    onViewAll: { viewAllShelf = shelf },
                    onSelect: onSelect,
                    itemTitle: { $0.title },
                    itemAuthor: { $0.author },
                    itemArtwork: { artwork(for: $0) }
                ) { result in
                    SubscribeButton(state: states[result.id] ?? .idle) {
                        subscribe(result)
                    }
                }
            }
        }
        .sheet(item: $viewAllShelf) { shelf in
            NavigationStack {
                ScrollView {
                    PodGrid(
                        items: shelf.items,
                        onSelect: onSelect,
                        itemTitle: { $0.title },
                        itemAuthor: { $0.author },
                        itemArtwork: { artwork(for: $0) }
                    ) { result in
                        SubscribeButton(state: states[result.id] ?? .idle) {
                            subscribe(result)
                        }
                    }
                    .padding(Spacing.gutter)
                }
                .navigationTitle(shelf.id)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { viewAllShelf = nil }
                    }
                }
            }
        }
    }

    // MARK: - Subscribe state

    private func subscribe(_ result: SearchResult) {
        switch states[result.id] ?? .idle {
        case .idle:
            states[result.id] = .subscribing
            onSubscribe(result)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                states[result.id] = .subscribed
            }
        case .subscribed:
            states[result.id] = .idle
        case .subscribing:
            break
        }
    }

    /// Deterministic gradient tile per show (stable across launches, unlike
    /// `hashValue`). Sums the title's scalars so the same show always gets the
    /// same `.a1…a6` placeholder.
    private func artwork(for result: SearchResult) -> ArtworkStyle {
        let seed = result.title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return ArtworkStyle(seed: seed)
    }
}

#if DEBUG
private struct ShelvesListPreviewHost: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            ShelvesList(results: DiscoverViewModel.sampleResults)
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.sp5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.groupedBg)
    }
}

#Preview("Shelves — dark") {
    ShelvesListPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}

#Preview("Shelves — light") {
    ShelvesListPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}
#endif
