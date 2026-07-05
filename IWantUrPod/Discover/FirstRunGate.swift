// Once-only first-run explainer gate (E1-S1). Doc: ROADMAP.md E1-S1 ("A
// once-only intro … shown before Discover; re-openable from Settings").
//
// Persistence choice: a single boolean flag in `UserDefaults` — the simplest
// mechanism for "has this device seen the explainer", with no user content to
// protect and no relationship to the SwiftData schema (definition-of-done.md
// §4's "no unintended SwiftData schema change" bar doesn't apply to a flag
// like this). Documented here rather than added as a `@Model` field.
import Foundation

/// Tracks whether the once-only first-run explainer has been shown and
/// dismissed. `DiscoverView` presents the explainer as a `fullScreenCover`
/// while `!hasSeenFirstRun`; Settings' "Show first-run intro again" control
/// calls `reset()` so it reappears the next time Discover is shown.
///
/// Not `Sendable`: it wraps a `UserDefaults` (a non-`Sendable` reference type),
/// and it doesn't need to cross concurrency domains — it's read/written on the
/// main actor from `DiscoverView`/`SourcesView`. Declaring `Sendable` here would
/// be an error under the Swift 6 language mode.
public struct FirstRunGate {
    private let defaults: UserDefaults
    private static let hasSeenKey = "com.iwanturpod.firstRun.hasSeen"

    /// - Parameter defaults: Overridable for tests (an isolated suite) and
    ///   previews; defaults to the standard app defaults.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the explainer has already been shown and dismissed on this
    /// device. `false` on a fresh install (the key is absent).
    public var hasSeenFirstRun: Bool {
        defaults.bool(forKey: Self.hasSeenKey)
    }

    /// Marks the explainer as seen — called when the user dismisses it.
    public func markSeen() {
        defaults.set(true, forKey: Self.hasSeenKey)
    }

    /// Clears the flag so the explainer shows again on next appearance —
    /// Settings' reset control.
    public func reset() {
        defaults.set(false, forKey: Self.hasSeenKey)
    }
}
