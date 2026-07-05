// swift-tools-version: 5.9
// ChapterKit — M5 milestone stub package.
import PackageDescription

let package = Package(
    name: "ChapterKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ChapterKit", targets: ["ChapterKit"]),
    ],
    targets: [
        .target(name: "ChapterKit"),
    ]
)
