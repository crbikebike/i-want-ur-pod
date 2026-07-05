// swift-tools-version: 5.9
// PodcastModels — SwiftData model layer for "i want ur pod".
import PackageDescription

let package = Package(
    name: "PodcastModels",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "PodcastModels",
            targets: ["PodcastModels"]
        )
    ],
    targets: [
        .target(
            name: "PodcastModels"
        ),
        .testTarget(
            name: "PodcastModelsTests",
            dependencies: ["PodcastModels"]
        )
    ]
)
