// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HomePadUI",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "HomePadUI", targets: ["HomePadUI"]),
    ],
    dependencies: [
        .package(path: "../HomePadCore"),
    ],
    targets: [
        .target(
            name: "HomePadUI",
            dependencies: ["HomePadCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HomePadUITests",
            dependencies: ["HomePadUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
