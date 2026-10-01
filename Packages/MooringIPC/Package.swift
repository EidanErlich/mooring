// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MooringIPC",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MooringIPC", targets: ["MooringIPC"]),
        .library(name: "MooringCLICore", targets: ["MooringCLICore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(name: "MooringIPC"),
        .target(
            name: "MooringCLICore",
            dependencies: [
                "MooringIPC",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(name: "MooringIPCTests", dependencies: ["MooringIPC"]),
        .testTarget(name: "MooringCLICoreTests", dependencies: ["MooringCLICore", "MooringIPC"])
    ]
)
