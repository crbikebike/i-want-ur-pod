// swift-tools-version: 5.9
// DirectoryKit — podcast search source contract layer.
// Design/source model: docs/design/direction.md §12 (Apple primary keyless;
// PodcastIndex opt-in with user key; PRIMARY + FALLBACK, no merge).
import PackageDescription

let package = Package(
    name: "DirectoryKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DirectoryKit",
            targets: ["DirectoryKit"]
        )
    ],
    targets: [
        .target(
            name: "DirectoryKit"
        ),
        .testTarget(
            name: "DirectoryKitTests",
            dependencies: ["DirectoryKit"],
            resources: [
                .copy("Resources/sample-podcasts.json")
            ]
        )
    ]
)
