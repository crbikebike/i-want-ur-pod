// Translated from design/kit/screens/podcast-detail-american-history-tellers.html
// (real-data + story arcs — the "Season 97", `S97 · E5` case) with the
// no-season graceful-degrade variant from
// design/kit/screens/podcast-detail-explorers-podcast.html (`arc · Part N`,
// no season badge). Both are the same anatomy (`pd-*` header, `arc-*` shelf,
// `ep-*` rows) over the shared kit chrome — see design/kit/MANIFEST.md's
// Podcast Detail entry. Header (artwork/title/author/category/Subscribe) and
// the description clamp were already close to the kit and are unchanged;
// the story-arcs shelf and the episode rows' compact icon controls below are
// this reconciliation's new ground (docs/design/direction.md §11).
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
/// title, author/publisher, a Subscribe control (E2-S2), a **Story arcs**
/// shelf (when the feed's episode titles derive any — direction.md §11),
/// and the episode list newest-first with played markers / remaining-time
/// hints (E2-S3 shell).
public struct PodcastDetailView: View {
    @State private var viewModel: PodcastDetailViewModel

    /// The Story-arc filter applied to the Episodes list below (kit's
    /// `applyFilter()` / `.arc-card.active`). `nil` = unfiltered (all
    /// episodes). Ephemeral view state only — never persisted on the
    /// view model.
    @State private var selectedArcID: Arc.ID?

    @Environment(\.palette) private var palette
    @Environment(QueueStore.self) private var queueStore

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
            arcsShelf
            episodesSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Description (show-level summary, E2-S1)

    @ViewBuilder
    private func descriptionSection(_ podcast: Podcast) -> some View {
        if !podcast.summary.isEmpty {
            // .pd-desc body + .pd-more toggle.
            ExpandableText(
                podcast.summary.htmlToPlainText(),
                collapsedLineLimit: 4,
                textStyle: Typography.detailBodyStyle,
                actionFont: Typography.expandLabel
            )
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
                Text(podcast.title)                            // .pd-title — UI face, NOT mono
                    .typeStyle(Typography.podcastDetailTitleStyle)
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)

                if !podcast.author.isEmpty {
                    Text(podcast.author)                       // .pd-author
                        .typeStyle(Typography.detailAuthorStyle)
                        .foregroundStyle(palette.textDim)
                }

                if !podcast.category.isEmpty {
                    Text(podcast.category)                     // .pd-cat
                        .typeStyle(Typography.categoryLabelStyle)
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

    // MARK: - Story arcs shelf (direction.md §11: "Add all" queues the whole arc)
    //
    // Translated from the kit's `.arc-rail` / `.arc-card` (both podcast-detail-*
    // mocks share this markup — AHT's cards show a "Season N" badge because its
    // feed sets `<itunes:season>`; Explorers' don't, and the badge is simply
    // omitted, matching the kit's graceful degrade). Hidden entirely when no
    // arcs derive from the episode titles (singles-only feeds look like today).
    @ViewBuilder
    private var arcsShelf: some View {
        if !viewModel.arcs.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sp1) {
                SectionHeader(title: "Story arcs")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Spacing.sp3) {
                        ForEach(viewModel.arcs) { arc in
                            ArcCard(
                                arc: arc,
                                artworkURL: viewModel.artworkURL(for: arc.episodes[0]),
                                isAdded: arc.episodes.allSatisfy { queueStore.isQueued($0) },
                                isSelected: selectedArcID == arc.id,
                                onSelect: {
                                    // Tap the card body to filter Episodes to this
                                    // arc; tap the active card again to clear
                                    // (kit's applyFilter() toggle).
                                    selectedArcID = (selectedArcID == arc.id) ? nil : arc.id
                                }
                            ) {
                                // Queue oldest-first so playback proceeds Part 1 → N,
                                // even though `arc.episodes` itself is newest-first
                                // (matching the main episode list's ordering).
                                for episode in arc.episodes.reversed() {
                                    queueStore.add(episode)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)   // optical inset matching SectionHeader
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Episodes (E2-S1 list, E2-S3 played markers)

    /// The Story-arc filter's selected arc (`nil` when unfiltered) — used both
    /// to compute `shownEpisodes` and to render the `Showing: <arc> ✕` chip.
    private var selectedArc: Arc? {
        selectedArcID.flatMap { id in viewModel.arcs.first { $0.id == id } }
    }

    /// Episodes shown below: the selected arc's own episodes (already
    /// newest-first, matching `viewModel.episodes`' ordering — see the
    /// "Add all" comment above) when a filter is active, otherwise the full
    /// library. The app has no row limit, so this is the whole filtered set —
    /// docs/design/arc-filter.md's note on ignoring the kit's `.ep-extra`
    /// hidden-row mock.
    private var shownEpisodes: [Episode] {
        selectedArc?.episodes ?? viewModel.episodes
    }

    /// The Episodes header: title + count pill when unfiltered (unchanged,
    /// via the frozen `SectionHeader(title:count:)`); title + `Showing: <arc>
    /// ✕` chip (kit `.ep-filter`) when a Story-arc filter is active.
    /// `SectionHeader` has no trailing-accessory slot, so the filtered state
    /// renders the title-only variant with the chip placed beside it.
    @ViewBuilder
    private var episodesHeader: some View {
        if let selectedArc {
            HStack(alignment: .center, spacing: Spacing.sp2) {
                SectionHeader(title: "Episodes")
                Spacer(minLength: 0)
                filterChip(for: selectedArc)
                    .padding(.top, Spacing.sp1)   // roughly aligns with SectionHeader's own bottom inset
            }
        } else {
            SectionHeader(title: "Episodes", count: viewModel.episodes.count)
        }
    }

    /// `.ep-filter` — an accent-2 tinted pill mirroring `SectionHeader`'s
    /// private `CountPill` recipe (accent-2 text on a 15% accent-2 tint,
    /// `Typography.countBadge`, `4×10` padding, pill radius), plus a trailing
    /// "✕" glyph. Tapping it clears the filter, same as tapping the active
    /// card again.
    private func filterChip(for arc: Arc) -> some View {
        Button {
            selectedArcID = nil
        } label: {
            HStack(spacing: 6) {
                Text("Showing: \(arc.name)")
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .heavy))
            }
            .font(Typography.countBadge)
            .foregroundStyle(palette.accent2)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(palette.accent2.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear filter")
    }

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sp1) {
            episodesHeader

            if viewModel.episodes.isEmpty {
                Text("No episodes yet.")
                    .typeStyle(Typography.bodyStyle)
                    .foregroundStyle(palette.textFaint)
            } else {
                VStack(spacing: Spacing.sp4) {
                    ForEach(shownEpisodes, id: \.id) { episode in
                        let arcInfo = viewModel.arcInfo(for: episode)
                        VStack(spacing: Spacing.sp4) {
                            EpisodeRow(
                                episode: episode,
                                artworkURL: viewModel.artworkURL(for: episode),
                                arcName: arcInfo.arcName,
                                displayTitle: arcInfo.displayTitle,
                                part: arcInfo.part
                            )
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

// MARK: - Arc card (`.arc-card` — cover + optional season badge, name, count, Add all)

private struct ArcCard: View {
    let arc: Arc
    let artworkURL: URL?
    let isAdded: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onAddAll: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sp2) {   // .arc-card { gap: 8px }
            // Tap target: cover + name + count only — the "Add all" button
            // below stays outside so it keeps consuming its own tap (kit
            // stops the click from bubbling; a SwiftUI Button already does).
            VStack(alignment: .leading, spacing: Spacing.sp2) {
                cover

                Text(arc.name)                                    // .arc-name
                    .typeStyle(Typography.arcCardTitleStyle)
                    .foregroundStyle(palette.text)
                    // .arc-name { min-height: 2.3em; -webkit-line-clamp: 2 } — always
                    // reserve two lines so a one-line arc name occupies the same
                    // height as a two-line one, keeping the count + "Add all" button
                    // aligned across cards in the rail.
                    .lineLimit(2, reservesSpace: true)

                Text("\(arc.episodes.count) episodes")            // .arc-parts
                    .typeStyle(Typography.arcCardMetaStyle)
                    .foregroundStyle(palette.textDim)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
            .accessibilityLabel("Filter episodes to \(arc.name)")

            addAllButton
        }
        .padding(Spacing.sp3)                                  // .arc-card { padding: --sp-3 }
        .frame(width: 176, alignment: .leading)               // .arc-card { width: 176px }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
        .elevList(hairline: palette.hairline)                 // --elev-list: surface float
        .overlay {
            // .arc-card.active { box-shadow: inset 0 0 0 2px var(--accent) } —
            // an inset ring, so `strokeBorder` (draws inward) rather than `stroke`.
            if isSelected {
                RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous)
                    .strokeBorder(palette.accent, lineWidth: 2)
            }
        }
    }

    /// `.arc-cover` — a 16:10 cover-cropped image (falling back to the seeded
    /// gradient tile) with an inset white hairline and the optional season badge.
    /// Can't reuse `RemoteArtwork`, which hard-forces a square aspect.
    private var cover: some View {
        RoundedRectangle(cornerRadius: Radius.rSm12, style: .continuous)
            .fill(ArtworkStyle(seed: seed).gradient)          // fallback (no image yet / nil)
            .overlay {
                if let artworkURL {
                    AsyncImage(url: artworkURL) { image in
                        image.resizable().scaledToFill()      // background-size: cover
                    } placeholder: {
                        Color.clear                           // gradient shows through
                    }
                }
            }
            .aspectRatio(16.0 / 10.0, contentMode: .fit)      // .arc-cover { aspect-ratio: 16/10 }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Radius.rSm12, style: .continuous))
            .overlay {                                        // inset 0 0 0 .5px rgba(255,255,255,.14)
                RoundedRectangle(cornerRadius: Radius.rSm12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
            }
            .overlay(alignment: .topLeading) { seasonBadge }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var seasonBadge: some View {
        if let season = arc.season {                          // .arc-season
            Text("Season \(season)")
                .typeStyle(Typography.seasonBadgeStyle)       // .arc-season .68rem/800, title-case
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.sp2)            // 3px 8px
                .padding(.vertical, 3)
                .background(Color(hex: 0x0A070E, alpha: 0.62), in: Capsule())
                .padding(Spacing.sp2)                         // top: 8px, left: 8px
        }
    }

    /// `.arc-add` — a filled 135° accent→accent-2 gradient pill (not a tinted
    /// outline). Added state flips to a `--chip` fill with `--accent-2` text.
    private var addAllButton: some View {
        Button(action: onAddAll) {
            HStack(spacing: 6) {                              // .arc-add { gap: 6px }
                Image(systemName: "plus")                     // .arc-add svg — kit 15×15
                    .font(.system(size: 15, weight: .heavy))
                Text(isAdded ? "Added" : "Add all \(arc.episodes.count)")
                    .typeStyle(Typography.arcAddLabelStyle)    // .arc-add .8rem/800, no tracking
                    .lineLimit(1)
            }
            .foregroundStyle(isAdded ? palette.accent2 : palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 34)        // .arc-add { height: 34px }
            .background {
                if isAdded {
                    Capsule(style: .continuous).fill(palette.chip)
                } else {
                    // linear-gradient(135deg, accent, color-mix(accent 55%, accent-2))
                    Capsule(style: .continuous).fill(
                        LinearGradient(
                            // color-mix(in srgb, accent 55%, accent-2) — 45% toward accent-2.
                            colors: [palette.accent, palette.accent.mix(with: palette.accent2, by: 0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
        }
        .buttonStyle(ArcAddPressStyle())                      // .arc-add:active { scale .94 }
        .accessibilityLabel(isAdded ? "Added all \(arc.episodes.count) episodes" : "Add all \(arc.episodes.count) episodes")
    }

    private var seed: Int {
        arc.name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    }

    private var initial: String {
        guard let first = arc.name.first(where: { !$0.isWhitespace }) else { return "?" }
        return String(first).uppercased()
    }
}

/// `.arc-add:active { transform: scale(.94) }` — press feedback for the Add-all pill.
private struct ArcAddPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(Motion.easeSpring(), value: configuration.isPressed)
    }
}

// MARK: - Episode row (E2-S1 list item, E2-S3 played marker / remaining hint,
// E4-S1 download control, direction.md §11 arc/season/episode meta)

struct EpisodeRow: View {
    let episode: Episode
    let artworkURL: URL?

    /// Arc presentation info (`PodcastDetailViewModel.arcInfo(for:)`): `nil`
    /// arcName for a single. `displayTitle` is the arc-stripped title shown
    /// as this row's title (so rows read "A Devil of a Whipping", not
    /// "American Revolution | A Devil of a Whipping | 5" — the kit's rows
    /// show the bare episode title, with the arc surfaced separately in the
    /// meta line below). `part` is the title-derived part number, used as a
    /// fallback in the meta line when the feed has no `<itunes:episode>`
    /// (the Explorers graceful-degrade case: "Part 4" instead of "E4").
    let arcName: String?
    let displayTitle: String
    let part: Int?

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
                Text(displayTitle)                             // .ep-title
                    .typeStyle(Typography.episodeTitleStyle)
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                metaLine

                if !episode.summary.isEmpty {
                    ExpandableText(episode.summary.htmlToPlainText(), collapsedLineLimit: 3)
                }

                playedMarker

                HStack(spacing: Spacing.sp3) {
                    downloadControl
                    playControl
                    queueControl
                }
                .padding(.top, Spacing.sp1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Meta line (`.ep-meta` — arc · S·E/Part · date · duration)
    //
    // Translated from the kit's `.ep-meta`/`.ep-arc`: `arc · S3 · E5 · Jul 1,
    // 2026 · 41 min` when the feed sets season+episode (AHT); `arc · Part 4 ·
    // date · min` when it doesn't (Explorers); missing segments are omitted
    // gracefully rather than rendering empty dots.
    @ViewBuilder
    private var metaLine: some View {
        let segments = metaSegments
        if !segments.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Text("·")                              // .ep-meta separator
                            .typeStyle(Typography.episodeMetaStyle)
                            .foregroundStyle(palette.textFaint)
                    }
                    // `.ep-arc` is `.ep-meta` at weight 800 in accent-2; other
                    // segments are the plain `.ep-meta` role.
                    Text(segment.text)
                        .typeStyle(segment.isArc ? Typography.metaEmphasisStyle : Typography.episodeMetaStyle)
                        .foregroundStyle(segment.isArc ? palette.accent2 : palette.textDim)
                }
            }
            .lineLimit(1)
        }
    }

    private struct MetaSegment {
        let text: String
        var isArc: Bool = false
    }

    private var metaSegments: [MetaSegment] {
        var segments: [MetaSegment] = []
        if let arcName {
            segments.append(MetaSegment(text: arcName, isArc: true))
        }
        if let season = episode.season {
            segments.append(MetaSegment(text: "S\(season)"))
        }
        if let episodeNumber = episode.episodeNumber {
            segments.append(MetaSegment(text: "E\(episodeNumber)"))
        } else if let part {
            segments.append(MetaSegment(text: "Part \(part)"))
        }
        segments.append(MetaSegment(text: Self.dateFormatter.string(from: episode.publishDate)))
        segments.append(MetaSegment(text: "\(durationMinutes) min"))
        return segments
    }

    private var durationMinutes: Int {
        max(Int((episode.duration / 60).rounded()), 0)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Played marker / remaining-time hint (E2-S3 shell, made live by E4-S2's
    /// writes to `Episode.playbackProgress`). Reads `Episode.isPlayed`
    /// (model-computed, ≥0.98) and `Episode.remainingTime` directly — no
    /// duplicated threshold logic here.
    @ViewBuilder
    private var playedMarker: some View {
        HStack(spacing: Spacing.sp1) {
            if episode.isPlayed {
                Image(systemName: "checkmark.circle.fill")    // .ep-played ✓
                    .foregroundStyle(palette.accent2)
                    .font(.system(size: 12, weight: .bold))
                Text("Played")                                 // .ep-played .72rem/800, accent-2
                    .typeStyle(Typography.shelfBadgeStyle)
                    .foregroundStyle(palette.accent2)
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
    // Translated from the kit's `.ep-btn.play` — a filled accent circle with
    // a play/pause glyph. Play is offered **iff** the episode is downloaded
    // (playback-state-machine.md's download-first guard, `isPlayOffered`
    // above); otherwise this control doesn't render at all (only Download
    // shows). Toggles to a pause glyph while this episode is the one
    // current+playing; a resume tap uses the same play glyph.
    @ViewBuilder
    private var playControl: some View {
        if Self.isPlayOffered(for: episode) {
            if isCurrentAndPlaying {
                EpisodeIconButton(
                    systemImage: "pause.fill",
                    style: .filledAccent,
                    accessibilityLabel: "Pause",
                    action: { playbackEngine.pause() }
                )
            } else if isCurrentAndPaused {
                EpisodeIconButton(
                    systemImage: "play.fill",
                    style: .filledAccent,
                    accessibilityLabel: "Resume",
                    action: { playbackEngine.resume() }
                )
            } else {
                EpisodeIconButton(
                    systemImage: "play.fill",
                    style: .filledAccent,
                    accessibilityLabel: "Play",
                    action: { playbackEngine.load(episode: episode, context: modelContext) }
                )
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
    // Translated from the kit's `.ep-btn.ep-dl` — a compact chip circle that
    // swaps its glyph per `DownloadState`: `arrow.down` (idle) → a circular
    // progress ring (downloading) → a mint checkmark (`.ep-dl.done`,
    // non-interactive) → a retry arrow (failed, with the failure message as
    // a caption underneath when present).
    @ViewBuilder
    private var downloadControl: some View {
        switch episode.downloadState {
        case .notDownloaded:
            EpisodeIconButton(
                systemImage: "arrow.down",
                style: .chip,
                accessibilityLabel: "Download",
                action: startDownload
            )

        case .downloading(let progress):
            ZStack {
                Circle()
                    .fill(palette.chip)
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .tint(palette.accent)
                    .scaleEffect(0.7)
            }
            .frame(width: EpisodeIconButton.diameter, height: EpisodeIconButton.diameter)
            .accessibilityLabel("Downloading, \(Int((progress * 100).rounded())) percent")

        case .downloaded:
            EpisodeIconButton(
                systemImage: "checkmark",
                style: .done,
                accessibilityLabel: "Downloaded",
                action: {}
            )
            .allowsHitTesting(false)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 2) {
                EpisodeIconButton(
                    systemImage: "arrow.clockwise",
                    style: .chip,
                    accessibilityLabel: "Retry download",
                    action: startDownload
                )
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
    // Translated from the kit's `.ep-btn.ep-add` — a plus chip that flips to
    // a mint checkmark once queued. Tapping Play (above) never requires an
    // episode to be queued first — queue-semantics.md: "an episode can
    // therefore be 'currently playing' without ever having been queued."
    // This control is purely additive to the Up Next list.
    @ViewBuilder
    private var queueControl: some View {
        if queueStore.isQueued(episode) {
            EpisodeIconButton(
                systemImage: "checkmark",
                style: .done,
                accessibilityLabel: "In Up Next",
                action: {}
            )
            .allowsHitTesting(false)
        } else {
            EpisodeIconButton(
                systemImage: "plus",
                style: .chip,
                accessibilityLabel: "Add to Up Next",
                action: { queueStore.add(episode) }
            )
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

// MARK: - Compact icon control (`.ep-btn` — shared 38pt circular button)

/// The kit's `.ep-btn`: a 38pt circular icon-only button in one of three
/// roles — a neutral chip fill (Download idle/retry, Add to Up Next idle), a
/// filled accent circle (Play/Pause/Resume), or a mint "done" tint (Downloaded
/// / In Up Next, both non-interactive here).
struct EpisodeIconButton: View {
    enum Style { case chip, filledAccent, done }

    /// The detail screen's `.ep-btn` default; Up Next's `.dl` passes 40.
    static let diameter: CGFloat = 38

    let systemImage: String
    let style: Style
    let diameter: CGFloat
    let accessibilityLabel: String
    let action: () -> Void

    init(
        systemImage: String,
        style: Style,
        diameter: CGFloat = EpisodeIconButton.diameter,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.style = style
        self.diameter = diameter
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: diameter, height: diameter)
                .background(background)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var foreground: Color {
        switch style {
        case .chip: return palette.text
        case .filledAccent: return palette.onAccent
        case .done: return palette.accent2
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .chip:
            Circle().fill(palette.chip)
        case .filledAccent:
            if colorScheme == .dark {
                Circle().fill(
                    LinearGradient(colors: [palette.accent, palette.accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            } else {
                Circle().fill(palette.accent)
            }
        case .done:
            Circle().fill(palette.accent2.opacity(0.16))
        }
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
private func previewPodcast(isSubscribed: Bool, in context: ModelContext) -> Podcast {
    let podcast = Podcast(
        title: "American History Tellers",
        author: "Wondery",
        feedURL: URL(string: "https://feeds.example.com/aht")!,
        artworkURL: nil,
        category: "History",
        summary: """
        The Cold War, Prohibition, the Gold Rush, the Space Race. Every part \
        of your life can be traced to our history — we'll take you to the \
        events, the times, and the people that shaped America, and show you \
        how it still affects you today.
        """,
        isSubscribed: isSubscribed
    )
    let episodes = [
        Episode(
            guid: "ep-5",
            title: "American Revolution | A Devil of a Whipping | 5",
            summary: "The war turns south — and turns brutal.",
            publishDate: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 41 * 60,
            audioURL: URL(string: "https://cdn.example.com/ep5.mp3")!,
            downloadState: .downloaded,
            playbackProgress: 0,
            season: 97,
            episodeNumber: 5,
            podcast: podcast
        ),
        Episode(
            guid: "ep-4",
            title: "American Revolution | Saratoga | 4",
            summary: "A turning-point battle draws France into the war.",
            publishDate: Date(timeIntervalSince1970: 1_699_000_000),
            duration: 39 * 60,
            audioURL: URL(string: "https://cdn.example.com/ep4.mp3")!,
            playbackProgress: 0.4,
            season: 97,
            episodeNumber: 4,
            podcast: podcast
        ),
        Episode(
            guid: "ep-single",
            title: "Foul Play",
            summary: "A bonus short between seasons.",
            publishDate: Date(timeIntervalSince1970: 1_698_500_000),
            duration: 7 * 60,
            audioURL: URL(string: "https://cdn.example.com/ep-single.mp3")!,
            podcast: podcast
        ),
        Episode(
            guid: "ep-3",
            title: "American Revolution | The Times That Try Men's Souls | 3",
            summary: "",
            publishDate: Date(timeIntervalSince1970: 1_698_000_000),
            duration: 37 * 60,
            audioURL: URL(string: "https://cdn.example.com/ep3.mp3")!,
            downloadState: .downloading(progress: 0.6),
            season: 97,
            episodeNumber: 3,
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
