// swift-tools-version:5.9
// LedgeCore, the shared engine for Ledge. Built by Claude (Anthropic).
import PackageDescription

let package = Package(
    name: "LedgeCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "LedgeCore", targets: ["LedgeCore"])
    ],
    targets: [
        .target(name: "LedgeCore", path: "Sources/LedgeCore"),
        .testTarget(name: "LedgeCoreTests", dependencies: ["LedgeCore"], path: "Tests/LedgeCoreTests")
    ]
)
