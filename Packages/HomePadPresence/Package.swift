// swift-tools-version: 6.2
import PackageDescription

// TrueDepth and camera presence, recognition, gestures, sounds.
let package = Package(
    name: "HomePadPresence",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "HomePadPresence", targets: ["HomePadPresence"]),
    ],
    dependencies: [
        .package(path: "../HomePadCore"),
        .package(path: "../HomePadUI"),
    ],
    targets: [
        .target(
            name: "HomePadPresence",
            dependencies: ["HomePadCore", "HomePadUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HomePadPresenceTests",
            dependencies: ["HomePadPresence"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
