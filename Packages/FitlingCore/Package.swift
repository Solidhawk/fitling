// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FitlingCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FitlingCore", targets: ["FitlingCore"]),
    ],
    targets: [
        .target(name: "FitlingCore"),
        .testTarget(name: "FitlingCoreTests", dependencies: ["FitlingCore"]),
    ]
)
