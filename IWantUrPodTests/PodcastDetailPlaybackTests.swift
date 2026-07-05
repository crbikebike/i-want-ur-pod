// PodcastDetailPlaybackTests — E4-S2 app-target coverage. Runs on the iOS
// simulator (SwiftData relationship rules don't fire under host `swift test`
// — see docs/spec/definition-of-done.md). Asserts the exact condition
// `PodcastDetailView`'s `EpisodeRow.playControl` switches on: Play renders
// iff `episode.downloadState.isDownloaded`, mirroring
// docs/spec/playback-state-machine.md's download-first guard.
import XCTest
import PodcastModels
@testable import IWantUrPod

final class PodcastDetailPlaybackTests: XCTestCase {

    private func makeEpisode(downloadState: DownloadState) -> Episode {
        Episode(
            guid: "ep-play-\(UUID().uuidString)",
            title: "Test Episode",
            audioURL: URL(string: "https://cdn.example.com/ep.mp3")!,
            downloadState: downloadState
        )
    }

    func test_playOffered_onlyWhenDownloaded() {
        XCTAssertFalse(EpisodeRow.isPlayOffered(for: makeEpisode(downloadState: .notDownloaded)))
        XCTAssertFalse(EpisodeRow.isPlayOffered(for: makeEpisode(downloadState: .downloading(progress: 0.5))))
        XCTAssertFalse(EpisodeRow.isPlayOffered(for: makeEpisode(downloadState: .failed(message: "oops"))))
        XCTAssertTrue(EpisodeRow.isPlayOffered(for: makeEpisode(downloadState: .downloaded)))
    }
}
