// Composed from docs/design/direction.md tokens — no design/kit source (see
// design/kit/MANIFEST.md). ROADMAP.md E5-S2: the Up Next tab lists the
// queued episodes in `QueueStore` order, supporting drag-to-reorder
// (`.onMove`, docs/spec/queue-semantics.md's "Reorder — drag") and
// left-swipe-to-remove (`.swipeActions`, "Remove — left swipe"), with an
// empty state when nothing is queued.
//
// Mirrors `IWantUrPod/Library/PodcastsScreen.swift`'s row shape (a
// `RemoteArtwork` tile + title/subtitle `VStack`) — this screen uses a real
// `List` (rather than `PodcastsScreen`'s plain `ScrollView`) because drag
// reorder and swipe actions are native `List` affordances.
import SwiftUI
import SwiftData
import DesignSystem
import PodcastModels

/// The Up Next tab: every queued episode, ordered by `QueueStore.items`
/// (ascending `order` — index 0 plays next). Reads the shared, app-scoped
/// `QueueStore` from the environment (frozen nav contract — never constructs
/// its own store) and reserves the floating tab bar's 104pt gap.
public struct UpNextScreen: View {
    @Environment(QueueStore.self) private var queueStore
    @Environment(\.palette) private var palette

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if queueStore.items.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(palette.groupedBg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear { queueStore.reload() }
    }

    // MARK: - Populated list

    private var list: some View {
        List {
            Section {
                ForEach(queueStore.items, id: \.id) { item in
                    QueueRow(item: item)
                        .listRowBackground(palette.groupedBg)
                        .listRowSeparatorTint(palette.hairline)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                queueStore.remove(item)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
                .onMove { offsets, destination in
                    queueStore.move(fromOffsets: offsets, toOffset: destination)
                }
            } header: {
                titleBar
                    .padding(.top, Spacing.sp5)
                    .padding(.bottom, Spacing.sp3)
                    .textCase(nil)
                    .listRowInsets(EdgeInsets())
            }
            .listRowBackground(palette.groupedBg)

            Color.clear
                .frame(height: AppShell.tabBarReservedPadding)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 64)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleBar
                    .padding(.top, Spacing.sp5)

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

    // MARK: - Large title (mirrors PodcastsScreen's titlewrap / h1.big)

    private var titleBar: some View {
        Text("Up Next")
            .typeStyle(Typography.displayLargeTitleStyle)
            .foregroundStyle(palette.text)
            .padding(.horizontal, Spacing.gutter + 2)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Queue row

/// One queued episode: artwork + episode title + owning show title. Same
/// shape as `PodcastsScreen`'s `PodcastRow` scaled to the queue's data.
private struct QueueRow: View {
    let item: QueueItem

    @Environment(\.palette) private var palette

    var body: some View {
        if let episode = item.episode {
            HStack(alignment: .center, spacing: Spacing.sp3) {
                RemoteArtwork(url: artworkURL(for: episode), seed: seed(for: episode), initial: initial(for: episode))
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.sp1) {
                    Text(episode.title)
                        .typeStyle(Typography.rowTitleStyle)
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let showTitle = episode.podcast?.title, !showTitle.isEmpty {
                        Text(showTitle)
                            .typeStyle(Typography.subheadStyle)
                            .foregroundStyle(palette.textDim)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Spacing.sp2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(episode.title), \(episode.podcast?.title ?? "")")
        }
    }

    private func artworkURL(for episode: Episode) -> URL? {
        episode.remoteArtworkURL ?? episode.podcast?.artworkURL
    }

    private func seed(for episode: Episode) -> Int {
        episode.guid.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    }

    private func initial(for episode: Episode) -> String {
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
            Episode(guid: "queue-1", title: "The Fall of the Grifter King, Part One", audioURL: URL(string: "https://cdn.example.com/ep1.mp3")!, podcast: podcast),
            Episode(guid: "queue-2", title: "The Fall of the Grifter King, Part Two", audioURL: URL(string: "https://cdn.example.com/ep2.mp3")!, podcast: podcast),
            Episode(guid: "queue-3", title: "A Bonus Episode About Nothing In Particular", audioURL: URL(string: "https://cdn.example.com/ep3.mp3")!, podcast: podcast)
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
    UpNextScreen()
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .environment(previewQueueStore(populated: true))
}

#Preview("Up Next — populated (light)") {
    UpNextScreen()
        .themedPalette()
        .environment(\.colorScheme, .light)
        .environment(previewQueueStore(populated: true))
}

#Preview("Up Next — empty (dark)") {
    UpNextScreen()
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .environment(previewQueueStore(populated: false))
}

#Preview("Up Next — empty (light)") {
    UpNextScreen()
        .themedPalette()
        .environment(\.colorScheme, .light)
        .environment(previewQueueStore(populated: false))
}
#endif
