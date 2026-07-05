// Downloading — the testable seam behind episode downloads (E4-S1).
// Architecture source: this story's build brief (no design/kit source — pure
// data-layer contract). Kept deliberately small so a test can inject a stub
// that emits progress and yields/throws without any real network.
import Foundation

/// A single-shot transfer of a remote audio asset to a local temp file.
///
/// `DownloadManager` depends on this protocol rather than `URLSession`
/// directly so tests can inject a stub that emits a canned progress sequence
/// and either succeeds with a temp file or throws, with no network involved.
/// The live conformer is ``URLSessionDownloader``.
///
/// `Sendable`: a downloader is a shared, effectively-immutable service that
/// `DownloadManager` (`@MainActor`) hands to a background transfer, so it must
/// be safe to pass across actor boundaries — required once the module builds
/// under complete strict concurrency.
public protocol Downloading: Sendable {
    /// Downloads `remote` to a local temporary file, reporting fractional
    /// progress (`0...1`) as bytes arrive.
    ///
    /// - Parameters:
    ///   - remote: The remote audio URL (`Episode.audioURL`).
    ///   - progress: Invoked with each new fractional progress value, in
    ///     order. **`@MainActor`**: `DownloadManager` (the caller) is
    ///     `@MainActor` and mutates a SwiftData `@Model` (`episode
    ///     .downloadState`) inside this closure; the live conformer receives
    ///     raw bytes on a background `URLSession` delegate queue, so hopping
    ///     the callback to the main actor here is what keeps that model
    ///     mutation from racing SwiftUI reads. Conformers must call this
    ///     sequentially (never concurrently) so a caller can rely on
    ///     receiving updates one at a time without additional
    ///     synchronization.
    /// - Returns: The URL of a local temp file containing the complete
    ///   download. Callers are responsible for moving it somewhere durable.
    /// - Throws: On any transfer failure (network, HTTP, filesystem).
    func download(from remote: URL, progress: @escaping @Sendable @MainActor (Double) -> Void) async throws -> URL
}

/// Typed errors surfaced by ``Downloading`` conformers.
public enum DownloadError: Error, LocalizedError, Equatable {
    /// The transfer failed; `message` is a user-presentable reason when one
    /// is available (e.g. from the underlying `URLError`/HTTP status).
    case transferFailed(String)
    /// The transfer "completed" without producing a usable local file.
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .transferFailed(let message):
            return message
        case .invalidResponse:
            return "The download didn't complete correctly."
        }
    }
}
