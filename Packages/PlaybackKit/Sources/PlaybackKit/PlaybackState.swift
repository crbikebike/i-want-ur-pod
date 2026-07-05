// PlaybackState — the player states from docs/spec/playback-state-machine.md.
// Model layer for PlaybackKit; no design source (data type only).
import Foundation

/// The playback engine's state, per `playback-state-machine.md`'s transition
/// table.
///
/// ```
/// idle --load(downloaded episode)--> loading
/// loading --ready--> playing            loading --error--> failed
/// playing <--pause / play--> paused
/// playing --reach end--> finished
/// finished --auto-advance (queue non-empty)--> loading(next)   (E5, not here)
/// finished --queue empty--> idle
/// failed --load(other episode)--> loading
/// any --load(new episode)--> loading    (replaces current)
/// ```
public enum PlaybackState: Equatable, Sendable {
    /// No episode loaded. Mini-player hidden (E6, not built here).
    case idle
    /// A downloaded file is being prepared for the player.
    case loading
    /// Audio advancing; progress ticking.
    case playing
    /// Loaded, position held, not advancing.
    case paused
    /// Reached end-of-item.
    case finished
    /// The local asset couldn't be played (missing/corrupt file, or the
    /// download-first guard was violated).
    case failed(String)
}
