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
        ),
        .testTarget(
            name: "SimpleNotrTests",
            dependencies: ["SimpleNotr"],
            path: "Tests/SimpleNotrTests",
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-disable-cross-import-overlays"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-framework", "Testing",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
                ])
            ]
        )
    ]
)
