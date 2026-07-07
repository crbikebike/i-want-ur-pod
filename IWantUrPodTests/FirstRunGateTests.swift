// Tests for E1-S1's once-only first-run explainer gate. Determinate criteria
// from ROADMAP.md E1-S1:
//   - fresh install shows it before the first destination (hasSeenFirstRun ==
//     false) — Home as of the E8-S1 dock-IA revision, Discover before it
//   - a relaunch (re-reading the flag) does not re-show it
//   - the persisted flag is resettable from Settings, which re-shows it
// Runs on the iOS simulator target alongside the rest of IWantUrPodTests; an
// isolated UserDefaults suite keeps each test hermetic (no shared state with
// the real app defaults or other tests).
import XCTest
@testable import IWantUrPod

final class FirstRunGateTests: XCTestCase {

    /// A fresh, isolated `UserDefaults` suite per test so runs never see a
    /// flag left over from a previous test or the real device.
    private func makeDefaults(suiteName: String = #function) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func test_freshInstall_hasNotSeenFirstRun() {
        let gate = FirstRunGate(defaults: makeDefaults())
        XCTAssertFalse(gate.hasSeenFirstRun, "A fresh install must show the explainer before Discover")
    }

    func test_markSeen_persistsAcrossRelaunch() {
        let suite = "\(#function)"
        let gate = FirstRunGate(defaults: makeDefaults(suiteName: suite))
        gate.markSeen()

        // Simulate "relaunch" by reading the flag through a brand-new gate
        // instance backed by the same defaults suite (not by reusing `gate`,
        // so this doesn't just prove in-memory state held over).
        let relaunched = FirstRunGate(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertTrue(relaunched.hasSeenFirstRun, "Dismissal must persist so a relaunch does not re-show the explainer")
    }

    func test_settingsReset_clearsFlagSoExplainerShowsAgain() {
        let suite = "\(#function)"
        let defaults = makeDefaults(suiteName: suite)
        let gate = FirstRunGate(defaults: defaults)
        gate.markSeen()
        XCTAssertTrue(gate.hasSeenFirstRun)

        // Settings' "Show first-run intro again" control.
        gate.reset()

        let afterReset = FirstRunGate(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertFalse(afterReset.hasSeenFirstRun, "Resetting from Settings must re-show the explainer")
    }
}
