// Translated from design/kit/screens/up-next.html — the queue screen's real
// bespoke content: the large "Up Next" title with pulse-dot, the top-right
// `.util-gear` Settings button, the "Queue" `.sec-head` (title + count +
// `.sec-sub` hint), a grouped-inset `.list` of `.row`s (each a `.grip` drag
// handle, 60pt `.art`, `.meta` title/author, and a `.dl` inline download
// control), and the centered `.foot` note — see design/kit/MANIFEST.md's
// "Home / Shows / Up Next screens" entry (up-next.html supersedes this
// screen's earlier composed-no-kit-mock history, ROADMAP.md E8-S5/kit
// reconciliation). The `.tabbar`/`.statusbar`/`.notch`/theme-toggle chrome is
// the shared kit frame AppShell + LiquidGlassTabBar already own, not
// re-translated here.
//
// **Deliberate departure from `List`:** the kit's `.grip` is a dedicated drag
// handle distinct from the row itself, and each row's trailing control is a
// live, tappable download button — neither composes cleanly with `List`'s
// `.onMove` (whole-row drag only) or `.swipeActions` (hides the row's own
// trailing content while swiping). This screen is therefore a hand-built
// `ScrollView`/`VStack` card (mirroring `HomeScreen.swift`'s
// `GroupedRowList` container shape) with:
//   - **Reorder**: a `LongPressGesture(minimumDuration: 0.2).sequenced(before:
//     DragGesture())` on the grip only, translating vertical drag distance
//     into a row-height-quantized index and calling
//     `queueStore.move(fromOffsets:toOffset:)` live as the finger crosses
//     row boundaries (the dragged row lifts/scales slightly rather than a
//     full native reflow — the reorder itself persists correctly).
//   - **Remove**: a `.contextMenu` "Remove from Queue" action on each row
//     (a left-swipe was considered but rejected — this screen has no `List`
//     to host `.swipeActions`, and a hand-rolled swipe gesture would fight
//     the grip's drag gesture for the same rows) → `queueStore.remove(item)`.
// Same underlying `QueueStore` order rules (docs/spec/queue-semantics.md)
// apply either way.
import SwiftUI
import SwiftData
import DesignSystem
import PodcastModels
import DownloadKit
import PlaybackKit

/// The Up Next tab: every queued episode, ordered by `QueueStore.items`
/// (ascending `order` — index 0 plays next). Reads the shared, app-scoped
/// `QueueStore` from the environment (frozen nav contract — never constructs
/// its own store) and reserves the floating tab bar's 104pt gap.
public struct UpNextScreen: View {
    @Environment(QueueStore.self) private var queueStore
    @Environment(\.palette) private var palette

    @State private var path = NavigationPath()

    public init() {}

    public var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if queueStore.items.isEmpty {
                        emptyState
                    } else {
                        populated
                    }
                }

                SettingsGearButton { path.append(SettingsRoute.settings) }
                    .padding(.top, Spacing.sp5)
                    .padding(.trailing, Spacing.gutter)
            }
            .background(palette.groupedBg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SettingsRoute.self) { _ in
                SettingsScreen()
            }
        }
        .onAppear { queueStore.reload() }
    }

    // MARK: - Populated (titlewrap / sec-head / list / foot)

    private var populated: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleBar

                SectionHeader(
                    title: "Queue",
                    count: queueStore.items.count,
                    subtitle: "Drag to reorder. Each row shows whether it's downloaded for offline."
                )

                QueueList(items: queueStore.items)

                footNote
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, AppShell.tabBarReservedPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleBar

                EmptyStateView(
                    kind: .firstRun,
                    title: "Nothing queued",
                    message: "Add an episode from a show's page and it'll play next, in order, right here."
                ) {
                    EmptyView()
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, AppShell.tabBarReservedPadding)
            .frame(maxWidth: .infinity, minHeight: 500, alignment: .top)
        }
    }

    // MARK: - Large title (h1.big) + gear (.util-gear)

    /// Mirrors `HomeScreen.titleBar` verbatim (kit's `.titlewrap` reserves
    /// `padding-right: 52px` so the title never runs under the floating gear
    /// occupying the same row).
    private var titleBar: some View {
        HStack(spacing: Spacing.sp2) {
            Text("Up Next")
                .typeStyle(Typography.displayLargeTitleStyle)
                .foregroundStyle(palette.text)

            Circle()   // .pulse-dot
                .fill(
                    LinearGradient(
                        colors: [palette.accent, palette.accent2],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 11, height: 11)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 2)
        .padding(.trailing, 50)
        .padding(.top, Spacing.sp5)
        .padding(.bottom, Spacing.sp4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Footer note (.foot)

    private var footNote: some View {
        Text("Downloaded episodes are safe to play offline. Manage storage in Settings.")
            .typeStyle(Typography.footnoteStyle)
            .foregroundStyle(palette.textFaint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .padding(.horizontal, 6)
    }
}

// MARK: - Grouped-inset queue list (.list)

/// The kit's `.list` grouped-inset surface card, hand-built (not
/// `HomeScreen`'s `GroupedRowList`, which can't host a leading grip / trailing
/// interactive control / drag) but replicating the same surface/clip/elevation
/// treatment: `palette.surface` fill, `Radius.rLg20` clip, `.elevList`, with
/// inset `Divider`s between rows.
private struct QueueList: View {
    let items: [QueueItem]

    @Environment(QueueStore.self) private var queueStore
    @Environment(\.palette) private var palette

    /// Drag state for the hand-rolled grip-drag reorder (see file header).
    /// `draggingID` is the dragged item's `persistentModelID`; `dragOffset`
    /// is the live vertical translation applied to that row's `.offset`.
    @State private var draggingID: PersistentIdentifier?
    @State private var dragOffset: CGFloat = 0
    /// Measured once per row via `.onAppear`/`GeometryReader`-free constant —
    /// rows are a fixed height by construction (60pt art + fixed vertical
    /// padding), so a single measured height quantizes drag distance into
    /// index deltas without needing per-row geometry.
    @State private var rowHeight: CGFloat = 84

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if let episode = item.episode {
                    QueueRow(
                        episode: episode,
                        isDragging: draggingID == item.persistentModelID,
                        dragOffset: draggingID == item.persistentModelID ? dragOffset : 0,
                        onGripDragChanged: { translation in
                            handleDragChanged(item: item, index: index, translation: translation)
                        },
                        onGripDragEnded: {
                            draggingID = nil
                            dragOffset = 0
                        },
                        onRemove: { queueStore.remove(item) }
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { rowHeight = proxy.size.height }
                        }
                    )
                    .zIndex(draggingID == item.persistentModelID ? 1 : 0)

                    if index != items.count - 1 {
                        Divider()
                            .overlay(palette.separator)
                            .padding(.leading, Spacing.sp4 + 60 + Spacing.sp3)
                    }
                }
            }
        }
        .padding(.top, Spacing.sp3)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
        .elevList(hairline: palette.hairline)
    }

    /// Live-reorders as the finger crosses row boundaries: converts the
    /// current drag translation into a target index (translation ÷ measured
    /// row height, rounded) and calls `queueStore.move` whenever that index
    /// differs from the dragged item's current position.
    private func handleDragChanged(item: QueueItem, index: Int, translation: CGFloat) {
        draggingID = item.persistentModelID
        dragOffset = translation

        guard rowHeight > 0 else { return }
        let delta = Int((translation / rowHeight).rounded())
        guard delta != 0 else { return }

        let targetIndex = max(0, min(items.count - 1, index + delta))
        guard targetIndex != index else { return }

        queueStore.move(fromOffsets: IndexSet(integer: index), toOffset: targetIndex > index ? targetIndex + 1 : targetIndex)
        // The moved row is now at `targetIndex`; re-zero the running
        // translation against its new resting position so the drag continues
        // smoothly rather than jumping.
        dragOffset -= CGFloat(delta) * rowHeight
    }
}

// MARK: - Queue row (.row)

/// One queued episode: `.grip` handle, 60pt `.art`, `.meta` title/subtitle,
/// and the trailing `.dl` download control.
private struct QueueRow: View {
    let episode: Episode
    let isDragging: Bool
    let dragOffset: CGFloat
    let onGripDragChanged: (CGFloat) -> Void
    let onGripDragEnded: () -> Void
    let onRemove: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.modelContext) private var modelContext
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(PlaybackIntentCoordinator.self) private var playbackIntent

    /// Horizontal swipe-to-remove state. `swipeOffset` is the row face's live
    /// x-translation (0 closed, `-removeActionWidth` open); `swipeStart`
    /// snapshots the offset at gesture begin so a drag can resume from an
    /// already-open row.
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeStart: CGFloat?

    /// Width of the revealed trailing Remove action (kit `.row-remove` = 96px).
    private let removeActionWidth: CGFloat = 96

    var body: some View {
        ZStack(alignment: .trailing) {
            removeAction
            rowFace
        }
        .clipped()                       // clip the revealed action + swiped face to the row
        .offset(y: dragOffset)           // vertical reorder lift (grip drag)
        .scaleEffect(isDragging ? 1.02 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.25 : 0), radius: 12, y: 6)
        .animation(.interactiveSpring(), value: isDragging)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(episode.title). \(subtitle)")
        .accessibilityAction(named: "Play") { playbackIntent.play(episode, context: modelContext) }
        .accessibilityAction(named: "Remove from Queue") { onRemove() }
    }

    // MARK: - Row face (.face) — grip · art · meta · [play][download]

    /// The visible row content. Opaque (`palette.surface`) so it occludes the
    /// destructive action behind it until swiped, and offset horizontally by
    /// the live swipe translation. Trailing controls mirror the kit's
    /// `.controls` group: a `PlayButton` beside the download control.
    private var rowFace: some View {
        HStack(alignment: .center, spacing: Spacing.sp3) {
            grip

            RemoteArtwork(url: artworkURL, seed: seed, initial: initial)
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(episode.title)
                    .typeStyle(Typography.rowTitleStyle)
                    .foregroundStyle(palette.text)
                    .lineLimit(1)                    // kit `.rtitle`: white-space: nowrap
                    .truncationMode(.tail)

                Text(subtitle)
                    .typeStyle(Typography.subheadStyle)
                    .foregroundStyle(palette.textDim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Spacing.sp2) {   // .controls
                PlayButton(
                    diameter: 40,
                    accessibilityLabel: "Play \(episode.title)",
                    action: { playbackIntent.play(episode, context: modelContext) }
                )
                downloadControl(for: episode)
            }
        }
        .padding(.horizontal, Spacing.sp4)
        .padding(.vertical, Spacing.sp3)
        .background(palette.surface)
        .contentShape(Rectangle())
        .offset(x: swipeOffset)
        .gesture(swipeGesture)
        .contextMenu {                       // secondary remove path (long-press)
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove from Queue", systemImage: "trash")
            }
        }
    }

    // MARK: - Swipe-to-remove trailing action (.row-remove)

    /// The destructive action revealed by swiping the row left. Pinned to the
    /// trailing edge behind `rowFace`; tapping it (or completing a full swipe)
    /// removes the episode from the queue. Exposed to VoiceOver via the row's
    /// `.accessibilityAction(named: "Remove from Queue")`, so hidden here.
    private var removeAction: some View {
        Button(action: onRemove) {
            VStack(spacing: 3) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                Text("Remove")
                    .typeStyle(Typography.subheadStyle)
                    .fontWeight(.bold)
            }
            .foregroundStyle(.white)
            .frame(width: removeActionWidth)
            .frame(maxHeight: .infinity)
            .background(palette.danger)
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    /// A horizontal-only drag that reveals/hides the trailing Remove action.
    /// Scoped to `rowFace` and gated on horizontal dominance so it does not
    /// fight the grip's long-press vertical reorder gesture or the enclosing
    /// vertical `ScrollView`. Snaps open past half-width; a full swipe removes.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if swipeStart == nil { swipeStart = swipeOffset }
                let start = swipeStart ?? swipeOffset
                swipeOffset = min(0, max(start + value.translation.width, -(removeActionWidth + 44)))
            }
            .onEnded { value in
                let start = swipeStart ?? 0
                swipeStart = nil
                let projected = start + value.translation.width
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    if projected < -(removeActionWidth + 24) {
                        onRemove()                        // full swipe → remove
                    } else if projected < -removeActionWidth / 2 {
                        swipeOffset = -removeActionWidth   // snap open
                    } else {
                        swipeOffset = 0                    // snap closed
                    }
                }
            }
    }

    // MARK: - Grip (.grip) — 2×3 dot drag handle

    /// Kit's `.grip` svg: six `r="1.3"` circles at (6,4)/(10,4)/(6,8)/(10,8)/
    /// (6,12)/(10,12) inside a 16×16 box — a 2-column × 3-row dot grid.
    /// Hosts the reorder gesture: a long press (to disambiguate from
    /// scrolling) sequenced before a drag, whose translation drives
    /// `onGripDragChanged`.
    private var grip: some View {
        VStack(spacing: 2.4) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 2.4) {
                    ForEach(0..<2, id: \.self) { _ in
                        Circle().frame(width: 2.6, height: 2.6)
                    }
                }
            }
        }
        .foregroundStyle(palette.textFaint)
        .opacity(0.6)
        .frame(width: 16, height: 16)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
        .gesture(
            LongPressGesture(minimumDuration: 0.2)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    switch value {
                    case .second(true, let drag):
                        onGripDragChanged(drag?.translation.height ?? 0)
                    default:
                        break
                    }
                }
                .onEnded { _ in
                    onGripDragEnded()
                }
        )
    }

    // MARK: - Download control (E8-S5, reused verbatim)
    //
    // Translated from design/kit/screens/up-next.html's `.dl` row button
    // (idle "download into tray" glyph flipping to a mint done-check) — the
    // same compact circular control as `PodcastDetailView.swift`'s
    // `EpisodeIconButton`/`downloadControl`, reused verbatim (rather than
    // reinvented) so both screens present download state identically. Adds
    // the two states the kit's binary mock collapses into "not done": a
    // spinning progress ring while `.downloading`, and a tappable retry
    // glyph (plus failure message) for `.failed`. Kit's `.dl` is 40pt (not
    // `EpisodeIconButton`'s 38pt detail-screen default).
    @ViewBuilder
    private func downloadControl(for episode: Episode) -> some View {
        switch episode.downloadState {
        case .notDownloaded:
            EpisodeIconButton(
                systemImage: "arrow.down",
                style: .chip,
                diameter: 40,
                accessibilityLabel: "Download",
                action: { startDownload(episode) }
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
            .frame(width: 40, height: 40)
            .accessibilityLabel("Downloading, \(Int((progress * 100).rounded())) percent")

        case .downloaded:
            EpisodeIconButton(
                systemImage: "checkmark",
                style: .done,
                diameter: 40,
                accessibilityLabel: "Downloaded",
                action: {}
            )
            .allowsHitTesting(false)

        case .failed(let message):
            VStack(alignment: .trailing, spacing: 2) {
                EpisodeIconButton(
                    systemImage: "arrow.clockwise",
                    style: .chip,
                    diameter: 40,
                    accessibilityLabel: "Retry download",
                    action: { startDownload(episode) }
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

    private func startDownload(_ episode: Episode) {
        Task { await downloadManager.download(episode, context: modelContext) }
    }

    // MARK: - Row derivations

    /// "Show · duration/time-left".
    private var subtitle: String {
        let show = episode.podcast?.title ?? ""
        guard let duration = HomeFeedProvider.durationLabel(for: episode) else { return show }
        return show.isEmpty ? duration : "\(show) · \(duration)"
    }

    private var artworkURL: URL? {
        episode.remoteArtworkURL ?? episode.podcast?.artworkURL
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
private func previewContainer(populated: Bool) -> ModelContainer {
    let container = ModelSchema.previewContainer()
    if populated {
        let context = ModelContext(container)
        let podcast = Podcast(
            title: "Behind the Bastards",
            author: "Cool Zone Media",
            feedURL: URL(string: "https://feeds.example.com/bastards")!,
            isSubscribed: true
        )
        context.insert(podcast)

        let episodes = [
            Episode(guid: "queue-1", title: "The Fall of the Grifter King, Part One", audioURL: URL(string: "https://cdn.example.com/ep1.mp3")!, downloadState: .downloaded, podcast: podcast),
            Episode(guid: "queue-2", title: "The Fall of the Grifter King, Part Two", audioURL: URL(string: "https://cdn.example.com/ep2.mp3")!, downloadState: .downloading(progress: 0.4), podcast: podcast),
            Episode(guid: "queue-3", title: "A Bonus Episode About Nothing In Particular", audioURL: URL(string: "https://cdn.example.com/ep3.mp3")!, downloadState: .failed(message: "Check your connection and try again."), podcast: podcast)
        ]
        for episode in episodes { context.insert(episode) }
        for (index, episode) in episodes.enumerated() {
            context.insert(QueueItem(order: index, episode: episode))
        }
        try? context.save()
    }
    return container
}

@MainActor
private func previewQueueStore(populated: Bool) -> QueueStore {
    let container = previewContainer(populated: populated)
    return QueueStore(context: ModelContext(container))
}

#Preview("Up Next — populated (dark)") {
    let queueStore = previewQueueStore(populated: true)
    let playbackEngine = PlaybackEngine(localURLResolver: { _ in nil })
    let downloadManager = DownloadManager()
    UpNextScreen()
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .environment(queueStore)
        .environment(downloadManager)
        .environment(PlaybackIntentCoordinator(playbackEngine: playbackEngine, downloadManager: downloadManager, queueStore: queueStore))
}

#Preview("Up Next — populated (light)") {
    let queueStore = previewQueueStore(populated: true)
    let playbackEngine = PlaybackEngine(localURLResolver: { _ in nil })
    let downloadManager = DownloadManager()
    UpNextScreen()
        .themedPalette()
        .environment(\.colorScheme, .light)
        .environment(queueStore)
        .environment(downloadManager)
        .environment(PlaybackIntentCoordinator(playbackEngine: playbackEngine, downloadManager: downloadManager, queueStore: queueStore))
}

#Preview("Up Next — empty (dark)") {
    let queueStore = previewQueueStore(populated: false)
    let playbackEngine = PlaybackEngine(localURLResolver: { _ in nil })
    let downloadManager = DownloadManager()
    UpNextScreen()
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .environment(queueStore)
        .environment(downloadManager)
        .environment(PlaybackIntentCoordinator(playbackEngine: playbackEngine, downloadManager: downloadManager, queueStore: queueStore))
}

#Preview("Up Next — empty (light)") {
    let queueStore = previewQueueStore(populated: false)
    let playbackEngine = PlaybackEngine(localURLResolver: { _ in nil })
    let downloadManager = DownloadManager()
    UpNextScreen()
        .themedPalette()
        .environment(\.colorScheme, .light)
        .environment(queueStore)
        .environment(downloadManager)
        .environment(PlaybackIntentCoordinator(playbackEngine: playbackEngine, downloadManager: downloadManager, queueStore: queueStore))
}
#endif
