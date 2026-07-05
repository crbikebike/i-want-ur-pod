// swift-tools-version: 5.9
// PlaybackKit — M3 milestone stub package.
import PackageDescription

let package = Package(
    name: "PlaybackKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PlaybackKit", targets: ["PlaybackKit"]),
    ],
    targets: [
        .target(name: "PlaybackKit"),
    ]
)
