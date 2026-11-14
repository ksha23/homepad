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
            swiftSettings: [
                .swiftLanguageMode(.v5),
                // Optimized in Debug builds too: the depth face work (the lit
                // depth, the crop, lining faces up) took about a quarter
                // second a map unoptimized, so only 4 of face tracking's 6
                // depth maps a second were looked at.
                .unsafeFlags(["-O"], .when(configuration: .debug)),
            ]
        ),
        .testTarget(
            name: "HomePadPresenceTests",
            dependencies: ["HomePadPresence"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
