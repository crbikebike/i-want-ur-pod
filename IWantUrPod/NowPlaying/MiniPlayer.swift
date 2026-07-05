// MiniPlayer — E6-S1. Persistent shell chrome (not any tab's content) drawn
// once by AppShell directly above LiquidGlassTabBar, spanning the width, on
// every tab whenever playback isn't idle (navigation-map.md's "Persistent
// chrome placement"). Reads the app-scoped PlaybackEngine straight from the
// environment (same pattern as PodcastDetailView.EpisodeRow) rather than
// having AppShell thread state down as parameters — AppShell only asks
// `PlaybackTransport.isMiniPlayerPresented(for:)` to decide whether to draw
// this view at all. Composed from docs/design/direction.md tokens — no
// design/kit source (see design/kit/MANIFEST.md's E6 entry).
import SwiftUI
import DesignSystem
import PodcastModels
import PlaybackKit

/// Artwork thumb + title/show + play/pause, tappable to present the Now
/// Playing sheet (E6-S2). The trailing transport button toggles play/pause
/// in place without presenting the sheet (a nested plain-style button inside
/// the row's own tap target, the same "row + trailing control" shape as
/// `PodcastDetailView`'s `EpisodeRow`).
struct MiniPlayer: View {
    /// Presents the Now Playing sheet (E6-S2). Owned by `AppShell` since it
    /// holds the `@State` driving the sheet.
    let onTap: () -> Void

    @Environment(PlaybackEngine.self) private var playbackEngine
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sp3) {
                RemoteArtwork(url: episode?.remoteArtworkURL, seed: seed, initial: initial)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(episode?.title ?? "")
                        .typeStyle(Typography.rowTitleStyle)
                        .foregroundStyle(palette.text)
                        .lineLimit(1)

                    if let showTitle = episode?.podcast?.title, !showTitle.isEmpty {
                        Text(showTitle)
                            .typeStyle(Typography.subheadStyle)
                            .foregroundStyle(palette.textDim)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: Spacing.sp2)

                Button(action: togglePlayPause) {
                    Image(systemName: PlaybackTransport.playPauseSymbolName(for: playbackEngine.state))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playbackEngine.state == .playing ? "Pause" : "Play")
            }
            .padding(.horizontal, Spacing.sp3)
            .padding(.vertical, Spacing.sp2)
            .frame(height: AppShell.miniPlayerHeight)
            .background(glass)
            .clipShape(RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous)
                    .strokeBorder(palette.tabbarHairline, lineWidth: 0.5)
            )
            .shadow(color: shadowColor, radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(episode?.title ?? "Now Playing"))
        .accessibilityHint(Text("Opens Now Playing"))
    }

    private var episode: Episode? { playbackEngine.currentEpisode }

    private var glass: some View {
        RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous)
                    .fill(palette.tabbarGlass)
            )
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.12)
    }

    private func togglePlayPause() {
        switch PlaybackTransport.playPauseAction(for: playbackEngine.state) {
        case .pause: playbackEngine.pause()
        case .resume: playbackEngine.resume()
        case .none: break
        }
    }

    private var seed: Int {
        (episode?.guid ?? "").unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    }

    private var initial: String {
        guard let first = episode?.title.first(where: { !$0.isWhitespace }) else { return "?" }
        return String(first).uppercased()
    }
}

// MARK: - Preview

#if DEBUG
import SwiftData

/// Drives a real `PlaybackEngine` synchronously into `.playing`/`.paused` for
/// previews (the engine sets state on `load()`/`pause()` without waiting on
/// any real async player readiness), so both transport-icon states render
/// without needing PlaybackKitTests' `@testable`-only `StubAudioPlayer`.
@MainActor
private func previewEngine(paused: Bool) -> (PlaybackEngine, Episode) {
    let episode = Episode(
        guid: "preview-ep",
        title: "The Long Way Round: Chapter Twelve",
        duration: 2400,
        audioURL: URL(string: "https://cdn.example.com/ep.mp3")!,
        downloadState: .downloaded
    )
    let podcast = Podcast(title: "Field Notes", feedURL: URL(string: "https://example.com/feed")!)
    episode.podcast = podcast

    let container = try! ModelSchema.makeContainer(inMemory: true)
    let context = ModelContext(container)
    context.insert(podcast)
    context.insert(episode)

    let engine = PlaybackEngine(localURLResolver: { _ in URL(fileURLWithPath: "/tmp/preview.mp3") })
    engine.load(episode: episode, context: context)
    if paused { engine.pause() }
    return (engine, episode)
}

private struct MiniPlayerPreviewHost: View {
    let paused: Bool

    var body: some View {
        let (engine, _) = previewEngine(paused: paused)
        return VStack {
            Spacer()
            MiniPlayer(onTap: {})
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.05))
        .environment(engine)
    }
}

#Preview("Mini-player — playing, dark") {
    MiniPlayerPreviewHost(paused: false)
        .themedPalette()
        .environment(\.colorScheme, .dark)
}

#Preview("Mini-player — paused, light") {
    MiniPlayerPreviewHost(paused: true)
        .themedPalette()
        .environment(\.colorScheme, .light)
}
#endif
