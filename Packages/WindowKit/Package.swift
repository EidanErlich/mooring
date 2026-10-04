// swift-tools-version: 6.0
import PackageDescription

// Vendored Loop@0ac6d83 (GPL-3.0), kept in Swift 5 mode. Revisions: THIRD_PARTY/Loop/UPSTREAM.md.

// Loop builds with SWIFT_APPROACHABLE_CONCURRENCY = YES; these are the features that setting turns on.
let approachableConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

let package = Package(
    name: "WindowKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WindowKit", targets: ["WindowKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/Defaults", exact: "9.0.9"),
        .package(url: "https://github.com/mrkai77/Luminare", revision: "99c14e36cd536c8252ea147c36e270675fe9c187"),
        // Subsurface requires Scribe on `main`, and SwiftPM refuses a second revision-based pin; Package.resolved fixes it.
        .package(url: "https://github.com/SenpaiHunters/Scribe", branch: "main"),
        .package(url: "https://github.com/mrkai77/Subsurface", revision: "660fe2bd7fbefe8f60b587905748b8e1ea413e2f")
    ],
    targets: [
        .target(
            name: "WindowKit",
            dependencies: [
                .product(name: "Defaults", package: "Defaults"),
                .product(name: "Luminare", package: "Luminare"),
                .product(name: "Scribe", package: "Scribe"),
                .product(name: "Subsurface", package: "Subsurface")
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)] + approachableConcurrency
        ),
        .testTarget(
            name: "WindowKitTests",
            dependencies: ["WindowKit"],
            swiftSettings: [.swiftLanguageMode(.v5), .enableUpcomingFeature("MemberImportVisibility")] + approachableConcurrency
        )
    ]
)
