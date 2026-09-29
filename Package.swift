// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Leaf",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LeafCore", targets: ["LeafCore"]),
        .executable(name: "Leaf", targets: ["Leaf"])
    ],
    targets: [
        .target(name: "CZip", publicHeadersPath: "include", linkerSettings: [.linkedLibrary("z")]),
        .target(name: "LeafCore", dependencies: ["CZip"]),
        .executableTarget(name: "Leaf", dependencies: ["LeafCore"], path: "Sources/Leaf"),
        .testTarget(name: "LeafCoreTests", dependencies: ["LeafCore"])
    ],
    swiftLanguageModes: [.v6]
)
