// swift-tools-version: 6.4

import PackageDescription

var swiftSettings: [SwiftSetting] = [
    .strictMemorySafety(),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
]

var package = Package(
    name: "hegel-swift",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "Hegel",
            targets: ["Hegel"],
        ),
        .library(
            name: "HegelTesting",
            targets: ["HegelTesting"],
        )
    ],
    targets: [
        .binaryTarget(
            name: "CHegel",
            path: "Artifacts/CHegel.artifactbundle",
        ),
        .target(
            name: "Hegel",
            dependencies: ["CHegel"],
            swiftSettings: swiftSettings,
        ),
        .target(
            name: "HegelTesting",
            dependencies: ["Hegel"],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "HegelTests",
            dependencies: ["HegelTesting"],
            swiftSettings: swiftSettings,
        ),
    ],
    swiftLanguageModes: [.v6],
)
