// The one adaptive Podcast Detail screen (navigation-map.md). Composed from
// docs/design/direction.md tokens + existing DesignSystem primitives — there
// is no design/kit mock for this screen (see design/kit/MANIFEST.md).
//
// Show-level description: `Podcast.summary` (feed-field-mapping.md's Podcast
// table — `<channel><description>` → `<channel><itunes:summary>` → `""`) is
// rendered here via the reusable `ExpandableText` component
// (Components/ExpandableText.swift), which also backs each episode's
// `summary` in `EpisodeRow` below.
import SwiftUI
import SwiftData
import DesignSystem
import PodcastModels
import DownloadKit
import PlaybackKit

/// Presents a loaded/loading/error `PodcastDetailViewModel`: large artwork,
/// title, author/publisher, a Subscribe control (E2-S2), and the episode list
/// newest-first with played markers / remaining-time hints (E2-S3 shell).
public struct PodcastDetailView: View {
    @State private var viewModel: PodcastDetailViewModel

    @Environment(\.palette) private var palette

    public init(viewModel: PodcastDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Spacing.gutter)
                .padding(.top, Spacing.sp5)
                .padding(.bottom, AppShell.tabBarReservedPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.groupedBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(navigationTitleText)
    }

    private var navigationTitleText: String {
        if case .loaded(let podcast) = viewModel.state { return podcast.title }
        return "Podcast"
    }

    // MARK: - State-driven body

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            loadingState

        case .error(let message):
            EmptyStateView(
                kind: .error,
                title: "Couldn't load this show",
                message: message
            ) {
                PrimaryButton(title: "Retry") {
                    Task { await viewModel.load() }
                }
            }
            .frame(maxWidth: .infinity)

        case .loaded(let podcast):
            loadedState(podcast)
        }
    }

    private var loadingState: some View {
        LoadingSkeleton(shelves: 1)
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .top)
    }

    private func loadedState(_ podcast: Podcast) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sp6) {
            header(podcast)
            descriptionSection(podcast)
            episodesSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Description (show-level summary, E2-S1)

    @ViewBuilder
    private func descriptionSection(_ podcast: Podcast) -> some View {
        if !podcast.summary.isEmpty {
            ExpandableText(podcast.summary, collapsedLineLimit: 4)
        }
    }

    // MARK: - Header (artwork, title, author/publisher, subscribe)

    private func header(_ podcast: Podcast) -> some View {
        HStack(alignment: .top, spacing: Spacing.sp4) {
            RemoteArtwork(
                url: podcast.artworkURL,
                seed: seed(for: podcast.title),
                initial: initial(for: podcast.title),
                cornerRadius: Radius.rMd16
            )
            .frame(width: 132, height: 132)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.sp2) {
                Text(podcast.title)
                    .typeStyle(Typography.sectionStyle)
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)

                if !podcast.author.isEmpty {
                    Text(podcast.author)                       // publisher/author (E2-S1 "hosts" note)
                        .typeStyle(Typography.subheadStyle)
                        .foregroundStyle(palette.textDim)
                }

                if !podcast.category.isEmpty {
                    Text(podcast.category)
                        .typeStyle(Typography.tagStyle)
                        .foregroundStyle(palette.accent2)
                }

                subscribeControl
                    .padding(.top, Spacing.sp2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var subscribeControl: some View {
        HStack(spacing: Spacing.sp3) {
            SubscribeButton(state: viewModel.isSubscribed ? .subscribed : .idle) {
                viewModel.toggleSubscribe()
            }
            Text(viewModel.isSubscribed ? "Subscribed" : "Subscribe")
                .typeStyle(Typography.subheadStyle)
                .foregroundStyle(viewModel.isSubscribed ? palette.accent2 : palette.textDim)
        }
    }

    // MARK: - Episodes (E2-S1 list, E2-S3 played markers)

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sp1) {
            SectionHeader(title: "Episodes", count: viewModel.episodes.count)

            if viewModel.episodes.isEmpty {
                Text("No episodes yet.")
                    .typeStyle(Typography.bodyStyle)
                    .foregroundStyle(palette.textFaint)
            } else {
                VStack(spacing: Spacing.sp4) {
                    ForEach(viewModel.episodes, id: \.id) { episode in
                        VStack(spacing: Spacing.sp4) {
                            EpisodeRow(episode: episode, artworkURL: viewModel.artworkURL(for: episode))
                            Divider().overlay(palette.hairline)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func seed(for title: String) -> Int {
        title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    }

    private func initial(for title: String) -> String {
        guard let first = title.first(where: { !$0.isWhitespace }) else { return "?" }
        return String(first).uppercased()
    }
}

// MARK: - Episode row (E2-S1 list item, E2-S3 played marker / remaining hint,
// E4-S1 download control)

struct EpisodeRow: View {
    let episode: Episode
    let artworkURL: URL?

    /// Whether the Play affordance renders for `episode` — the exact
    /// predicate `playControl` below switches on. Exposed as a static, pure
    /// function (rather than left inline) so `IWantUrPodTests` can assert
    /// "Play offered iff downloaded" against the real rendering condition
    /// without a view-inspection dependency. Not `private`/`fileprivate` (and
    /// the type itself no longer `private`) for the same reason.
    static func isPlayOffered(for episode: Episode) -> Bool {
        episode.downloadState.isDownloaded
    }

    @Environment(\.palette) private var palette
    @Environment(\.modelContext) private var modelContext
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(PlaybackEngine.self) private var playbackEngine
    @Environment(QueueStore.self) private var queueStore

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sp3) {
            RemoteArtwork(url: artworkURL, seed: seed, initial: initial)
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.sp1) {
                Text(episode.title)
                    .typeStyle(Typography.rowTitleStyle)
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !episode.summary.isEmpty {
                    ExpandableText(episode.summary, collapsedLineLimit: 3)
                }

                playedMarker
                HStack(spacing: Spacing.sp2) {
                    downloadControl
                    playControl
                }
                .padding(.top, Spacing.sp1)
                queueControl
                    .padding(.top, Spacing.sp1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// Played marker / remaining-time hint (E2-S3 shell, made live by E4-S2's
    /// writes to `Episode.playbackProgress`). Reads `Episode.isPlayed`
    /// (model-computed, ≥0.98) and `Episode.remainingTime` directly — no
    /// duplicated threshold logic here.
    @ViewBuilder
    private var playedMarker: some View {
        HStack(spacing: Spacing.sp1) {
            if episode.isPlayed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(palette.accent2)
                    .font(.system(size: 12, weight: .bold))
                Text("Played")
                    .typeStyle(Typography.subheadStyle)
                    .foregroundStyle(palette.textFaint)
            } else {
                Text(remainingLabel)
                    .typeStyle(Typography.subheadStyle)
                    .foregroundStyle(palette.textFaint)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Play control (E4-S2)
    //
    // Composed from tokens — no design/kit mock for this affordance (see
    // design/kit/MANIFEST.md's Podcast Detail entry, which already covers
    // this file as composed rather than kit-translated). Play is offered
    // **iff** the episode is downloaded (playback-state-machine.md's
    // download-first guard); otherwise only the Download control above
    // shows.
    @ViewBuilder
    private var playControl: some View {
        if Self.isPlayOffered(for: episode) {
            if isCurrentAndPlaying {
                SecondaryButton(title: "Pause") { playbackEngine.pause() }
            } else if isCurrentAndPaused {
                PrimaryButton(title: "Resume") { playbackEngine.resume() }
            } else {
                PrimaryButton(title: "Play") { playbackEngine.load(episode: episode, context: modelContext) }
            }
        }
    }

    private var isCurrentEpisode: Bool {
        playbackEngine.currentEpisode?.id == episode.id
    }

    private var isCurrentAndPlaying: Bool {
        isCurrentEpisode && playbackEngine.state == .playing
    }

    private var isCurrentAndPaused: Bool {
        isCurrentEpisode && playbackEngine.state == .paused
    }

    // MARK: - Download control (E4-S1)
    //
    // Composed from tokens — no design/kit mock for this affordance (see
    // design/kit/MANIFEST.md's Podcast Detail entry). Play itself is E4-S2's
    // responsibility (playback-state-machine.md: Play is offered only when
    // `.downloaded`); this row never offers Play, only Download/Downloaded.
    @ViewBuilder
    private var downloadControl: some View {
        switch episode.downloadState {
        case .notDownloaded:
            SecondaryButton(title: "Download") { startDownload() }

        case .downloading(let progress):
            HStack(spacing: Spacing.sp2) {
                ProgressView(value: progress)
                    .tint(palette.accent)
                    .frame(width: 72)
                Text("\(Int((progress * 100).rounded()))%")
                    .typeStyle(Typography.subheadStyle)
                    .foregroundStyle(palette.textFaint)
            }

        case .downloaded:
            HStack(spacing: Spacing.sp1) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(palette.accent2)
                    .font(.system(size: 12, weight: .bold))
                Text("Downloaded")
                    .typeStyle(Typography.subheadStyle)
                    .foregroundStyle(palette.textFaint)
            }

        case .failed(let message):
            HStack(spacing: Spacing.sp2) {
                SecondaryButton(title: "Retry") { startDownload() }
                if let message {
                    Text(message)
                        .typeStyle(Typography.subheadStyle)
                        .foregroundStyle(palette.textFaint)
                        .lineLimit(1)
                }
            }
        }
    }

    private func startDownload() {
        Task { await downloadManager.download(episode, context: modelContext) }
    }

    // MARK: - Add to Up Next (E5-S1)
    //
    // Composed from tokens — no design/kit mock for this affordance (same
    // precedent as the download/play controls above). Tapping Play (above)
    // never requires an episode to be queued first — queue-semantics.md:
    // "an episode can therefore be 'currently playing' without ever having
    // been queued." This control is purely additive to the Up Next list.
    @ViewBuilder
    private var queueControl: some View {
        if queueStore.isQueued(episode) {
            HStack(spacing: Spacing.sp1) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(palette.accent2)
                    .font(.system(size: 12, weight: .bold))
                Text("In Up Next")
                    .typeStyle(Typography.subheadStyle)
                    .foregroundStyle(palette.textFaint)
            }
        } else {
            GhostButton(title: "Add to Up Next") {
                queueStore.add(episode)
            }
        }
    }

    /// "N min left" from `Episode.remainingTime` — the E2-S3 shell hint,
    /// real once E4-S2/S3 start writing `playbackProgress`.
    private var remainingLabel: String {
        let minutes = max(Int((episode.remainingTime / 60).rounded()), 0)
        return "\(minutes) min left"
    }

    private var seed: Int {
        episode.guid.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    }

    private var initial: String {
        guard let first = episode.title.first(where: { !$0.isWhitespace }) else { return "?" }
        return String(first).uppercased()
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
private func previewPodcast(isSubscribed: Bool, in context: ModelContext) -> Podcast {
    let podcast = Podcast(
        title: "Behind the Bastards",
        author: "Cool Zone Media",
        feedURL: URL(string: "https://feeds.example.com/bastards")!,
        artworkURL: nil,
        category: "History",
        summary: """
        A deep dive into the worst people in history and the terrible things \
        they did, told with equal parts rage and dark comedy. Every episode \
        traces one figure's rise from ordinary grievance to full-blown \
        catastrophe.
        """,
        isSubscribed: isSubscribed
    )
    let episodes = [
        Episode(
            guid: "ep-3",
            title: "The Fall of the Grifter King, Part Three",
            summary: """
            In our finale, the empire collapses under the weight of its own \
            paperwork. We trace the last six months through court filings, \
            leaked emails, and one extremely ill-advised podcast appearance \
            that started this whole investigation in the first place.
            """,
            publishDate: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 3600,
            audioURL: URL(string: "https://cdn.example.com/ep3.mp3")!,
            playbackProgress: 1.0,
            podcast: podcast
        ),
        Episode(
            guid: "ep-2",
            title: "The Fall of the Grifter King, Part Two",
            summary: "The middle chapter, where things get worse.",
            publishDate: Date(timeIntervalSince1970: 1_699_000_000),
            duration: 3200,
            audioURL: URL(string: "https://cdn.example.com/ep2.mp3")!,
            playbackProgress: 0.4,
            podcast: podcast
        ),
        Episode(
            guid: "ep-1",
            title: "The Fall of the Grifter King, Part One",
            summary: "",
            publishDate: Date(timeIntervalSince1970: 1_698_000_000),
            duration: 2800,
            audioURL: URL(string: "https://cdn.example.com/ep1.mp3")!,
            podcast: podcast
        )
    ]
    podcast.episodes = episodes
    context.insert(podcast)
    for episode in episodes { context.insert(episode) }
    return podcast
}

@MainActor
private func makePreviewModelContext() -> ModelContext {
    ModelContext(ModelSchema.previewContainer())
}

#Preview("Podcast detail — unsubscribed (dark)") {
    let context = makePreviewModelContext()
    let podcast = previewPodcast(isSubscribed: false, in: context)
    NavigationStack {
        PodcastDetailView(viewModel: PodcastDetailViewModel(previewPodcast: podcast, modelContext: context))
    }
    .themedPalette()
    .environment(DownloadManager())
    .environment(PlaybackEngine(localURLResolver: { _ in nil }))
    .environment(QueueStore(context: context))
    .environment(\.colorScheme, .dark)
}

#Preview("Podcast detail — subscribed (dark)") {
    let context = makePreviewModelContext()
    let podcast = previewPodcast(isSubscribed: true, in: context)
    NavigationStack {
        PodcastDetailView(viewModel: PodcastDetailViewModel(previewPodcast: podcast, modelContext: context))
    }
    .themedPalette()
    .environment(DownloadManager())
    .environment(PlaybackEngine(localURLResolver: { _ in nil }))
    .environment(QueueStore(context: context))
    .environment(\.colorScheme, .dark)
}

#Preview("Podcast detail — unsubscribed (light)") {
    let context = makePreviewModelContext()
    let podcast = previewPodcast(isSubscribed: false, in: context)
    NavigationStack {
        PodcastDetailView(viewModel: PodcastDetailViewModel(previewPodcast: podcast, modelContext: context))
    }
    .themedPalette()
    .environment(DownloadManager())
    .environment(PlaybackEngine(localURLResolver: { _ in nil }))
    .environment(QueueStore(context: context))
    .environment(\.colorScheme, .light)
}

#Preview("Podcast detail — subscribed (light)") {
    let context = makePreviewModelContext()
    let podcast = previewPodcast(isSubscribed: true, in: context)
    NavigationStack {
        PodcastDetailView(viewModel: PodcastDetailViewModel(previewPodcast: podcast, modelContext: context))
    }
    .themedPalette()
    .environment(DownloadManager())
    .environment(PlaybackEngine(localURLResolver: { _ in nil }))
    .environment(QueueStore(context: context))
    .environment(\.colorScheme, .light)
}

#Preview("Podcast detail — loading (dark)") {
    let context = makePreviewModelContext()
    NavigationStack {
        PodcastDetailView(viewModel: PodcastDetailViewModel(previewState: .loading, modelContext: context))
    }
    .themedPalette()
    .environment(DownloadManager())
    .environment(PlaybackEngine(localURLResolver: { _ in nil }))
    .environment(QueueStore(context: context))
    .environment(\.colorScheme, .dark)
}

#Preview("Podcast detail — error (dark)") {
    let context = makePreviewModelContext()
    NavigationStack {
        PodcastDetailView(viewModel: PodcastDetailViewModel(
            previewState: .error("Check your connection and try again."),
            modelContext: context
        ))
    }
    .themedPalette()
    .environment(DownloadManager())
    .environment(PlaybackEngine(localURLResolver: { _ in nil }))
    .environment(QueueStore(context: context))
    .environment(\.colorScheme, .dark)
}
#endif
