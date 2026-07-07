// DownloadManager — drives Episode.downloadState through the E4-S1 state
// machine. Architecture source: this story's build brief + PodcastModels'
// frozen DownloadState (.notDownloaded/.downloading(progress:)/.downloaded/
// .failed(message:)). App-scoped like AppSources (IWantUrPod/App/AppSources.swift):
// created once in IWantUrPodApp and injected via .environment, never built
// inside AppShell's tab switch (frozen nav contract).
import Foundation
import Observation
import SwiftData
import PodcastModels

/// Drives a single `Episode`'s `downloadState` from `.notDownloaded` (or a
/// prior `.failed`) through `.downloading(progress:)` to `.downloaded`,
/// persisting the transition, or to `.failed(message:)` on error.
///
/// Kept as a thin orchestrator over two testable seams: ``Downloading`` (the
/// transfer itself) and ``DownloadStore`` (the local-file path convention).
/// The transition/persistence logic below is what `DownloadManagerTests`
/// exercises against a stub downloader — no real network in tests.
@MainActor
@Observable
public final class DownloadManager {
    private let downloader: Downloading
    private let store: DownloadStore

    /// - Parameters:
    ///   - downloader: The transfer seam. Defaults to the live
    ///     `URLSessionDownloader`; tests inject a stub.
    ///   - store: The local-file path convention. Defaults to the live
    ///     Application Support location; tests inject a temp-directory store.
    public init(downloader: Downloading = URLSessionDownloader(), store: DownloadStore = DownloadStore()) {
        self.downloader = downloader
        self.store = store
    }

    /// Starts (or retries) downloading `episode`'s audio, driving
    /// `episode.downloadState` through the full state machine and persisting
    /// via `context.save()` on every terminal transition.
    ///
    /// Safe to call again on a `.failed` (or even `.downloaded`, re-fetching)
    /// episode — always restarts from `.downloading(progress: 0)`. Progress
    /// updates applied to `episode.downloadState` are clamped to be
    /// non-decreasing relative to the episode's current fractional progress,
    /// so an out-of-order or jittery progress callback from the downloader
    /// can never move the UI backwards.
    public func download(_ episode: Episode, context: ModelContext) async {
        // Re-entrancy guard: a double-tap (or an auto-retry firing while a
        // transfer is already in flight) must not start a second concurrent
        // download to the same store path. Only `.notDownloaded`/`.failed`/
        // `.downloaded` are (re)startable; an in-flight `.downloading` is a
        // no-op. This runs on the main actor, so the check-then-set below is
        // atomic w.r.t. other `download(_:)` calls.
        guard !episode.downloadState.isDownloading else { return }

        episode.downloadState = .downloading(progress: 0)

        do {
            let tempURL = try await downloader.download(from: episode.audioURL) { [weak episode] value in
                guard let episode else { return }
                let monotonic = Self.clampMonotonic(value, previous: episode.downloadState.fractionComplete)
                episode.downloadState = .downloading(progress: monotonic)
            }
            // Preserve a real audio extension so AVFoundation can decode the
            // file on playback (a non-media extension makes a valid MP3
            // unplayable — the `.audio` bug). Derived from the enclosure URL.
            let ext = DownloadStore.audioExtension(for: episode.audioURL)
            try store.moveIntoStore(from: tempURL, guid: episode.guid, fileExtension: ext)
            episode.downloadState = .downloaded
            try context.save()
        } catch {
            episode.downloadState = .failed(message: Self.message(for: error))
            try? context.save()
        }
    }

    /// The local file URL for a `.downloaded` episode (E4-S2 resolves
    /// playback against this). `nil` when no file is on disk yet.
    public func localURL(for episode: Episode) -> URL? {
        store.existingFileURL(forGuid: episode.guid)
    }

    /// Removes a downloaded episode's local audio file and resets its state
    /// back to `.notDownloaded` (E8-S4's Settings "Manage downloaded
    /// episodes" — removing a row deletes the file while the `Episode`
    /// record and its feed membership stay untouched). Safe to call even if
    /// no file exists (`DownloadStore.remove(forGuid:)` is a no-op then);
    /// the state reset + `context.save()` still happen so a desynced
    /// `.downloaded` state can't linger.
    public func remove(_ episode: Episode, context: ModelContext) {
        try? store.remove(forGuid: episode.guid)
        episode.downloadState = .notDownloaded
        try? context.save()
    }

    /// Clamps `new` so progress reported to the UI never decreases relative
    /// to `previous`, and stays within `0...1`.
    static func clampMonotonic(_ new: Double, previous: Double) -> Double {
        min(max(max(new, previous), 0), 1)
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? "Download failed. Check your connection and try again."
    }
}
