// swift-tools-version: 6.0
import PackageDescription

// FitlingCore for the web: the same rules, built as a WebAssembly reactor (D-24). This package only adds
// the JSON bridge. Under WASI the sources import FoundationEssentials instead of Foundation: the full
// Foundation brings about 50 MB of language data (ICU) along that the rules never use.
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
        // FitlingCore too: a test compares an answer with what the engine itself gives.
        .testTarget(name: "FitlingWebTests", dependencies: ["FitlingWeb", .product(name: "FitlingCore", package: "FitlingCore")]),
    ]
)
