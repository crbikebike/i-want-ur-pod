// Translated from design/kit/screens/settings.html (E8-S4). Settings is a
// PUSHED screen reached only from the top-right gear on Home/Shows/Up Next —
// never a tab (that's `SourcesView.swift`'s retired role; see
// design/kit/MANIFEST.md's note that v1 is Apple-only, no source picker).
// Its one section, "Manage downloaded episodes", lists every `Episode` whose
// `downloadState == .downloaded`; removing a row deletes the local audio file
// via `DownloadManager.remove(_:context:)` and resets the state to
// `.notDownloaded` — the `Episode` record and its feed membership stay.
//
// CAVEAT (documented per the build brief): E1-S1 requires the first-run
// explainer to be re-openable from Settings, and `FirstRunGateTests` exercises
// exactly that reset path. Keeping the kit's literal "exactly one section"
// would regress that behavior, so a minimal footer row ("Show first-run intro
// again") is kept below the downloads list rather than deleted — a second,
// much smaller section is judged less bad than losing a tested capability.
import SwiftUI
import SwiftData
import DesignSystem
import PodcastModels
import DownloadKit

/// Settings' entry point, pushed from Home/Shows/Up Next's gear (E8-S4).
public struct SettingsScreen: View {
    /// Live SwiftData query, sorted only — filtered to `.downloaded` in plain
    /// Swift below (same precedent as `PodcastsListProvider`/`HomeScreen`:
    /// avoid a `#Predicate` over an associated-value enum case).
    @Query(sort: \Episode.publishDate, order: .reverse) private var allEpisodes: [Episode]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.palette) private var palette
    @Environment(DownloadManager.self) private var downloadManager

    public init() {}

    private var downloadedEpisodes: [Episode] {
        allEpisodes.filter { $0.downloadState == .downloaded }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleBar

                groupLabel("Downloaded episodes")
                    .padding(.top, Spacing.sp6)

                if downloadedEpisodes.isEmpty {
                    emptyState
                } else {
                    downloadsList
                    footnote("Removing an episode deletes the downloaded audio from this device. The episode stays in your feeds and can be downloaded again from Up Next.")
                        .padding(.top, Spacing.sp3)
                }

                showFirstRunButton
                    .padding(.top, Spacing.sp6)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.top, Spacing.sp4)
            .padding(.bottom, AppShell.tabBarReservedPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.groupedBg.ignoresSafeArea())
        // Unlike Home/Shows/Up Next (root tab screens that hide the system
        // nav bar entirely), Settings is PUSHED — it needs the system back
        // chevron, so the nav bar stays, just with no duplicate title (this
        // screen draws its own `h1.big` below) — "Has its own 'Done'/back
        // affordance back to the tab the gear was tapped from" (settings.html).
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
    }

    // MARK: - Header (h1.big "Settings")

    private var titleBar: some View {
        Text("Settings")
            .typeStyle(Typography.displayLargeTitleStyle)
            .foregroundStyle(palette.text)
            .padding(.horizontal, 2)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Downloads list (.dllist / .drow)

    private var downloadsList: some View {
        card {
            ForEach(Array(downloadedEpisodes.enumerated()), id: \.element.id) { index, episode in
                downloadRow(for: episode)

                if index != downloadedEpisodes.count - 1 {
                    Divider()
                        .overlay(palette.separator)
                        .padding(.leading, Spacing.sp4 + 56 + Spacing.sp3)
                }
            }
        }
    }

    private func downloadRow(for episode: Episode) -> some View {
        HStack(alignment: .center, spacing: Spacing.sp3) {
            RemoteArtwork(url: artworkURL(for: episode), seed: seed(for: episode), initial: initial(for: episode))
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.sp1) {
                Text(episode.title)
                    .typeStyle(Typography.rowTitleStyle)
                    .foregroundStyle(palette.text)
                    .lineLimit(2)

                if let showTitle = episode.podcast?.title, !showTitle.isEmpty {
                    Text(showTitle)
                        .typeStyle(Typography.subheadStyle)
                        .foregroundStyle(palette.textDim)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                downloadManager.remove(episode, context: modelContext)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 36, height: 36)
                    .background(palette.chip, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove download of \(episode.title)")
        }
        .padding(.vertical, Spacing.sp3)
        .padding(.horizontal, Spacing.sp4)
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

    // MARK: - Empty state

    private var emptyState: some View {
        EmptyStateView(
            kind: .firstRun,
            title: "No downloaded episodes",
            message: "Episodes you download from Up Next will show up here so you can manage local storage."
        ) {
            EmptyView()
        }
    }

    // MARK: - First-run reset (E1-S1 caveat)

    /// Resets the `FirstRunGate` flag so `HomeScreen` presents the once-only
    /// explainer again the next time Home appears (no relaunch needed — the
    /// gate is checked on every `onAppear`).
    private var showFirstRunButton: some View {
        card {
            Button {
                FirstRunGate().reset()
            } label: {
                HStack(spacing: Spacing.sp3) {
                    Text("Show first-run intro again")
                        .typeStyle(Typography.rowTitleStyle)
                        .foregroundStyle(palette.text)
                    Spacer(minLength: 0)
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textFaint)
                }
                .padding(.vertical, Spacing.sp3)
                .padding(.horizontal, Spacing.sp4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Shared pieces

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
            .elevList(hairline: palette.hairline)
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .typeStyle(Typography.groupLabelStyle)
            .foregroundStyle(palette.textFaint)
            .padding(.horizontal, Spacing.sp4)
            .padding(.bottom, Spacing.sp2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(Typography.subhead)
            .foregroundStyle(palette.textFaint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.sp4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
private func previewContainer(populated: Bool) -> ModelContainer {
    let container = ModelSchema.previewContainer()
    guard populated else { return container }
    let context = ModelContext(container)

    let podcast = Podcast(
        title: "Twenty Thousand Hertz",
        author: "Defacto Sound",
        feedURL: URL(string: "https://feeds.example.com/20k")!,
        isSubscribed: true
    )
    context.insert(podcast)

    let episodes = [
        Episode(guid: "set-1", title: "The Sample-Rate Wars", audioURL: URL(string: "https://cdn.example.com/1.mp3")!, downloadState: .downloaded, podcast: podcast),
        Episode(guid: "set-2", title: "Cold Open, Warm Ending", audioURL: URL(string: "https://cdn.example.com/2.mp3")!, downloadState: .downloaded, podcast: podcast),
    ]
    for episode in episodes { context.insert(episode) }
    try? context.save()
    return container
}

#Preview("Settings — populated (dark)") {
    NavigationStack {
        SettingsScreen()
            .environment(DownloadManager())
    }
    .themedPalette()
    .environment(\.colorScheme, .dark)
    .modelContainer(previewContainer(populated: true))
}

#Preview("Settings — empty (light)") {
    NavigationStack {
        SettingsScreen()
            .environment(DownloadManager())
    }
    .themedPalette()
    .environment(\.colorScheme, .light)
    .modelContainer(previewContainer(populated: false))
}
#endif
