// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "lethe-app",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "LetheCore", targets: ["LetheCore"]),
        .executable(name: "LetheApp", targets: ["LetheApp"]),
    ],
    targets: [
        .target(
            name: "LetheCore"
        ),
        .executableTarget(
            name: "LetheApp",
            dependencies: ["LetheCore"]
        ),
        .testTarget(
            name: "LetheCoreTests",
            dependencies: ["LetheCore"]
        ),
    ]
)
