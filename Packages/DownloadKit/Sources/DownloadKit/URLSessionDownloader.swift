// URLSessionDownloader — the live `Downloading` conformer (E4-S1). A real
// `URLSessionDownloadTask` reporting progress via its delegate. Not exercised
// by the determinate host `swift test` suite (no network in CI/tests) — see
// `DownloadManagerTests` for the stub-driven coverage of the state machine.
import Foundation

/// Downloads an episode's audio via a real `URLSession` download task.
///
/// Bridges the delegate's background-queue callbacks into a single ordered
/// `AsyncStream`, consumed by one `for await` loop in ``download(from:progress:)``
/// so progress values are always delivered to the caller in order, one at a
/// time — satisfying `Downloading`'s sequential-callback contract.
///
/// `@unchecked Sendable`: the only stored state (`sessionConfiguration`) is
/// set once at init and thereafter read-only — a fresh `URLSession` is built
/// per `download(_:progress:)` call, so no mutable state is shared across
/// concurrent transfers. (`URLSessionConfiguration` itself isn't `Sendable`,
/// hence `@unchecked` rather than a synthesized conformance.)
public final class URLSessionDownloader: NSObject, Downloading, @unchecked Sendable {

    /// One event out of the underlying session: either a progress tick or
    /// the terminal outcome (success with a temp file, or failure).
    enum Event {
        case progress(Double)
        case completed(Result<URL, Error>)
    }

    private let sessionConfiguration: URLSessionConfiguration

    public init(sessionConfiguration: URLSessionConfiguration = .default) {
        self.sessionConfiguration = sessionConfiguration
    }

    public func download(from remote: URL, progress: @escaping @Sendable @MainActor (Double) -> Void) async throws -> URL {
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        let delegate = DownloadProgressDelegate(continuation: continuation)
        let session = URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let task = session.downloadTask(with: remote)
        task.resume()

        for await event in stream {
            switch event {
            case .progress(let value):
                await progress(value)   // hops to the main actor (@MainActor closure)
            case .completed(.success(let url)):
                return url
            case .completed(.failure(let error)):
                throw error
            }
        }

        // The stream finished without a terminal `.completed` event — treat
        // as a typed failure rather than trapping.
        throw DownloadError.invalidResponse
    }
}

/// Forwards `URLSessionDownloadDelegate` callbacks (which arrive on the
/// session's delegate queue, not necessarily the caller's task) into the
/// `AsyncStream` that `URLSessionDownloader.download` consumes.
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let continuation: AsyncStream<URLSessionDownloader.Event>.Continuation

    init(continuation: AsyncStream<URLSessionDownloader.Event>.Continuation) {
        self.continuation = continuation
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        continuation.yield(.progress(fraction))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The system deletes `location` once this method returns, so move
        // the file to a temp location we own before handing it back.
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            continuation.yield(.completed(.success(destination)))
        } catch {
            continuation.yield(.completed(.failure(error)))
        }
        continuation.finish()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        continuation.yield(.completed(.failure(error)))
        continuation.finish()
    }
}
