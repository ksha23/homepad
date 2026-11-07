// swift-tools-version: 6.2
import PackageDescription

// AI assistant, voice, providers, tools.
let package = Package(
    name: "HomePadAssistant",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "HomePadAssistant", targets: ["HomePadAssistant"]),
    ],
    dependencies: [
        .package(path: "../HomePadCore"),
        .package(path: "../HomePadUI"),
        // On-device natural voice: Kokoro-82M on MLX. KokoroSwift (MIT) and its
        // MisakiSwift pronunciation (Apache 2.0, no eSpeak) are vendored in
        // ../ThirdParty, see their Package.swift for the one change.
        .package(path: "../ThirdParty/KokoroSwift"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2"),
        .package(url: "https://github.com/mlalma/MLXUtilsLibrary.git", exact: "0.0.6"),
    ],
    targets: [
        .target(
            name: "HomePadAssistant",
            dependencies: [
                "HomePadCore", "HomePadUI",
                .product(name: "KokoroSwift", package: "KokoroSwift"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXUtilsLibrary", package: "MLXUtilsLibrary"),
            ],
            resources: [.copy("Resources/KokoroVoices.npz")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HomePadAssistantTests",
            dependencies: ["HomePadAssistant", "HomePadCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
