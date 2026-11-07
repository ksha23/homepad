// swift-tools-version: 6.2
import PackageDescription

// HomeKit and Home Assistant.
let package = Package(
    name: "HomePadSmartHome",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "HomePadSmartHome", targets: ["HomePadSmartHome"]),
    ],
    dependencies: [
        .package(path: "../HomePadCore"),
        .package(path: "../HomePadUI"),
        // Home Assistant's own Swift client (Apache 2.0). WebSocket auth, subscriptions, REST.
        .package(url: "https://github.com/home-assistant/HAKit.git", exact: "0.4.19"),
        // Google's WebRTC built unmodified from webrtc.googlesource.com, as a binary
        // xcframework (BSD 3-Clause). Live view of Home Assistant cameras over WebRTC.
        .package(url: "https://github.com/stasel/WebRTC.git", exact: "155.0.0"),
    ],
    targets: [
        .target(
            name: "HomePadSmartHome",
            dependencies: [
                "HomePadCore",
                "HomePadUI",
                .product(name: "HAKit", package: "HAKit"),
                .product(name: "WebRTC", package: "WebRTC"),
            ],
            resources: [.copy("Resources/DashboardFixture.html")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HomePadSmartHomeTests",
            dependencies: [
                "HomePadSmartHome",
                .product(name: "HAKit", package: "HAKit"),
                .product(name: "HAKit+Mocks", package: "HAKit"),
            ],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
