// PlaybackTransport — small pure seams behind E6's mini-player (S1) and Now
// Playing sheet (S2). Composed from docs/design/direction.md tokens — no
// design/kit source (see design/kit/MANIFEST.md's E6 entry). Factored out of
// both views so IWantUrPodTests can assert the state → behavior mapping
// (visibility, play/pause action, icon) without a live PlaybackEngine or
// AVPlayer, mirroring PodcastDetailView.EpisodeRow.isPlayOffered's precedent
// of exposing the exact predicate a view switches on as a testable static.
import PlaybackKit

enum PlaybackTransport {

    /// Whether the mini-player is shown for `state` — the exact predicate
    /// `MiniPlayer` switches on, and navigation-map.md's rule verbatim:
    /// "present ... whenever the player is not idle ... hidden at idle."
    static func isMiniPlayerPresented(for state: PlaybackState) -> Bool {
        state != .idle
    }

    /// What the transport's single play/pause control should do for the
    /// engine's current `state`. `.none` covers `.loading`/`.finished`/
    /// `.failed`, where there's nothing sensible to toggle — the control
    /// still renders (so the row doesn't jump) but taps are a no-op,
    /// matching `PlaybackEngine.pause()`/`resume()`'s own state guards.
    enum PlayPauseAction: Equatable {
        case pause
        case resume
        case none
    }

    static func playPauseAction(for state: PlaybackState) -> PlayPauseAction {
        switch state {
        case .playing: return .pause
        case .paused: return .resume
        default: return .none
        }
    }

    /// SF Symbol for the transport control, mirroring `playPauseAction`.
    static func playPauseSymbolName(for state: PlaybackState) -> String {
        state == .playing ? "pause.fill" : "play.fill"
    }
}
