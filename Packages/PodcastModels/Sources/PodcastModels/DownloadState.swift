// DownloadState — persisted per-episode download status.
// Model layer for "i want ur pod"; no design source (data type only).
import Foundation

/// The download status of an episode's audio asset.
///
/// Stored on `Episode` as a `Codable` value so SwiftData can persist the
/// associated download progress alongside the case.
public enum DownloadState: Codable, Hashable, Sendable {
    /// No local copy exists and no download is in flight.
    case notDownloaded
    /// A download is in progress. `progress` is clamped to `0...1`.
    case downloading(progress: Double)
    /// A complete local copy of the audio is available.
    case downloaded
    /// The most recent download attempt failed. `message` is an optional reason.
    case failed(message: String?)

    /// Convenience: fractional progress in `0...1` for UI, where
    /// `.downloaded` reports `1` and terminal/idle states report `0`.
    public var fractionComplete: Double {
        switch self {
        case .notDownloaded, .failed:
            return 0
        case .downloading(let progress):
            return min(max(progress, 0), 1)
        case .downloaded:
            return 1
        }
    }

    /// Whether a complete local copy is available for offline playback.
    public var isDownloaded: Bool {
        if case .downloaded = self { return true }
        return false
    }

    /// Whether a download is currently in flight.
    public var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}
