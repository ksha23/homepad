// swift-tools-version: 6.2
import PackageDescription

// Back-camera features: Ask About This, scanners, Security Camera, LiDAR floor plan, timelapse.
let package = Package(
    name: "HomePadCameraLab",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "HomePadCameraLab", targets: ["HomePadCameraLab"]),
    ],
    dependencies: [
        .package(path: "../HomePadCore"),
        .package(path: "../HomePadUI"),
    ],
    targets: [
        .target(
            name: "HomePadCameraLab",
            dependencies: ["HomePadCore", "HomePadUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HomePadCameraLabTests",
            dependencies: ["HomePadCameraLab"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
