// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "MacMuster",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacMuster", targets: ["MacMuster"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MacMuster",
            dependencies: []
        ),
        .testTarget(
            name: "MacMusterTests",
            dependencies: ["MacMuster"],
            path: "Tests")
    ]
)

// Universal binary build notes:
// To build a universal binary (Intel + Apple Silicon), use:
//   swift build -c release --arch arm64 --arch x86_64
//
// To create the final universal binary, merge both architectures:
//   lipo -create -output MacMuster_universal \
//       .build/arm64-apple-macosx/release/MacMuster \
//       .build/x86_64-apple-macosx/release/MacMuster
//
// For production builds with universal support, modify build_production.sh:
//   swift build -c release --arch arm64 --arch x86_64 -Xswiftc -O -Xswiftc -Osize
