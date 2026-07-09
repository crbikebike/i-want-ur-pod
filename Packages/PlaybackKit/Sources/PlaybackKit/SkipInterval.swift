// SkipInterval — the single source of truth for transport skip distances.
//
// Rewind / skip-ahead is offered on four surfaces: the mini-player, the Now
// Playing sheet, the lock-screen remote commands (MPRemoteCommandCenter), and
// CarPlay. These distances used to be scattered integer literals (15 / 30) that
// had already drifted apart — CarPlay rewound 30s while every other surface
// rewound 15s. Centralizing them here keeps all surfaces in lockstep and gives
// the UI a value to render its numeral from instead of hardcoding it.
import Foundation

public enum SkipInterval {
    /// Rewind distance, in seconds. Pass negated to `PlaybackEngine.skip(by:)`.
    public static let back: TimeInterval = 15

    /// Skip-ahead distance, in seconds.
    public static let forward: TimeInterval = 30
}
