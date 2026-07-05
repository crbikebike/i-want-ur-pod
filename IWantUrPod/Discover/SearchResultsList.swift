// Translated from design/kit/screens/{first-run,typing}.html results list (.list / .row + .sub).
// The grouped inset results list: a stack of DesignSystem `ResultRow`s on a
// `--surface` card with `--elev-list`, each carrying a trailing `SubscribeButton`
// whose per-row state lives here. Subscribing persists via the `onSubscribe`
// closure the Discover screen supplies (it inserts a Podcast into SwiftData).
import SwiftUI
import DesignSystem
import DirectoryKit

/// The composition of `ResultRow` + `SubscribeButton` for a set of search hits.
///
/// Renders the kit's grouped inset list: rows on a single `--surface` card with
/// `--r-lg` corners and `--elev-list`, hairline separators inset past the 60pt
/// artwork. Each row's subscribe control cycles idle → subscribing → subscribed
/// locally; the transition into subscribing fires `onSubscribe` so the parent can
/// persist the show.
struct SearchResultsList: View {
    let results: [SearchResult]
    /// Called the moment a row is subscribed — the parent persists the show.
    var onSubscribe: (SearchResult) -> Void = { _ in }
    /// Called when a row (not its subscribe button) is tapped.
    var onSelect: (SearchResult) -> Void = { _ in }

    @Environment(\.palette) private var palette
    @State private var states: [String: SubscribeState] = [:]

    private let shape = RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                Button {
                    onSelect(result)
                } label: {
                    ResultRow(
                        title: result.title,
                        author: result.author,
                        artwork: artwork(for: result)
                    ) {
                        SubscribeButton(state: states[result.id] ?? .idle) {
                            subscribe(result)
                        }
                    }
                }
                .buttonStyle(.plain)

                if index < results.count - 1 {
                    // .row::after — inset hairline past the 60pt art + gap.
                    Rectangle()
                        .fill(palette.separator)
                        .frame(height: 0.5)
                        .padding(.leading, Spacing.sp4 + 60 + Spacing.sp3)
                }
            }
        }
        .background(palette.surface, in: shape)
        .clipShape(shape)
        .elevList(hairline: palette.hairline)
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
private struct SearchResultsListPreviewHost: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            SearchResultsList(results: DiscoverViewModel.sampleResults)
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.sp5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.groupedBg)
    }
}

#Preview("Search results — dark") {
    SearchResultsListPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}

#Preview("Search results — light") {
    SearchResultsListPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}
#endif
