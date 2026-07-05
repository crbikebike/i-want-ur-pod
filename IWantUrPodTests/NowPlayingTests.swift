// NowPlayingTests — E6-S1/S2 app-target coverage. Runs on the iOS simulator
// (SwiftData relationship rules don't fire under host `swift test` — see
// docs/spec/definition-of-done.md), mirroring `PodcastDetailPlaybackTests`'
// precedent of asserting the exact predicate/mapping a view switches on
// rather than view-inspecting SwiftUI itself. Covers:
//   - Mini-player visibility: `PlaybackTransport.isMiniPlayerPresented(for:)`
//     is true for playing/paused/loading/finished/failed, false only at idle
//     (navigation-map.md: "present ... whenever the player is not idle").
//   - Play/pause action mapping: `PlaybackTransport.playPauseAction(for:)`.
//   - The Now Playing sheet's scrub action: calling
//     `PlaybackEngine.seek(toFraction:)` (exactly what the sheet's slider
//     calls on `onEditingChanged(false)`) persists `Episode.playbackProgress`
//     — the scrub-persists-progress determinate behavior, exercised here at
//     the app layer against the real `PlaybackEngine` (the exhaustive
//     state-machine/cadence coverage already lives in
//     `PlaybackKitTests/PlaybackEngineTests.swift`; this test only proves the
//     app-level wiring calls the right seam).
import XCTest
import SwiftData
import PodcastModels
import PlaybackKit
@testable import IWantUrPod

@MainActor
final class NowPlayingTests: XCTestCase {

    // MARK: - Mini-player visibility (E6-S1)

    func test_miniPlayerVisibility_trueWheneverNotIdle() {
        XCTAssertFalse(PlaybackTransport.isMiniPlayerPresented(for: .idle))
        XCTAssertTrue(PlaybackTransport.isMiniPlayerPresented(for: .loading))
        XCTAssertTrue(PlaybackTransport.isMiniPlayerPresented(for: .playing))
        XCTAssertTrue(PlaybackTransport.isMiniPlayerPresented(for: .paused))
        XCTAssertTrue(PlaybackTransport.isMiniPlayerPresented(for: .finished))
        XCTAssertTrue(PlaybackTransport.isMiniPlayerPresented(for: .failed("not downloaded")))
    }

    // MARK: - Play/pause action mapping (E6-S1/S2 transport)

    func test_playPauseAction_mapsPlayingToPause_pausedToResume_otherwiseNone() {
        XCTAssertEqual(PlaybackTransport.playPauseAction(for: .playing), .pause)
        XCTAssertEqual(PlaybackTransport.playPauseAction(for: .paused), .resume)
        XCTAssertEqual(PlaybackTransport.playPauseAction(for: .idle), .none)
        XCTAssertEqual(PlaybackTransport.playPauseAction(for: .loading), .none)
        XCTAssertEqual(PlaybackTransport.playPauseAction(for: .finished), .none)
        XCTAssertEqual(PlaybackTransport.playPauseAction(for: .failed("x")), .none)
    }

    func test_playPauseSymbolName_reflectsPlayingVsEverythingElse() {
        XCTAssertEqual(PlaybackTransport.playPauseSymbolName(for: .playing), "pause.fill")
        XCTAssertEqual(PlaybackTransport.playPauseSymbolName(for: .paused), "play.fill")
        XCTAssertEqual(PlaybackTransport.playPauseSymbolName(for: .idle), "play.fill")
    }

    // MARK: - Scrub wiring (E6-S2)

    func test_scrubToHalf_callsEngineSeek_andPersistsPlaybackProgress() throws {
        let container = try ModelSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let episode = Episode(
            guid: "now-playing-scrub",
            title: "Test Episode",
            duration: 200,
            audioURL: URL(string: "https://cdn.example.com/ep.mp3")!,
            downloadState: .downloaded
        )
        context.insert(episode)

        let engine = PlaybackEngine(localURLResolver: { _ in URL(fileURLWithPath: "/tmp/now-playing-scrub.audio") })
        engine.load(episode: episode, context: context)
        XCTAssertEqual(engine.state, .playing)

        // Exactly what NowPlayingSheet's Slider calls from
        // `onEditingChanged(false)`.
        engine.seek(toFraction: 0.5)

        XCTAssertEqual(episode.playbackProgress, 0.5, accuracy: 0.001)
    }
}
