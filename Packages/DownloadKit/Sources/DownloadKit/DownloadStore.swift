// DownloadStore — deterministic guid → local-file path convention (E4-S1).
// Architecture source: this story's build brief. `DownloadState` carries no
// file path (frozen model, PodcastModels/DownloadState.swift), so the local
// file location is derived on demand from `Episode.guid`. This is also how a
// later Play (E4-S2) resolves the local URL for a `.downloaded` episode.
//
// The stored file keeps a REAL audio extension (e.g. `.mp3`, `.m4a`): AVURLAsset
// / AVPlayer resolve the media format from the file extension's UTI, and a
// non-media extension (the old `.audio`) makes an otherwise-valid MP3
// undecodable ("media format not supported", AVFoundation error -11828). The
// digest names the file; the extension is derived from the enclosure URL. The
// reader resolves by the digest stem (any extension), so it never depends on
// which extension was chosen at write time.
import Foundation
import CryptoKit

/// Maps an episode's `guid` to a stable local file under Application Support,
/// and moves completed downloads into place there.
///
/// The stem is a pure function of `guid` (a SHA-256 hex digest, so path
/// length/character-set are always filesystem-safe regardless of the feed's
/// `<guid>`); the extension reflects the audio container so AVFoundation can
/// decode it.
public struct DownloadStore {
    private let baseDirectory: URL

    /// Audio container extensions we accept from a feed's enclosure URL. Any
    /// other (or a missing) extension falls back to `mp3` — the podcast norm.
    static let knownAudioExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "mp4", "wav", "aif", "aiff", "caf",
        "flac", "opus", "ogg", "oga"
    ]

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

    /// A validated, filesystem-safe audio extension for `sourceURL`'s enclosure:
    /// the URL's path extension if it's a recognized audio container, else `mp3`.
    public static func audioExtension(for sourceURL: URL) -> String {
        let ext = sourceURL.pathExtension.lowercased()
        return knownAudioExtensions.contains(ext) ? ext : "mp3"
    }

    /// The write destination for `guid` with the given (already-validated)
    /// audio `fileExtension`. Does not imply the file exists yet.
    public func destinationURL(forGuid guid: String, fileExtension: String) -> URL {
        baseDirectory
            .appendingPathComponent(Self.digest(for: guid))
            .appendingPathExtension(Self.knownAudioExtensions.contains(fileExtension.lowercased()) ? fileExtension.lowercased() : "mp3")
    }

    /// The existing local file for `guid`, whatever its extension — the read
    /// side resolves by digest stem so it's independent of the write-time
    /// extension. `nil` if no download is present.
    public func existingFileURL(forGuid guid: String) -> URL? {
        let stem = Self.digest(for: guid)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil
        ) else { return nil }
        // Ignore the legacy `.audio` extension: files written by earlier builds
        // are undecodable by AVFoundation, so treat them as absent (a
        // re-download replaces them with a real audio extension) rather than
        // resolving to an unplayable file.
        return entries.first {
            $0.deletingPathExtension().lastPathComponent == stem
                && $0.pathExtension.lowercased() != "audio"
        }
    }

    /// Whether a complete local file already exists for `guid`.
    public func fileExists(forGuid guid: String) -> Bool {
        existingFileURL(forGuid: guid) != nil
    }

    /// Moves a completed download's temp file into the store at `guid`'s
    /// deterministic stem with `fileExtension`, creating the Downloads
    /// directory if needed and replacing any prior file for this guid (a retry
    /// after `.failed`, a re-download, or a stale legacy-extension file).
    ///
    /// - Returns: The destination URL.
    @discardableResult
    public func moveIntoStore(from tempURL: URL, guid: String, fileExtension: String) throws -> URL {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        // Purge any prior file(s) for this guid — including a legacy `.audio`
        // one that `existingFileURL` intentionally ignores — so a re-download
        // never leaves an orphan behind.
        purgeFiles(forGuid: guid)
        let destination = destinationURL(forGuid: guid, fileExtension: fileExtension)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    /// Removes the local file(s) for `guid`, if any (including a legacy
    /// `.audio` file). No-op if nothing is there.
    public func remove(forGuid guid: String) throws {
        purgeFiles(forGuid: guid)
    }

    /// Deletes every file whose stem matches `guid`'s digest, any extension.
    private func purgeFiles(forGuid guid: String) {
        let stem = Self.digest(for: guid)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for entry in entries where entry.deletingPathExtension().lastPathComponent == stem {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private static func digest(for guid: String) -> String {
        SHA256.hash(data: Data(guid.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
