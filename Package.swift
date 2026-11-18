// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Dockyard",
    platforms: [.macOS(.v14)],
    targets: [
        // Logic with no AppKit dependency, so it can be unit tested.
        .target(name: "DockyardCore", path: "Sources/DockyardCore"),
        .executableTarget(name: "Dockyard", dependencies: ["DockyardCore"], path: "Sources/Dockyard"),
        .testTarget(name: "DockyardCoreTests", dependencies: ["DockyardCore"], path: "Tests/DockyardCoreTests"),
    ]
)
