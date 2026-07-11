// Translated from design/kit/components/result-row.html (.shelf / .shelf-head /
// .sh-title / .view-all / .rail / .pod / .pod-art / .pod-meta / .gridview /
// .podgrid + SHARED KIT EXTRAS). This is the file's actual bespoke content —
// horizontal category shelves of poster cards, each with a corner subscribe
// button, and a "View all" affordance that expands into a full grid — not a
// flat row (see design/kit/MANIFEST.md for the history of that confusion).
//
// A `ResultShelf` groups one taxonomy's results into a horizontally scrolling
// rail of `PodCard`s. `PodGrid` renders the same cards in a 2-up grid — the
// kit's "View all" destination. Colors/sizing come only from the active
// ThemePalette and the Spacing/Radius/Typography/Motion tokens; the `.pod-art`
// gradient placeholders come from `ArtworkTile.swift`.
import SwiftUI

// MARK: - Pod card (.pod / .pod-art / .pod-meta)

/// One poster card: square gradient artwork with a corner subscribe button,
/// a 2-line clamped title, and a single truncated author/studio line. Used
/// both in a `ResultShelf`'s horizontal rail and in a `PodGrid`.
public struct PodCard<Trailing: View>: View {
    private let title: String
    private let author: String
    private let artwork: ArtworkStyle
    private let artworkURL: URL?
    private let trailing: () -> Trailing

    @Environment(\.palette) private var palette

    /// - Parameters:
    ///   - artwork: The gradient placeholder style, used when `artworkURL` is
    ///     `nil` or the remote image fails to load.
    ///   - artworkURL: Remote poster artwork; when present it loads via
    ///     `RemoteArtwork`, falling back to the `artwork` gradient.
    public init(
        title: String,
        author: String,
        artwork: ArtworkStyle,
        artworkURL: URL? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.author = author
        self.artwork = artwork
        self.artworkURL = artworkURL
        self.trailing = trailing
    }

    private var initial: String {
        guard let first = title.first(where: { !$0.isWhitespace }) else { return "?" }
        return String(first).uppercased()
    }

    /// Seed that reproduces `artwork` through `ArtworkStyle(seed:)`, so the
    /// `RemoteArtwork` gradient fallback matches this card's placeholder style.
    private var fallbackSeed: Int {
        ArtworkStyle.allCases.firstIndex(of: artwork) ?? 0
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {   // .pod { gap: 9px }
            RemoteArtwork(
                url: artworkURL,
                seed: fallbackSeed,
                initial: initial,
                cornerRadius: Radius.rMd16
            )
                .overlay(alignment: .bottomTrailing) {
                    // .sub — corner circular subscribe, floats on the artwork.
                    trailing()
                        .padding(6)
                }

            VStack(alignment: .leading, spacing: 3) {   // .pod-meta
                Text(title)
                    .typeStyle(Typography.rowTitleStyle)   // .pod-title ≈ .96rem/700
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(author)
                    .typeStyle(Typography.subheadStyle)    // .pod-studio ≈ .8rem/500
                    .foregroundStyle(palette.textDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(author)")
    }
}

// MARK: - Shelf (.shelf / .shelf-head / .rail)

/// A horizontally scrolling shelf of `PodCard`s under a title + optional
/// "View all" affordance. Mirrors `result-row.html`'s category-shelf pattern —
/// e.g. "Trending now", "True Crime" — each shelf independent, never merged.
public struct ResultShelf<Item: Identifiable, Trailing: View>: View {
    private let title: String
    private let items: [Item]
    private let totalCount: Int?
    private let onViewAll: (() -> Void)?
    private let onSelect: (Item) -> Void
    private let itemTitle: (Item) -> String
    private let itemAuthor: (Item) -> String
    private let itemArtwork: (Item) -> ArtworkStyle
    private let itemArtworkURL: (Item) -> URL?
    private let trailing: (Item) -> Trailing

    @Environment(\.palette) private var palette

    /// - Parameters:
    ///   - title: The shelf's taxonomy label (the kit's `.sh-title`).
    ///   - items: The shelf's items, in display order.
    ///   - totalCount: The full count for "View all" (the kit's `.n`); defaults
    ///     to `items.count` when the shelf isn't a truncated preview.
    ///   - onViewAll: Shown as a trailing "View all" link when non-nil.
    ///   - onSelect: Fired when a card (not its trailing control) is tapped.
    ///   - itemArtworkURL: Remote poster artwork per item; defaults to `nil`
    ///     (gradient placeholder), and falls back to the gradient when the load
    ///     fails.
    public init(
        title: String,
        items: [Item],
        totalCount: Int? = nil,
        onViewAll: (() -> Void)? = nil,
        onSelect: @escaping (Item) -> Void = { _ in },
        itemTitle: @escaping (Item) -> String,
        itemAuthor: @escaping (Item) -> String,
        itemArtwork: @escaping (Item) -> ArtworkStyle,
        itemArtworkURL: @escaping (Item) -> URL? = { _ in nil },
        @ViewBuilder trailing: @escaping (Item) -> Trailing
    ) {
        self.title = title
        self.items = items
        self.totalCount = totalCount
        self.onViewAll = onViewAll
        self.onSelect = onSelect
        self.itemTitle = itemTitle
        self.itemAuthor = itemAuthor
        self.itemArtwork = itemArtwork
        self.itemArtworkURL = itemArtworkURL
        self.trailing = trailing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sp3) {   // .shelf-head margin-bottom
            header

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sp3) {   // .rail { gap: --sp-3 }
                    ForEach(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            PodCard(
                                title: itemTitle(item),
                                author: itemAuthor(item),
                                artwork: itemArtwork(item),
                                artworkURL: itemArtworkURL(item)
                            ) {
                                trailing(item)
                            }
                            .frame(width: 150)   // .pod { width: 150px }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)   // .rail padding clears the pod's active-scale
            }
        }
    }

    @ViewBuilder private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sp3) {   // .shelf-head
            Text(title)
                .typeStyle(Typography.shelfTitleStyle)
                .foregroundStyle(palette.text)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let onViewAll {
                Button(action: onViewAll) {
                    HStack(spacing: 3) {
                        Text("\(totalCount ?? items.count)")
                            .font(Typography.subhead)
                            .foregroundStyle(palette.textFaint)
                        Text("View all")
                            .font(Typography.subhead.weight(.heavy))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Pod grid (.gridview / .podgrid — the "View all" destination)

/// The same `PodCard`s in a 2-up grid — the kit's "View all" expansion.
/// Chrome (back button, title, count) is left to the caller (typically a
/// `NavigationStack` + toolbar), since that's app-level navigation, not a
/// design-system concern.
public struct PodGrid<Item: Identifiable, Trailing: View>: View {
    private let items: [Item]
    private let onSelect: (Item) -> Void
    private let itemTitle: (Item) -> String
    private let itemAuthor: (Item) -> String
    private let itemArtwork: (Item) -> ArtworkStyle
    private let itemArtworkURL: (Item) -> URL?
    private let trailing: (Item) -> Trailing

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.sp3),
        GridItem(.flexible(), spacing: Spacing.sp3)
    ]

    public init(
        items: [Item],
        onSelect: @escaping (Item) -> Void = { _ in },
        itemTitle: @escaping (Item) -> String,
        itemAuthor: @escaping (Item) -> String,
        itemArtwork: @escaping (Item) -> ArtworkStyle,
        itemArtworkURL: @escaping (Item) -> URL? = { _ in nil },
        @ViewBuilder trailing: @escaping (Item) -> Trailing
    ) {
        self.items = items
        self.onSelect = onSelect
        self.itemTitle = itemTitle
        self.itemAuthor = itemAuthor
        self.itemArtwork = itemArtwork
        self.itemArtworkURL = itemArtworkURL
        self.trailing = trailing
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.sp4) {   // .podgrid gaps
            ForEach(items) { item in
                Button {
                    onSelect(item)
                } label: {
                    PodCard(
                        title: itemTitle(item),
                        author: itemAuthor(item),
                        artwork: itemArtwork(item),
                        artworkURL: itemArtworkURL(item)
                    ) {
                        trailing(item)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
private struct ResultShelfPreviewHost: View {
    @Environment(\.palette) private var palette

    private struct Item: Identifiable {
        let id: String
        let title: String
        let author: String
        let art: ArtworkStyle
    }

    private let trending: [Item] = [
        .init(id: "1", title: "Acquired", author: "Ben Gilbert & David Rosenthal", art: .a2),
        .init(id: "2", title: "Behind the Bastards", author: "Cool Zone Media", art: .a3),
        .init(id: "3", title: "99% Invisible", author: "Roman Mars", art: .a1),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sp6) {
                ResultShelf(
                    title: "Trending now",
                    items: trending,
                    totalCount: 128,
                    onViewAll: {},
                    itemTitle: { $0.title },
                    itemAuthor: { $0.author },
                    itemArtwork: { $0.art }
                ) { _ in
                    SubscribeButton(state: .idle) {}
                }
            }
            .padding(Spacing.gutter)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.groupedBg)
    }
}

#Preview("Result shelf — light") {
    ResultShelfPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Result shelf — dark") {
    ResultShelfPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}
#endif
