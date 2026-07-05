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

    func test_destinationURL_isDeterministic_forSameGuid() throws {
        let store = DownloadStore(baseDirectory: try makeTempDirectory())
        let first = store.destinationURL(forGuid: "feed-item-42", fileExtension: "mp3")
        let second = store.destinationURL(forGuid: "feed-item-42", fileExtension: "mp3")
        XCTAssertEqual(first, second)
    }

    func test_destinationURL_differsAcrossGuids() throws {
        let store = DownloadStore(baseDirectory: try makeTempDirectory())
        XCTAssertNotEqual(
            store.destinationURL(forGuid: "a", fileExtension: "mp3"),
            store.destinationURL(forGuid: "b", fileExtension: "mp3")
        )
    }

    // Regression: the stored file must carry a REAL audio extension (mp3/m4a/…),
    // never the old `.audio`, or AVFoundation can't decode it on playback.
    func test_destinationURL_usesRealAudioExtension_notDotAudio() throws {
        let store = DownloadStore(baseDirectory: try makeTempDirectory())
        XCTAssertEqual(store.destinationURL(forGuid: "g", fileExtension: "mp3").pathExtension, "mp3")
        XCTAssertEqual(store.destinationURL(forGuid: "g", fileExtension: "m4a").pathExtension, "m4a")
        // A bogus/non-media extension is coerced to mp3, never left as-is.
        XCTAssertEqual(store.destinationURL(forGuid: "g", fileExtension: "audio").pathExtension, "mp3")
    }

    func test_audioExtension_derivesFromEnclosureURL_withMp3Fallback() {
        // Podtrac-style redirect URL whose path still ends in audio.mp3.
        let mp3 = URL(string: "https://podtrac.com/pts/redirect.mp3/x/audio.mp3?utm_source=Podcast")!
        XCTAssertEqual(DownloadStore.audioExtension(for: mp3), "mp3")

        let m4a = URL(string: "https://cdn.example.com/clips/ep123.m4a")!
        XCTAssertEqual(DownloadStore.audioExtension(for: m4a), "m4a")

        // Extensionless / tracking URL -> mp3 (the podcast norm).
        let noExt = URL(string: "https://chtbl.com/track/ABCDE/traffic.megaphone.fm/ADV1234567890")!
        XCTAssertEqual(DownloadStore.audioExtension(for: noExt), "mp3")

        // A non-audio extension is not trusted -> mp3.
        let weird = URL(string: "https://example.com/redirect.php")!
        XCTAssertEqual(DownloadStore.audioExtension(for: weird), "mp3")
    }

    func test_fileExists_falseUntilMoved_thenTrue() throws {
        let store = DownloadStore(baseDirectory: try makeTempDirectory())
        XCTAssertFalse(store.fileExists(forGuid: "ep-9"))

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("bytes".utf8).write(to: tempFile)

        try store.moveIntoStore(from: tempFile, guid: "ep-9", fileExtension: "mp3")

        XCTAssertTrue(store.fileExists(forGuid: "ep-9"))
        XCTAssertEqual(store.existingFileURL(forGuid: "ep-9")?.pathExtension, "mp3")
    }

    // The reader resolves by digest stem, so it finds the file whatever
    // extension it was written with — and a re-download with a DIFFERENT
    // extension replaces the prior file rather than orphaning it.
    func test_existingFileURL_resolvesRegardlessOfExtension_andReplaceIsClean() throws {
        let store = DownloadStore(baseDirectory: try makeTempDirectory())

        let first = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("first".utf8).write(to: first)
        try store.moveIntoStore(from: first, guid: "ep-x", fileExtension: "m4a")
        XCTAssertEqual(store.existingFileURL(forGuid: "ep-x")?.pathExtension, "m4a")

        let second = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("second".utf8).write(to: second)
        try store.moveIntoStore(from: second, guid: "ep-x", fileExtension: "mp3")

        let resolved = try XCTUnwrap(store.existingFileURL(forGuid: "ep-x"))
        XCTAssertEqual(resolved.pathExtension, "mp3")
        XCTAssertEqual(try String(contentsOf: resolved, encoding: .utf8), "second")
        // Exactly one file for this guid (the m4a was removed, not orphaned).
        XCTAssertNoThrow(try store.remove(forGuid: "ep-x"))
        XCTAssertNil(store.existingFileURL(forGuid: "ep-x"))
    }

    func test_destinationURL_isFilesystemSafe_forAnAwkwardGuid() throws {
        let store = DownloadStore(baseDirectory: try makeTempDirectory())
        let awkwardGuid = "https://feeds.example.com/ep?id=1&x=<odd>/chars \u{1F600}"
        let url = store.destinationURL(forGuid: awkwardGuid, fileExtension: "mp3")
        // A plain hex-named file directly under baseDirectory (no traversal).
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL,
                       store.destinationURL(forGuid: "x", fileExtension: "mp3").deletingLastPathComponent().standardizedFileURL)
        XCTAssertEqual(url.pathExtension, "mp3")
    }
}
