// Translated from design/kit/screens/search-start.html (and the same shelves
// beneath search-typing.html): the rest/browse state's horizontal category
// rails ("Trending now", "True Crime") of poster pods, each with a corner
// Subscribe. Backed by the bundled curated "start here" picks (E1-S2, schema
// docs/spec/curated-list.schema.md) grouped by category into one `ResultShelf`
// rail per taxonomy — the kit's shelf/rail pattern (`result-row.html` via
// `ResultShelf`/`PodCard`), not the earlier vertical editorial cards. Behavior:
// file order preserved, tap a pod → E2 detail keyed by `feedUrl`, the corner
// Subscribe drives the same per-item state machine `ShelvesList` uses.
import SwiftUI
import DesignSystem
import DirectoryKit

struct CuratedShelf: View {
    let entries: [CuratedEntry]
    /// Called the moment an entry is subscribed — the parent persists the show.
    var onSubscribe: (SearchResult) -> Void = { _ in }
    /// Called when a pod (not its subscribe button) is tapped.
    var onSelect: (CuratedEntry) -> Void = { _ in }

    @State private var states: [String: SubscribeState] = [:]

    private struct Shelf: Identifiable {
        let id: String   // category name (or the fallback bucket label)
        let items: [CuratedEntry]
    }

    /// The fallback shelf title for entries with no category — the kit's rest
    /// state leads with a "Trending now" browse rail; uncategorised curated
    /// picks fold into a single "Popular now" rail.
    private static let fallbackTitle = "Popular now"

    /// Groups `entries` by `category`, preserving first-seen order (file order).
    private var shelves: [Shelf] {
        var order: [String] = []
        var groups: [String: [CuratedEntry]] = [:]
        for entry in entries {
            let key = (entry.category?.isEmpty == false) ? entry.category! : Self.fallbackTitle
            if groups[key] == nil {
                order.append(key)
                groups[key] = []
            }
            groups[key, default: []].append(entry)
        }
        return order.map { Shelf(id: $0, items: groups[$0] ?? []) }
    }

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sp6) {   // .shelf gap
                ForEach(shelves) { shelf in
                    ResultShelf(
                        title: shelf.id,
                        items: shelf.items,
                        onSelect: onSelect,
                        itemTitle: { $0.title },
                        itemAuthor: { $0.author },
                        itemArtwork: { artwork(for: $0) },
                        itemArtworkURL: { $0.artworkURL }
                    ) { entry in
                        SubscribeButton(state: states[entry.id] ?? .idle) {
                            subscribe(entry)
                        }
                    }
                }
            }
        }
    }

    private func subscribe(_ entry: CuratedEntry) {
        switch states[entry.id] ?? .idle {
        case .idle:
            states[entry.id] = .subscribing
            onSubscribe(entry.searchResult)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                states[entry.id] = .subscribed
            }
        case .subscribed:
            states[entry.id] = .idle
        case .subscribing:
            break
        }
    }

    /// Deterministic gradient tile per pick, seeded from the title so the same
    /// show always gets the same `.a1…a6` placeholder (same scheme as
    /// `ShelvesList.artwork(for:)`).
    private func artwork(for entry: CuratedEntry) -> ArtworkStyle {
        let seed = entry.title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return ArtworkStyle(seed: seed)
    }
}

// MARK: - Preview

#if DEBUG
private let previewEntries: [CuratedEntry] = [
    CuratedEntry(
        title: "Bone Valley",
        author: "Lava for Good Podcasts",
        feedURL: URL(string: "https://feeds.example.com/bone-valley")!,
        artworkURL: nil,
        category: "True Crime",
        blurb: "A nine-part investigation into a wrongful murder conviction — start at episode one; it's built as a single arc."
    ),
    CuratedEntry(
        title: "Adrift",
        author: "Apple TV / Blanchard House",
        feedURL: URL(string: "https://feeds.example.com/adrift")!,
        artworkURL: nil,
        category: "Documentary",
        blurb: "A single true story told across the season — the kind of arc this app is built for."
    ),
]

private struct CuratedShelfPreviewHost: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            CuratedShelf(entries: previewEntries)
                .padding(Spacing.gutter)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.groupedBg)
    }
}

#Preview("Curated shelf — dark") {
    CuratedShelfPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}

#Preview("Curated shelf — light") {
    CuratedShelfPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}
#endif
