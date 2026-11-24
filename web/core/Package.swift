// swift-tools-version: 6.0
import PackageDescription

// FitlingCore for the web: the same rules, built as a WebAssembly reactor (D-24). The iOS package
// itself stays as it is; this package only adds the JSON bridge.
let package = Package(
    name: "FitlingWeb",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "fitling-core", targets: ["fitling-core"]),
    ],
    dependencies: [
        .package(path: "../../Packages/FitlingCore"),
    ],
    targets: [
        .target(name: "FitlingWeb", dependencies: [.product(name: "FitlingCore", package: "FitlingCore")]),
        .executableTarget(name: "fitling-core", dependencies: ["FitlingWeb"]),
        .testTarget(name: "FitlingWebTests", dependencies: ["FitlingWeb"]),
    ]
)
