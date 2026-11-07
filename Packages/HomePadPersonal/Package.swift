// swift-tools-version: 6.2
import PackageDescription

// Calendar, reminders, weather, photos, clocks, Find My.
let package = Package(
    name: "HomePadPersonal",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "HomePadPersonal", targets: ["HomePadPersonal"]),
    ],
    dependencies: [
        .package(path: "../HomePadCore"),
        .package(path: "../HomePadUI"),
    ],
    targets: [
        .target(
            name: "HomePadPersonal",
            dependencies: ["HomePadCore", "HomePadUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HomePadPersonalTests",
            dependencies: ["HomePadPersonal"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
