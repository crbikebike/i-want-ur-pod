// swift-tools-version: 5.9
// FeedParsingKit — M2 milestone stub package.
import PackageDescription

let package = Package(
    name: "FeedParsingKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "FeedParsingKit", targets: ["FeedParsingKit"]),
    ],
    targets: [
        .target(name: "FeedParsingKit"),
    ]
)
