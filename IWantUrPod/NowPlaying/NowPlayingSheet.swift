// NowPlayingSheet — E6-S2. Presented modally over the whole shell when the
// mini-player is tapped (navigation-map.md): large artwork, show/episode
// details, and full transport (play/pause, skip fwd/back, scrub). Scrubbing
// seeks via `PlaybackEngine.seek(toFraction:)`, which persists
// `Episode.playbackProgress` immediately (playback-state-machine.md's
// explicit "scrubbing" persistence trigger — no duplicated logic here).
// Dismissing (the sheet's own drag/Close) returns to the mini-player with
// playback state intact: this view only *reads* the app-scoped
// `PlaybackEngine` via the environment, it owns no playback state of its
// own, so nothing is torn down on dismiss. Composed from
// docs/design/direction.md tokens — no design/kit source (see
// design/kit/MANIFEST.md's E6 entry).
import SwiftUI
import DesignSystem
import PodcastModels
import PlaybackKit

struct NowPlayingSheet: View {
    @Environment(PlaybackEngine.self) private var playbackEngine
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    /// Local scrub position while the user is actively dragging the slider,
    /// so the control doesn't fight the engine's own progress ticks
    /// mid-gesture. `nil` when not scrubbing — the slider then tracks
    /// `Episode.playbackProgress` directly.
    @State private var scrubFraction: Double?

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.sp6) {
                Spacer(minLength: Spacing.sp4)
                artwork
                details
                scrubber
                transport
                Spacer(minLength: Spacing.sp4)
            }
            .padding(.horizontal, Spacing.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.groupedBg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var episode: Episode? { playbackEngine.currentEpisode }

    // MARK: - Artwork + details

    private var artwork: some View {
        RemoteArtwork(url: episode?.remoteArtworkURL, seed: seed, initial: initial, cornerRadius: Radius.rLg20)
            .frame(width: 280, height: 280)
            .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(spacing: Spacing.sp1) {
            Text(episode?.title ?? "Nothing playing")
                .typeStyle(Typography.sectionStyle)
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let showTitle = episode?.podcast?.title, !showTitle.isEmpty {
                Text(showTitle)
                    .typeStyle(Typography.subheadStyle)
                    .foregroundStyle(palette.textDim)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Scrubber (seeks + persists `Episode.playbackProgress`)

    private var scrubber: some View {
        VStack(spacing: Spacing.sp1) {
            Slider(
                value: Binding(
                    get: { scrubFraction ?? currentFraction },
                    set: { scrubFraction = $0 }
                ),
                in: 0...1,
                onEditingChanged: { isEditing in
                    guard !isEditing else { return }
                    let fraction = scrubFraction ?? currentFraction
                    playbackEngine.seek(toFraction: fraction)
                    scrubFraction = nil
                }
            )
            .tint(palette.accent)
            .disabled(episode == nil)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(Int((currentFraction * 100).rounded())) percent")

            HStack {
                Text(timeLabel(elapsedSeconds))
                Spacer()
                Text(timeLabel(episode?.duration ?? 0))
            }
            .typeStyle(Typography.subheadStyle)
            .foregroundStyle(palette.textFaint)
        }
    }

    /// The slider/elapsed position when the user isn't dragging. Reads
    /// `PlaybackEngine.displayProgress` (the smooth per-~1s tick value), NOT
    /// `Episode.playbackProgress` (only written every 5s) — otherwise the bar
    /// would stall then jump every 5 seconds while the lock screen ticks
    /// smoothly. See `PlaybackEngine.displayProgress`.
    private var currentFraction: Double {
        min(max(playbackEngine.displayProgress, 0), 1)
    }

    private var elapsedSeconds: TimeInterval {
        (episode?.duration ?? 0) * currentFraction
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: Spacing.sp7) {
            SeekButton(
                direction: .backward,
                seconds: Int(SkipInterval.back),
                diameter: 44,
                accessibilityLabel: "Skip back \(Int(SkipInterval.back)) seconds"
            ) {
                playbackEngine.skip(by: -SkipInterval.back)
            }
            .disabled(episode == nil)

            Button(action: togglePlayPause) {
                if playbackEngine.state == .preparing {
                    // `.preparing` (E6: auto-download-then-play) — same
                    // spinner-in-place-of-glyph treatment as `MiniPlayer`.
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: PlaybackTransport.playPauseSymbolName(for: playbackEngine.state))
                        .font(.system(size: 40, weight: .bold))
                        .frame(width: 64, height: 64)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.accent)
            .disabled(episode == nil)
            .accessibilityLabel(playbackEngine.state == .preparing ? "Preparing" : (playbackEngine.state == .playing ? "Pause" : "Play"))

            SeekButton(
                direction: .forward,
                seconds: Int(SkipInterval.forward),
                diameter: 44,
                accessibilityLabel: "Skip forward \(Int(SkipInterval.forward)) seconds"
            ) {
                playbackEngine.skip(by: SkipInterval.forward)
            }
            .disabled(episode == nil)
        }
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

@MainActor
private func previewSheetEngine(paused: Bool, progress: Double = 0.35) -> PlaybackEngine {
    let episode = Episode(
        guid: "preview-sheet-ep",
        title: "The Long Way Round: Chapter Twelve — Into the Delta",
        duration: 2400,
        audioURL: URL(string: "https://cdn.example.com/ep.mp3")!,
        downloadState: .downloaded,
        playbackProgress: progress
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
    return engine
}

#Preview("Now Playing sheet — playing, dark") {
    NowPlayingSheet()
        .themedPalette()
        .environment(\.colorScheme, .dark)
        .environment(previewSheetEngine(paused: false))
}

#Preview("Now Playing sheet — paused, light") {
    NowPlayingSheet()
        .themedPalette()
        .environment(\.colorScheme, .light)
        .environment(previewSheetEngine(paused: true))
}
#endif
