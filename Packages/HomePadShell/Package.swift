// swift-tools-version: 6.2
import PackageDescription

// App shell, kiosk mode, Home Screen, Control Center, People switcher.
let package = Package(
    name: "HomePadShell",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "HomePadShell", targets: ["HomePadShell"]),
    ],
    dependencies: [
        .package(path: "../HomePadCore"),
        .package(path: "../HomePadUI"),
    ],
    targets: [
        .target(
            name: "HomePadShell",
            dependencies: ["HomePadCore", "HomePadUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HomePadShellTests",
            dependencies: ["HomePadShell", "HomePadCore", "HomePadUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
