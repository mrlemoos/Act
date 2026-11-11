// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Act",
    defaultLocalization: "en-GB",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ActCore", targets: ["ActCore"]),
        .executable(name: "Act", targets: ["Act"])
    ],
    targets: [
        .target(name: "ActCore", resources: [.process("Resources")]),
        .executableTarget(name: "Act", dependencies: ["ActCore"]),
        .testTarget(name: "ActCoreTests", dependencies: ["ActCore"]),
        .testTarget(name: "ActAppTests", dependencies: ["Act", "ActCore"])
    ]
)
