// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HyperKey",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "HyperKey",
            path: "Sources"
        ),
    ]
)
