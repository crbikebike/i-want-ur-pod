// swift-tools-version: 5.9
// DesignSystem — token + theme foundation for "i want ur pod".
// Design source of truth: docs/design/direction.md
import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "DesignSystem",
            targets: ["DesignSystem"]
        )
    ],
    targets: [
        .target(
            name: "DesignSystem",
            resources: [
                // Bundle + register brand display face. Only the Regular
                // weight of IBM Plex Mono is available in the kit; heavier
                // display weights fall back to system. See FontRegistration.swift.
                .process("Fonts")
            ]
        )
    ]
)
