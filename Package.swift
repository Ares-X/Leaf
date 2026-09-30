// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Leaf", platforms: [.macOS(.v13)],
    products: [.executable(name: "Leaf", targets: ["Leaf"])],
    targets: [
        .target(name: "CArchive", linkerSettings: [.linkedLibrary("archive")]),
        .target(name: "LeafCore", dependencies: ["CArchive"]),
        .executableTarget(name: "Leaf", dependencies: ["LeafCore"],
                          resources: [.copy("Resources/Reader")]),
        .testTarget(name: "LeafCoreTests", dependencies: ["LeafCore"]),
        .testTarget(name: "LeafAppTests", dependencies: ["Leaf"])
    ]
)
