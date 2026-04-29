// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FocusPal",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FocusPal",
            path: "Sources/FocusPal",
            resources: [
                .copy("Resources/Main Characters"),
                .copy("Resources/Items"),
                .copy("Resources/Terrain"),
                .copy("Resources/Background"),
                .copy("Resources/config.default.json"),
            ]
        )
    ]
)
