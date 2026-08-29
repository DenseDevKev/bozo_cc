// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeadphoneCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "HeadphoneCore", targets: ["HeadphoneCore"]),
    ],
    targets: [
        .target(name: "HeadphoneCore"),
        .testTarget(name: "HeadphoneCoreTests", dependencies: ["HeadphoneCore"]),
    ]
)
