// swift-tools-version: 5.9
// FeedParsingKit — RSS/iTunes feed → Podcast/Episode parsing + upsert.
// Field mapping source of truth: docs/spec/feed-field-mapping.md
import PackageDescription

let package = Package(
    name: "FeedParsingKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FeedParsingKit", targets: ["FeedParsingKit"]),
    ],
    dependencies: [
        .package(path: "../PodcastModels")
    ],
    targets: [
        .target(
            name: "FeedParsingKit",
            dependencies: ["PodcastModels"]
        ),
        .testTarget(
            name: "FeedParsingKitTests",
            dependencies: ["FeedParsingKit"],
            resources: [
                .copy("Resources/good-feed.xml"),
                .copy("Resources/skip-item-feed.xml"),
                .copy("Resources/empty-feed.xml"),
                .copy("Resources/not-xml.txt")
            ]
        )
    ]
)
