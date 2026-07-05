// swift-tools-version: 5.9
// PlaybackKit — download-first audio playback engine (E4-S2/E4-S3).
// `.macOS(.v14)` added so the pure state-machine + stub-player tests run on
// host `swift test` (same convention as PodcastModels/FeedParsingKit/
// DownloadKit) — the one iOS-only seam (AVAudioSession, MPNowPlayingInfoCenter
// remote commands) is gated with `#if os(iOS)` inside its own file so the rest
// of the module still builds and is testable on macOS.
import PackageDescription

let package = Package(
    name: "PlaybackKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PlaybackKit", targets: ["PlaybackKit"]),
    ],
    dependencies: [
        .package(path: "../PodcastModels")
    ],
    targets: [
        .target(
            name: "PlaybackKit",
            dependencies: ["PodcastModels"],
            // Compiler-catch off-main-actor SwiftData mutations and
            // player-callback data races. Matches the app target's
            // `SWIFT_STRICT_CONCURRENCY: complete` (project.yml).
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "PlaybackKitTests",
            dependencies: ["PlaybackKit", "PodcastModels"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        )
    ]
)
