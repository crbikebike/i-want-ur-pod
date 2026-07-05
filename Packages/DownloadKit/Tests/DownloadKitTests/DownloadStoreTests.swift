// DownloadStoreTests — the guid -> local-file path convention (E4-S1). Pure
// filesystem logic against a temp directory; no network, no SwiftData.
import XCTest
@testable import DownloadKit

final class DownloadStoreTests: XCTestCase {

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func test_localURL_isDeterministic_forSameGuid() throws {
        let store = DownloadStore(baseDirectory: try makeTempDirectory())
        let first = store.localURL(forGuid: "feed-item-42")
        let second = store.localURL(forGuid: "feed-item-42")
        XCTAssertEqual(first, second)
    }

    func test_localURL_differsAcrossGuids() throws {
        let store = DownloadStore(baseDirectory: try makeTempDirectory())
        XCTAssertNotEqual(store.localURL(forGuid: "a"), store.localURL(forGuid: "b"))
    }

    func test_fileExists_falseUntilMoved_thenTrue() throws {
        let store = DownloadStore(baseDirectory: try makeTempDirectory())
        XCTAssertFalse(store.fileExists(forGuid: "ep-9"))

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("bytes".utf8).write(to: tempFile)

        try store.moveIntoStore(from: tempFile, guid: "ep-9")

        XCTAssertTrue(store.fileExists(forGuid: "ep-9"))
    }

    func test_moveIntoStore_replacesAnExistingFile() throws {
        let store = DownloadStore(baseDirectory: try makeTempDirectory())

        let first = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("first".utf8).write(to: first)
        try store.moveIntoStore(from: first, guid: "ep-retry")

        let second = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("second".utf8).write(to: second)
        try store.moveIntoStore(from: second, guid: "ep-retry")

        let destination = store.localURL(forGuid: "ep-retry")
        let contents = try Data(contentsOf: destination)
        XCTAssertEqual(String(data: contents, encoding: .utf8), "second")
    }

    func test_localURL_isFilesystemSafe_forAnAwkwardGuid() throws {
        let store = DownloadStore(baseDirectory: try makeTempDirectory())
        let awkwardGuid = "https://feeds.example.com/ep?id=1&x=<odd>/chars \u{1F600}"
        let url = store.localURL(forGuid: awkwardGuid)
        // Should not throw and should produce a plain hex-named file directly
        // under baseDirectory (no path traversal / slashes surviving).
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL,
                       store.localURL(forGuid: "x").deletingLastPathComponent().standardizedFileURL)
        XCTAssertEqual(url.pathExtension, "audio")
    }
}
