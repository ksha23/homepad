// swift-tools-version: 6.2
import PackageDescription

// MisakiSwift 1.0.6 (github.com/mlalma/MisakiSwift, Apache 2.0, see LICENSE), vendored.
// One change: its dictionaries and fallback model live in MisakiData/ instead of
// a top-level Resources/ folder, which codesign rejects in iOS resource bundles.
// DataResourcesUtil.swift and EnglishFallbackNetwork.swift look there.
let package = Package(
    name: "MisakiSwift",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "MisakiSwift", targets: ["MisakiSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2"),
        .package(url: "https://github.com/mlalma/MLXUtilsLibrary.git", exact: "0.0.6"),
    ],
    targets: [
        .target(
            name: "MisakiSwift",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXUtilsLibrary", package: "MLXUtilsLibrary"),
            ],
            resources: [.copy("MisakiData")]
        ),
    ]
)
