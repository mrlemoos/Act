// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Act",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ActCore", targets: ["ActCore"]),
        .executable(name: "Act", targets: ["Act"])
    ],
    targets: [
        .target(name: "ActCore"),
        .executableTarget(name: "Act", dependencies: ["ActCore"]),
        .testTarget(name: "ActCoreTests", dependencies: ["ActCore"]),
        .testTarget(name: "ActAppTests", dependencies: ["Act", "ActCore"])
    ]
)
