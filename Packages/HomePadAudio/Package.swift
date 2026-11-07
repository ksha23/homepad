// swift-tools-version: 6.2
import PackageDescription

// AirPlay routing, music, now playing.
let package = Package(
    name: "HomePadAudio",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "HomePadAudio", targets: ["HomePadAudio"]),
    ],
    dependencies: [
        .package(path: "../HomePadCore"),
        .package(path: "../HomePadUI"),
    ],
    targets: [
        .target(
            name: "HomePadAudio",
            dependencies: ["HomePadCore", "HomePadUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HomePadAudioTests",
            dependencies: ["HomePadAudio"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
