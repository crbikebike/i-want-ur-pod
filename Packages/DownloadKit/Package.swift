// swift-tools-version: 5.9
// DownloadKit — episode download manager (E4-S1). `.macOS(.v14)` is added so
// the pure state-machine + stub-downloader tests run on host `swift test`,
// same convention as FeedParsingKit/PodcastModels.
import PackageDescription

let package = Package(
    name: "DownloadKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DownloadKit",
            targets: ["DownloadKit"]
        )
    ],
    dependencies: [
        .package(path: "../PodcastModels")
    ],
    targets: [
        .target(
            name: "DownloadKit",
            dependencies: ["PodcastModels"],
            // Compiler-catch off-main-actor SwiftData mutations (e.g. the
            // background-queue download-progress callback mutating an
            // `@Model`). Matches the app target's `SWIFT_STRICT_CONCURRENCY:
            // complete` (project.yml).
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "DownloadKitTests",
            dependencies: ["DownloadKit"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        )
    ]
)
