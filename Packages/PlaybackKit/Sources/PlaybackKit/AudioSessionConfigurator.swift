// AudioSessionConfigurator — activates the shared AVAudioSession for
// background playback. Architecture source: docs/spec/playback-state-machine
// .md ("Background audio & session"). `AVAudioSession` is iOS-only (no
// macOS/Mac Catalyst equivalent API), so this whole file is `#if os(iOS)`-
// gated per the build brief; `PlaybackEngine` calls it unconditionally and it
// no-ops on macOS, keeping the engine's own logic platform-agnostic for host
// `swift test`.
import Foundation
#if os(iOS)
import AVFoundation
#endif

enum AudioSessionConfigurator {
    /// Configures `.playback` category so audio continues when the app is
    /// backgrounded and mixes/ducks per iOS norms, then activates the
    /// session. Best-effort: a failure here doesn't block playback, it just
    /// means background audio may not continue (e.g. simulator quirks) — not
    /// a fatal condition.
    ///
    // MANUAL VERIFICATION: background-audio continuation cannot be exercised
    // by `swift test` or an automated simulator test (no way to simulate
    // backgrounding + observe continued audio output). Verify by hand: play a
    // downloaded episode, press the Home button (or swipe up) to background
    // the app, and confirm audio keeps playing.
    static func activatePlaybackSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            // Best-effort — see doc comment above.
        }
        #endif
    }
}
