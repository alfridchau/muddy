// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NewZMud",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NewZMud", targets: ["NewZMud"])
    ],
    targets: [
        .executableTarget(name: "NewZMud"),
        .testTarget(name: "NewZMudTests", dependencies: ["NewZMud"])
    ]
)
