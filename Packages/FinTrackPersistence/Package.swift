// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FinTrackPersistence",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "FinTrackPersistence", targets: ["FinTrackPersistence"])],
    dependencies: [.package(path: "../FinTrackCore")],
    targets: [
        .target(name: "FinTrackPersistence", dependencies: ["FinTrackCore"]),
        .testTarget(name: "FinTrackPersistenceTests",
                    dependencies: ["FinTrackPersistence", "FinTrackCore"])
    ]
)
