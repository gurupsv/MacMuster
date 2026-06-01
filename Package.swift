// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "MacMuster",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacMuster", targets: ["MacMuster"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MacMuster",
            dependencies: []),
        .testTarget(
            name: "MacMusterTests",
            dependencies: ["MacMuster"],
            path: "Tests")
    ]
)