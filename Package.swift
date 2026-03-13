// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SimpleNotr",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "SimpleNotr",
            path: "Sources/SimpleNotr"
        )
    ]
)
