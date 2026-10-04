// swift-tools-version: 6.0
import PackageDescription

// Vendored Maccy@c376789 (MIT), kept in Swift 5 mode. Revisions: THIRD_PARTY/Maccy/UPSTREAM.md.

let package = Package(
    name: "ClipKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClipKit", targets: ["ClipKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/Defaults", exact: "9.0.9"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "2.0.2"),
        .package(url: "https://github.com/Clipy/Sauce", exact: "2.4.1"),
        .package(url: "https://github.com/thii/SwiftHEXColors", exact: "1.4.1"),
        .package(url: "https://github.com/krisk/fuse-swift", exact: "1.4.0"),
        .package(url: "https://github.com/apple/swift-log", exact: "1.6.4")
    ],
    targets: [
        .target(
            name: "ClipKit",
            dependencies: [
                .product(name: "Defaults", package: "Defaults"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Sauce", package: "Sauce"),
                .product(name: "SwiftHEXColors", package: "SwiftHEXColors"),
                .product(name: "Fuse", package: "fuse-swift"),
                .product(name: "Logging", package: "swift-log")
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ClipKitTests",
            dependencies: ["ClipKit"],
            resources: [.process("Maccy/Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
