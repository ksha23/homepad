// swift-tools-version: 6.2
import PackageDescription

// Recipes, cooking mode, timers.
let package = Package(
    name: "HomePadKitchen",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "HomePadKitchen", targets: ["HomePadKitchen"]),
    ],
    dependencies: [
        .package(path: "../HomePadCore"),
        .package(path: "../HomePadUI"),
    ],
    targets: [
        .target(
            name: "HomePadKitchen",
            dependencies: ["HomePadCore", "HomePadUI"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HomePadKitchenTests",
            dependencies: ["HomePadKitchen"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
