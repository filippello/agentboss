// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DesktopHelper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DesktopHelper",
            path: "Sources/DesktopHelper",
            resources: [
                .copy("Resources/Main Characters"),
                .copy("Resources/config.default.json"),
            ]
        )
    ]
)
