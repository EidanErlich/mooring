// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AwakeKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AwakeKit", targets: ["AwakeKit"])
    ],
    targets: [
        .target(name: "AwakeKit", linkerSettings: [.linkedFramework("IOKit")]),
        .testTarget(name: "AwakeKitTests", dependencies: ["AwakeKit"])
    ]
)
