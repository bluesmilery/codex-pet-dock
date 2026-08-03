// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PetDock",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PetDock",
            path: "Sources/PetDock"
        )
    ]
)
