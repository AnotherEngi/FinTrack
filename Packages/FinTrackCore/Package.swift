// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FinTrackCore",
    products: [.library(name: "FinTrackCore", targets: ["FinTrackCore"])],
    targets: [
        .target(name: "FinTrackCore"),
        .testTarget(name: "FinTrackCoreTests", dependencies: ["FinTrackCore"])
    ]
)
