// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MooringIPC",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MooringIPC", targets: ["MooringIPC"]),
    ],
    targets: [
        .target(name: "MooringIPC"),
        .testTarget(name: "MooringIPCTests", dependencies: ["MooringIPC"]),
    ]
)
