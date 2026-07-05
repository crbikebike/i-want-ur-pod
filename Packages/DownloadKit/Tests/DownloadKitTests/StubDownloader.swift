// StubDownloader — test double for `Downloading`. Emits a canned progress
// sequence (in order, synchronously — no real threading), then either
// succeeds by writing a temp file or throws. No network involved.
import Foundation
@testable import DownloadKit

// `@unchecked Sendable`: `Downloading` now requires `Sendable` (see
// Downloading.swift). This stub is only ever driven synchronously from a
// single `@MainActor` test, so its non-Sendable `onProgressApplied` hook can't
// actually race; the unchecked conformance documents that rather than forcing
// `@Sendable` onto every test's progress-observing closure.
final class StubDownloader: Downloading, @unchecked Sendable {
    enum Outcome {
        case success
        case failure(String)
    }

    private let progressSequence: [Double]
    private let outcome: Outcome
    /// Fired synchronously right after each progress value is applied by the
    /// caller (`DownloadManager`), letting a test observe the *clamped*
    /// sequence the manager actually wrote — not just what this stub emitted.
    private let onProgressApplied: (() -> Void)?

    init(progressSequence: [Double], outcome: Outcome, onProgressApplied: (() -> Void)? = nil) {
        self.progressSequence = progressSequence
        self.outcome = outcome
        self.onProgressApplied = onProgressApplied
    }

    func download(from remote: URL, progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        for value in progressSequence {
            await progress(value)
            onProgressApplied?()
        }
        switch outcome {
        case .success:
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data("stub audio bytes".utf8).write(to: tempURL)
            return tempURL
        case .failure(let message):
            throw DownloadError.transferFailed(message)
        }
    }
}
