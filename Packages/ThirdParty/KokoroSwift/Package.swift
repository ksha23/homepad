// swift-tools-version: 6.2
import PackageDescription

// KokoroSwift 1.0.11 (github.com/mlalma/kokoro-ios, MIT, see LICENSE), vendored.
// One change: config.json lives in KokoroData/ instead of a top-level Resources/
// folder, which codesign rejects in iOS resource bundles ("bundle format
// unrecognized"). KokoroConfig.swift looks there. It also links MLXSimulatorShims
// so the app still builds for the simulator.
let package = Package(
    name: "KokoroSwift",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "KokoroSwift", targets: ["KokoroSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2"),
        .package(path: "../MisakiSwift"),
        .package(url: "https://github.com/mlalma/MLXUtilsLibrary.git", exact: "0.0.6"),
        .package(path: "../MLXSimulatorShims"),
    ],
    targets: [
        .target(
            name: "KokoroSwift",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift"),
                .product(name: "MisakiSwift", package: "MisakiSwift"),
                .product(name: "MLXUtilsLibrary", package: "MLXUtilsLibrary"),
                // HomePad: lets MLX link for the simulator, see that package.
                .product(name: "MLXSimulatorShims", package: "MLXSimulatorShims"),
            ],
            resources: [.copy("KokoroData")]
        ),
    ]
)
