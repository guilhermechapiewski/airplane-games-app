// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GameLogic",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GameLogic", targets: ["GameLogic"]),
    ],
    targets: [
        .target(
            name: "GameLogic",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "GameLogicTests",
            dependencies: ["GameLogic"]
        ),
    ]
)
