// AVPlayerAudioPlaying — the live `AudioPlaying` conformer, wrapping
// `AVPlayer`. Architecture source: docs/spec/playback-state-machine.md
// (download-first: always given a local file URL, never a remote one).
// `AVFoundation` builds on both iOS and macOS, so this file compiles under
// host `swift test` too — it just isn't exercised there (tests inject
// `StubAudioPlayer` instead); only the AVAudioSession/MediaPlayer background-
// audio and lock-screen integration (AudioSessionConfigurator.swift,
// NowPlayingCenter.swift) is `#if os(iOS)`-gated.
import Foundation
import AVFoundation

/// Wraps a single `AVPlayer` to conform to `AudioPlaying`. One instance per
/// `PlaybackEngine`; a new `load` tears down and replaces the previous item's
/// observers (per the spec's "any --load(new episode)--> loading, replaces
/// current").
///
/// `@MainActor` (matching the `AudioPlaying` protocol): the `AVPlayer`
/// periodic-time and item-status/end callbacks are all delivered on the main
/// queue, so isolating the class to the main actor is correct and lets its
/// callbacks touch `self` without an unsafe cross-actor capture.
@MainActor
public final class AVPlayerAudioPlaying: AudioPlaying {
    public var onTimeUpdate: ((TimeInterval) -> Void)?
    public var onFinish: (() -> Void)?
    public var onError: ((String) -> Void)?

    public private(set) var duration: TimeInterval = 0

    public var currentTime: TimeInterval {
        guard let player else { return 0 }
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    // `nonisolated(unsafe)`: these are mutated only on the main actor (in
    // `load`/`teardown`), but must also be torn down from the nonisolated
    // `deinit` (removing an AVPlayer time observer before the player
    // deallocates is required to avoid a crash). At `deinit` the object has no
    // remaining references, so there is provably no concurrent access — the
    // unsafe opt-out asserts that invariant the compiler can't see, rather
    // than suppressing a real race. (macOS 14 / iOS 17 predate `isolated
    // deinit`, so that cleaner tool isn't available here.)
    nonisolated(unsafe) private var player: AVPlayer?
    nonisolated(unsafe) private var timeObserverToken: Any?
    nonisolated(unsafe) private var endObserver: NSObjectProtocol?
    nonisolated(unsafe) private var statusObservation: NSKeyValueObservation?

    public init() {}

    public func load(url: URL, knownDuration: TimeInterval) throws {
        teardown()

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        duration = knownDuration

        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        // The block is `@Sendable` and runs on `.main`; `assumeIsolated`
        // re-enters this class's `@MainActor` isolation to fire the callback
        // without an unsafe capture.
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            MainActor.assumeIsolated {
                self?.onTimeUpdate?(seconds)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onFinish?()
            }
        }
        // Observe item readiness: a corrupt/undecodable local file lands in
        // `.failed`, which we surface so PlaybackEngine can go to
        // `.failed(message)` (spec's `loading --error--> failed`), instead of
        // sitting silently in `.playing`.
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            guard observedItem.status == .failed else { return }
            let message = observedItem.error?.localizedDescription ?? "This episode couldn't be played."
            MainActor.assumeIsolated {
                self?.onError?(message)
            }
        }
    }

    public func play() {
        player?.play()
    }

    public func pause() {
        player?.pause()
    }

    public func seek(toFraction fraction: Double) {
        guard duration > 0, let player else { return }
        let clamped = min(max(fraction, 0), 1)
        let target = CMTime(seconds: duration * clamped, preferredTimescale: 600)
        player.seek(to: target)
    }

    private func teardown() {
        if let timeObserverToken {
            player?.removeTimeObserver(timeObserverToken)
        }
        timeObserverToken = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
        player = nil
    }

    deinit {
        // `deinit` is nonisolated; the observers are all safe to invalidate
        // from any thread, so tear them down directly rather than hop actors
        // during deallocation.
        if let timeObserverToken {
            player?.removeTimeObserver(timeObserverToken)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        statusObservation?.invalidate()
    }
}
