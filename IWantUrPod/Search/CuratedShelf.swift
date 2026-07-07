// Composed from docs/design/direction.md tokens + the DesignSystem
// `RemoteArtwork`/`SubscribeButton`/`SectionHeader` components — no design/kit
// source (E1-S2's curated "start here" section has no separate kit mock; see
// design/kit/MANIFEST.md). Schema + loader behavior:
// docs/spec/curated-list.schema.md.
//
// Deliberately NOT the horizontal gradient `ResultShelf` that search results
// use: the curated list's value over raw search is the editorial `blurb`
// ("why start here?"), and a one-sentence blurb reads far better in a vertical
// card than a 150pt rail cell. So this renders a vertical stack of editorial
// cards, each showing REAL artwork (via `RemoteArtwork`, gradient fallback),
// title, author · category, the corner Subscribe control, and the blurb set
// against a coral→mint gradient hairline — the single accent that marks a card
// as a human pick (echoing the Discover title's pulse-dot), not an algorithm
// result. Behavior matches the search shelf: file order, tap a card → E2
// detail keyed by `feedUrl`, corner Subscribe drives the same state machine.
import SwiftUI
import DesignSystem
import DirectoryKit

struct CuratedShelf: View {
    let entries: [CuratedEntry]
    /// Called the moment an entry is subscribed — the parent persists the show.
    var onSubscribe: (SearchResult) -> Void = { _ in }
    /// Called when a card (not its subscribe button) is tapped.
    var onSelect: (CuratedEntry) -> Void = { _ in }

    @State private var states: [String: SubscribeState] = [:]

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sp3) {
                SectionHeader(
                    title: "Start here",
                    subtitle: "Story-driven picks — a place to begin."
                )

                ForEach(entries) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        CuratedCard(
                            entry: entry,
                            subscribeState: states[entry.id] ?? .idle,
                            onSubscribe: { subscribe(entry) }
                        )
                    }
                    .buttonStyle(.plain)
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
}

// MARK: - Curated card

/// One editorial curated pick: artwork + title + author·category + corner
/// Subscribe, with the `blurb` as the hero beneath, marked by a coral→mint
/// gradient rule. Composed from tokens (`Spacing`/`Radius`/`Typography` +
/// the active `ThemePalette`).
private struct CuratedCard: View {
    let entry: CuratedEntry
    let subscribeState: SubscribeState
    let onSubscribe: () -> Void

    @Environment(\.palette) private var palette

    /// Seed the gradient fallback from the title so a missing/slow artwork URL
    /// still resolves to a stable tile (same scheme as the search shelf).
    private var seed: Int {
        entry.title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    }

    private var initial: String {
        guard let first = entry.title.first(where: { !$0.isWhitespace }) else { return "?" }
        return String(first).uppercased()
    }

    /// "Author · Category" — the category folds into the author line rather
    /// than earning its own row, keeping the blurb the loudest thing on the card.
    private var authorLine: String {
        if let category = entry.category, !category.isEmpty {
            return "\(entry.author) · \(category)"
        }
        return entry.author
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sp3) {
            HStack(alignment: .top, spacing: Spacing.sp3) {
                RemoteArtwork(
                    url: entry.artworkURL,
                    seed: seed,
                    initial: initial,
                    cornerRadius: Radius.rMd16
                )
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .typeStyle(Typography.rowTitleStyle)
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(authorLine)
                        .typeStyle(Typography.subheadStyle)
                        .foregroundStyle(palette.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SubscribeButton(state: subscribeState, action: onSubscribe)
            }

            if let blurb = entry.blurb, !blurb.isEmpty {
                HStack(alignment: .top, spacing: Spacing.sp3) {
                    // The one signature: a coral→mint gradient hairline that
                    // marks this as an editorial pick (echoes the Discover
                    // title's pulse-dot). Stretches to the blurb's height.
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [palette.accent, palette.accent2],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2.5)
                        .accessibilityHidden(true)

                    Text(blurb)
                        .typeStyle(Typography.bodyStyle)
                        .foregroundStyle(palette.textDim)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(Spacing.sp4)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
        .elevList(hairline: palette.hairline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [entry.title, authorLine]
        if let blurb = entry.blurb, !blurb.isEmpty { parts.append(blurb) }
        return parts.joined(separator: ". ")
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
