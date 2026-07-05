// DownloadStore — deterministic guid → local-file path convention (E4-S1).
// Architecture source: this story's build brief. `DownloadState` carries no
// file path (frozen model, PodcastModels/DownloadState.swift), so the local
// file location is derived on demand from `Episode.guid`. This is also how a
// later Play (E4-S2) resolves the local URL for a `.downloaded` episode —
// hence `localURL(forGuid:)` is public.
import Foundation
import CryptoKit

/// Maps an episode's `guid` to a stable local file URL under Application
/// Support, and moves completed downloads into place there.
///
/// The mapping is a pure function of `guid` (via a SHA-256 hex digest, so
/// path length/character-set are always filesystem-safe regardless of what
/// characters a feed's `<guid>` contains) — no state to persist, and stable
/// across app relaunches.
public struct DownloadStore {
    private let baseDirectory: URL

    /// - Parameter baseDirectory: Override for tests (a temp directory).
    ///   Defaults to `<Application Support>/Downloads` for the live app.
    public init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.baseDirectory = appSupport.appendingPathComponent("Downloads", isDirectory: true)
        }
    }

    /// The deterministic local file URL for `guid`. Stable across calls and
    /// across relaunches; does not imply the file exists yet.
    public func localURL(forGuid guid: String) -> URL {
        baseDirectory
            .appendingPathComponent(Self.digest(for: guid))
            .appendingPathExtension("audio")
    }

    /// Whether a complete local file already exists for `guid`.
    public func fileExists(forGuid guid: String) -> Bool {
        FileManager.default.fileExists(atPath: localURL(forGuid: guid).path)
    }

    /// Moves a completed download's temp file into the store at `guid`'s
    /// deterministic path, creating the Downloads directory if needed and
    /// replacing any prior file at that path (a retry after `.failed`, or a
    /// re-download).
    ///
    /// - Returns: The destination URL (same as ``localURL(forGuid:)``).
    @discardableResult
    public func moveIntoStore(from tempURL: URL, guid: String) throws -> URL {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        let destination = localURL(forGuid: guid)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    /// Removes the local file for `guid`, if any. No-op if nothing is there.
    public func remove(forGuid guid: String) throws {
        let url = localURL(forGuid: guid)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func digest(for guid: String) -> String {
        SHA256.hash(data: Data(guid.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
