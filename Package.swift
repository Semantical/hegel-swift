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
        .testTarget(
            name: "HegelTests",
            dependencies: ["Hegel"],
            swiftSettings: swiftSettings,
        ),
    ],
    swiftLanguageModes: [.v6],
)
