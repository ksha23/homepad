// swift-tools-version: 6.2
import PackageDescription

// Always-on faces.
let package = Package(
    name: "HomePadFaces",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "HomePadFaces", targets: ["HomePadFaces"]),
    ],
    dependencies: [
        .package(path: "../HomePadCore"),
        .package(path: "../HomePadUI"),
    ],
    targets: [
        .target(
            name: "HomePadFaces",
            dependencies: ["HomePadCore", "HomePadUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HomePadFacesTests",
            dependencies: ["HomePadFaces", "HomePadCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
