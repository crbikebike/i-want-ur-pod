// Translated from design/kit/screens/search-typing.html (.sug row) +
// search-results.html (.reslist / .list grouped-inset surface). The compact
// search row (art + bold-matched name + publisher + trailing slot) and its
// iOS grouped-inset list container, shared by the Suggestions list
// (search-typing.html) and the "More shows" list (search-results.html,
// which reuses the `.sug` rhythm with a circular subscribe trailing slot
// per its `.reslist .sub` override, lines 660–664).
import SwiftUI
import DesignSystem
#if DEBUG
import DirectoryKit
#endif

// MARK: - Row (.sug)

/// One compact search result row: 40×40 artwork, title (with an optional
/// bold-matched leading run) + author, and a caller-supplied trailing slot
/// (a chevron for Suggestions, a `SubscribeButton` for "More shows").
///
/// Kit: `.sug` — `gap: 12px`, `padding: 8px 12px`, `min-height: 56px`;
/// `.sug-av` is a 40×40 tile at `border-radius: 10px` (no matching token
/// exists in `Radius` — the closest is `Radius.rSm12` (12), used here).
/// `.sug .t` is `.98rem/600` (`Typography.rowTitleStyle` is the closest
/// existing type token) with `.sug .t b { font-weight: 800 }` for the
/// bold-matched run; `.sug .s` is `.8rem/500 text-dim`
/// (`Typography.subheadStyle`).
public struct SearchResultRow<Trailing: View>: View {
    private let title: String
    private let author: String
    private let artworkURL: URL?
    private let matchPrefix: String?
    private let trailing: () -> Trailing

    @Environment(\.palette) private var palette

    /// - Parameters:
    ///   - title: The show title (`.sug .t`).
    ///   - author: The show author/publisher (`.sug .s`).
    ///   - artworkURL: Remote artwork URL, if any (falls back to a seeded
    ///     gradient tile via `RemoteArtwork`).
    ///   - matchPrefix: When the title case-insensitively starts with this
    ///     string, that leading run renders bold (kit `.sug .t b`) and the
    ///     remainder renders at normal weight. Pass `nil` for a plain title.
    ///   - trailing: The trailing slot — a chevron for Suggestions, a
    ///     `SubscribeButton` for "More shows".
    public init(
        title: String,
        author: String,
        artworkURL: URL? = nil,
        matchPrefix: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.author = author
        self.artworkURL = artworkURL
        self.matchPrefix = matchPrefix
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .center, spacing: Spacing.sp3) {
            RemoteArtwork(url: artworkURL, seed: seed, initial: initial, cornerRadius: Radius.rSm12)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.sp1) {
                titleText
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !author.isEmpty {
                    Text(author)
                        .typeStyle(Typography.subheadStyle)
                        .foregroundStyle(palette.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(.horizontal, Spacing.sp3)
        .padding(.vertical, Spacing.sp2)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(author)")
    }

    // MARK: - Title (bold-matched run)

    @ViewBuilder private var titleText: some View {
        if let matchPrefix, !matchPrefix.isEmpty,
           let matchRange = title.range(of: matchPrefix, options: [.caseInsensitive, .anchored]) {
            let matched = String(title[title.startIndex..<matchRange.upperBound])
            let remainder = String(title[matchRange.upperBound...])

            (
                Text(matched).fontWeight(.bold)
                + Text(remainder)
            )
            .typeStyle(Typography.rowTitleStyle)
            .foregroundStyle(palette.text)
        } else {
            Text(title)
                .typeStyle(Typography.rowTitleStyle)
                .foregroundStyle(palette.text)
        }
    }

    // MARK: - Artwork fallback idiom (mirrors PodcastsScreen.PodcastRow)

    private var seed: Int {
        title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    }

    private var initial: String {
        guard let first = title.first(where: { !$0.isWhitespace }) else { return "?" }
        return String(first).uppercased()
    }
}

// MARK: - Grouped inset list container (.list)

/// The kit's grouped-inset surface (`.list`): a `palette.surface` card,
/// `Radius.rLg20` corners, clipped, with a soft drop shadow approximating
/// `0 1px 0 hairline, 0 8px 24px -18px black`. Rows are supplied by
/// `row(_:)` and separated by a hairline inset to clear the 40pt artwork
/// (kit `.sug:not(:last-child)::after { left: 64px }`).
public struct GroupedList<Item, ID: Hashable, RowContent: View>: View {
    private let items: [Item]
    private let id: KeyPath<Item, ID>
    private let row: (Item) -> RowContent

    @Environment(\.palette) private var palette

    public init(
        items: [Item],
        id: KeyPath<Item, ID>,
        @ViewBuilder row: @escaping (Item) -> RowContent
    ) {
        self.items = items
        self.id = id
        self.row = row
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(items, id: id) { item in
                row(item)

                if item[keyPath: id] != items.last?[keyPath: id] {
                    Divider()
                        .overlay(palette.separator)
                        .padding(.leading, 64)
                }
            }
        }
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous)
                .strokeBorder(palette.hairline, lineWidth: 1)
        )
        .shadow(color: Color(hex: 0x000000, alpha: 0.28), radius: 12, x: 0, y: 8)
    }
}

// MARK: - Preview

#if DEBUG
private struct SearchResultRowPreviewHost: View {
    @Environment(\.palette) private var palette

    private var results: [SearchResult] {
        Array(DiscoverViewModel.sampleResults.prefix(3))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sp6) {
                GroupedList(items: results, id: \.id) { result in
                    SearchResultRow(
                        title: result.title,
                        author: result.author,
                        artworkURL: result.artworkURL,
                        matchPrefix: result.id == results.first?.id ? "Acqu" : nil
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textFaint)
                            .accessibilityHidden(true)
                    }
                }

                GroupedList(items: results, id: \.id) { result in
                    SearchResultRow(
                        title: result.title,
                        author: result.author,
                        artworkURL: result.artworkURL
                    ) {
                        SubscribeButton(state: .idle) {}
                    }
                }
            }
            .padding(Spacing.gutter)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.groupedBg)
    }
}

#Preview("Search result row — dark") {
    SearchResultRowPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}
#endif
