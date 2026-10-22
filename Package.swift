// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Limitbar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Limitbar", targets: ["Limitbar"]),
        .executable(name: "LimitbarBridge", targets: ["LimitbarBridge"])
    ],
    targets: [
        .target(name: "LimitbarCore"),
        .executableTarget(name: "Limitbar", dependencies: ["LimitbarCore"]),
        .executableTarget(name: "LimitbarBridge", dependencies: ["LimitbarCore"]),
        .testTarget(name: "LimitbarCoreTests", dependencies: ["LimitbarCore"])
    ]
)
