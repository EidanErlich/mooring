// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AwakeKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AwakeKit", targets: ["AwakeKit"]),
        .library(name: "AwaykeMonitors", targets: ["AwaykeMonitors"])
    ],
    targets: [
        .target(name: "AwakeKit", dependencies: ["AwaykeMonitors"], linkerSettings: [.linkedFramework("IOKit")]),
        // Vendored Awayke code, kept in Swift 5 mode (docs/SPEC.md, Languages and packages).
        .target(
            name: "AwaykeMonitors",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(name: "AwakeKitTests", dependencies: ["AwakeKit"]),
        .testTarget(name: "AwaykeMonitorsTests", dependencies: ["AwaykeMonitors"])
    ]
)
