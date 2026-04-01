// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BozoBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BozoBar",
            path: "Sources/BozoBar"
        ),
    ]
)
