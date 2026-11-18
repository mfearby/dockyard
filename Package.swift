// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Dockyard",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Dockyard", path: "Sources/Dockyard")
    ]
)
