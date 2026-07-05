// StubAudioPlayer — test double for `AudioPlaying`. Drives time/end
// synchronously (no real threading, no AVFoundation) so `PlaybackEngineTests`
// can exercise the whole state machine + progress-persistence cadence
// deterministically.
import Foundation
@testable import PlaybackKit

struct StubLoadError: Error, LocalizedError {
    var errorDescription: String? { "stub load error" }
}

@MainActor
final class StubAudioPlayer: AudioPlaying {
    var onTimeUpdate: ((TimeInterval) -> Void)?
    var onFinish: (() -> Void)?
    var onError: ((String) -> Void)?

    private(set) var duration: TimeInterval = 0
    private(set) var currentTime: TimeInterval = 0

    /// URLs passed to `load`, in call order.
    private(set) var loadedURLs: [URL] = []
    /// Fractions passed to `seek(toFraction:)`, in call order (proves e.g.
    /// resume-seek happens before `play()`).
    private(set) var seekedFractions: [Double] = []
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0

    /// When set, the next `load` throws this instead of succeeding.
    var loadError: Error?

    func load(url: URL, knownDuration: TimeInterval) throws {
        if let loadError {
            throw loadError
        }
        loadedURLs.append(url)
        duration = knownDuration
        currentTime = 0
    }

    func play() {
        playCallCount += 1
    }

    func pause() {
        pauseCallCount += 1
    }

    func seek(toFraction fraction: Double) {
        seekedFractions.append(fraction)
        currentTime = duration * fraction
    }

    /// Test helper: advances `currentTime` by `seconds` and fires
    /// `onTimeUpdate`, simulating a live player's periodic time observer.
    func advanceTime(by seconds: TimeInterval) {
        currentTime += seconds
        onTimeUpdate?(currentTime)
    }

    /// Test helper: fires `onFinish`, simulating reaching end-of-item.
    func finish() {
        currentTime = duration
        onFinish?()
    }

    /// Test helper: fires `onError`, simulating an async `AVPlayerItem.status
    /// == .failed` after a successful `load` (corrupt/undecodable file).
    func failItem(_ message: String) {
        onError?(message)
    }
}
