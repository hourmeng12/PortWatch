// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PortWatch",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "PortWatch"),
        .testTarget(name: "PortWatchTests", dependencies: ["PortWatch"]),
    ],
    swiftLanguageModes: [.v5]
)
