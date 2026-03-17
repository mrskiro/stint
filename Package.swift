// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Stint",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Stint", path: "Sources/Stint"),
        .testTarget(name: "StintTests", dependencies: ["Stint"], path: "Tests/StintTests"),
    ]
)
