// swift-tools-version: 5.9
// DownloadKit — M4 milestone stub package.
import PackageDescription

let package = Package(
    name: "DownloadKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DownloadKit", targets: ["DownloadKit"]),
    ],
    targets: [
        .target(name: "DownloadKit"),
    ]
)
