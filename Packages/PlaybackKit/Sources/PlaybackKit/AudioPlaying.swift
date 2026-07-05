// AudioPlaying — the testable seam abstracting the real player (`AVPlayer` in
// production, via `AVPlayerAudioPlaying`). Architecture source: this story's
// build brief (docs/spec/playback-state-machine.md's engine needs a seam
// tests can drive synchronously — no real audio, no AVFoundation dependency
// in the test target). `PlaybackEngine`'s entire state machine + progress-
// persistence cadence is exercised against a stub conforming to this
// protocol (`PlaybackKitTests/StubAudioPlayer.swift`).
import Foundation

/// Abstracts the underlying audio player so `PlaybackEngine` can be unit
/// tested with a synchronous stub instead of a real `AVPlayer`.
///
/// `@MainActor`: the seam is only ever driven from `PlaybackEngine` (itself
/// `@MainActor`), and the live `AVPlayer` conformer delivers its time/end/
/// error callbacks on the main queue — isolating the whole protocol to the
/// main actor is both correct and what lets the module build clean under
/// complete strict concurrency (no non-Sendable `self` captured across an
/// actor hop).
@MainActor
public protocol AudioPlaying: AnyObject {
    /// Total duration of the loaded item, in seconds. `0` before a
    /// successful `load(url:knownDuration:)`.
    var duration: TimeInterval { get }

    /// Current playback position, in seconds.
    var currentTime: TimeInterval { get }

    /// Fired with the new `currentTime` as playback advances. The live
    /// conformer drives this from an `AVPlayer` periodic time observer
    /// (~1s cadence); the test stub drives it synchronously via
    /// `advanceTime(by:)`. `PlaybackEngine` uses each tick to decide whether
    /// the 5s progress-persistence interval has elapsed.
    var onTimeUpdate: ((TimeInterval) -> Void)? { get set }

    /// Fired once when the item reaches its end.
    var onFinish: (() -> Void)? { get set }

    /// Fired if the loaded item fails to become playable (a corrupt or
    /// undecodable local file). The live conformer observes
    /// `AVPlayerItem.status == .failed`; `PlaybackEngine` routes this to
    /// `.failed(message)`, making the spec's `loading --error--> failed`
    /// transition reachable for the real player, not just the guard path.
    var onError: ((String) -> Void)? { get set }

    /// Loads `url` (always a local file URL — download-first, no streaming)
    /// for playback.
    ///
    /// - Parameter knownDuration: Seeds `duration` immediately from
    ///   `Episode.duration`, since a live `AVPlayerItem`'s duration isn't
    ///   always available synchronously right after loading.
    func load(url: URL, knownDuration: TimeInterval) throws

    /// Starts/resumes playback from the current position.
    func play()

    /// Holds the current position without advancing.
    func pause()

    /// Seeks to `fraction` (`0...1`) of `duration`.
    func seek(toFraction fraction: Double)
}
