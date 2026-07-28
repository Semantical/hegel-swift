// swift-tools-version: 6.3

import CompilerPluginSupport
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
    traits: [
        .default(enabledTraits: ["HegelMacros"]),
        .trait(
            name: "HegelMacros",
            description: "Enables Hegel's macros.",
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-syntax",
            "603.0.0"..<"605.0.0",
        )
    ],
    targets: [
        .binaryTarget(
            name: "CHegel",
            path: "Artifacts/CHegel.artifactbundle",
        ),
        .target(
            name: "Hegel",
            dependencies: [
                "CHegel",
                .target(
                    name: "HegelMacrosPlugin",
                    condition: .when(traits: ["HegelMacros"]),
                ),
            ],
            swiftSettings: swiftSettings,
            linkerSettings: [
                .linkedLibrary("ntdll", .when(platforms: [.windows])),
            ],
        ),
        .macro(
            name: "HegelMacrosPlugin",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "HegelTests",
            dependencies: ["Hegel"],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "HegelMacroTests",
            dependencies: [
                .target(
                    name: "HegelMacrosPlugin",
                    condition: .when(traits: ["HegelMacros"]),
                ),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ],
            swiftSettings: swiftSettings,
        ),
    ],
    swiftLanguageModes: [.v6],
)

let macroCondition = TargetDependencyCondition.when(traits: ["HegelMacros"])
for target in package.targets {
    target.dependencies = target.dependencies.map { dependency in
        guard
            case .productItem(let name, let package?, let moduleAliases, _) = dependency,
            package == "swift-syntax"
        else {
            return dependency
        }
        return .product(
            name: name,
            package: package,
            moduleAliases: moduleAliases,
            condition: macroCondition,
        )
    }
}
