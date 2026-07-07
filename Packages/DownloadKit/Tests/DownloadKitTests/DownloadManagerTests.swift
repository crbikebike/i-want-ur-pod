// DownloadManagerTests — E4-S1 determinate coverage, host `swift test` (no
// network; StubDownloader stands in for the transfer). Covers ROADMAP E4-S1:
// notDownloaded -> downloading(progress) -> downloaded with monotonic
// progress; a failed download landing in .failed(message:) and a subsequent
// retry succeeding; the local file existing at the DownloadStore path on
// completion.
import XCTest
import SwiftData
@testable import DownloadKit
import PodcastModels

@MainActor
final class DownloadManagerTests: XCTestCase {

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let container = try ModelSchema.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    private func makeTempStoreDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeEpisode(guid: String = "ep-1") -> Episode {
        Episode(
            guid: guid,
            title: "Test Episode",
            audioURL: URL(string: "https://cdn.example.com/\(guid).mp3")!
        )
    }

    // MARK: - notDownloaded -> downloading(progress) -> downloaded

    func test_download_drivesStateMachineToDownloaded_withMonotonicProgress() async throws {
        let context = try makeContext()
        let episode = makeEpisode()
        context.insert(episode)

        let store = DownloadStore(baseDirectory: try makeTempStoreDirectory())
        var observed: [Double] = []
        // Deliberately includes a dip (0.6 -> 0.4) to prove clamping.
        let stub = StubDownloader(progressSequence: [0.1, 0.4, 0.6, 0.4, 1.0], outcome: .success) {
            observed.append(episode.downloadState.fractionComplete)
        }
        let manager = DownloadManager(downloader: stub, store: store)

        XCTAssertEqual(episode.downloadState, .notDownloaded)

        await manager.download(episode, context: context)

        // Every observed value is non-decreasing relative to the one before it.
        for index in 1..<observed.count {
            XCTAssertGreaterThanOrEqual(
                observed[index], observed[index - 1],
                "progress must never decrease (index \(index))"
            )
        }
        XCTAssertEqual(observed, [0.1, 0.4, 0.6, 0.6, 1.0])

        XCTAssertEqual(episode.downloadState, .downloaded)
        XCTAssertTrue(store.fileExists(forGuid: episode.guid))
        let resolved = try XCTUnwrap(manager.localURL(for: episode))
        XCTAssertEqual(resolved, store.existingFileURL(forGuid: episode.guid))
        // A real, decodable audio extension (never the old `.audio`).
        XCTAssertEqual(resolved.pathExtension, "mp3")
    }

    // MARK: - Failure -> retry

    func test_failedDownload_landsInFailedState_andRetrySucceeds() async throws {
        let context = try makeContext()
        let episode = makeEpisode()
        context.insert(episode)

        let store = DownloadStore(baseDirectory: try makeTempStoreDirectory())

        let failingStub = StubDownloader(progressSequence: [0.3], outcome: .failure("connection lost"))
        let failingManager = DownloadManager(downloader: failingStub, store: store)
        await failingManager.download(episode, context: context)

        guard case .failed(let message) = episode.downloadState else {
            return XCTFail("expected .failed, got \(episode.downloadState)")
        }
        XCTAssertEqual(message, "connection lost")
        XCTAssertFalse(store.fileExists(forGuid: episode.guid))

        // Retry with a downloader that now succeeds.
        let succeedingStub = StubDownloader(progressSequence: [0.5, 1.0], outcome: .success)
        let succeedingManager = DownloadManager(downloader: succeedingStub, store: store)
        await succeedingManager.download(episode, context: context)

        XCTAssertEqual(episode.downloadState, .downloaded)
        XCTAssertTrue(store.fileExists(forGuid: episode.guid))
    }

    // MARK: - Re-entrancy guard (double-tap can't start two transfers)

    func test_download_whileAlreadyDownloading_isNoOp() async throws {
        let context = try makeContext()
        let episode = makeEpisode()
        context.insert(episode)
        // Simulate a transfer already in flight.
        episode.downloadState = .downloading(progress: 0.3)

        let store = DownloadStore(baseDirectory: try makeTempStoreDirectory())
        // This stub would drive the episode to `.downloaded` if it ran; the
        // guard must prevent that.
        let stub = StubDownloader(progressSequence: [1.0], outcome: .success)
        let manager = DownloadManager(downloader: stub, store: store)

        await manager.download(episode, context: context)

        // State is untouched and no file was written — the second call bailed.
        XCTAssertEqual(episode.downloadState, .downloading(progress: 0.3))
        XCTAssertFalse(store.fileExists(forGuid: episode.guid))
    }

    // MARK: - File existence at the DownloadStore path

    func test_onCompletion_fileExistsAtDeterministicStorePath() async throws {
        let context = try makeContext()
        let episode = makeEpisode(guid: "abc-123-guid")
        context.insert(episode)

        let store = DownloadStore(baseDirectory: try makeTempStoreDirectory())
        let stub = StubDownloader(progressSequence: [1.0], outcome: .success)
        let manager = DownloadManager(downloader: stub, store: store)

        await manager.download(episode, context: context)

        let expectedPath = try XCTUnwrap(store.existingFileURL(forGuid: "abc-123-guid"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedPath.path))
        // Written with a real audio extension so AVFoundation can decode it.
        XCTAssertEqual(expectedPath.pathExtension, "mp3")
    }

    // MARK: - Remove (E8-S4: Settings "Manage downloaded episodes")

    func test_remove_deletesLocalFile_andResetsStateToNotDownloaded() async throws {
        let context = try makeContext()
        let episode = makeEpisode(guid: "remove-me")
        context.insert(episode)

        let store = DownloadStore(baseDirectory: try makeTempStoreDirectory())
        let stub = StubDownloader(progressSequence: [1.0], outcome: .success)
        let manager = DownloadManager(downloader: stub, store: store)

        await manager.download(episode, context: context)
        XCTAssertEqual(episode.downloadState, .downloaded)
        let downloadedPath = try XCTUnwrap(store.existingFileURL(forGuid: episode.guid))
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloadedPath.path))

        manager.remove(episode, context: context)

        XCTAssertEqual(episode.downloadState, .notDownloaded, "removing must reset downloadState so no stale .downloaded UI can desync from disk")
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloadedPath.path), "removing must delete the local audio file")
        XCTAssertNil(store.existingFileURL(forGuid: episode.guid))
    }

    func test_remove_whenNoFileExists_isSafeNoOp() throws {
        let context = try makeContext()
        let episode = makeEpisode(guid: "never-downloaded")
        context.insert(episode)
        XCTAssertEqual(episode.downloadState, .notDownloaded)

        let store = DownloadStore(baseDirectory: try makeTempStoreDirectory())
        let manager = DownloadManager(store: store)

        manager.remove(episode, context: context)

        XCTAssertEqual(episode.downloadState, .notDownloaded)
    }
}
