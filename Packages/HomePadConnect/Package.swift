// swift-tools-version: 6.2
import PackageDescription

// Siri, Handoff, iCloud sync, intercom, companion devices.
let package = Package(
    name: "HomePadConnect",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "HomePadConnect", targets: ["HomePadConnect"]),
    ],
    dependencies: [
        .package(path: "../HomePadCore"),
        .package(path: "../HomePadUI"),
        .package(path: "ShareKit"),
    ],
    targets: [
        .target(
            name: "HomePadConnect",
            dependencies: ["HomePadCore", "HomePadUI", .product(name: "HomePadShareKit", package: "ShareKit")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HomePadConnectTests",
            dependencies: ["HomePadConnect", .product(name: "HomePadShareKit", package: "ShareKit")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
