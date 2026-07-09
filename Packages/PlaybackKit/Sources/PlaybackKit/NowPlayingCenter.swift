// NowPlayingCenter — lock-screen / Control Center integration. Architecture
// source: docs/spec/playback-state-machine.md's `MPNowPlayingInfoCenter`
// field-mapping table and remote-command list. `MediaPlayer`'s remote-command
// surface is the lock-screen/Control Center integration point and is
// meaningful only on iOS, so this whole file is `#if os(iOS)`-gated per the
// build brief (mirrors AudioSessionConfigurator.swift); `PlaybackEngine` calls
// it unconditionally and it no-ops on macOS, keeping the engine's own logic
// platform-agnostic for host `swift test`.
import Foundation
import PodcastModels
#if os(iOS)
import MediaPlayer
import UIKit
#endif

/// Bridges `PlaybackEngine`'s state to the system Now Playing surface: sets
/// `MPNowPlayingInfoCenter.default().nowPlayingInfo` per the spec's field
/// table, and wires transport controls via `MPRemoteCommandCenter` so
/// lock-screen and CarPlay (parked, but seam-compatible) controls work.
@MainActor
final class NowPlayingCenter {
    init() {}

    #if os(iOS)
    /// The artwork URL currently cached in `cachedArtwork`. Keyed so a routine
    /// ~1s time tick reuses the already-fetched image instead of re-hitting
    /// the network every tick.
    private var cachedArtworkURL: URL?
    /// The last successfully fetched artwork, reused across ticks for the
    /// same `cachedArtworkURL`.
    private var cachedArtwork: MPMediaItemArtwork?
    /// Monotonic token bumped on each new episode/artwork URL. A slow,
    /// older fetch checks this before writing so it can't clobber the info
    /// for a newer episode (stale-overwrite guard).
    private var artworkFetchToken = 0
    #endif

    /// Registers play/pause/skip-forward/skip-back/scrub remote commands.
    /// Call once, after `PlaybackEngine` has finished initializing, so the
    /// closures can safely capture it.
    func configureRemoteCommands(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onSkipForward: @escaping () -> Void,
        onSkipBackward: @escaping () -> Void,
        onScrub: @escaping (TimeInterval) -> Void
    ) {
        #if os(iOS)
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { _ in
            onPlay()
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { _ in
            onPause()
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [NSNumber(value: SkipInterval.forward)]
        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.addTarget { _ in
            onSkipForward()
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: SkipInterval.back)]
        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.addTarget { _ in
            onSkipBackward()
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            onScrub(event.positionTime)
            return .success
        }
        #endif
    }

    /// Updates the Now Playing info per the spec's field-mapping table.
    /// Called on every state change and on each progress write.
    ///
    // MANUAL VERIFICATION: a lock-screen Now Playing entry with title +
    // artwork cannot be exercised by `swift test` or the simulator test
    // runner (no lock-screen automation). Verify by hand: play a downloaded
    // episode, lock the device (or open Control Center in the simulator),
    // and confirm the entry shows the episode title, the show's artwork, and
    // that play/pause/scrub controls there work.
    func update(episode: Episode, podcastTitle: String, state: PlaybackState, elapsed: TimeInterval) {
        #if os(iOS)
        let rate: Double
        switch state {
        case .playing: rate = 1.0
        default: rate = 0.0
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPMediaItemPropertyArtist: podcastTitle,
            MPMediaItemPropertyPlaybackDuration: episode.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: rate
        ]

        let artworkURL = episode.remoteArtworkURL ?? episode.podcast?.artworkURL

        // Reuse already-fetched artwork synchronously — the common case for a
        // routine time tick — so text/elapsed/rate refresh without any
        // network work.
        if let artworkURL, artworkURL == cachedArtworkURL, let cachedArtwork {
            info[MPMediaItemPropertyArtwork] = cachedArtwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Only fetch when the artwork URL is new (episode changed). A tick for
        // the same episode never re-fetches.
        guard let artworkURL, artworkURL != cachedArtworkURL else { return }

        artworkFetchToken += 1
        let token = artworkFetchToken
        cachedArtworkURL = artworkURL
        cachedArtwork = nil

        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: artworkURL),
                  let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            guard let self else { return }
            // Stale-overwrite guard: a newer episode already superseded this
            // fetch — drop it rather than clobber the current info.
            guard token == self.artworkFetchToken else { return }
            self.cachedArtwork = artwork
            var latest = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            latest[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = latest
        }
        #endif
    }

    /// Clears the Now Playing surface (e.g. when the engine returns to
    /// `.idle`).
    func clear() {
        #if os(iOS)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        // Invalidate any in-flight fetch and drop the cache so the next
        // episode re-fetches its own artwork.
        artworkFetchToken += 1
        cachedArtworkURL = nil
        cachedArtwork = nil
        #endif
    }
}
